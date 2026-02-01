/**
 * Onelist Memory Sync Plugin v0.2.1
 * 
 * BULLETPROOF EDITION - Hardened for production reliability
 * 
 * Features:
 * 1. AUTO-INJECT RECOVERY: On session start, automatically injects recent
 *    conversation context into the agent's context. Ensures continuity
 *    after compaction without requiring manual recovery.
 * 
 * 2. ONELIST SYNC: Streams chat messages to Onelist for persistent
 *    memory extraction.
 * 
 * Design Principles:
 * - Fail gracefully: Never crash the session, never block startup
 * - Log everything: Every decision, every failure, observable behavior
 * - Defensive parsing: Assume all input is malformed
 * - Resource limits: Cap memory usage, file reads, processing time
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
  // Auto-inject recovery configuration
  autoInjectEnabled?: boolean;        // Default: true
  autoInjectMessageCount?: number;    // Default: 50
  autoInjectHoursBack?: number;       // Default: 24
  autoInjectMinMessages?: number;     // Minimum messages to trigger inject (default: 5)
  // Safety limits
  maxFileSizeBytes?: number;          // Default: 10MB per file
  maxTotalReadBytes?: number;         // Default: 50MB total
  maxMessageLength?: number;          // Default: 4000 chars per message
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
  source: string; // Which file it came from
}

interface RecoveryResult {
  content: string;
  messageCount: number;
  filesProcessed: number;
  errors: string[];
}

// Resource limits (hardcoded safety rails)
const HARD_LIMITS = {
  MAX_FILE_SIZE: 10 * 1024 * 1024,     // 10MB per file
  MAX_TOTAL_READ: 50 * 1024 * 1024,    // 50MB total across all files
  MAX_MESSAGE_LENGTH: 4000,             // Chars per message in output
  MAX_FILES_TO_SCAN: 100,               // Don't scan more than 100 session files
  MAX_LINES_PER_FILE: 10000,            // Don't parse more than 10k lines per file
  HOOK_TIMEOUT_MS: 5000,                // Recovery must complete in 5s
};

// Track sync state per session file (for Onelist sync)
const syncState = new Map<string, {
  lastLineCount: number;
  lastTimestamp: string;
}>();

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
// MAIN PLUGIN REGISTRATION
// =============================================================================

console.log('[onelist-memory] Plugin file loaded (v0.2.1 bulletproof)');

export default function register(api: any) {
  const logger: Logger = api?.logger ?? createFallbackLogger();
  
  logger.info('Register function called');
  
  const pluginId = 'onelist-memory';
  let config: PluginConfig;
  
  // Safely extract config with fallbacks
  try {
    config = (api?.config?.plugins?.entries?.[pluginId]?.config as PluginConfig) ?? {};
  } catch (err) {
    logger.warn(`Failed to read plugin config, using defaults: ${String(err)}`);
    config = {};
  }
  
  // Check if plugin is explicitly disabled
  if (config.enabled === false) {
    logger.info('Plugin explicitly disabled in config');
    return;
  }
  
  // =========================================================================
  // AUTO-INJECT RECOVERY HOOK
  // =========================================================================
  
  const autoInjectEnabled = config.autoInjectEnabled !== false; // Default: true
  
  if (autoInjectEnabled) {
    logger.info('Registering auto-inject recovery hook');
    
    try {
      api.on('before_agent_start', async (event: any, ctx: any): Promise<{ prependContext?: string } | undefined> => {
        const startTime = Date.now();
        
        try {
          // Wrap recovery in a timeout
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
          
          // Log recovery stats
          if (result.errors.length > 0) {
            logger.warn(`Recovery completed with ${result.errors.length} errors: ${result.errors.slice(0, 3).join('; ')}`);
          }
          
          logger.info(`Auto-injecting ${result.messageCount} messages from ${result.filesProcessed} files (${elapsed}ms)`);
          
          return { prependContext: result.content };
          
        } catch (err) {
          const elapsed = Date.now() - startTime;
          
          // Categorize the error
          const errStr = String(err);
          if (errStr.includes('timeout')) {
            logger.error(`Recovery timed out after ${elapsed}ms - skipping injection`);
          } else {
            logger.error(`Recovery failed after ${elapsed}ms: ${errStr}`);
          }
          
          // CRITICAL: Never throw from the hook - just skip injection
          return undefined;
        }
      }, { priority: 100 });
      
      logger.info('Auto-inject hook registered successfully');
      
    } catch (err) {
      logger.error(`Failed to register auto-inject hook: ${String(err)}`);
      // Don't throw - let the plugin continue without this feature
    }
  } else {
    logger.info('Auto-inject disabled in config');
  }
  
  // =========================================================================
  // ONELIST SYNC (optional)
  // =========================================================================
  
  startOnlistSync(config, api, logger).catch(err => {
    logger.error(`Onelist sync startup failed: ${String(err)}`);
    // Don't throw - sync is optional
  });
}

// =============================================================================
// AUTO-INJECT RECOVERY IMPLEMENTATION
// =============================================================================

/**
 * Recover recent conversation context from session files.
 * 
 * Design: Defensive, resource-limited, never throws.
 */
