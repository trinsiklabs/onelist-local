/**
 * Onelist Memory Sync Plugin v0.5.3
 *
 * HARDENED EDITION - Feedback loop fix
 *
 * v0.5.3 FIXES (Session Recreation Bug):
 *   - State read FRESH from disk on every injection check (was cached at startup)
 *   - Track session file birth time to detect recreated files
 *   - If session file is newer than last injection → file was recreated → BLOCK
 *   - Atomic read-modify-write with proper locking
 *   - incrementBlockedCount now persists to disk
 *
 * v0.5.2 FEATURES:
 *   - Telegram metadata extraction from message text
 *   - Parses user info, message IDs, reply threading, reactions
 *   - Adds source metadata to Onelist sync payload
 *
 * v0.5.1 FIXES:
 *   - State file moved to persistent location (/root/.openclaw/)
 *   - State pruning (sessions older than 7 days, max 100 entries)
 *   - State file versioning for future migrations
 *   - Onelist sync circuit breaker (backoff after failures)
 *   - Memory leak fix (syncState Map capped at 50 entries)
 *   - Simple file locking for state writes
 *   - Startup health logging
 *   - Hourly stats logging
 *
 * v0.5.0: Five-layer defense-in-depth protection
 * v0.4.0: Depth marker + rate limiting (insufficient - reset on restart)
 * v0.3.0: Message-level blocklist
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
// v0.5.2: TELEGRAM METADATA EXTRACTION
// =============================================================================

interface TelegramMetadata {
  channel: 'telegram';
  session_key?: string;
  telegram_user_id?: string;
  handle?: string;
  display_name?: string;
  message_id?: string;
  reply_to_role?: string;
  reply_to_message_id?: string;
  reaction?: string;
  reaction_target_id?: string;
}

function extractTelegramMetadata(content: string, sessionKey?: string): TelegramMetadata {
  const metadata: TelegramMetadata = {
    channel: 'telegram',
  };

  if (sessionKey) {
    metadata.session_key = sessionKey;
  }

  const userInfoMatch = content.match(/\[Telegram (\w+) \(@(\w+)\) id:(\d+)/);
  if (userInfoMatch) {
    metadata.display_name = userInfoMatch[1];
    metadata.handle = `@${userInfoMatch[2]}`;
    metadata.telegram_user_id = userInfoMatch[3];
  }

  const messageIdMatch = content.match(/\[message_id: (\d+)\]/);
  if (messageIdMatch) {
    metadata.message_id = messageIdMatch[1];
  }

  const replyMatch = content.match(/\[Replying to (\w+) id:(\d+)\]/);
  if (replyMatch) {
    metadata.reply_to_role = replyMatch[1];
    metadata.reply_to_message_id = replyMatch[2];
  }

  const reactionMatch = content.match(/reaction added: (.+?) by .* on msg (\d+)/);
  if (reactionMatch) {
    metadata.reaction = reactionMatch[1].trim();
    metadata.reaction_target_id = reactionMatch[2];
  }

  return metadata;
}

// =============================================================================
// HARD LIMITS
// =============================================================================

const HARD_LIMITS = {
  MAX_FILE_SIZE: 5 * 1024 * 1024,
  MAX_TOTAL_READ: 50 * 1024 * 1024,
  MAX_MESSAGE_LENGTH: 4000,
  MAX_FILES_TO_SCAN: 100,
  MAX_LINES_PER_FILE: 10000,
  HOOK_TIMEOUT_MS: 5000,
  MAX_RECOVERY_OUTPUT_CHARS: 50000,

  MAX_INJECTIONS_PER_SESSION: 2,
  INJECTION_COOLDOWN_MS: 60000,
  MAX_SESSION_SIZE_FOR_INJECT: 500000,
  MAX_SESSION_MESSAGES_FOR_INJECT: 200,

  STATE_MAX_SESSIONS: 100,
  STATE_PRUNE_DAYS: 7,
  SYNC_STATE_MAX_ENTRIES: 50,

  ONELIST_MAX_CONSECUTIVE_FAILURES: 5,
  ONELIST_INITIAL_BACKOFF_MS: 60000,
  ONELIST_MAX_BACKOFF_MS: 3600000,

  // v0.5.3: Lock timeout
  STATE_LOCK_TIMEOUT_MS: 5000,
  STATE_LOCK_RETRY_MS: 50,
};

// =============================================================================
// v0.5.3: PERSISTENT STATE (with fresh reads and file birth tracking)
// =============================================================================

const STATE_FILE_PATH = '/root/.openclaw/onelist-memory-state.json';
const STATE_VERSION = 2; // Bumped for v0.5.3 schema change

interface SessionInjectionData {
  count: number;
  lastUpdated: number;
  // v0.5.3: Track when file existed at injection time
  lastFileBirthTime?: number;
}

interface PersistentState {
  version: number;
  lastInjectionTime: number;
  sessionInjectionCounts: Record<string, SessionInjectionData>;
  lastUpdated: string;
  stats: {
    totalInjections: number;
    totalBlocked: number;
    startupTime: number;
  };
}

// v0.5.3: Improved file locking with timeout
function acquireStateLock(timeoutMs: number = HARD_LIMITS.STATE_LOCK_TIMEOUT_MS): boolean {
  const lockPath = STATE_FILE_PATH + '.lock';
  const startTime = Date.now();
  
  while (Date.now() - startTime < timeoutMs) {
    try {
      if (fs.existsSync(lockPath)) {
        const lockStat = fs.statSync(lockPath);
        // Stale lock (older than 10 seconds)
        if (Date.now() - lockStat.mtimeMs > 10000) {
          fs.unlinkSync(lockPath);
        } else {
          // Wait and retry
          const waitTime = HARD_LIMITS.STATE_LOCK_RETRY_MS;
          const start = Date.now();
          while (Date.now() - start < waitTime) { /* spin */ }
          continue;
        }
      }
      // Create lock with exclusive flag
      fs.writeFileSync(lockPath, String(process.pid), { flag: 'wx' });
      return true;
    } catch (err: any) {
      if (err.code === 'EEXIST') {
        // Lock exists, retry
        const waitTime = HARD_LIMITS.STATE_LOCK_RETRY_MS;
        const start = Date.now();
        while (Date.now() - start < waitTime) { /* spin */ }
        continue;
      }
      // Other error, try to proceed
      return false;
    }
  }
  return false;
}

