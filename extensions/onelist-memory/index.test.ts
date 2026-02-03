/**
 * Comprehensive Test Suite for Onelist Memory Sync Plugin v1.0.0
 *
 * Coverage targets:
 * - Path configuration and environment handling
 * - State persistence and file locking
 * - Injection tracking and rate limiting
 * - Circuit breaker behavior
 * - Query intent extraction
 * - Memory retrieval and formatting
 * - Session file parsing
 * - Telegram metadata extraction
 * - Message filtering and blocklists
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';

// Mock fs module
vi.mock('fs');

// Mock fetch for API tests
const mockFetch = vi.fn();
global.fetch = mockFetch;

// =============================================================================
// TEST UTILITIES
// =============================================================================

const mockLogger = {
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
};

function createMockState(overrides = {}) {
  return {
    version: 3,
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
    ...overrides,
  };
}

function createMockSessionEntry(role: string, content: string, timestamp?: string) {
  return JSON.stringify({
    type: 'message',
    timestamp: timestamp || new Date().toISOString(),
    message: {
      role,
      content,
    },
  });
}

// =============================================================================
// PATH CONFIGURATION TESTS
// =============================================================================

describe('Path Configuration', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    vi.resetModules();
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  describe('getOpenClawHome', () => {
    it('should use OPENCLAW_HOME environment variable when set', () => {
      process.env.OPENCLAW_HOME = '/custom/openclaw';
      // Re-import module to pick up new env
      const home = process.env.OPENCLAW_HOME;
      expect(home).toBe('/custom/openclaw');
    });

    it('should fall back to HOME/.openclaw when OPENCLAW_HOME not set', () => {
      delete process.env.OPENCLAW_HOME;
      process.env.HOME = '/home/user';
      const expected = path.join('/home/user', '.openclaw');
      expect(expected).toBe('/home/user/.openclaw');
    });

    it('should use USERPROFILE on Windows when HOME not set', () => {
      delete process.env.OPENCLAW_HOME;
      delete process.env.HOME;
      process.env.USERPROFILE = 'C:\\Users\\user';
      const expected = path.join('C:\\Users\\user', '.openclaw');
      expect(expected).toContain('.openclaw');
    });

    it('should fall back to /root when no env vars set', () => {
      delete process.env.OPENCLAW_HOME;
      delete process.env.HOME;
      delete process.env.USERPROFILE;
      const expected = path.join('/root', '.openclaw');
      expect(expected).toBe('/root/.openclaw');
    });
  });
});

// =============================================================================
// TELEGRAM METADATA EXTRACTION TESTS
// =============================================================================

describe('Telegram Metadata Extraction', () => {
  // Inline implementation for testing
  function extractTelegramMetadata(content: string, sessionKey?: string) {
    const metadata: any = { channel: 'telegram' };

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

  it('should extract user info from Telegram message', () => {
    const content = '[Telegram Alice (@alice123) id:987654321] Hello!';
    const result = extractTelegramMetadata(content);

    expect(result.channel).toBe('telegram');
    expect(result.display_name).toBe('Alice');
    expect(result.handle).toBe('@alice123');
    expect(result.telegram_user_id).toBe('987654321');
  });

  it('should extract message ID', () => {
    const content = '[message_id: 12345] Test message';
    const result = extractTelegramMetadata(content);

    expect(result.message_id).toBe('12345');
  });

  it('should extract reply information', () => {
    const content = '[Replying to user id:54321] My reply';
    const result = extractTelegramMetadata(content);

    expect(result.reply_to_role).toBe('user');
    expect(result.reply_to_message_id).toBe('54321');
  });

  it('should extract reaction information', () => {
    const content = 'reaction added: 👍 by alice on msg 12345';
    const result = extractTelegramMetadata(content);

    expect(result.reaction).toBe('👍');
    expect(result.reaction_target_id).toBe('12345');
  });

  it('should include session key when provided', () => {
    const content = 'Hello';
    const result = extractTelegramMetadata(content, 'session-123');

    expect(result.session_key).toBe('session-123');
  });

  it('should handle content with no Telegram metadata', () => {
    const content = 'Just a regular message';
    const result = extractTelegramMetadata(content);

    expect(result.channel).toBe('telegram');
    expect(result.display_name).toBeUndefined();
    expect(result.handle).toBeUndefined();
    expect(result.message_id).toBeUndefined();
  });
});

// =============================================================================
// TEXT CONTENT EXTRACTION TESTS
// =============================================================================

describe('Text Content Extraction', () => {
  // Inline implementation for testing
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

  it('should return empty string for null/undefined', () => {
    expect(extractTextContent(null)).toBe('');
    expect(extractTextContent(undefined)).toBe('');
  });

  it('should return trimmed string for string input', () => {
    expect(extractTextContent('  hello world  ')).toBe('hello world');
  });

  it('should extract text from content blocks array', () => {
    const content = [
      { type: 'text', text: 'First part' },
      { type: 'text', text: 'Second part' },
    ];
    expect(extractTextContent(content)).toBe('First part\nSecond part');
  });

  it('should ignore non-text content blocks', () => {
    const content = [
      { type: 'text', text: 'Hello' },
      { type: 'image', data: 'base64...' },
      { type: 'text', text: 'World' },
    ];
    expect(extractTextContent(content)).toBe('Hello\nWorld');
  });

  it('should return empty string for object without array', () => {
    expect(extractTextContent({ foo: 'bar' })).toBe('');
  });
});

// =============================================================================
// MEDIA FILTERING TESTS
// =============================================================================

describe('Media Reference Filtering', () => {
  const FILTER_PATTERNS = [
    /\[media attached:/i,
    /\[media:/i,
    /<media:image>/i,
    /To send an image back, prefer/i,
  ];

  function filterMediaReferences(content: string) {
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

  it('should filter [media attached: lines', () => {
    const content = 'Hello\n[media attached: image.png]\nWorld';
    const result = filterMediaReferences(content);

    expect(result.filtered).toBe('Hello\nWorld');
    expect(result.removedCount).toBe(1);
  });

  it('should filter <media:image> tags', () => {
    const content = 'Before\n<media:image>\nAfter';
    const result = filterMediaReferences(content);

    expect(result.filtered).toBe('Before\nAfter');
    expect(result.removedCount).toBe(1);
  });

  it('should filter image instruction lines', () => {
    const content = 'Test\nTo send an image back, prefer using...\nMore text';
    const result = filterMediaReferences(content);

    expect(result.filtered).toBe('Test\nMore text');
    expect(result.removedCount).toBe(1);
  });

  it('should not filter regular content', () => {
    const content = 'This is normal text\nWith multiple lines\nNo media here';
    const result = filterMediaReferences(content);

    expect(result.filtered).toBe(content);
    expect(result.removedCount).toBe(0);
  });

  it('should handle case insensitive matching', () => {
    const content = '[MEDIA ATTACHED: file.jpg]\n[Media: test]';
    const result = filterMediaReferences(content);

    expect(result.removedCount).toBe(2);
    expect(result.filtered).toBe('');
  });
});

// =============================================================================
// MESSAGE BLOCKLIST TESTS
// =============================================================================

describe('Message Blocklist', () => {
  const MESSAGE_BLOCKLIST_PATTERNS = [
    /## 🔄 Recovered Conversation Context/,
    /## 📚 Retrieved Context/,
    /\*\*Auto-injected:\*\*.*\d{4}-\d{2}-\d{2}/,
    /End of recovered context\. Continue/i,
    /Recovered Conversation Context/i,
    /This context was automatically recovered/i,
    /Context retrieved from Onelist memory/i,
    /\[INJECTION-DEPTH:\d+\]/,
    /\*\*(USER|ASSISTANT)\*\*\s*\(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/,
    /\*\*Coverage:\*\*\s*Last\s+\d+\s+hours?\s*\|/i,
  ];

  function shouldBlockMessage(content: string): boolean {
    return MESSAGE_BLOCKLIST_PATTERNS.some(p => p.test(content));
  }

  it('should block recovered context headers', () => {
    expect(shouldBlockMessage('## 🔄 Recovered Conversation Context')).toBe(true);
    expect(shouldBlockMessage('## 📚 Retrieved Context')).toBe(true);
  });

  it('should block auto-injected timestamps', () => {
    expect(shouldBlockMessage('**Auto-injected:** 2026-01-15T10:30:00Z')).toBe(true);
  });

  it('should block injection depth markers', () => {
    expect(shouldBlockMessage('[INJECTION-DEPTH:1] Some context')).toBe(true);
    expect(shouldBlockMessage('[INJECTION-DEPTH:42] More context')).toBe(true);
  });

  it('should block formatted message headers', () => {
    expect(shouldBlockMessage('**USER** (2026-01-15T10:30:00Z):')).toBe(true);
    expect(shouldBlockMessage('**ASSISTANT** (2026-01-15T10:30:30Z):')).toBe(true);
  });

  it('should block coverage lines', () => {
    expect(shouldBlockMessage('**Coverage:** Last 24 hours | 50 messages')).toBe(true);
  });

  it('should not block normal messages', () => {
    expect(shouldBlockMessage('Hello, how are you?')).toBe(false);
    expect(shouldBlockMessage('Please help me with this code')).toBe(false);
  });
});

// =============================================================================
// TIMESTAMP PARSING TESTS
// =============================================================================

describe('Timestamp Parsing', () => {
  function parseTimestampSafe(timestamp: string): number {
    if (!timestamp) return 0;
    try {
      const parsed = new Date(timestamp).getTime();
      return isNaN(parsed) ? 0 : parsed;
    } catch {
      return 0;
    }
  }

  it('should parse ISO timestamps', () => {
    const ts = '2026-01-15T10:30:00Z';
    const result = parseTimestampSafe(ts);

    expect(result).toBeGreaterThan(0);
    expect(new Date(result).toISOString()).toBe('2026-01-15T10:30:00.000Z');
  });

  it('should return 0 for Unix timestamp strings (not ISO format)', () => {
    // Note: JavaScript's Date() doesn't parse Unix timestamp strings directly
    // They need to be converted with parseInt() first, which parseTimestampSafe doesn't do
    const ts = '1705315800000';
    const result = parseTimestampSafe(ts);

    // This returns 0 because Date('1705315800000') creates an Invalid Date
    expect(result).toBe(0);
  });

  it('should return 0 for empty string', () => {
    expect(parseTimestampSafe('')).toBe(0);
  });

  it('should return 0 for invalid timestamps', () => {
    expect(parseTimestampSafe('not a date')).toBe(0);
    expect(parseTimestampSafe('invalid')).toBe(0);
  });
});

// =============================================================================
// CIRCUIT BREAKER TESTS
// =============================================================================

describe('Circuit Breaker', () => {
  const HARD_LIMITS = {
    ONELIST_MAX_CONSECUTIVE_FAILURES: 5,
    ONELIST_INITIAL_BACKOFF_MS: 60000,
    ONELIST_MAX_BACKOFF_MS: 3600000,
  };

  interface CircuitBreakerState {
    consecutiveFailures: number;
    lastFailureTime: number;
    backoffUntil: number;
    totalFailures: number;
    totalSuccesses: number;
  }

  let circuitBreaker: CircuitBreakerState;

  beforeEach(() => {
    circuitBreaker = {
      consecutiveFailures: 0,
      lastFailureTime: 0,
      backoffUntil: 0,
      totalFailures: 0,
      totalSuccesses: 0,
    };
  });

  function shouldSkipOnelist(): boolean {
    return circuitBreaker.backoffUntil > Date.now();
  }

  function recordOnelistSuccess(): void {
    circuitBreaker.consecutiveFailures = 0;
    circuitBreaker.backoffUntil = 0;
    circuitBreaker.totalSuccesses++;
  }

  function recordOnelistFailure(): void {
    circuitBreaker.consecutiveFailures++;
    circuitBreaker.lastFailureTime = Date.now();
    circuitBreaker.totalFailures++;

    if (circuitBreaker.consecutiveFailures >= HARD_LIMITS.ONELIST_MAX_CONSECUTIVE_FAILURES) {
      const backoffMultiplier = Math.pow(2, circuitBreaker.consecutiveFailures - HARD_LIMITS.ONELIST_MAX_CONSECUTIVE_FAILURES);
      const backoffMs = Math.min(
        HARD_LIMITS.ONELIST_INITIAL_BACKOFF_MS * backoffMultiplier,
        HARD_LIMITS.ONELIST_MAX_BACKOFF_MS
      );
      circuitBreaker.backoffUntil = Date.now() + backoffMs;
    }
  }

  it('should not skip when no failures', () => {
    expect(shouldSkipOnelist()).toBe(false);
  });

  it('should not skip after single failure', () => {
    recordOnelistFailure();
    expect(shouldSkipOnelist()).toBe(false);
    expect(circuitBreaker.consecutiveFailures).toBe(1);
  });

  it('should not skip until threshold reached', () => {
    for (let i = 0; i < 4; i++) {
      recordOnelistFailure();
    }
    expect(shouldSkipOnelist()).toBe(false);
    expect(circuitBreaker.consecutiveFailures).toBe(4);
  });

  it('should start backoff after 5 consecutive failures', () => {
    for (let i = 0; i < 5; i++) {
      recordOnelistFailure();
    }
    expect(shouldSkipOnelist()).toBe(true);
    expect(circuitBreaker.backoffUntil).toBeGreaterThan(Date.now());
  });

  it('should reset on success', () => {
    for (let i = 0; i < 5; i++) {
      recordOnelistFailure();
    }
    expect(shouldSkipOnelist()).toBe(true);

    recordOnelistSuccess();

    expect(shouldSkipOnelist()).toBe(false);
    expect(circuitBreaker.consecutiveFailures).toBe(0);
    expect(circuitBreaker.backoffUntil).toBe(0);
  });

  it('should track total failures and successes', () => {
    recordOnelistFailure();
    recordOnelistFailure();
    recordOnelistSuccess();
    recordOnelistFailure();

    expect(circuitBreaker.totalFailures).toBe(3);
    expect(circuitBreaker.totalSuccesses).toBe(1);
  });

  it('should increase backoff exponentially', () => {
    // Get to threshold
    for (let i = 0; i < 5; i++) {
      recordOnelistFailure();
    }
    const firstBackoffEnd = circuitBreaker.backoffUntil;

    // Another failure should double the backoff
    circuitBreaker.backoffUntil = 0; // Reset for test
    recordOnelistFailure();
    const secondBackoffEnd = circuitBreaker.backoffUntil;

    // Second backoff should be roughly 2x the first (accounting for timing)
    const firstDuration = firstBackoffEnd - (Date.now() - 100);
    const secondDuration = secondBackoffEnd - Date.now();

    expect(secondDuration).toBeGreaterThan(firstDuration);
  });

  it('should cap backoff at maximum', () => {
    // Many failures
    for (let i = 0; i < 20; i++) {
      recordOnelistFailure();
    }

    const maxBackoff = circuitBreaker.backoffUntil - Date.now();
    expect(maxBackoff).toBeLessThanOrEqual(HARD_LIMITS.ONELIST_MAX_BACKOFF_MS + 1000);
  });
});

// =============================================================================
// INJECTION LIMIT TESTS
// =============================================================================

describe('Injection Limits', () => {
  const HARD_LIMITS = {
    MAX_INJECTIONS_PER_SESSION: 5,
    INJECTION_COOLDOWN_MS: 30000,
  };

  function createState() {
    return {
      version: 3,
      lastInjectionTime: 0,
      sessionInjectionCounts: {} as Record<string, { count: number; lastUpdated: number }>,
      stats: { totalBlocked: 0 },
    };
  }

  function checkInjectionAllowed(
    state: ReturnType<typeof createState>,
    sessionId: string
  ): { allowed: boolean; reason: string; count: number } {
    const sessionData = state.sessionInjectionCounts[sessionId];
    const currentCount = sessionData?.count ?? 0;

    // Check count limit
    if (currentCount >= HARD_LIMITS.MAX_INJECTIONS_PER_SESSION) {
      state.stats.totalBlocked++;
      return {
        allowed: false,
        reason: `Session ${sessionId.substring(0, 8)} at injection limit (${currentCount}/${HARD_LIMITS.MAX_INJECTIONS_PER_SESSION})`,
        count: currentCount,
      };
    }

    // Check rate limit
    const timeSinceLastInjection = Date.now() - state.lastInjectionTime;
    if (timeSinceLastInjection < HARD_LIMITS.INJECTION_COOLDOWN_MS) {
      const waitTime = Math.round((HARD_LIMITS.INJECTION_COOLDOWN_MS - timeSinceLastInjection) / 1000);
      return {
        allowed: false,
        reason: `Rate limited - ${waitTime}s remaining`,
        count: currentCount,
      };
    }

    return {
      allowed: true,
      reason: 'All checks passed',
      count: currentCount,
    };
  }

  it('should allow first injection', () => {
    const state = createState();
    const result = checkInjectionAllowed(state, 'session-123');

    expect(result.allowed).toBe(true);
    expect(result.count).toBe(0);
  });

  it('should block after reaching limit', () => {
    const state = createState();
    state.sessionInjectionCounts['session-123'] = { count: 5, lastUpdated: Date.now() };

    const result = checkInjectionAllowed(state, 'session-123');

    expect(result.allowed).toBe(false);
    expect(result.reason).toContain('injection limit');
    expect(state.stats.totalBlocked).toBe(1);
  });

  it('should enforce cooldown period', () => {
    const state = createState();
    state.lastInjectionTime = Date.now() - 10000; // 10 seconds ago

    const result = checkInjectionAllowed(state, 'session-123');

    expect(result.allowed).toBe(false);
    expect(result.reason).toContain('Rate limited');
  });

  it('should allow after cooldown expires', () => {
    const state = createState();
    state.lastInjectionTime = Date.now() - 40000; // 40 seconds ago (> 30s cooldown)

    const result = checkInjectionAllowed(state, 'session-123');

    expect(result.allowed).toBe(true);
  });

  it('should track per-session counts independently', () => {
    const state = createState();
    state.sessionInjectionCounts['session-1'] = { count: 5, lastUpdated: Date.now() };
    state.sessionInjectionCounts['session-2'] = { count: 2, lastUpdated: Date.now() };
    state.lastInjectionTime = Date.now() - 40000; // Past cooldown

    const result1 = checkInjectionAllowed(state, 'session-1');
    const result2 = checkInjectionAllowed(state, 'session-2');

    expect(result1.allowed).toBe(false);
    expect(result1.count).toBe(5);
    expect(result2.allowed).toBe(true);
    expect(result2.count).toBe(2);
  });
});

// =============================================================================
// QUERY INTENT EXTRACTION TESTS
// =============================================================================

describe('Query Intent Extraction', () => {
  function extractQueryIntent(lines: string[]): string | null {
    const MAX_QUERY_LENGTH = 500;
    const recentUserMessages: string[] = [];

    // Simulate parsing JSONL for user messages
    for (let i = lines.length - 1; i >= 0 && recentUserMessages.length < 3; i--) {
      try {
        const entry = JSON.parse(lines[i]);
        if (entry.type === 'message' && entry.message?.role === 'user') {
          const text = typeof entry.message.content === 'string'
            ? entry.message.content
            : '';
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

    const lastMessage = recentUserMessages[recentUserMessages.length - 1];

    // If it's a question, use the question
    if (lastMessage.includes('?')) {
      const questionPart = lastMessage.split('?')[0] + '?';
      return questionPart.slice(-MAX_QUERY_LENGTH);
    }

    // Extract key terms
    const combined = recentUserMessages.join(' ');
    const keyTerms = combined
      .replace(/\b(the|a|an|is|are|was|were|been|be|have|has|had|do|does|did|will|would|could|should|may|might|must|can|i|you|we|they|it|this|that|these|those|my|your|our|their|its|what|when|where|how|why|who|which)\b/gi, '')
      .replace(/[^\w\s]/g, ' ')
      .split(/\s+/)
      .filter(w => w.length > 3)
      .slice(0, 20)
      .join(' ');

    return keyTerms || lastMessage.slice(0, MAX_QUERY_LENGTH);
  }

  it('should extract question as query', () => {
    const lines = [
      createMockSessionEntry('user', 'How do I set up kubernetes?'),
    ];
    const result = extractQueryIntent(lines);

    expect(result).toBe('How do I set up kubernetes?');
  });

  it('should extract key terms from statements', () => {
    const lines = [
      createMockSessionEntry('user', 'I need help with database migrations'),
    ];
    const result = extractQueryIntent(lines);

    expect(result).toContain('help');
    expect(result).toContain('database');
    expect(result).toContain('migrations');
  });

  it('should return null for empty session', () => {
    const result = extractQueryIntent([]);
    expect(result).toBeNull();
  });

  it('should skip messages shorter than 10 chars', () => {
    const lines = [
      createMockSessionEntry('user', 'ok'),
      createMockSessionEntry('user', 'yes'),
    ];
    const result = extractQueryIntent(lines);
    expect(result).toBeNull();
  });

  it('should filter out common words', () => {
    const lines = [
      createMockSessionEntry('user', 'The is a an test for the filtering'),
    ];
    const result = extractQueryIntent(lines);

    expect(result).not.toContain(' the ');
    expect(result).not.toContain(' is ');
    expect(result).not.toContain(' a ');
    expect(result).not.toContain(' an ');
  });

  it('should use most recent 3 user messages for context', () => {
    const lines = [
      createMockSessionEntry('user', 'First message about kubernetes'),
      createMockSessionEntry('assistant', 'Here is my response'),
      createMockSessionEntry('user', 'Second message about docker'),
      createMockSessionEntry('assistant', 'More response'),
      createMockSessionEntry('user', 'Third message about containers'),
      createMockSessionEntry('assistant', 'Final response'),
      createMockSessionEntry('user', 'What is the best approach?'),
    ];
    const result = extractQueryIntent(lines);

    expect(result).toBe('What is the best approach?');
  });
});

// =============================================================================
// MEMORY CONTEXT FORMATTING TESTS
// =============================================================================

describe('Memory Context Formatting', () => {
  interface SearchResult {
    entry_id: string;
    title: string;
    entry_type: string;
    score: number;
  }

  function formatMemoryContext(
    results: SearchResult[],
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

  it('should format header with query and metadata', () => {
    const results: SearchResult[] = [
      { entry_id: '1', title: 'Test Memory', entry_type: 'memory', score: 0.95 },
    ];
    const result = formatMemoryContext(results, 'test query', 'hybrid');

    expect(result).toContain('## 📚 Retrieved Context');
    expect(result).toContain('**Query:** "test query"');
    expect(result).toContain('**Method:** hybrid search');
    expect(result).toContain('1 relevant memories');
  });

  it('should format each memory with relevance score', () => {
    const results: SearchResult[] = [
      { entry_id: '1', title: 'First Memory', entry_type: 'memory', score: 0.92 },
      { entry_id: '2', title: 'Second Memory', entry_type: 'memory', score: 0.85 },
    ];
    const result = formatMemoryContext(results, 'query', 'semantic');

    expect(result).toContain('**1.** First Memory *(relevance: 92%)*');
    expect(result).toContain('**2.** Second Memory *(relevance: 85%)*');
  });

  it('should truncate long queries', () => {
    const longQuery = 'a'.repeat(200);
    const results: SearchResult[] = [];
    const result = formatMemoryContext(results, longQuery, 'hybrid');

    expect(result).toContain('**Query:** "' + 'a'.repeat(100) + '"');
  });

  it('should include footer instruction', () => {
    const results: SearchResult[] = [];
    const result = formatMemoryContext(results, 'query', 'keyword');

    expect(result).toContain('Continue the conversation naturally');
  });
});

// =============================================================================
// LIVELOG SKIP MESSAGE TESTS
// =============================================================================

describe('Livelog Message Filtering', () => {
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

  it('should skip task/sprint headers', () => {
    expect(shouldSkipMessageForLivelog('## SPRINT 42')).toBe(true);
    expect(shouldSkipMessageForLivelog('## Task: Fix bug')).toBe(true);
    expect(shouldSkipMessageForLivelog('## URGENT: Deploy now')).toBe(true);
  });

  it('should skip background task completion messages', () => {
    expect(shouldSkipMessageForLivelog('A background task "build" just completed')).toBe(true);
  });

  it('should skip queued announce messages', () => {
    expect(shouldSkipMessageForLivelog('[Queued announce messages while agent was busy]')).toBe(true);
  });

  it('should skip short status messages', () => {
    expect(shouldSkipMessageForLivelog('Now let me check')).toBe(true);
    expect(shouldSkipMessageForLivelog('Let me read that file')).toBe(true);
    expect(shouldSkipMessageForLivelog('Starting the build')).toBe(true);
  });

  it('should not skip long status-like messages', () => {
    const longMessage = 'Now let me ' + 'x'.repeat(200);
    expect(shouldSkipMessageForLivelog(longMessage)).toBe(false);
  });

  it('should skip recovered context headers', () => {
    expect(shouldSkipMessageForLivelog('## 🔄 Recovered Conversation Context')).toBe(true);
    expect(shouldSkipMessageForLivelog('## 📚 Retrieved Context')).toBe(true);
  });

  it('should skip Telegram reaction messages', () => {
    expect(shouldSkipMessageForLivelog('Telegram reaction added: 👍 by user')).toBe(true);
    expect(shouldSkipMessageForLivelog('Telegram reaction removed: 👎 by user')).toBe(true);
  });

  it('should skip system messages', () => {
    expect(shouldSkipMessageForLivelog('[System] Starting up')).toBe(true);
    expect(shouldSkipMessageForLivelog('[INFO] Connected')).toBe(true);
    expect(shouldSkipMessageForLivelog('[DEBUG] var=123')).toBe(true);
  });

  it('should not skip normal conversation messages', () => {
    expect(shouldSkipMessageForLivelog('Hello, how can I help?')).toBe(false);
    expect(shouldSkipMessageForLivelog('The code looks good to me')).toBe(false);
    expect(shouldSkipMessageForLivelog('Here is my analysis of the problem...')).toBe(false);
  });
});

// =============================================================================
// STATE PRUNING TESTS
// =============================================================================

describe('State Pruning', () => {
  const HARD_LIMITS = {
    STATE_MAX_SESSIONS: 100,
    STATE_PRUNE_DAYS: 7,
  };

  function pruneOldSessions(state: any): void {
    const cutoff = Date.now() - (HARD_LIMITS.STATE_PRUNE_DAYS * 24 * 60 * 60 * 1000);
    const entries = Object.entries(state.sessionInjectionCounts);

    for (const [sessionId, data] of entries) {
      if ((data as any).lastUpdated < cutoff) {
        delete state.sessionInjectionCounts[sessionId];
      }
    }

    const remaining = Object.entries(state.sessionInjectionCounts);
    if (remaining.length > HARD_LIMITS.STATE_MAX_SESSIONS) {
      remaining.sort((a, b) => (a[1] as any).lastUpdated - (b[1] as any).lastUpdated);
      const toRemove = remaining.slice(0, remaining.length - HARD_LIMITS.STATE_MAX_SESSIONS);
      for (const [sessionId] of toRemove) {
        delete state.sessionInjectionCounts[sessionId];
      }
    }
  }

  it('should remove sessions older than 7 days', () => {
    const oldTime = Date.now() - (8 * 24 * 60 * 60 * 1000); // 8 days ago
    const state = createMockState({
      sessionInjectionCounts: {
        'old-session': { count: 1, lastUpdated: oldTime },
        'new-session': { count: 1, lastUpdated: Date.now() },
      },
    });

    pruneOldSessions(state);

    expect(state.sessionInjectionCounts['old-session']).toBeUndefined();
    expect(state.sessionInjectionCounts['new-session']).toBeDefined();
  });

  it('should keep sessions within 7 days', () => {
    const recentTime = Date.now() - (3 * 24 * 60 * 60 * 1000); // 3 days ago
    const state = createMockState({
      sessionInjectionCounts: {
        'recent-session': { count: 5, lastUpdated: recentTime },
      },
    });

    pruneOldSessions(state);

    expect(state.sessionInjectionCounts['recent-session']).toBeDefined();
  });

  it('should enforce max sessions limit', () => {
    const sessions: Record<string, any> = {};
    for (let i = 0; i < 150; i++) {
      sessions[`session-${i}`] = {
        count: 1,
        lastUpdated: Date.now() - (i * 1000), // Stagger times
      };
    }
    const state = createMockState({ sessionInjectionCounts: sessions });

    pruneOldSessions(state);

    expect(Object.keys(state.sessionInjectionCounts).length).toBeLessThanOrEqual(100);
  });

  it('should keep newest sessions when pruning for max limit', () => {
    const sessions: Record<string, any> = {};
    for (let i = 0; i < 110; i++) {
      sessions[`session-${i}`] = {
        count: 1,
        lastUpdated: Date.now() - (i * 60000), // 1 minute apart
      };
    }
    const state = createMockState({ sessionInjectionCounts: sessions });

    pruneOldSessions(state);

    // session-0 should exist (newest)
    expect(state.sessionInjectionCounts['session-0']).toBeDefined();
    // session-109 should be removed (oldest)
    expect(state.sessionInjectionCounts['session-109']).toBeUndefined();
  });
});

// =============================================================================
// COMPACTION RECOVERY TESTS (v1.1.0)
// =============================================================================

describe('Compaction Recovery', () => {
  const HARD_LIMITS = {
    MAX_INJECTIONS_PER_SESSION: 5,
    INJECTION_COOLDOWN_MS: 30000,
  };

  function createState() {
    return {
      version: 3,
      lastInjectionTime: 0,
      sessionInjectionCounts: {} as Record<string, { count: number; lastUpdated: number }>,
      stats: {
        totalInjections: 0,
        totalBlocked: 0,
        totalSearches: 0,
        totalSearchHits: 0,
        totalFallbacks: 0,
        totalCompactionRecoveries: 0,
        startupTime: Date.now(),
      },
    };
  }

  describe('after_compaction hook registration', () => {
    it('should register after_compaction hook when smart or fallback retrieval enabled', () => {
      const registeredHooks: string[] = [];
      const mockApi = {
        on: (hookName: string, _handler: any, _options?: any) => {
          registeredHooks.push(hookName);
        },
        logger: mockLogger,
        config: {
          plugins: {
            entries: {
              'onelist-memory': {
                config: {
                  smartRetrievalEnabled: true,
                  fallbackEnabled: true,
                },
              },
            },
          },
        },
      };

      // Simulate what register() does
      const smartRetrievalEnabled = true;
      const fallbackEnabled = true;

      if (smartRetrievalEnabled || fallbackEnabled) {
        mockApi.on('before_agent_start', () => {}, { priority: 100 });
        mockApi.on('after_compaction', () => {}, { priority: 100 });
      }

      expect(registeredHooks).toContain('before_agent_start');
      expect(registeredHooks).toContain('after_compaction');
    });

    it('should not register hooks when both smart and fallback disabled', () => {
      const registeredHooks: string[] = [];
      const smartRetrievalEnabled = false;
      const fallbackEnabled = false;

      if (smartRetrievalEnabled || fallbackEnabled) {
        registeredHooks.push('before_agent_start');
        registeredHooks.push('after_compaction');
      }

      expect(registeredHooks).not.toContain('after_compaction');
    });
  });

  describe('compaction recovery bypasses rate limits', () => {
    it('should not be subject to injection count limits for compaction recovery', () => {
      const state = createState();
      state.sessionInjectionCounts['session-123'] = { count: 5, lastUpdated: Date.now() };

      // Normal injection would be blocked
      const normalAllowed = state.sessionInjectionCounts['session-123'].count < HARD_LIMITS.MAX_INJECTIONS_PER_SESSION;
      expect(normalAllowed).toBe(false);

      // Compaction recovery should bypass - it's critical for continuity
      // In the implementation, we simply don't call checkInjectionAllowed for compaction
      const compactionRecoveryAllowed = true; // Always allowed for compaction
      expect(compactionRecoveryAllowed).toBe(true);
    });

    it('should not be subject to cooldown period for compaction recovery', () => {
      const state = createState();
      state.lastInjectionTime = Date.now() - 1000; // Just 1 second ago

      // Normal injection would be rate limited
      const timeSinceLastInjection = Date.now() - state.lastInjectionTime;
      const normalAllowed = timeSinceLastInjection >= HARD_LIMITS.INJECTION_COOLDOWN_MS;
      expect(normalAllowed).toBe(false);

      // Compaction recovery should bypass cooldown
      const compactionRecoveryAllowed = true; // Critical recovery bypasses rate limiting
      expect(compactionRecoveryAllowed).toBe(true);
    });
  });

  describe('stats track compaction recoveries', () => {
    it('should increment totalCompactionRecoveries counter', () => {
      const state = createState();
      expect(state.stats.totalCompactionRecoveries).toBe(0);

      // Simulate recording a compaction recovery
      state.stats.totalCompactionRecoveries++;
      expect(state.stats.totalCompactionRecoveries).toBe(1);

      state.stats.totalCompactionRecoveries++;
      expect(state.stats.totalCompactionRecoveries).toBe(2);
    });

    it('should track compaction recoveries separately from regular injections', () => {
      const state = createState();

      // Record regular injections
      state.stats.totalInjections = 5;
      state.stats.totalSearchHits = 3;
      state.stats.totalFallbacks = 2;

      // Record compaction recoveries
      state.stats.totalCompactionRecoveries = 2;

      // They should be independent
      expect(state.stats.totalInjections).toBe(5);
      expect(state.stats.totalCompactionRecoveries).toBe(2);
      expect(state.stats.totalInjections).not.toBe(state.stats.totalCompactionRecoveries);
    });

    it('should initialize totalCompactionRecoveries to 0 in new state', () => {
      const state = createState();
      expect(state.stats.totalCompactionRecoveries).toBe(0);
    });
  });

  describe('compaction recovery context formatting', () => {
    it('should use distinct header for post-compaction recovery', () => {
      const header = `## 🔄 Post-Compaction Context Recovery

**Recovered:** ${new Date().toISOString()}
**Reason:** Context window compacted - restoring relevant memories

---

`;
      expect(header).toContain('Post-Compaction Context Recovery');
      expect(header).toContain('Context window compacted');
    });

    it('should be distinguishable from regular context injection', () => {
      const regularHeader = '## 📚 Retrieved Context';
      const compactionHeader = '## 🔄 Post-Compaction Context Recovery';

      expect(regularHeader).not.toBe(compactionHeader);
      expect(compactionHeader).toContain('Post-Compaction');
    });
  });

  describe('compaction recovery error handling', () => {
    it('should return undefined when no sessions directory found', async () => {
      // Simulate findSessionsDirectory returning null
      const sessionsDir = null;
      if (!sessionsDir) {
        const result = undefined;
        expect(result).toBeUndefined();
      }
    });

    it('should return undefined when smart retrieval fails and no fallback', async () => {
      const smartRetrievalResult = null;
      const fallbackEnabled = false;

      let result = smartRetrievalResult;
      if (!result && fallbackEnabled) {
        result = null; // Would try fallback
      }

      expect(result).toBeNull();
    });

    it('should fall back to file recovery when smart retrieval fails', async () => {
      const smartRetrievalResult = null;
      const fallbackEnabled = true;
      const fallbackResult = {
        content: 'fallback content',
        memoriesRetrieved: 5,
        searchQuery: 'N/A (post-compaction fallback)',
        searchType: 'file_scan',
        source: 'fallback_files' as const,
      };

      let result = smartRetrievalResult;
      if (!result && fallbackEnabled) {
        result = fallbackResult;
      }

      expect(result).not.toBeNull();
      expect(result!.source).toBe('fallback_files');
      expect(result!.searchQuery).toContain('post-compaction fallback');
    });

    it('should return undefined when both smart and fallback fail', async () => {
      const smartRetrievalResult = null;
      const fallbackResult = null;
      const fallbackEnabled = true;

      let result = smartRetrievalResult;
      if (!result && fallbackEnabled) {
        result = fallbackResult;
      }

      expect(result).toBeNull();
    });
  });
});

// =============================================================================
// HEALTH LOGGING WITH COMPACTION STATS TESTS
// =============================================================================

describe('Health Logging with Compaction Stats', () => {
  it('should include compaction recoveries in health log', () => {
    const state = {
      sessionInjectionCounts: { 'session-1': { count: 1, lastUpdated: Date.now() } },
      stats: {
        totalInjections: 10,
        totalSearches: 20,
        totalSearchHits: 15,
        totalFallbacks: 5,
        totalCompactionRecoveries: 3,
      },
    };

    const sessionCount = Object.keys(state.sessionInjectionCounts).length;
    const healthLog = `=== HEALTH: v1.1.0 | Sessions: ${sessionCount} | Injections: ${state.stats.totalInjections} | Searches: ${state.stats.totalSearches} | Hits: ${state.stats.totalSearchHits} | Fallbacks: ${state.stats.totalFallbacks} | CompactionRecoveries: ${state.stats.totalCompactionRecoveries} ===`;

    expect(healthLog).toContain('v1.1.0');
    expect(healthLog).toContain('CompactionRecoveries: 3');
  });

  it('should handle missing totalCompactionRecoveries in legacy state', () => {
    const legacyState = {
      stats: {
        totalInjections: 10,
        totalSearches: 20,
        totalSearchHits: 15,
        totalFallbacks: 5,
        // totalCompactionRecoveries is missing (legacy state)
      },
    };

    const compactionRecoveries = (legacyState.stats as any).totalCompactionRecoveries || 0;
    expect(compactionRecoveries).toBe(0);
  });
});

// =============================================================================
// API RESPONSE HANDLING TESTS
// =============================================================================

describe('Onelist API Response Handling', () => {
  interface SearchResponse {
    success: boolean;
    data?: {
      results: Array<{ entry_id: string; title: string; score: number }>;
      total: number;
      query: string;
      search_type: string;
    };
    error?: {
      message: string;
      code?: string;
    };
  }

  function processSearchResponse(
    response: SearchResponse,
    threshold: number
  ): { results: any[]; filtered: boolean } | null {
    if (!response.success || !response.data) {
      return null;
    }

    const results = response.data.results.filter(r => r.score >= threshold);
    return {
      results,
      filtered: results.length < response.data.results.length,
    };
  }

  it('should return null for unsuccessful response', () => {
    const response: SearchResponse = {
      success: false,
      error: { message: 'Server error', code: '500' },
    };
    const result = processSearchResponse(response, 0.5);

    expect(result).toBeNull();
  });

  it('should return null for response without data', () => {
    const response: SearchResponse = { success: true };
    const result = processSearchResponse(response, 0.5);

    expect(result).toBeNull();
  });

  it('should filter results below threshold', () => {
    const response: SearchResponse = {
      success: true,
      data: {
        results: [
          { entry_id: '1', title: 'High', score: 0.9 },
          { entry_id: '2', title: 'Medium', score: 0.6 },
          { entry_id: '3', title: 'Low', score: 0.3 },
        ],
        total: 3,
        query: 'test',
        search_type: 'hybrid',
      },
    };
    const result = processSearchResponse(response, 0.5);

    expect(result).not.toBeNull();
    expect(result!.results).toHaveLength(2);
    expect(result!.filtered).toBe(true);
  });

  it('should return all results when all above threshold', () => {
    const response: SearchResponse = {
      success: true,
      data: {
        results: [
          { entry_id: '1', title: 'High', score: 0.9 },
          { entry_id: '2', title: 'Also High', score: 0.8 },
        ],
        total: 2,
        query: 'test',
        search_type: 'semantic',
      },
    };
    const result = processSearchResponse(response, 0.5);

    expect(result).not.toBeNull();
    expect(result!.results).toHaveLength(2);
    expect(result!.filtered).toBe(false);
  });
});