async function recoverContext(config: PluginConfig, logger: Logger): Promise<RecoveryResult | null> {
  const messageCount = Math.min(config.autoInjectMessageCount ?? 50, 200); // Cap at 200
  const hoursBack = Math.min(config.autoInjectHoursBack ?? 24, 168); // Cap at 1 week
  const minMessages = config.autoInjectMinMessages ?? 5;
  const maxFileSize = Math.min(config.maxFileSizeBytes ?? HARD_LIMITS.MAX_FILE_SIZE, HARD_LIMITS.MAX_FILE_SIZE);
  const maxTotalRead = Math.min(config.maxTotalReadBytes ?? HARD_LIMITS.MAX_TOTAL_READ, HARD_LIMITS.MAX_TOTAL_READ);
  
  const errors: string[] = [];
  
  // Find sessions directory
  const sessionsDir = findSessionsDirectory(logger);
  
  if (!sessionsDir) {
    logger.debug('Sessions directory not found - no context to recover');
    return null;
  }
  
  logger.debug(`Using sessions directory: ${sessionsDir}`);
  
  // Calculate cutoff time
  const cutoffTime = Date.now() - (hoursBack * 60 * 60 * 1000);
  
  // List and filter session files
  let sessionFiles: Array<{ name: string; path: string; mtime: number; size: number }>;
  
  try {
    const files = fs.readdirSync(sessionsDir);
    
    sessionFiles = files
      .filter(f => {
        // Only .jsonl files, not deleted/lock files
        if (!f.endsWith('.jsonl')) return false;
        if (f.includes('.deleted')) return false;
        if (f.includes('.lock')) return false;
        return true;
      })
      .slice(0, HARD_LIMITS.MAX_FILES_TO_SCAN) // Safety limit
      .map(f => {
        const filePath = path.join(sessionsDir, f);
        try {
          const stat = fs.statSync(filePath);
          return {
            name: f,
            path: filePath,
            mtime: stat.mtimeMs,
            size: stat.size,
          };
        } catch (err) {
          errors.push(`stat failed for ${f}: ${String(err)}`);
          return null;
        }
      })
      .filter((f): f is NonNullable<typeof f> => f !== null)
      .filter(f => f.mtime >= cutoffTime)
      .filter(f => f.size <= maxFileSize)
      .sort((a, b) => b.mtime - a.mtime); // Most recent first
      
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
  
  // Parse messages from files (with resource limits)
  const allMessages: ParsedMessage[] = [];
  let totalBytesRead = 0;
  let filesProcessed = 0;
  
  for (const file of sessionFiles) {
    // Check total bytes limit
    if (totalBytesRead + file.size > maxTotalRead) {
      logger.debug(`Skipping ${file.name}: would exceed total read limit`);
      break;
    }
    
    // Check if we have enough messages
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
      // This shouldn't happen since parseSessionFileSafe catches internally,
      // but belt-and-suspenders
      errors.push(`Unexpected error parsing ${file.name}: ${String(err)}`);
    }
  }
  
  if (allMessages.length < minMessages) {
    logger.debug(`Only ${allMessages.length} messages found, below minimum ${minMessages}`);
    return null;
  }
  
  // Sort by timestamp (best effort - timestamps may be missing/malformed)
  allMessages.sort((a, b) => {
    const timeA = parseTimestampSafe(a.timestamp);
    const timeB = parseTimestampSafe(b.timestamp);
    return timeA - timeB; // Oldest first for now, we'll reverse after slicing
  });
  
  // Take the most recent N messages
  const recentMessages = allMessages.slice(-messageCount);
  
  // Format for context injection
  const formattedContext = formatRecoveredContext(recentMessages, hoursBack, filesProcessed, errors.length);
  
  return {
    content: formattedContext,
    messageCount: recentMessages.length,
    filesProcessed,
    errors,
  };
}

/**
 * Find the sessions directory. Checks multiple possible locations.
 */