function releaseStateLock(): void {
  const lockPath = STATE_FILE_PATH + '.lock';
  try {
    fs.unlinkSync(lockPath);
  } catch {
    // Ignore
  }
}

// v0.5.3: Load state fresh from disk (not cached!)
function loadPersistentState(): PersistentState {
  const defaultState: PersistentState = {
    version: STATE_VERSION,
    lastInjectionTime: 0,
    sessionInjectionCounts: {},
    lastUpdated: new Date().toISOString(),
    stats: {
      totalInjections: 0,
      totalBlocked: 0,
      startupTime: Date.now(),
    },
  };

  try {
    if (fs.existsSync(STATE_FILE_PATH)) {
      const data = fs.readFileSync(STATE_FILE_PATH, 'utf-8');
      const loaded = JSON.parse(data);

      // Migrate old formats
      if (!loaded.version || loaded.version < STATE_VERSION) {
        const migrated: PersistentState = {
          ...defaultState,
          lastInjectionTime: loaded.lastInjectionTime || 0,
          sessionInjectionCounts: {},
          stats: loaded.stats || defaultState.stats,
        };

        for (const [sessionId, data] of Object.entries(loaded.sessionInjectionCounts || {})) {
          if (typeof data === 'number') {
            // v0.5.0 format
            migrated.sessionInjectionCounts[sessionId] = {
              count: data,
              lastUpdated: Date.now(),
            };
          } else if (typeof data === 'object' && data !== null) {
            // v0.5.1+ format
            migrated.sessionInjectionCounts[sessionId] = data as SessionInjectionData;
          }
        }

        return migrated;
      }

      return { ...defaultState, ...loaded };
    }
  } catch {
    // Corrupted state - start fresh
  }

  return defaultState;
}

function savePersistentState(state: PersistentState): boolean {
  if (!acquireStateLock()) {
    return false;
  }

  try {
    state.lastUpdated = new Date().toISOString();
    state.version = STATE_VERSION;
    pruneOldSessions(state);
    fs.writeFileSync(STATE_FILE_PATH, JSON.stringify(state, null, 2));
    return true;
  } catch {
    return false;
  } finally {
    releaseStateLock();
  }
}

