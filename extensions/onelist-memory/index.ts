/**
 * Onelist Memory Sync Plugin v1.0.0
 *
 * QUERY-BASED RETRIEVAL EDITION
 *
 * v1.0.0 MAJOR UPGRADE (Smart Retrieval):
 *   - NEW: Query-based context retrieval from Onelist Search API
 *   - NEW: Semantic + keyword hybrid search for relevant memories
 *   - NEW: Extracts query intent from recent conversation
 *   - NEW: Retrieves atomic memories instead of raw messages
 *   - NEW: 95%+ token savings vs dumb injection
 *   - KEPT: All livelog sync functionality from v0.5.7
 *   - KEPT: Feedback loop protection (simplified - search API is bounded)
 *   - KEPT: Circuit breaker, main session filtering
 *
 * v0.5.7 and earlier: See git history
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

  // v1.0: Smart retrieval config
  smartRetrievalEnabled?: boolean;
  retrievalLimit?: number;           // Max memories to retrieve (default: 10)
  retrievalThreshold?: number;       // Min relevance score 0-1 (default: 0.5)
  retrievalSearchType?: 'hybrid' | 'semantic' | 'keyword';

  // Legacy: Fallback to dumb injection if search fails
  fallbackEnabled?: boolean;
  autoInjectMessageCount?: number;
  autoInjectHoursBack?: number;
  autoInjectMinMessages?: number;

  // Limits
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

// v1.0: Onelist Search API types
interface OnelistSearchResult {
  entry_id: string;
  title: string;
  entry_type: string;
  score: number;
  semantic_score?: number;
  keyword_score?: number;
}

interface OnelistSearchResponse {
  success: boolean;
  data?: {
    results: OnelistSearchResult[];
    total: number;
    query: string;
    search_type: string;
  };
  error?: {
    message: string;
    code?: string;
  };
}

// v1.0: Memory retrieval result
interface MemoryRetrievalResult {
  content: string;
  memoriesRetrieved: number;
  searchQuery: string;
  searchType: string;
  source: 'onelist_search' | 'fallback_files';
}

interface RecoveryResult {
  content: string;
  messageCount: number;
  filesProcessed: number;
  errors: string[];
}

// =============================================================================
// v0.5.2: TELEGRAM METADATA EXTRACTION (kept as-is)
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

  // v1.0: Simplified - search API is inherently bounded
  MAX_INJECTIONS_PER_SESSION: 5,  // Raised - search results are small
  INJECTION_COOLDOWN_MS: 30000,   // Reduced - less risk with bounded results

  STATE_MAX_SESSIONS: 100,
  STATE_PRUNE_DAYS: 7,
  SYNC_STATE_MAX_ENTRIES: 50,

  ONELIST_MAX_CONSECUTIVE_FAILURES: 5,
  ONELIST_INITIAL_BACKOFF_MS: 60000,
  ONELIST_MAX_BACKOFF_MS: 3600000,

  STATE_LOCK_TIMEOUT_MS: 5000,
  STATE_LOCK_RETRY_MS: 50,

  // v1.0: Search limits
  SEARCH_TIMEOUT_MS: 8000,
  MAX_QUERY_LENGTH: 500,
  DEFAULT_RETRIEVAL_LIMIT: 10,
  DEFAULT_RETRIEVAL_THRESHOLD: 0.5,
};

// =============================================================================
// PATHS - Respect user's OpenClaw installation location
// =============================================================================

// Get OpenClaw home directory from environment or fall back to ~/.openclaw
function getOpenClawHome(): string {
  // OPENCLAW_HOME is the standard env var (used by OCTO)
  if (process.env.OPENCLAW_HOME) {
    return process.env.OPENCLAW_HOME;
  }
  // Fall back to ~/.openclaw
  const home = process.env.HOME || process.env.USERPROFILE || '/root';
  return path.join(home, '.openclaw');
}

const OPENCLAW_HOME = getOpenClawHome();

// =============================================================================
// PERSISTENT STATE (simplified for v1.0)
// =============================================================================

const STATE_FILE_PATH = path.join(OPENCLAW_HOME, 'onelist-memory-state.json');
const STATE_VERSION = 3; // v1.0 schema

interface SessionInjectionData {
  count: number;
  lastUpdated: number;
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
    totalSearches: number;      // v1.0
    totalSearchHits: number;    // v1.0
    totalFallbacks: number;     // v1.0
    startupTime: number;
  };
}

function acquireStateLock(timeoutMs: number = HARD_LIMITS.STATE_LOCK_TIMEOUT_MS): boolean {
  const lockPath = STATE_FILE_PATH + '.lock';
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    try {
      if (fs.existsSync(lockPath)) {
        const lockStat = fs.statSync(lockPath);
        if (Date.now() - lockStat.mtimeMs > 10000) {
          fs.unlinkSync(lockPath);
        } else {
          const waitTime = HARD_LIMITS.STATE_LOCK_RETRY_MS;
          const start = Date.now();
          while (Date.now() - start < waitTime) { /* spin */ }
          continue;
        }
      }
      fs.writeFileSync(lockPath, String(process.pid), { flag: 'wx' });
      return true;
    } catch (err: any) {
      if (err.code === 'EEXIST') {
        const waitTime = HARD_LIMITS.STATE_LOCK_RETRY_MS;
        const start = Date.now();
        while (Date.now() - start < waitTime) { /* spin */ }
        continue;
      }
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

function loadPersistentState(): PersistentState {
  const defaultState: PersistentState = {
    version: STATE_VERSION,
    lastInjectionTime: 0,
    sessionInjectionCounts: {},
    lastUpdated: new Date().toISOString(),
    stats: {
      totalInjections: 0,
      totalBlocked: 0,
      totalSearches: 0,
      totalSearchHits: 0,
      totalFallbacks: 0,
      startupTime: Date.now(),
    },
  };

  try {
    if (fs.existsSync(STATE_FILE_PATH)) {
      const data = fs.readFileSync(STATE_FILE_PATH, 'utf-8');
      const loaded = JSON.parse(data);

      if (!loaded.version || loaded.version < STATE_VERSION) {
        // Migrate from older versions
        const migrated: PersistentState = {
          ...defaultState,
          lastInjectionTime: loaded.lastInjectionTime || 0,
          sessionInjectionCounts: {},
          stats: {
            ...defaultState.stats,
            totalInjections: loaded.stats?.totalInjections || 0,
            totalBlocked: loaded.stats?.totalBlocked || 0,
          },
        };

        for (const [sessionId, data] of Object.entries(loaded.sessionInjectionCounts || {})) {
          if (typeof data === 'number') {
            migrated.sessionInjectionCounts[sessionId] = {
              count: data,
              lastUpdated: Date.now(),
            };
          } else if (typeof data === 'object' && data !== null) {
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

function getFileBirthTime(filePath: string): number {
  try {
    const stat = fs.statSync(filePath);
    return stat.birthtimeMs || stat.ctimeMs || stat.mtimeMs;
  } catch {
    return 0;
  }
}

function checkInjectionAllowed(
  sessionId: string,
  sessionPath: string | null,
  logger: Logger
): { allowed: boolean; reason: string; count: number } {
  const state = loadPersistentState();
  const sessionData = state.sessionInjectionCounts[sessionId];
  const currentCount = sessionData?.count ?? 0;

  // Check 1: Count limit (raised for v1.0 since results are bounded)
  if (currentCount >= HARD_LIMITS.MAX_INJECTIONS_PER_SESSION) {
    state.stats.totalBlocked++;
    savePersistentState(state);
    return {
      allowed: false,
      reason: `Session ${sessionId.substring(0, 8)} at injection limit (${currentCount}/${HARD_LIMITS.MAX_INJECTIONS_PER_SESSION})`,
      count: currentCount,
    };
  }

  // Check 2: Global rate limit
  const timeSinceLastInjection = Date.now() - state.lastInjectionTime;
  if (timeSinceLastInjection < HARD_LIMITS.INJECTION_COOLDOWN_MS) {
    const waitTime = Math.round((HARD_LIMITS.INJECTION_COOLDOWN_MS - timeSinceLastInjection) / 1000);
    return {
      allowed: false,
      reason: `Rate limited - ${waitTime}s remaining`,
      count: currentCount,
    };
  }

  // Check 3: File recreation detection (reset count for new sessions)
  if (sessionPath && sessionData?.lastFileBirthTime) {
    const currentBirthTime = getFileBirthTime(sessionPath);
    if (currentBirthTime - sessionData.lastFileBirthTime > 2000) {
      logger.info(`Session file recreated - resetting injection count`);
      state.sessionInjectionCounts[sessionId] = {
        count: 0,
        lastUpdated: Date.now(),
        lastFileBirthTime: currentBirthTime,
      };
      savePersistentState(state);
      return {
        allowed: true,
        reason: 'Session file recreated - count reset',
        count: 0,
      };
    }
  }

  return {
    allowed: true,
    reason: 'All checks passed',
    count: currentCount,
  };
}

function recordInjection(sessionId: string, sessionPath: string | null, source: string, logger: Logger): void {
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

  if (source === 'onelist_search') {
    state.stats.totalSearchHits++;
  } else {
    state.stats.totalFallbacks++;
  }

  savePersistentState(state);
}

// =============================================================================
// CIRCUIT BREAKER (kept from v0.5.x)
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
// HEALTH LOGGING
// =============================================================================

function logStartupHealth(logger: Logger): void {
  const state = loadPersistentState();
  const sessionCount = Object.keys(state.sessionInjectionCounts).length;

  logger.info(`=== HEALTH: v1.0.0 | Sessions: ${sessionCount} | Injections: ${state.stats.totalInjections} | Searches: ${state.stats.totalSearches} | Hits: ${state.stats.totalSearchHits} | Fallbacks: ${state.stats.totalFallbacks} ===`);
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
// v1.0: ONELIST SEARCH API CLIENT
// =============================================================================

async function searchOnelist(
  config: PluginConfig,
  query: string,
  logger: Logger
): Promise<OnelistSearchResponse> {
  if (!config.apiUrl || !config.apiKey) {
    throw new Error('Missing Onelist API credentials');
  }

  const url = `${config.apiUrl}/api/v1/search`;
  const limit = config.retrievalLimit ?? HARD_LIMITS.DEFAULT_RETRIEVAL_LIMIT;
  const searchType = config.retrievalSearchType ?? 'hybrid';

  const payload = {
    query: query.slice(0, HARD_LIMITS.MAX_QUERY_LENGTH),
    search_type: searchType,
    limit: limit,
    semantic_weight: 0.7,
    keyword_weight: 0.3,
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), HARD_LIMITS.SEARCH_TIMEOUT_MS);

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

    return await response.json() as OnelistSearchResponse;
  } finally {
    clearTimeout(timeout);
  }
}

// =============================================================================
// v1.0: QUERY INTENT EXTRACTION
// =============================================================================

function extractQueryIntent(sessionPath: string | null, logger: Logger): string | null {
  if (!sessionPath || !fs.existsSync(sessionPath)) {
    return null;
  }

  try {
    const content = fs.readFileSync(sessionPath, 'utf-8');
    const lines = content.trim().split('\n');

    // Get last few user messages to understand context
    const recentUserMessages: string[] = [];

    for (let i = lines.length - 1; i >= 0 && recentUserMessages.length < 3; i--) {
      try {
        const entry = JSON.parse(lines[i]);
        if (entry.type === 'message' && entry.message?.role === 'user') {
          const text = extractTextContent(entry.message.content);
          if (text && text.length > 10) {
            recentUserMessages.unshift(text);
          }
        }
      } catch {
        continue;
      }
    }

    if (recentUserMessages.length === 0) {
      return null;
    }

    // Build query from recent user messages
    // Prioritize the most recent message, but include context
    const lastMessage = recentUserMessages[recentUserMessages.length - 1];

    // If it's a question, use the question
    if (lastMessage.includes('?')) {
      const questionPart = lastMessage.split('?')[0] + '?';
      return questionPart.slice(-HARD_LIMITS.MAX_QUERY_LENGTH);
    }

    // Extract key terms from recent messages
    const combined = recentUserMessages.join(' ');

    // Remove common filler words and get key terms
    const keyTerms = combined
      .replace(/\b(the|a|an|is|are|was|were|been|be|have|has|had|do|does|did|will|would|could|should|may|might|must|can|i|you|we|they|it|this|that|these|those|my|your|our|their|its|what|when|where|how|why|who|which)\b/gi, '')
      .replace(/[^\w\s]/g, ' ')
      .split(/\s+/)
      .filter(w => w.length > 3)
      .slice(0, 20)
      .join(' ');

    return keyTerms || lastMessage.slice(0, HARD_LIMITS.MAX_QUERY_LENGTH);
  } catch (err) {
    logger.debug(`Failed to extract query intent: ${String(err)}`);
    return null;
  }
}

// =============================================================================
// v1.0: SMART MEMORY RETRIEVAL
// =============================================================================

async function retrieveRelevantMemories(
  config: PluginConfig,
  sessionPath: string | null,
  logger: Logger
): Promise<MemoryRetrievalResult | null> {
  // Track search attempt
  const state = loadPersistentState();
  state.stats.totalSearches++;
  savePersistentState(state);

  // Check circuit breaker
  if (shouldSkipOnelist()) {
    logger.debug('Circuit breaker open - skipping Onelist search');
    return null;
  }

  // Extract query from current conversation
  const query = extractQueryIntent(sessionPath, logger);
  if (!query) {
    logger.debug('No query intent extracted - skipping retrieval');
    return null;
  }

  logger.info(`Searching Onelist: "${query.slice(0, 50)}..."`);

  try {
    const searchResponse = await searchOnelist(config, query, logger);
    recordOnelistSuccess();

    if (!searchResponse.success || !searchResponse.data) {
      logger.warn(`Search failed: ${searchResponse.error?.message || 'Unknown error'}`);
      return null;
    }

    const results = searchResponse.data.results;
    if (results.length === 0) {
      logger.debug('No relevant memories found');
      return null;
    }

    // Filter by threshold
    const threshold = config.retrievalThreshold ?? HARD_LIMITS.DEFAULT_RETRIEVAL_THRESHOLD;
    const relevantResults = results.filter(r => r.score >= threshold);

    if (relevantResults.length === 0) {
      logger.debug(`No results above threshold ${threshold}`);
      return null;
    }

    // Format memories as context
    const context = formatMemoryContext(relevantResults, query, searchResponse.data.search_type);

    logger.info(`Retrieved ${relevantResults.length} memories (query: "${query.slice(0, 30)}...")`);

    return {
      content: context,
      memoriesRetrieved: relevantResults.length,
      searchQuery: query,
      searchType: searchResponse.data.search_type,
      source: 'onelist_search',
    };

  } catch (err) {
    recordOnelistFailure();
    logger.error(`Onelist search failed: ${String(err)}`);
    return null;
  }
}

function formatMemoryContext(
  results: OnelistSearchResult[],
  query: string,
  searchType: string
): string {
  const now = new Date().toISOString();

  let header = `## 📚 Retrieved Context

**Query:** "${query.slice(0, 100)}"
**Retrieved:** ${now}
**Method:** ${searchType} search | ${results.length} relevant memories

---

`;

  let body = '';
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    const scoreDisplay = (r.score * 100).toFixed(0);
    body += `**${i + 1}.** ${r.title} *(relevance: ${scoreDisplay}%)*\n\n`;
  }

  const footer = `
---

*Context retrieved from Onelist memory. Continue the conversation naturally.*
`;

  return header + body + footer;
}

// =============================================================================
// FALLBACK: LEGACY SESSION FILE RECOVERY (from v0.5.x)
// =============================================================================

const FILTER_PATTERNS = [
  /\[media attached:/i,
  /\[media:/i,
  /<media:image>/i,
  /To send an image back, prefer/i,
];

const MESSAGE_BLOCKLIST_PATTERNS = [
  /## 🔄 Recovered Conversation Context/,
  /## 📚 Retrieved Context/,  // v1.0: Also skip our own injection
  /\*\*Auto-injected:\*\*.*\d{4}-\d{2}-\d{2}/,
  /End of recovered context\. Continue/i,
  /Recovered Conversation Context/i,
  /This context was automatically recovered/i,
  /Context retrieved from Onelist memory/i,  // v1.0
  /\[INJECTION-DEPTH:\d+\]/,
  /\*\*(USER|ASSISTANT)\*\*\s*\(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/,
  /\*\*Coverage:\*\*\s*Last\s+\d+\s+hours?\s*\|/i,
];

function findSessionsDirectory(logger: Logger): string | null {
  // Primary: Use OPENCLAW_HOME (respects user's installation location)
  const primaryDir = path.join(OPENCLAW_HOME, 'agents', 'main', 'sessions');

  try {
    if (fs.existsSync(primaryDir) && fs.statSync(primaryDir).isDirectory()) {
      return primaryDir;
    }
  } catch {
    // Continue to fallback
  }

  // Fallback: Try common alternative locations (for edge cases)
  const fallbackCandidates = [
    // XDG config directory (Linux)
    process.env.XDG_CONFIG_HOME
      ? path.join(process.env.XDG_CONFIG_HOME, 'openclaw', 'agents', 'main', 'sessions')
      : null,
    // Windows AppData
    process.env.APPDATA
      ? path.join(process.env.APPDATA, 'openclaw', 'agents', 'main', 'sessions')
      : null,
  ].filter((dir): dir is string => dir !== null);

  for (const dir of fallbackCandidates) {
    try {
      if (fs.existsSync(dir) && fs.statSync(dir).isDirectory()) {
        logger.info(`Using fallback sessions directory: ${dir}`);
        return dir;
      }
    } catch {
      continue;
    }
  }

  logger.warn(`Sessions directory not found. Expected: ${primaryDir}`);
  return null;
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

async function fallbackRecoverContext(config: PluginConfig, logger: Logger): Promise<RecoveryResult | null> {
  logger.info('Using fallback: session file recovery');

  const messageCount = Math.min(config.autoInjectMessageCount ?? 30, 100);  // Reduced default
  const hoursBack = Math.min(config.autoInjectHoursBack ?? 12, 48);  // Reduced default
  const minMessages = config.autoInjectMinMessages ?? 3;
  const maxFileSize = Math.min(config.maxFileSizeBytes ?? HARD_LIMITS.MAX_FILE_SIZE, HARD_LIMITS.MAX_FILE_SIZE);
  const maxTotalRead = Math.min(config.maxTotalReadBytes ?? HARD_LIMITS.MAX_TOTAL_READ, HARD_LIMITS.MAX_TOTAL_READ);

  const errors: string[] = [];
  const sessionsDir = findSessionsDirectory(logger);

  if (!sessionsDir) {
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
    return null;
  }

  if (sessionFiles.length === 0) {
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
    return null;
  }

  allMessages.sort((a, b) => parseTimestampSafe(a.timestamp) - parseTimestampSafe(b.timestamp));

  const recentMessages = allMessages.slice(-messageCount);
  const formattedContext = formatFallbackContext(recentMessages, hoursBack, filesProcessed, errors.length);

  return {
    content: formattedContext,
    messageCount: recentMessages.length,
    filesProcessed,
    errors,
  };
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

function formatFallbackContext(
  messages: ParsedMessage[],
  hoursBack: number,
  filesProcessed: number,
  errorCount: number
): string {
  const now = new Date().toISOString();

  let header = `## 🔄 Recovered Context (Fallback)

**Auto-injected:** ${now}
**Coverage:** Last ${hoursBack} hours | ${messages.length} messages | ${filesProcessed} session files`;

  if (errorCount > 0) {
    header += ` | ${errorCount} warnings`;
  }

  header += `

*Note: Smart retrieval unavailable, using session file recovery.*

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
// MAIN PLUGIN REGISTRATION
// =============================================================================

console.log(`[onelist-memory] Plugin file loaded (v1.0.0 - query-based retrieval) | OPENCLAW_HOME=${OPENCLAW_HOME}`);

// =============================================================================
// MAIN SESSION FILTERING (kept from v0.5.4)
// =============================================================================

interface SessionsJson {
  [key: string]: {
    sessionId?: string;
    sessionFile?: string;
  };
}

let mainSessionFileCache: { filename: string | null; refreshedAt: number } = {
  filename: null,
  refreshedAt: 0,
};

const MAIN_SESSION_CACHE_TTL_MS = 30000;

function getMainSessionFilename(sessionsDir: string, logger: Logger): string | null {
  if (
    mainSessionFileCache.filename &&
    Date.now() - mainSessionFileCache.refreshedAt < MAIN_SESSION_CACHE_TTL_MS
  ) {
    return mainSessionFileCache.filename;
  }

  try {
    const sessionsJsonPath = path.join(sessionsDir, 'sessions.json');
    if (!fs.existsSync(sessionsJsonPath)) {
      return null;
    }

    const content = fs.readFileSync(sessionsJsonPath, 'utf-8');
    const sessions: SessionsJson = JSON.parse(content);

    const mainSession = sessions['agent:main:main'];
    if (!mainSession) {
      return null;
    }

    let filename: string | null = null;
    if (mainSession.sessionFile) {
      filename = path.basename(mainSession.sessionFile);
    } else if (mainSession.sessionId) {
      filename = `${mainSession.sessionId}.jsonl`;
    }

    if (filename) {
      mainSessionFileCache = { filename, refreshedAt: Date.now() };
    }

    return filename;
  } catch (err) {
    logger.warn(`Failed to read sessions.json: ${String(err)}`);
    return null;
  }
}

function isMainSessionFile(filename: string, sessionsDir: string, logger: Logger): boolean {
  const mainFilename = getMainSessionFilename(sessionsDir, logger);
  if (!mainFilename) {
    return true;
  }
  return filename === mainFilename;
}

export default function register(api: any) {
  const logger: Logger = api?.logger ?? createFallbackLogger();

  logger.info('Register function called (v1.0.0)');

  const pluginId = 'onelist-memory';
  let config: PluginConfig;

  try {
    config = (api?.config?.plugins?.entries?.[pluginId]?.config as PluginConfig) ?? {};
  } catch (err) {
    logger.warn(`Failed to read plugin config, using defaults: ${String(err)}`);
    config = {};
  }

  if (config.enabled === false) {
    logger.info('Plugin explicitly disabled');
    return;
  }

  logStartupHealth(logger);
  lastHealthLog = Date.now();

  // =========================================================================
  // v1.0: SMART RETRIEVAL HOOK
  // =========================================================================

  const smartRetrievalEnabled = config.smartRetrievalEnabled !== false;
  const fallbackEnabled = config.fallbackEnabled !== false;

  if (smartRetrievalEnabled || fallbackEnabled) {
    logger.info(`Registering context hook (smart: ${smartRetrievalEnabled}, fallback: ${fallbackEnabled})`);

    try {
      api.on('before_agent_start', async (event: any, ctx: any): Promise<{ prependContext?: string } | undefined> => {
        const startTime = Date.now();
        const sessionsDir = findSessionsDirectory(logger);

        maybeLogHealth(logger);

        if (!sessionsDir) {
          return undefined;
        }

        const currentSession = findCurrentSessionFile(sessionsDir);
        const sessionId = currentSession?.id ?? 'unknown';
        const sessionPath = currentSession?.path ?? null;

        // Check if injection is allowed
        const checkResult = checkInjectionAllowed(sessionId, sessionPath, logger);
        if (!checkResult.allowed) {
          logger.debug(checkResult.reason);
          return undefined;
        }

        let result: MemoryRetrievalResult | null = null;
        let source: 'onelist_search' | 'fallback_files' = 'onelist_search';

        // Try smart retrieval first
        if (smartRetrievalEnabled && config.apiUrl && config.apiKey) {
          try {
            result = await retrieveRelevantMemories(config, sessionPath, logger);
          } catch (err) {
            logger.error(`Smart retrieval failed: ${String(err)}`);
          }
        }

        // Fallback to session file recovery if smart retrieval failed or disabled
        if (!result && fallbackEnabled) {
          source = 'fallback_files';
          try {
            const fallbackResult = await fallbackRecoverContext(config, logger);
            if (fallbackResult && fallbackResult.content) {
              result = {
                content: fallbackResult.content,
                memoriesRetrieved: fallbackResult.messageCount,
                searchQuery: 'N/A (fallback)',
                searchType: 'file_scan',
                source: 'fallback_files',
              };
            }
          } catch (err) {
            logger.error(`Fallback recovery failed: ${String(err)}`);
          }
        }

        if (!result) {
          logger.debug('No context to inject');
          return undefined;
        }

        const elapsed = Date.now() - startTime;

        // Size check
        if (result.content.length > HARD_LIMITS.MAX_RECOVERY_OUTPUT_CHARS) {
          logger.error(`Output too large: ${result.content.length} > ${HARD_LIMITS.MAX_RECOVERY_OUTPUT_CHARS}`);
          return undefined;
        }

        logger.info(`INJECT: ${result.memoriesRetrieved} items via ${result.source} in ${elapsed}ms`);
        recordInjection(sessionId, sessionPath, result.source, logger);

        return { prependContext: result.content };

      }, { priority: 100 });

      logger.info('Context retrieval hook registered');

    } catch (err) {
      logger.error(`Failed to register hook: ${String(err)}`);
    }
  }

  // =========================================================================
  // ONELIST LIVELOG SYNC (kept from v0.5.x)
  // =========================================================================

  startOnelistSync(config, api, logger).catch(err => {
    logger.error(`Onelist sync startup failed: ${String(err)}`);
  });
}

// =============================================================================
// ONELIST LIVELOG SYNC (kept from v0.5.7)
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
    logger.info('Livelog sync disabled (no API credentials)');
    return;
  }

  logger.info('Starting Livelog sync service');

  const sessionsDir = findSessionsDirectory(logger);
  if (!sessionsDir) {
    logger.warn('Sessions directory not found - Livelog sync disabled');
    return;
  }

  try {
    watchSessionDirectory(sessionsDir, config, logger);
  } catch (err) {
    logger.error(`Failed to start session watcher: ${String(err)}`);
  }
}

function watchSessionDirectory(sessionsDir: string, config: PluginConfig, logger: Logger): void {
  logger.info(`Watching ${sessionsDir} (main session only)`);

  try {
    const watcher = fs.watch(sessionsDir, { persistent: true }, async (eventType, filename) => {
      if (!filename) return;
      if (!filename.endsWith('.jsonl')) return;
      if (filename.includes('.deleted') || filename.includes('.lock') || filename.includes('.archived')) return;

      if (!isMainSessionFile(filename, sessionsDir, logger)) {
        return;
      }

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

  // Initial sync
  try {
    const mainFilename = getMainSessionFilename(sessionsDir, logger);
    if (mainFilename && !shouldSkipOnelist()) {
      const filePath = path.join(sessionsDir, mainFilename);
      if (fs.existsSync(filePath)) {
        syncSessionFile(filePath, config, logger).catch(() => {});
      }
    }
  } catch (err) {
    logger.error(`Failed initial sync: ${String(err)}`);
  }
}

function shouldSkipMessageForLivelog(content: string): boolean {
  if (!content) return false;

  if (/^##\s+(SPRINT|Task|URGENT|CRITICAL|Fix|Create|Build|Deploy|Update|Check|Investigate)/i.test(content)) {
    return true;
  }

  if (/^A background task ["\u201c].*["\u201d] just completed/i.test(content)) {
    return true;
  }

  if (/^\[Queued announce messages while agent was busy\]/i.test(content)) {
    return true;
  }

  if (/^(Now let me|Let me|I'll now|Starting|Checking|Reading|Found|Looking)/i.test(content) &&
      content.length < 200) {
    return true;
  }

  if (/^## 🔄 Recovered Conversation Context/i.test(content)) {
    return true;
  }

  if (/^## 📚 Retrieved Context/i.test(content)) {
    return true;
  }

  if (/^Findings:/i.test(content)) {
    return true;
  }

  if (/^To send an image back, prefer/i.test(content)) {
    return true;
  }

  if (/^(To respond with|When sending|Use the message tool)/i.test(content)) {
    return true;
  }

  if (/Telegram reaction (added|removed|updated):/i.test(content)) {
    return true;
  }

  if (/^\[System\]|^\[INFO\]|^\[DEBUG\]/i.test(content)) {
    return true;
  }

  if (/^System:\s*\[\d{4}-\d{2}-\d{2}/i.test(content)) {
    return true;
  }

  return false;
}

function parseReactionEvent(content: string): { targetMessageId: string; emoji: string; fromUser: string } | null {
  const match = content.match(/Telegram reaction (?:added|updated):\s*(.+?)\s+by\s+(\S+)(?:\s+\([^)]+\))?\s+on\s+msg\s+(\d+)/i);
  if (match) {
    return {
      emoji: match[1].trim(),
      fromUser: match[2],
      targetMessageId: match[3],
    };
  }
  return null;
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
      break;
    }

    const msgContent = extractTextContent(msg.message?.content);

    const reactionData = parseReactionEvent(msgContent);
    if (reactionData) {
      try {
        await sendReactionToOnelist(config, reactionData, logger);
        recordOnelistSuccess();
      } catch (err) {
        recordOnelistFailure();
        logger.error(`Failed to send reaction: ${String(err)}`);
      }
      continue;
    }

    if (shouldSkipMessageForLivelog(msgContent)) {
      continue;
    }

    try {
      await sendToOnelist(config, sessionId, msg, logger);
      recordOnelistSuccess();
    } catch (err) {
      recordOnelistFailure();
      if (onelistCircuitBreaker.consecutiveFailures <= 3) {
        logger.error(`Livelog sync failed: ${String(err)}`);
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

async function sendReactionToOnelist(
  config: PluginConfig,
  reactionData: { targetMessageId: string; emoji: string; fromUser: string },
  logger: Logger
): Promise<void> {
  if (!config.apiUrl || !config.apiKey) {
    throw new Error('Missing API credentials');
  }

  const url = `${config.apiUrl}/api/v1/chat-stream/reaction`;

  const payload = {
    target_message_id: reactionData.targetMessageId,
    emoji: reactionData.emoji,
    from_user: reactionData.fromUser,
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
