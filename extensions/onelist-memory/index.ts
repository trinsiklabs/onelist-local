/**
 * Onelist Memory Sync Plugin v0.5.0
 *
 * DEFENSE IN DEPTH EDITION - Multiple layers against feedback loops
 *
 * v0.5.0: FIVE-LAYER PROTECTION against session bloat:
 *
 *   LAYER 1: SESSION PRE-CHECK
 *   - Before injecting, scan current session file
 *   - If ANY message contains [INJECTION-DEPTH:], ABORT
 *   - Makes injection ONE-TIME per session
 *
 *   LAYER 2: PERSISTENT INJECTION TRACKING
 *   - Track injection count per session in state file (survives restarts)
 *   - Hard limit: max 2 injections per session lifetime
 *   - Prevents restart storms from causing repeated injections
 *
 *   LAYER 3: FILE-BASED RATE LIMITING
 *   - Write last injection timestamp to file (survives restarts)
 *   - 60-second cooldown between ANY injections (global, not per-session)
 *   - Replaces in-memory rate limiter that reset on restart
 *
 *   LAYER 4: SESSION SIZE CIRCUIT BREAKER
 *   - If current session file > 500KB, ABORT (already bloated)
 *   - If session has > 200 messages, ABORT (lots of context already)
 *   - Prevents injecting into already-large sessions
 *
 *   LAYER 5: CONTENT BLOCKLIST (existing from v0.4.0)
 *   - Skip messages containing recovery markers when building context
 *   - Prevents nested injection content
 *
 * v0.4.0: Depth marker + in-memory rate limiting (insufficient - reset on restart)
 * v0.3.0: Message-level blocklist (works but doesn't prevent session accumulation)
 * v0.2.2: Line-level filtering (insufficient)
 *
 * ROOT CAUSE ANALYSIS (v0.5.0):
 * The v0.4.0 blocklist correctly prevents NESTED content, but OpenClaw saves
 * each prependContext as a session message. With rapid gateway restarts,
 * 60+ injection messages accumulated (1.5MB), causing API token limits.
 * The fix: prevent multiple injections per session, not just nested content.
 */

import * as fs from 'fs';
import * as path from 'path';

// =============================================================================
// CONFIGURATION & TYPES
// =============================================================================

interface PluginConfig {
  apiUrl?: string;
  apiKey?: string;
  sessionId?: string;
  enabled?: boolean;
  autoInjectEnabled?: boolean;
  autoInjectMessageCount?: number;
  autoInjectHoursBack?: number;
  autoInjectMinMessages?: number;
  maxFileSizeBytes?: number;
  maxTotalReadBytes?: number;
  maxMessageLength?: number;
}

interface SessionMessage {
  type?: string;
  id?: string;
  timestamp?: string;
  message?: {
    role?: string;
    content?: unknown;
    timestamp?: number;
  };
}

interface ParsedMessage {
  role: string;
  content: string;
  timestamp: string;
  source: string;
}

interface RecoveryResult {
  content: string;
  messageCount: number;
  filesProcessed: number;
  errors: string[];
}

// =============================================================================
// HARD LIMITS - Safety rails that cannot be overridden
// =============================================================================

const HARD_LIMITS = {
  // File processing limits
  MAX_FILE_SIZE: 5 * 1024 * 1024,
  MAX_TOTAL_READ: 50 * 1024 * 1024,
  MAX_MESSAGE_LENGTH: 4000,
  MAX_FILES_TO_SCAN: 100,
  MAX_LINES_PER_FILE: 10000,
  HOOK_TIMEOUT_MS: 5000,

  // v0.3.0: Circuit breaker for output size
  MAX_RECOVERY_OUTPUT_CHARS: 50000,

  // v0.5.0: DEFENSE IN DEPTH - Session protection
  MAX_INJECTIONS_PER_SESSION: 2,        // Layer 2: Hard limit on injections
  INJECTION_COOLDOWN_MS: 60000,         // Layer 3: 60 seconds between ANY injection
  MAX_SESSION_SIZE_FOR_INJECT: 500000,  // Layer 4: Don't inject into sessions > 500KB
  MAX_SESSION_MESSAGES_FOR_INJECT: 200, // Layer 4: Don't inject if > 200 messages
};