function pruneOldSessions(state: PersistentState): void {
  const cutoff = Date.now() - (HARD_LIMITS.STATE_PRUNE_DAYS * 24 * 60 * 60 * 1000);
  const entries = Object.entries(state.sessionInjectionCounts);

  for (const [sessionId, data] of entries) {
    if (data.lastUpdated < cutoff) {
      delete state.sessionInjectionCounts[sessionId];
    }
  }

  const remaining = Object.entries(state.sessionInjectionCounts);
  if (remaining.length > HARD_LIMITS.STATE_MAX_SESSIONS) {
    remaining.sort((a, b) => a[1].lastUpdated - b[1].lastUpdated);
    const toRemove = remaining.slice(0, remaining.length - HARD_LIMITS.STATE_MAX_SESSIONS);
    for (const [sessionId] of toRemove) {
      delete state.sessionInjectionCounts[sessionId];
    }
  }
}

// v0.5.3: Get file birth time (creation time) - falls back to ctime
function getFileBirthTime(filePath: string): number {
  try {
    const stat = fs.statSync(filePath);
    // birthtime is the creation time, falls back to ctime on some systems
    return stat.birthtimeMs || stat.ctimeMs || stat.mtimeMs;
  } catch {
    return 0;
  }
}

// v0.5.3: Atomic read-check-increment with file birth time validation
function checkAndIncrementInjection(
  sessionId: string,
  sessionPath: string | null,
  logger: Logger
): { allowed: boolean; reason: string; count: number } {
  // ALWAYS read fresh state from disk
  const state = loadPersistentState();
  const sessionData = state.sessionInjectionCounts[sessionId];
  const currentCount = sessionData?.count ?? 0;

  // Check 1: Count limit
  if (currentCount >= HARD_LIMITS.MAX_INJECTIONS_PER_SESSION) {
    state.stats.totalBlocked++;
    savePersistentState(state);
    return {
      allowed: false,
      reason: `LAYER 2 BLOCK: Session ${sessionId.substring(0, 8)} has ${currentCount}/${HARD_LIMITS.MAX_INJECTIONS_PER_SESSION} injections`,
      count: currentCount,
    };
  }

  // Check 2: Global rate limit
  const timeSinceLastInjection = Date.now() - state.lastInjectionTime;
  if (timeSinceLastInjection < HARD_LIMITS.INJECTION_COOLDOWN_MS) {
    const waitTime = Math.round((HARD_LIMITS.INJECTION_COOLDOWN_MS - timeSinceLastInjection) / 1000);
    state.stats.totalBlocked++;
    savePersistentState(state);
    return {
      allowed: false,
      reason: `LAYER 3 BLOCK: Rate limited - ${waitTime}s remaining`,
      count: currentCount,
    };
  }

  // v0.5.3 Check 3: File birth time validation (detects recreated files)
  if (sessionPath && sessionData?.lastFileBirthTime) {
    const currentBirthTime = getFileBirthTime(sessionPath);
    if (currentBirthTime > sessionData.lastFileBirthTime) {
      // File was recreated after our last injection!
      logger.warn(`LAYER 6 BLOCK: Session file recreated (birth: ${currentBirthTime} > last: ${sessionData.lastFileBirthTime})`);
      // Mark as maxed out to prevent future attempts
      state.sessionInjectionCounts[sessionId] = {
        count: HARD_LIMITS.MAX_INJECTIONS_PER_SESSION,
        lastUpdated: Date.now(),
        lastFileBirthTime: currentBirthTime,
      };
      state.stats.totalBlocked++;
      savePersistentState(state);
      return {
        allowed: false,
        reason: `LAYER 6 BLOCK: Session file was recreated - blocking permanently`,
        count: HARD_LIMITS.MAX_INJECTIONS_PER_SESSION,
      };
    }
  }

  return {
    allowed: true,
    reason: 'All checks passed',
    count: currentCount,
  };
}