function findSessionsDirectory(logger: Logger): string | null {
  const candidates = [
    '/root/.openclaw/agents/main/sessions',
    path.join(process.env.HOME || '', '.openclaw', 'agents', 'main', 'sessions'),
    // Add more fallbacks if needed
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

/**
 * Parse a session JSONL file safely. Never throws.
 */
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
  
  // Split into lines (handle both \n and \r\n)
  const lines = content.split(/\r?\n/);
  
  // Limit lines processed per file
  const linesToProcess = lines.slice(0, HARD_LIMITS.MAX_LINES_PER_FILE);
  
  if (lines.length > HARD_LIMITS.MAX_LINES_PER_FILE) {
    errors.push(`${fileName}: truncated to ${HARD_LIMITS.MAX_LINES_PER_FILE} lines (had ${lines.length})`);
  }
  
  let lineNum = 0;
  let parseErrors = 0;
  
  for (const line of linesToProcess) {
    lineNum++;
    
    // Skip empty lines
    const trimmed = line.trim();
    if (!trimmed) continue;
    
    // Parse JSON
    let entry: SessionMessage;
    try {
      entry = JSON.parse(trimmed);
    } catch {
      parseErrors++;
      if (parseErrors <= 3) {
        // Only log first few parse errors per file
        errors.push(`${fileName}:${lineNum}: invalid JSON`);
      }
      continue;
    }
    
    // Validate structure
    if (typeof entry !== 'object' || entry === null) continue;
    if (entry.type !== 'message') continue;
    if (!entry.message || typeof entry.message !== 'object') continue;
    
    const role = entry.message.role;
    if (role !== 'user' && role !== 'assistant') continue;
    
    // Extract content safely
    const textContent = extractTextContent(entry.message.content);
    if (!textContent) continue;
    
    // Truncate very long messages
    const truncated = textContent.length > HARD_LIMITS.MAX_MESSAGE_LENGTH
      ? textContent.substring(0, HARD_LIMITS.MAX_MESSAGE_LENGTH) + '\n[...truncated...]'
      : textContent;
    
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

/**
 * Extract text content from various content formats.
 * Handles: string, array with text objects, null, undefined.
 */
function extractTextContent(content: unknown): string {
  if (!content) return '';
  
  if (typeof content === 'string') {
    return content.trim();
  }
  
  if (Array.isArray(content)) {
    // Content array format: [{ type: 'text', text: '...' }, { type: 'toolCall', ... }, ...]
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
  
  // Unknown format
  return '';
}

/**
 * Parse a timestamp string to epoch ms. Returns 0 on failure (sorts to beginning).
 */
function parseTimestampSafe(timestamp: string): number {
  if (!timestamp) return 0;
  
  try {
    const parsed = new Date(timestamp).getTime();
    return isNaN(parsed) ? 0 : parsed;
  } catch {
    return 0;
  }
}

/**
 * Format recovered messages into a context block for injection.
 */
function formatRecoveredContext(
  messages: ParsedMessage[],
  hoursBack: number,
  filesProcessed: number,
  errorCount: number
): string {
  const now = new Date().toISOString();
  
  let header = `## 🔄 Recovered Conversation Context

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
// ONELIST SYNC IMPLEMENTATION (existing functionality, hardened)
// =============================================================================

async function startOnlistSync(config: PluginConfig, api: any, logger: Logger): Promise<void> {
  // Onelist sync requires API credentials
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
      if (filename.includes('.deleted') || filename.includes('.lock')) return;
      
      const filePath = path.join(sessionsDir, filename);
      
      try {
        await syncSessionFile(filePath, config, logger);
      } catch (err) {
        logger.error(`Error syncing ${filename}: ${String(err)}`);
      }
    });
    
    // Handle watcher errors
    watcher.on('error', (err) => {
      logger.error(`Watcher error: ${String(err)}`);
    });
    
  } catch (err) {
    logger.error(`Failed to create watcher: ${String(err)}`);
    return;
  }
  
  // Initial sync of existing files
  try {
    const files = fs.readdirSync(sessionsDir)
      .filter(f => f.endsWith('.jsonl') && !f.includes('.deleted') && !f.includes('.lock'));
    
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
  
  // Read the file
  let content: string;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch (err) {
    // File might have been deleted, ignore
    return;
  }
  
  const lines = content.trim().split('\n');
  
  if (lines.length <= state.lastLineCount) {
    return; // No new lines
  }
  
  // Process only new lines
  const newLines = lines.slice(state.lastLineCount);
  const messages: SessionMessage[] = [];
  
  for (const line of newLines) {
    try {
      const parsed = JSON.parse(line) as SessionMessage;
      if (parsed.type === 'message' && parsed.message) {
        messages.push(parsed);
      }
    } catch {
      // Skip invalid JSON lines
    }
  }
  
  if (messages.length === 0) {
    syncState.set(filePath, { lastLineCount: lines.length, lastTimestamp: state.lastTimestamp });
    return;
  }
  
  // Extract session ID from filename or use config
  const sessionId = config.sessionId || path.basename(filePath, '.jsonl');
  
  // Send messages to Onelist
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
  
  // Update state
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
  
  // Extract content
  const content = extractTextContent(msg.message?.content);
  if (!content) return; // Skip empty messages
  
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
  const timeout = setTimeout(() => controller.abort(), 10000); // 10s timeout
  
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