// =============================================================================
// v0.5.0: PERSISTENT STATE MANAGEMENT
// =============================================================================

// State file location - survives gateway restarts
const STATE_FILE_PATH = '/tmp/onelist-memory-state.json';

interface PersistentState {
  lastInjectionTime: number;
  sessionInjectionCounts: Record<string, number>;
  lastUpdated: string;
}

function loadPersistentState(): PersistentState {
  try {
    if (fs.existsSync(STATE_FILE_PATH)) {
      const data = fs.readFileSync(STATE_FILE_PATH, 'utf-8');
      return JSON.parse(data);
    }
  } catch (err) {
    // State file corrupted or unreadable - start fresh
  }
  return {
    lastInjectionTime: 0,
    sessionInjectionCounts: {},
    lastUpdated: new Date().toISOString(),
  };
}

function savePersistentState(state: PersistentState): void {
  try {
    state.lastUpdated = new Date().toISOString();
    fs.writeFileSync(STATE_FILE_PATH, JSON.stringify(state, null, 2));
  } catch (err) {
    // Best effort - don't crash if we can't save state
  }
}

function getSessionInjectionCount(state: PersistentState, sessionId: string): number {
  return state.sessionInjectionCounts[sessionId] ?? 0;
}

function incrementSessionInjectionCount(state: PersistentState, sessionId: string): void {
  state.sessionInjectionCounts[sessionId] = (state.sessionInjectionCounts[sessionId] ?? 0) + 1;
  savePersistentState(state);
}

// =============================================================================
// CONTENT BLOCKLIST PATTERNS (Layer 5)
// =============================================================================