// v0.5.3: Record successful injection with file birth time
function recordInjection(sessionId: string, sessionPath: string | null, logger: Logger): void {
  // Re-read state to avoid race conditions
  const state = loadPersistentState();
  const fileBirthTime = sessionPath ? getFileBirthTime(sessionPath) : undefined;
  
  const existing = state.sessionInjectionCounts[sessionId];
  state.sessionInjectionCounts[sessionId] = {
    count: (existing?.count ?? 0) + 1,
    lastUpdated: Date.now(),
    lastFileBirthTime: fileBirthTime || existing?.lastFileBirthTime,
  };
  state.lastInjectionTime = Date.now();
  state.stats.totalInjections++;
  
  if (!savePersistentState(state)) {
    logger.warn('Failed to persist injection state - may cause duplicate injections');
  }
}

// =============================================================================
// v0.5.1: ONELIST CIRCUIT BREAKER
// =============================================================================

interface CircuitBreakerState {
  consecutiveFailures: number;
  lastFailureTime: number;
  backoffUntil: number;
  totalFailures: number;
  totalSuccesses: number;
}

const onelistCircuitBreaker: CircuitBreakerState = {
  consecutiveFailures: 0,
  lastFailureTime: 0,
  backoffUntil: 0,
  totalFailures: 0,
  totalSuccesses: 0,
};

function shouldSkipOnelist(): boolean {
  return onelistCircuitBreaker.backoffUntil > Date.now();
}

function recordOnelistSuccess(): void {
  onelistCircuitBreaker.consecutiveFailures = 0;
  onelistCircuitBreaker.backoffUntil = 0;
  onelistCircuitBreaker.totalSuccesses++;
}

function recordOnelistFailure(): void {
  onelistCircuitBreaker.consecutiveFailures++;
  onelistCircuitBreaker.lastFailureTime = Date.now();
  onelistCircuitBreaker.totalFailures++;

  if (onelistCircuitBreaker.consecutiveFailures >= HARD_LIMITS.ONELIST_MAX_CONSECUTIVE_FAILURES) {
    const backoffMultiplier = Math.pow(2, onelistCircuitBreaker.consecutiveFailures - HARD_LIMITS.ONELIST_MAX_CONSECUTIVE_FAILURES);
    const backoffMs = Math.min(
      HARD_LIMITS.ONELIST_INITIAL_BACKOFF_MS * backoffMultiplier,
      HARD_LIMITS.ONELIST_MAX_BACKOFF_MS
    );
    onelistCircuitBreaker.backoffUntil = Date.now() + backoffMs;
  }
}

// =============================================================================
// CONTENT BLOCKLIST PATTERNS
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
// LOGGING
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
// DEFENSE LAYERS (kept for additional protection)
// =============================================================================

function sessionAlreadyHasInjection(sessionPath: string, logger: Logger): boolean {
  try {
    if (!fs.existsSync(sessionPath)) return false;
    const content = fs.readFileSync(sessionPath, 'utf-8');
    if (content.includes('[INJECTION-DEPTH:')) {
      logger.info('LAYER 1 BLOCK: Session already contains injection marker');
      return true;
    }
    if (content.includes('## 🔄 Recovered Conversation Context')) {
      logger.info('LAYER 1 BLOCK: Session already contains recovery header');
      return true;
    }
    return false;
  } catch (err) {
    logger.warn(`LAYER 1: Could not read session file: ${String(err)}`);
    return true; // Fail closed
  }
}

function sessionTooLargeForInjection(sessionPath: string, logger: Logger): boolean {
  try {
    if (!fs.existsSync(sessionPath)) return false;
    const stats = fs.statSync(sessionPath);
    if (stats.size > HARD_LIMITS.MAX_SESSION_SIZE_FOR_INJECT) {
      logger.info(`LAYER 4 BLOCK: Session size ${stats.size} > ${HARD_LIMITS.MAX_SESSION_SIZE_FOR_INJECT}`);
      return true;
    }
    const content = fs.readFileSync(sessionPath, 'utf-8');
    const messageCount = (content.match(/"type":"message"/g) || []).length;
    if (messageCount > HARD_LIMITS.MAX_SESSION_MESSAGES_FOR_INJECT) {
      logger.info(`LAYER 4 BLOCK: Session has ${messageCount} > ${HARD_LIMITS.MAX_SESSION_MESSAGES_FOR_INJECT} messages`);
      return true;
    }
    return false;
  } catch (err) {
    logger.warn(`LAYER 4: Could not check session size: ${String(err)}`);
    return false;
  }
}

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
    return { path: files[0].path, id: files[0].name.replace('.jsonl', '') };
  } catch {
    return null;
  }
}