const FILTER_PATTERNS = [
  /\[media attached:/i,
  /\[media:/i,
  /<media:image>/i,
  /To send an image back, prefer/i,
];

const MESSAGE_BLOCKLIST_PATTERNS = [
  /## 🔄 Recovered Conversation Context/,
  /\*\*Auto-injected:\*\*.*\d{4}-\d{2}-\d{2}/,
  /End of recovered context\. Continue/i,
  /Recovered Conversation Context/i,
  /This context was automatically recovered from recent session transcripts/i,
  /\[INJECTION-DEPTH:\d+\]/,
  /\*\*(USER|ASSISTANT)\*\*\s*\(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/,
  /\*\*Coverage:\*\*\s*Last\s+\d+\s+hours?\s*\|/i,
];

// =============================================================================
// LOGGING HELPERS
// =============================================================================

interface Logger {
  info: (msg: string) => void;
  warn: (msg: string) => void;
  error: (msg: string) => void;
  debug: (msg: string) => void;
}

function createFallbackLogger(): Logger {
  const prefix = '[onelist-memory]';
  return {
    info: (msg: string) => console.log(`${prefix} ${msg}`),
    warn: (msg: string) => console.warn(`${prefix} ${msg}`),
    error: (msg: string) => console.error(`${prefix} ${msg}`),
    debug: (msg: string) => console.log(`${prefix} [debug] ${msg}`),
  };
}

// =============================================================================
// v0.5.0: LAYER 1 - SESSION PRE-CHECK
// =============================================================================

/**
 * Check if a session file already contains injection markers.
 * If it does, we should NOT inject again.
 */
function sessionAlreadyHasInjection(sessionPath: string, logger: Logger): boolean {
  try {
    if (!fs.existsSync(sessionPath)) {
      return false;
    }

    const content = fs.readFileSync(sessionPath, 'utf-8');

    // Quick check for injection marker anywhere in file
    if (content.includes('[INJECTION-DEPTH:')) {
      logger.info('LAYER 1 BLOCK: Session already contains injection marker');
      return true;
    }

    // Also check for recovery header (in case marker was somehow stripped)
    if (content.includes('## 🔄 Recovered Conversation Context')) {
      logger.info('LAYER 1 BLOCK: Session already contains recovery header');
      return true;
    }

    return false;
  } catch (err) {
    // If we can't read the file, err on the side of caution
    logger.warn(`LAYER 1: Could not read session file: ${String(err)}`);
    return true; // Block injection if uncertain
  }
}

// =============================================================================
// v0.5.0: LAYER 4 - SESSION SIZE CHECK
// =============================================================================

/**
 * Check if session is too large for injection.
 */
function sessionTooLargeForInjection(sessionPath: string, logger: Logger): boolean {
  try {
    if (!fs.existsSync(sessionPath)) {
      return false;
    }

    const stats = fs.statSync(sessionPath);

    if (stats.size > HARD_LIMITS.MAX_SESSION_SIZE_FOR_INJECT) {
      logger.info(`LAYER 4 BLOCK: Session size ${stats.size} exceeds ${HARD_LIMITS.MAX_SESSION_SIZE_FOR_INJECT}`);
      return true;
    }

    // Count messages
    const content = fs.readFileSync(sessionPath, 'utf-8');
    const lines = content.split('\n').filter(l => l.trim());
    const messageCount = lines.filter(l => l.includes('"type":"message"')).length;

    if (messageCount > HARD_LIMITS.MAX_SESSION_MESSAGES_FOR_INJECT) {
      logger.info(`LAYER 4 BLOCK: Session has ${messageCount} messages, exceeds ${HARD_LIMITS.MAX_SESSION_MESSAGES_FOR_INJECT}`);
      return true;
    }

    return false;
  } catch (err) {
    logger.warn(`LAYER 4: Could not check session size: ${String(err)}`);
    return false; // Don't block on error - other layers will catch issues
  }
}

// =============================================================================
// v0.5.0: FIND CURRENT SESSION
// =============================================================================

/**
 * Find the most recently modified session file (likely the current one).
 */
function findCurrentSessionFile(sessionsDir: string): { path: string; id: string } | null {
  try {
    const files = fs.readdirSync(sessionsDir)
      .filter(f => f.endsWith('.jsonl') && !f.includes('.deleted') && !f.includes('.lock') && !f.includes('.archived'))
      .map(f => ({
        name: f,
        path: path.join(sessionsDir, f),
        mtime: fs.statSync(path.join(sessionsDir, f)).mtimeMs,
      }))
      .sort((a, b) => b.mtime - a.mtime);

    if (files.length === 0) return null;

    const sessionId = files[0].name.replace('.jsonl', '');
    return { path: files[0].path, id: sessionId };
  } catch {
    return null;
  }
}

// =============================================================================
// MAIN PLUGIN REGISTRATION
// =============================================================================

console.log('[onelist-memory] Plugin file loaded (v0.5.0 defense-in-depth - 5-layer protection)');

export default function register(api: any) {
  const logger: Logger = api?.logger ?? createFallbackLogger();

  logger.info('Register function called');

  const pluginId = 'onelist-memory';
  let config: PluginConfig;

  try {
    config = (api?.config?.plugins?.entries?.[pluginId]?.config as PluginConfig) ?? {};
  } catch (err) {
    logger.warn(`Failed to read plugin config, using defaults: ${String(err)}`);
    config = {};
  }

  if (config.enabled === false) {
    logger.info('Plugin explicitly disabled in config');
    return;
  }

  // =========================================================================
  // AUTO-INJECT RECOVERY HOOK
  // =========================================================================

  const autoInjectEnabled = config.autoInjectEnabled !== false;

  if (autoInjectEnabled) {
    logger.info('Registering auto-inject recovery hook (v0.5.0 defense-in-depth)');

    try {
      api.on('before_agent_start', async (event: any, ctx: any): Promise<{ prependContext?: string } | undefined> => {
        const startTime = Date.now();
        const sessionsDir = findSessionsDirectory(logger);

        if (!sessionsDir) {
          logger.debug('No sessions directory found');
          return undefined;
        }

        // Find current session
        const currentSession = findCurrentSessionFile(sessionsDir);
        const sessionId = currentSession?.id ?? 'unknown';
        const sessionPath = currentSession?.path;

        logger.debug(`Current session: ${sessionId}`);

        // Load persistent state
        const state = loadPersistentState();

        // =====================================================================
        // LAYER 3: FILE-BASED RATE LIMITING (survives restarts)
        // =====================================================================
        const timeSinceLastInjection = startTime - state.lastInjectionTime;
        if (timeSinceLastInjection < HARD_LIMITS.INJECTION_COOLDOWN_MS) {
          const waitTime = Math.round((HARD_LIMITS.INJECTION_COOLDOWN_MS - timeSinceLastInjection) / 1000);
          logger.info(`LAYER 3 BLOCK: Rate limited - ${waitTime}s until next injection allowed`);
          return undefined;
        }

        // =====================================================================
        // LAYER 2: PERSISTENT INJECTION COUNT
        // =====================================================================
        const injectionCount = getSessionInjectionCount(state, sessionId);
        if (injectionCount >= HARD_LIMITS.MAX_INJECTIONS_PER_SESSION) {
          logger.info(`LAYER 2 BLOCK: Session ${sessionId} already has ${injectionCount} injections (max: ${HARD_LIMITS.MAX_INJECTIONS_PER_SESSION})`);
          return undefined;
        }

        // =====================================================================
        // LAYER 1: SESSION PRE-CHECK (check for existing injections)
        // =====================================================================
        if (sessionPath && sessionAlreadyHasInjection(sessionPath, logger)) {
          // Also update the count so we don't keep checking
          if (injectionCount === 0) {
            state.sessionInjectionCounts[sessionId] = HARD_LIMITS.MAX_INJECTIONS_PER_SESSION;
            savePersistentState(state);
          }
          return undefined;
        }

        // =====================================================================
        // LAYER 4: SESSION SIZE CHECK
        // =====================================================================
        if (sessionPath && sessionTooLargeForInjection(sessionPath, logger)) {
          return undefined;
        }

        // =====================================================================
        // ALL LAYERS PASSED - Proceed with injection
        // =====================================================================
        logger.info(`All 4 pre-checks passed for session ${sessionId} - proceeding with recovery`);

        try {
          const timeoutPromise = new Promise<null>((_, reject) => {
            setTimeout(() => reject(new Error('Recovery timeout')), HARD_LIMITS.HOOK_TIMEOUT_MS);
          });

          const recoveryPromise = recoverContext(config, logger);

          const result = await Promise.race([recoveryPromise, timeoutPromise]);

          if (!result) {
            logger.debug('No context to inject (null result)');
            return undefined;
          }

          const elapsed = Date.now() - startTime;

          if (result.errors.length > 0) {
            logger.warn(`Recovery completed with ${result.errors.length} errors: ${result.errors.slice(0, 3).join('; ')}`);
          }

          // LAYER 5: Circuit breaker on output size
          const contentSize = result.content.length;
          if (contentSize > HARD_LIMITS.MAX_RECOVERY_OUTPUT_CHARS) {
            logger.error(`LAYER 5 BLOCK: Recovery output ${contentSize} chars exceeds ${HARD_LIMITS.MAX_RECOVERY_OUTPUT_CHARS} limit`);
            return undefined;
          }

          // Additional safety: check for nested markers
          const recoveryMarkerCount = (result.content.match(/Recovered Conversation Context/gi) || []).length;
          if (recoveryMarkerCount > 1) {
            logger.error(`LAYER 5 BLOCK: Found ${recoveryMarkerCount} nested recovery markers`);
            return undefined;
          }

          // =====================================================================
          // INJECTION APPROVED - Update state and return
          // =====================================================================
          logger.info(`INJECTION APPROVED: ${result.messageCount} messages from ${result.filesProcessed} files (${elapsed}ms, ${contentSize} chars)`);
          logger.info(`Session ${sessionId} injection count: ${injectionCount} -> ${injectionCount + 1}`);

          // Update persistent state
          state.lastInjectionTime = Date.now();
          incrementSessionInjectionCount(state, sessionId);

          return { prependContext: result.content };

        } catch (err) {
          const elapsed = Date.now() - startTime;
          const errStr = String(err);

          if (errStr.includes('timeout')) {
            logger.error(`Recovery timed out after ${elapsed}ms`);
          } else {
            logger.error(`Recovery failed after ${elapsed}ms: ${errStr}`);
          }

          return undefined;
        }
      }, { priority: 100 });

      logger.info('Auto-inject hook registered successfully');

    } catch (err) {
      logger.error(`Failed to register auto-inject hook: ${String(err)}`);
    }
  } else {
    logger.info('Auto-inject disabled in config');
  }

  // =========================================================================
  // ONELIST SYNC
  // =========================================================================

  startOnlistSync(config, api, logger).catch(err => {
    logger.error(`Onelist sync startup failed: ${String(err)}`);
  });
}

// =============================================================================
// AUTO-INJECT RECOVERY IMPLEMENTATION
// =============================================================================

async function recoverContext(config: PluginConfig, logger: Logger): Promise<RecoveryResult | null> {
  const messageCount = Math.min(config.autoInjectMessageCount ?? 50, 200);
  const hoursBack = Math.min(config.autoInjectHoursBack ?? 24, 168);
  const minMessages = config.autoInjectMinMessages ?? 5;
  const maxFileSize = Math.min(config.maxFileSizeBytes ?? HARD_LIMITS.MAX_FILE_SIZE, HARD_LIMITS.MAX_FILE_SIZE);
  const maxTotalRead = Math.min(config.maxTotalReadBytes ?? HARD_LIMITS.MAX_TOTAL_READ, HARD_LIMITS.MAX_TOTAL_READ);

  const errors: string[] = [];
  const sessionsDir = findSessionsDirectory(logger);

  if (!sessionsDir) {
    logger.debug('Sessions directory not found');
    return null;
  }

  logger.debug(`Using sessions directory: ${sessionsDir}`);

  const cutoffTime = Date.now() - (hoursBack * 60 * 60 * 1000);

  let sessionFiles: Array<{ name: string; path: string; mtime: number; size: number }>;

  try {
    const files = fs.readdirSync(sessionsDir);

    sessionFiles = files
      .filter(f => {
        if (!f.endsWith('.jsonl')) return false;
        if (f.includes('.deleted')) return false;
        if (f.includes('.lock')) return false;
        if (f.includes('.archived')) return false; // v0.5.0: Skip archived files
        return true;
      })
      .slice(0, HARD_LIMITS.MAX_FILES_TO_SCAN)
      .map(f => {
        const filePath = path.join(sessionsDir, f);
        try {
          const stat = fs.statSync(filePath);
          return { name: f, path: filePath, mtime: stat.mtimeMs, size: stat.size };
        } catch (err) {
          errors.push(`stat failed for ${f}: ${String(err)}`);
          return null;
        }
      })
      .filter((f): f is NonNullable<typeof f> => f !== null)
      .filter(f => f.mtime >= cutoffTime)
      .filter(f => f.size <= maxFileSize)
      .sort((a, b) => b.mtime - a.mtime);

  } catch (err) {
    errors.push(`Failed to list sessions directory: ${String(err)}`);
    logger.error(`Failed to list sessions directory: ${String(err)}`);
    return null;
  }

  if (sessionFiles.length === 0) {
    logger.debug(`No session files found within ${hoursBack} hours`);
    return null;
  }

  logger.debug(`Found ${sessionFiles.length} session files to process`);

  const allMessages: ParsedMessage[] = [];
  let totalBytesRead = 0;
  let filesProcessed = 0;

  for (const file of sessionFiles) {
    if (totalBytesRead + file.size > maxTotalRead) {
      logger.debug(`Skipping ${file.name}: would exceed total read limit`);
      break;
    }

    if (allMessages.length >= messageCount * 2) {
      logger.debug(`Have enough messages (${allMessages.length}), stopping file scan`);
      break;
    }

    try {
      const messages = parseSessionFileSafe(file.path, file.name, logger, errors);
      allMessages.push(...messages);
      totalBytesRead += file.size;
      filesProcessed++;

      logger.debug(`Parsed ${messages.length} messages from ${file.name}`);

    } catch (err) {
      errors.push(`Unexpected error parsing ${file.name}: ${String(err)}`);
    }
  }

  if (allMessages.length < minMessages) {
    logger.debug(`Only ${allMessages.length} messages found, below minimum ${minMessages}`);
    return null;
  }

  allMessages.sort((a, b) => {
    const timeA = parseTimestampSafe(a.timestamp);
    const timeB = parseTimestampSafe(b.timestamp);
    return timeA - timeB;
  });

  const recentMessages = allMessages.slice(-messageCount);
  const formattedContext = formatRecoveredContext(recentMessages, hoursBack, filesProcessed, errors.length);

  return {
    content: formattedContext,
    messageCount: recentMessages.length,
    filesProcessed,
    errors,
  };
}

function findSessionsDirectory(logger: Logger): string | null {
  const candidates = [
    '/root/.openclaw/agents/main/sessions',
    path.join(process.env.HOME || '', '.openclaw', 'agents', 'main', 'sessions'),
  ].filter(Boolean);

  for (const dir of candidates) {
    try {
      if (fs.existsSync(dir) && fs.statSync(dir).isDirectory()) {
        return dir;
      }
    } catch (err) {
      logger.debug(`Failed to check directory ${dir}: ${String(err)}`);
    }
  }

  return null;
}

function parseSessionFileSafe(
  filePath: string,
  fileName: string,
  logger: Logger,
  errors: string[]
): ParsedMessage[] {
  const messages: ParsedMessage[] = [];

  let content: string;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch (err) {
    errors.push(`Failed to read ${fileName}: ${String(err)}`);
    return messages;
  }

  const lines = content.split(/\r?\n/);
  const linesToProcess = lines.slice(0, HARD_LIMITS.MAX_LINES_PER_FILE);

  if (lines.length > HARD_LIMITS.MAX_LINES_PER_FILE) {
    errors.push(`${fileName}: truncated to ${HARD_LIMITS.MAX_LINES_PER_FILE} lines (had ${lines.length})`);
  }

  let lineNum = 0;
  let parseErrors = 0;

  for (const line of linesToProcess) {
    lineNum++;

    const trimmed = line.trim();
    if (!trimmed) continue;

    let entry: SessionMessage;
    try {
      entry = JSON.parse(trimmed);
    } catch {
      parseErrors++;
      if (parseErrors <= 3) {
        errors.push(`${fileName}:${lineNum}: invalid JSON`);
      }
      continue;
    }

    if (typeof entry !== 'object' || entry === null) continue;
    if (entry.type !== 'message') continue;
    if (!entry.message || typeof entry.message !== 'object') continue;

    const role = entry.message.role;
    if (role !== 'user' && role !== 'assistant') continue;

    const textContent = extractTextContent(entry.message.content);
    if (!textContent) continue;

    // LAYER 5: Message-level blocklist check
    const shouldBlockMessage = MESSAGE_BLOCKLIST_PATTERNS.some(pattern => pattern.test(textContent));
    if (shouldBlockMessage) {
      continue;
    }

    const { filtered: filteredContent, removedCount } = filterMediaReferences(textContent);

    if (!filteredContent || filteredContent.length < 10) {
      if (removedCount > 0) {
        continue;
      }
    }

    const truncated = filteredContent.length > HARD_LIMITS.MAX_MESSAGE_LENGTH
      ? filteredContent.substring(0, HARD_LIMITS.MAX_MESSAGE_LENGTH) + '\n[...truncated...]'
      : filteredContent;

    messages.push({
      role,
      content: truncated,
      timestamp: String(entry.timestamp ?? ''),
      source: fileName,
    });
  }

  if (parseErrors > 3) {
    errors.push(`${fileName}: ${parseErrors} total JSON parse errors`);
  }

  return messages;
}

function extractTextContent(content: unknown): string {
  if (!content) return '';

  if (typeof content === 'string') {
    return content.trim();
  }

  if (Array.isArray(content)) {
    const textParts: string[] = [];

    for (const item of content) {
      if (item && typeof item === 'object' && 'type' in item && 'text' in item) {
        if (item.type === 'text' && typeof item.text === 'string') {
          textParts.push(item.text);
        }
      }
    }

    return textParts.join('\n').trim();
  }

  return '';
}

function filterMediaReferences(content: string): { filtered: string; removedCount: number } {
  const lines = content.split('\n');
  const filteredLines: string[] = [];
  let removedCount = 0;

  for (const line of lines) {
    const shouldFilter = FILTER_PATTERNS.some(pattern => pattern.test(line));

    if (shouldFilter) {
      removedCount++;
    } else {
      filteredLines.push(line);
    }
  }

  return {
    filtered: filteredLines.join('\n').trim(),
    removedCount,
  };
}

function parseTimestampSafe(timestamp: string): number {
  if (!timestamp) return 0;

  try {
    const parsed = new Date(timestamp).getTime();
    return isNaN(parsed) ? 0 : parsed;
  } catch {
    return 0;
  }
}

function formatRecoveredContext(
  messages: ParsedMessage[],
  hoursBack: number,
  filesProcessed: number,
  errorCount: number
): string {
  const now = new Date().toISOString();

  // v0.5.0: Include version in marker for debugging
  let header = `[INJECTION-DEPTH:0][v0.5.0]

## 🔄 Recovered Conversation Context

**Auto-injected:** ${now}
**Coverage:** Last ${hoursBack} hours | ${messages.length} messages | ${filesProcessed} session files`;

  if (errorCount > 0) {
    header += ` | ${errorCount} parse warnings`;
  }

  header += `

This context was automatically recovered from recent session transcripts to maintain continuity after compaction.

---

`;

  let body = '';
  for (const msg of messages) {
    const roleLabel = msg.role === 'user' ? '**USER**' : '**ASSISTANT**';
    const timestamp = msg.timestamp ? ` (${msg.timestamp})` : '';

    body += `${roleLabel}${timestamp}:\n${msg.content}\n\n`;
  }

  const footer = `---

*End of recovered context. Continue the conversation naturally.*
`;

  return header + body + footer;
}

// =============================================================================
// ONELIST SYNC IMPLEMENTATION
// =============================================================================

const syncState = new Map<string, {
  lastLineCount: number;
  lastTimestamp: string;
}>();

async function startOnlistSync(config: PluginConfig, api: any, logger: Logger): Promise<void> {
  if (!config.apiUrl || !config.apiKey) {
    logger.info('Onelist sync disabled (no API credentials)');
    return;
  }

  logger.info('Starting Onelist sync service');

  const sessionsDir = findSessionsDirectory(logger);

  if (!sessionsDir) {
    logger.warn('Sessions directory not found - Onelist sync disabled');
    return;
  }

  try {
    watchSessionDirectory(sessionsDir, config, logger);
  } catch (err) {
    logger.error(`Failed to start session watcher: ${String(err)}`);
  }
}

function watchSessionDirectory(sessionsDir: string, config: PluginConfig, logger: Logger): void {
  logger.info(`Setting up watcher on: ${sessionsDir}`);

  let watcher: fs.FSWatcher;

  try {
    watcher = fs.watch(sessionsDir, { persistent: true }, async (eventType, filename) => {
      if (!filename) return;
      if (!filename.endsWith('.jsonl')) return;
      if (filename.includes('.deleted') || filename.includes('.lock') || filename.includes('.archived')) return;

      const filePath = path.join(sessionsDir, filename);

      try {
        await syncSessionFile(filePath, config, logger);
      } catch (err) {
        logger.error(`Error syncing ${filename}: ${String(err)}`);
      }
    });

    watcher.on('error', (err) => {
      logger.error(`Watcher error: ${String(err)}`);
    });

  } catch (err) {
    logger.error(`Failed to create watcher: ${String(err)}`);
    return;
  }

  try {
    const files = fs.readdirSync(sessionsDir)
      .filter(f => f.endsWith('.jsonl') && !f.includes('.deleted') && !f.includes('.lock') && !f.includes('.archived'));

    for (const file of files) {
      const filePath = path.join(sessionsDir, file);
      syncSessionFile(filePath, config, logger).catch(err => {
        logger.error(`Initial sync error for ${file}: ${String(err)}`);
      });
    }
  } catch (err) {
    logger.error(`Failed to list sessions for initial sync: ${String(err)}`);
  }

  logger.info(`Watching ${sessionsDir} for session changes`);
}

async function syncSessionFile(filePath: string, config: PluginConfig, logger: Logger): Promise<void> {
  const state = syncState.get(filePath) || { lastLineCount: 0, lastTimestamp: '' };

  let content: string;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch (err) {
    return;
  }

  const lines = content.trim().split('\n');

  if (lines.length <= state.lastLineCount) {
    return;
  }

  const newLines = lines.slice(state.lastLineCount);
  const messages: SessionMessage[] = [];

  for (const line of newLines) {
    try {
      const parsed = JSON.parse(line) as SessionMessage;
      if (parsed.type === 'message' && parsed.message) {
        messages.push(parsed);
      }
    } catch {
      // Skip invalid lines
    }
  }

  if (messages.length === 0) {
    syncState.set(filePath, { lastLineCount: lines.length, lastTimestamp: state.lastTimestamp });
    return;
  }

  const sessionId = config.sessionId || path.basename(filePath, '.jsonl');

  let successCount = 0;
  let failCount = 0;

  for (const msg of messages) {
    try {
      await sendToOnelist(config, sessionId, msg, logger);
      successCount++;
    } catch (err) {
      failCount++;
      if (failCount <= 3) {
        logger.error(`Failed to send message to Onelist: ${String(err)}`);
      }
    }
  }

  if (failCount > 3) {
    logger.error(`${failCount} total Onelist send failures for ${path.basename(filePath)}`);
  }

  syncState.set(filePath, {
    lastLineCount: lines.length,
    lastTimestamp: messages[messages.length - 1]?.timestamp || state.lastTimestamp,
  });

  if (successCount > 0) {
    logger.debug(`Synced ${successCount} messages from ${path.basename(filePath)}`);
  }
}

async function sendToOnelist(config: PluginConfig, sessionId: string, msg: SessionMessage, logger: Logger): Promise<void> {
  if (!config.apiUrl || !config.apiKey) {
    throw new Error('Missing API credentials');
  }

  const url = `${config.apiUrl}/api/v1/chat-stream/append`;

  const content = extractTextContent(msg.message?.content);
  if (!content) return;

  const payload = {
    session_id: sessionId,
    message: {
      role: msg.message?.role || 'unknown',
      content: content,
      timestamp: msg.timestamp,
      message_id: msg.id,
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.apiKey}`,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    if (!response.ok) {
      const text = await response.text().catch(() => 'unknown');
      throw new Error(`Onelist API error: ${response.status} - ${text.slice(0, 100)}`);
    }
  } finally {
    clearTimeout(timeout);
  }
}