// =============================================================================
// HEALTH LOGGING
// =============================================================================

function logStartupHealth(logger: Logger): void {
  const state = loadPersistentState();
  const sessionCount = Object.keys(state.sessionInjectionCounts).length;

  logger.info(`=== HEALTH: v0.5.3 | Sessions tracked: ${sessionCount} | Injections: ${state.stats.totalInjections} | Blocked: ${state.stats.totalBlocked} ===`);
}

let lastHealthLog = 0;
const HEALTH_LOG_INTERVAL = 3600000;

function maybeLogHealth(logger: Logger): void {
  if (Date.now() - lastHealthLog > HEALTH_LOG_INTERVAL) {
    logStartupHealth(logger);
    lastHealthLog = Date.now();
  }
}

// =============================================================================
// MAIN PLUGIN REGISTRATION
// =============================================================================

console.log('[onelist-memory] Plugin file loaded (v0.5.3 hardened - fresh state reads + file birth tracking)');

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

  // Log startup health (reads fresh from disk)
  logStartupHealth(logger);
  lastHealthLog = Date.now();

  // =========================================================================
  // AUTO-INJECT RECOVERY HOOK (v0.5.3: Fresh state reads)
  // =========================================================================

  const autoInjectEnabled = config.autoInjectEnabled !== false;

  if (autoInjectEnabled) {
    logger.info('Registering auto-inject recovery hook (v0.5.3 hardened)');

    try {
      api.on('before_agent_start', async (event: any, ctx: any): Promise<{ prependContext?: string } | undefined> => {
        const startTime = Date.now();
        const sessionsDir = findSessionsDirectory(logger);

        maybeLogHealth(logger);

        if (!sessionsDir) {
          logger.debug('No sessions directory found');
          return undefined;
        }

        const currentSession = findCurrentSessionFile(sessionsDir);
        const sessionId = currentSession?.id ?? 'unknown';
        const sessionPath = currentSession?.path ?? null;

        logger.debug(`Current session: ${sessionId}`);

        // v0.5.3: Atomic check with fresh state read
        const checkResult = checkAndIncrementInjection(sessionId, sessionPath, logger);
        if (!checkResult.allowed) {
          logger.info(checkResult.reason);
          return undefined;
        }

        // LAYER 1: Session content pre-check (still useful as additional defense)
        if (sessionPath && sessionAlreadyHasInjection(sessionPath, logger)) {
          // Sync state: mark session as maxed if file has markers but state doesn't reflect it
          const state = loadPersistentState();
          if ((state.sessionInjectionCounts[sessionId]?.count ?? 0) < HARD_LIMITS.MAX_INJECTIONS_PER_SESSION) {
            state.sessionInjectionCounts[sessionId] = {
              count: HARD_LIMITS.MAX_INJECTIONS_PER_SESSION,
              lastUpdated: Date.now(),
              lastFileBirthTime: getFileBirthTime(sessionPath),
            };
            state.stats.totalBlocked++;
            savePersistentState(state);
          }
          return undefined;
        }

        // LAYER 4: Session size check
        if (sessionPath && sessionTooLargeForInjection(sessionPath, logger)) {
          const state = loadPersistentState();
          state.stats.totalBlocked++;
          savePersistentState(state);
          return undefined;
        }

        logger.info(`All pre-checks passed for session ${sessionId.substring(0, 8)} - recovering context`);

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
            logger.warn(`Recovery had ${result.errors.length} errors: ${result.errors.slice(0, 3).join('; ')}`);
          }

          // LAYER 5: Output size check
          const contentSize = result.content.length;
          if (contentSize > HARD_LIMITS.MAX_RECOVERY_OUTPUT_CHARS) {
            logger.error(`LAYER 5 BLOCK: Output ${contentSize} > ${HARD_LIMITS.MAX_RECOVERY_OUTPUT_CHARS} chars`);
            const state = loadPersistentState();
            state.stats.totalBlocked++;
            savePersistentState(state);
            return undefined;
          }

          const recoveryMarkerCount = (result.content.match(/Recovered Conversation Context/gi) || []).length;
          if (recoveryMarkerCount > 1) {
            logger.error(`LAYER 5 BLOCK: ${recoveryMarkerCount} nested recovery markers detected`);
            const state = loadPersistentState();
            state.stats.totalBlocked++;
            savePersistentState(state);
            return undefined;
          }

          // SUCCESS - record the injection
          logger.info(`INJECTION APPROVED: ${result.messageCount} msgs, ${result.filesProcessed} files, ${contentSize} chars, ${elapsed}ms`);
          recordInjection(sessionId, sessionPath, logger);

          return { prependContext: result.content };

        } catch (err) {
          const elapsed = Date.now() - startTime;
          logger.error(`Recovery failed (${elapsed}ms): ${String(err)}`);
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

  startOnelistSync(config, api, logger).catch(err => {
    logger.error(`Onelist sync startup failed: ${String(err)}`);
  });
}

// =============================================================================
// AUTO-INJECT RECOVERY
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

  const cutoffTime = Date.now() - (hoursBack * 60 * 60 * 1000);

  let sessionFiles: Array<{ name: string; path: string; mtime: number; size: number }>;

  try {
    const files = fs.readdirSync(sessionsDir);

    sessionFiles = files
      .filter(f => {
        if (!f.endsWith('.jsonl')) return false;
        if (f.includes('.deleted') || f.includes('.lock') || f.includes('.archived')) return false;
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
      .filter(f => f.mtime >= cutoffTime && f.size <= maxFileSize)
      .sort((a, b) => b.mtime - a.mtime);

  } catch (err) {
    errors.push(`Failed to list sessions: ${String(err)}`);
    logger.error(`Failed to list sessions: ${String(err)}`);
    return null;
  }

  if (sessionFiles.length === 0) {
    logger.debug(`No session files within ${hoursBack} hours`);
    return null;
  }

  const allMessages: ParsedMessage[] = [];
  let totalBytesRead = 0;
  let filesProcessed = 0;

  for (const file of sessionFiles) {
    if (totalBytesRead + file.size > maxTotalRead) break;
    if (allMessages.length >= messageCount * 2) break;

    try {
      const messages = parseSessionFileSafe(file.path, file.name, logger, errors);
      allMessages.push(...messages);
      totalBytesRead += file.size;
      filesProcessed++;
    } catch (err) {
      errors.push(`Error parsing ${file.name}: ${String(err)}`);
    }
  }

  if (allMessages.length < minMessages) {
    logger.debug(`Only ${allMessages.length} messages, below minimum ${minMessages}`);
    return null;
  }

  allMessages.sort((a, b) => parseTimestampSafe(a.timestamp) - parseTimestampSafe(b.timestamp));

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
    } catch {
      // Continue
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

  const lines = content.split(/\r?\n/).slice(0, HARD_LIMITS.MAX_LINES_PER_FILE);
  let parseErrors = 0;

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    let entry: SessionMessage;
    try {
      entry = JSON.parse(trimmed);
    } catch {
      parseErrors++;
      continue;
    }

    if (typeof entry !== 'object' || entry === null) continue;
    if (entry.type !== 'message') continue;
    if (!entry.message || typeof entry.message !== 'object') continue;

    const role = entry.message.role;
    if (role !== 'user' && role !== 'assistant') continue;

    const textContent = extractTextContent(entry.message.content);
    if (!textContent) continue;

    if (MESSAGE_BLOCKLIST_PATTERNS.some(p => p.test(textContent))) {
      continue;
    }

    const { filtered: filteredContent, removedCount } = filterMediaReferences(textContent);

    if (!filteredContent || filteredContent.length < 10) {
      if (removedCount > 0) continue;
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
    errors.push(`${fileName}: ${parseErrors} JSON parse errors`);
  }

  return messages;
}

function extractTextContent(content: unknown): string {
  if (!content) return '';
  if (typeof content === 'string') return content.trim();

  if (Array.isArray(content)) {
    const textParts: string[] = [];
    for (const item of content) {
      if (item?.type === 'text' && typeof item.text === 'string') {
        textParts.push(item.text);
      }
    }
    return textParts.join('\n').trim();
  }

  return '';
}

function filterMediaReferences(content: string): { filtered: string; removedCount: number } {
  const lines = content.split('\n');
  let removedCount = 0;
  const filtered = lines.filter(line => {
    if (FILTER_PATTERNS.some(p => p.test(line))) {
      removedCount++;
      return false;
    }
    return true;
  });

  return { filtered: filtered.join('\n').trim(), removedCount };
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

  let header = `[INJECTION-DEPTH:0][v0.5.3]

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
// ONELIST SYNC (with circuit breaker)
// =============================================================================

const syncState = new Map<string, { lastLineCount: number; lastTimestamp: string }>();

function prunesSyncState(): void {
  if (syncState.size > HARD_LIMITS.SYNC_STATE_MAX_ENTRIES) {
    const entries = Array.from(syncState.entries());
    const toRemove = entries.slice(0, Math.floor(entries.length / 2));
    for (const [key] of toRemove) {
      syncState.delete(key);
    }
  }
}

async function startOnelistSync(config: PluginConfig, api: any, logger: Logger): Promise<void> {
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

  try {
    const watcher = fs.watch(sessionsDir, { persistent: true }, async (eventType, filename) => {
      if (!filename) return;
      if (!filename.endsWith('.jsonl')) return;
      if (filename.includes('.deleted') || filename.includes('.lock') || filename.includes('.archived')) return;

      if (shouldSkipOnelist()) {
        return;
      }

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
      if (shouldSkipOnelist()) break;
      const filePath = path.join(sessionsDir, file);
      syncSessionFile(filePath, config, logger).catch(() => {});
    }
  } catch (err) {
    logger.error(`Failed initial sync: ${String(err)}`);
  }

  logger.info(`Watching ${sessionsDir} for session changes`);
}

async function syncSessionFile(filePath: string, config: PluginConfig, logger: Logger): Promise<void> {
  prunesSyncState();

  const state = syncState.get(filePath) || { lastLineCount: 0, lastTimestamp: '' };

  let content: string;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch {
    return;
  }

  const lines = content.trim().split('\n');
  if (lines.length <= state.lastLineCount) return;

  const newLines = lines.slice(state.lastLineCount);
  const messages: SessionMessage[] = [];

  for (const line of newLines) {
    try {
      const parsed = JSON.parse(line) as SessionMessage;
      if (parsed.type === 'message' && parsed.message) {
        messages.push(parsed);
      }
    } catch {
      // Skip
    }
  }

  if (messages.length === 0) {
    syncState.set(filePath, { lastLineCount: lines.length, lastTimestamp: state.lastTimestamp });
    return;
  }

  const sessionId = config.sessionId || path.basename(filePath, '.jsonl');

  for (const msg of messages) {
    if (shouldSkipOnelist()) {
      logger.debug('Onelist circuit breaker open - skipping sync');
      break;
    }

    try {
      await sendToOnelist(config, sessionId, msg, logger);
      recordOnelistSuccess();
    } catch (err) {
      recordOnelistFailure();
      if (onelistCircuitBreaker.consecutiveFailures <= 3) {
        logger.error(`Onelist sync failed: ${String(err)}`);
      } else if (onelistCircuitBreaker.consecutiveFailures === HARD_LIMITS.ONELIST_MAX_CONSECUTIVE_FAILURES) {
        const backoffMin = Math.round((onelistCircuitBreaker.backoffUntil - Date.now()) / 60000);
        logger.warn(`Onelist circuit breaker OPEN - backing off for ${backoffMin}m`);
      }
    }
  }

  syncState.set(filePath, {
    lastLineCount: lines.length,
    lastTimestamp: messages[messages.length - 1]?.timestamp || state.lastTimestamp,
  });
}

async function sendToOnelist(config: PluginConfig, sessionId: string, msg: SessionMessage, logger: Logger): Promise<void> {
  if (!config.apiUrl || !config.apiKey) {
    throw new Error('Missing API credentials');
  }

  const url = `${config.apiUrl}/api/v1/chat-stream/append`;
  const content = extractTextContent(msg.message?.content);
  if (!content) return;

  const telegramMetadata = extractTelegramMetadata(content, sessionId);

  const payload = {
    session_id: sessionId,
    message: {
      role: msg.message?.role || 'unknown',
      content: content,
      timestamp: msg.timestamp,
      message_id: msg.id,
      source: telegramMetadata,
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
      throw new Error(`HTTP ${response.status}: ${text.slice(0, 100)}`);
    }
  } finally {
    clearTimeout(timeout);
  }
}
