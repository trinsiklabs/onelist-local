# Onelist Memory Sync Plugin

**v1.1.0 - Invisible Compaction Recovery Edition**

Bidirectional memory sync between OpenClaw and Onelist. Retrieves relevant memories from Onelist Search API on session start and after compaction, and streams conversation logs to Onelist for memory extraction.

**The bot never notices compaction.** When OpenClaw compacts the context window, this plugin automatically restores relevant memories so the conversation continues seamlessly.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         OpenClaw Session                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐                      ┌──────────────────────────┐ │
│  │  Session Start   │                      │    During Session        │ │
│  │                  │                      │                          │ │
│  │  ┌────────────┐  │                      │  ┌────────────────────┐  │ │
│  │  │ Query      │  │                      │  │ File Watcher       │  │ │
│  │  │ Intent     │  │                      │  │ (sessions/*.jsonl) │  │ │
│  │  │ Extraction │  │                      │  └─────────┬──────────┘  │ │
│  │  └─────┬──────┘  │                      │            │             │ │
│  │        │         │                      │            ▼             │ │
│  │        ▼         │                      │  ┌────────────────────┐  │ │
│  │  ┌────────────┐  │                      │  │ Main Session       │  │ │
│  │  │ Onelist    │  │                      │  │ Filter             │  │ │
│  │  │ Search API │◄─┼──────────────────────┼──│ (sessions.json)    │  │ │
│  │  │ (hybrid)   │  │                      │  └─────────┬──────────┘  │ │
│  │  └─────┬──────┘  │                      │            │             │ │
│  │        │         │                      │            ▼             │ │
│  │        ▼         │                      │  ┌────────────────────┐  │ │
│  │  ┌────────────┐  │                      │  │ POST /chat-stream  │  │ │
│  │  │ Context    │  │                      │  │ /append            │  │ │
│  │  │ Injection  │  │                      │  │ /reaction          │  │ │
│  │  └────────────┘  │                      │  └────────────────────┘  │ │
│  │                  │                      │                          │ │
│  └──────────────────┘                      └──────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │         Onelist Server        │
                    │                               │
                    │  ┌─────────────────────────┐  │
                    │  │ Search API              │  │
                    │  │ - Hybrid search         │  │
                    │  │ - Semantic embeddings   │  │
                    │  │ - Keyword matching      │  │
                    │  └─────────────────────────┘  │
                    │                               │
                    │  ┌─────────────────────────┐  │
                    │  │ Livelog API             │  │
                    │  │ - Chat stream ingestion │  │
                    │  │ - Memory extraction     │  │
                    │  └─────────────────────────┘  │
                    └───────────────────────────────┘
```

## Features

### 1. Smart Memory Retrieval (NEW in v1.0.0)

**Query-based context retrieval** from Onelist Search API:

1. **Query Intent Extraction** - Analyzes recent user messages to build a search query
2. **Hybrid Search** - Combines semantic embeddings + keyword matching for best results
3. **Relevance Filtering** - Only injects memories above a configurable score threshold
4. **Token Efficiency** - 95%+ token savings vs raw message injection

The injected context looks like:

```markdown
## 📚 Retrieved Context

**Query:** "setting up kubernetes cluster"
**Retrieved:** 2026-01-15T10:30:00Z
**Method:** hybrid search | 5 relevant memories

---

**1.** Kubernetes cluster setup guide *(relevance: 92%)*

**2.** Container networking best practices *(relevance: 87%)*

...

---

*Context retrieved from Onelist memory. Continue the conversation naturally.*
```

### 2. Invisible Compaction Recovery (NEW in v1.1.0)

When OpenClaw compacts the context window (summarizing old messages to free space), the bot loses important context. This plugin **automatically restores relevant memories** via the `after_compaction` hook.

**How it works:**

1. OpenClaw fires `after_compaction` hook when compaction completes
2. Plugin queries Onelist Search API for relevant memories (same as session start)
3. Falls back to local session files if Onelist unavailable
4. Injects recovered context immediately after compaction
5. **Bot continues seamlessly** without noticing the context loss

**Key features:**

- **Bypasses rate limits** - Compaction recovery is critical and not subject to injection limits
- **Distinct header** - Uses `## 🔄 Post-Compaction Context Recovery` to distinguish from regular injection
- **Stats tracking** - Compaction recoveries tracked separately in `totalCompactionRecoveries`

The injected context looks like:

```markdown
## 🔄 Post-Compaction Context Recovery

**Recovered:** 2026-01-15T10:30:00Z
**Reason:** Context window compacted - restoring relevant memories

---

**1.** Previous conversation context *(relevance: 95%)*

**2.** Project requirements *(relevance: 89%)*

...
```

### 3. Fallback Recovery

If smart retrieval fails (no API credentials, network issues, circuit breaker open), the plugin falls back to **local session file recovery**:

1. Scans recent session files (`.jsonl`)
2. Extracts the last N messages
3. Injects them as recovered context

This ensures continuity even when Onelist is unavailable.

### 4. Livelog Sync

Streams conversation to Onelist for persistent memory extraction:

1. **File Watcher** - Monitors `~/.openclaw/agents/main/sessions/` for changes
2. **Main Session Filter** - Only syncs the active main session (via `sessions.json`)
3. **Message Streaming** - POSTs new messages to `/api/v1/chat-stream/append`
4. **Reaction Sync** - POSTs Telegram reactions to `/api/v1/chat-stream/reaction`
5. **Telegram Metadata** - Extracts user info, message IDs, reply chains

### 5. Safety Systems

- **Circuit Breaker** - Backs off on consecutive API failures (exponential backoff up to 1 hour)
- **Injection Limits** - Max 5 injections per session, 30s cooldown between injections
- **Session File Detection** - Resets limits when session file is recreated
- **File Locking** - Prevents race conditions on state file
- **Size Limits** - 5MB max file size, 50MB max total read, 4KB max message length

## Configuration

Add to your OpenClaw config:

```json
{
  "plugins": {
    "entries": {
      "onelist-memory": {
        "enabled": true,
        "config": {
          "enabled": true,

          // Onelist API credentials
          "apiUrl": "http://localhost:4000",
          "apiKey": "your-onelist-api-key",

          // Smart retrieval settings (v1.0)
          "smartRetrievalEnabled": true,
          "retrievalLimit": 10,
          "retrievalThreshold": 0.5,
          "retrievalSearchType": "hybrid",

          // Fallback settings (if smart retrieval fails)
          "fallbackEnabled": true,
          "autoInjectMessageCount": 30,
          "autoInjectHoursBack": 12,
          "autoInjectMinMessages": 3
        }
      }
    }
  }
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable the entire plugin |
| `apiUrl` | string | - | Onelist API base URL |
| `apiKey` | string | - | Onelist API key |
| `sessionId` | string | - | Custom session identifier for Livelog |

**Smart Retrieval (v1.0)**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `smartRetrievalEnabled` | boolean | `true` | Enable query-based retrieval from Onelist Search API |
| `retrievalLimit` | number | `10` | Max memories to retrieve |
| `retrievalThreshold` | number | `0.5` | Min relevance score (0-1) |
| `retrievalSearchType` | string | `"hybrid"` | Search type: `"hybrid"`, `"semantic"`, or `"keyword"` |

**Fallback Recovery**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `fallbackEnabled` | boolean | `true` | Fall back to session file recovery if search fails |
| `autoInjectMessageCount` | number | `30` | Max messages to recover |
| `autoInjectHoursBack` | number | `12` | How many hours back to look |
| `autoInjectMinMessages` | number | `3` | Minimum messages required to trigger injection |

## API Endpoints Used

### Onelist Search API

```
POST /api/v1/search
Authorization: Bearer <api_key>
Content-Type: application/json

{
  "query": "search query",
  "search_type": "hybrid",
  "limit": 10,
  "semantic_weight": 0.7,
  "keyword_weight": 0.3
}
```

### Onelist Livelog API

```
POST /api/v1/chat-stream/append
Authorization: Bearer <api_key>
Content-Type: application/json

{
  "session_id": "session-uuid",
  "message": {
    "role": "user",
    "content": "message content",
    "timestamp": "2026-01-15T10:30:00Z",
    "message_id": "msg-uuid",
    "source": {
      "channel": "telegram",
      "telegram_user_id": "123456",
      "handle": "@username"
    }
  }
}
```

```
POST /api/v1/chat-stream/reaction
Authorization: Bearer <api_key>
Content-Type: application/json

{
  "target_message_id": "msg-uuid",
  "emoji": "👍",
  "from_user": "username"
}
```

## Minimal Setup

### Smart Retrieval Only (requires Onelist)

```json
{
  "plugins": {
    "entries": {
      "onelist-memory": {
        "enabled": true,
        "config": {
          "apiUrl": "http://localhost:4000",
          "apiKey": "your-api-key",
          "fallbackEnabled": false
        }
      }
    }
  }
}
```

### Fallback Only (no API needed)

```json
{
  "plugins": {
    "entries": {
      "onelist-memory": {
        "enabled": true,
        "config": {
          "smartRetrievalEnabled": false,
          "fallbackEnabled": true,
          "autoInjectMessageCount": 50
        }
      }
    }
  }
}
```

## Session Files

Session transcripts are stored at:

```
~/.openclaw/agents/main/sessions/*.jsonl
```

The main session is identified via `sessions.json`:

```json
{
  "agent:main:main": {
    "sessionId": "abc123",
    "sessionFile": "/root/.openclaw/agents/main/sessions/abc123.jsonl"
  }
}
```

## State Persistence

Plugin state is stored at `~/.openclaw/onelist-memory-state.json`:

```json
{
  "version": 3,
  "lastInjectionTime": 1705312200000,
  "sessionInjectionCounts": {
    "abc123": {
      "count": 2,
      "lastUpdated": 1705312200000,
      "lastFileBirthTime": 1705310000000
    }
  },
  "stats": {
    "totalInjections": 42,
    "totalBlocked": 5,
    "totalSearches": 100,
    "totalSearchHits": 85,
    "totalFallbacks": 15,
    "totalCompactionRecoveries": 3
  }
}
```

## Hard Limits

| Limit | Value | Description |
|-------|-------|-------------|
| `MAX_INJECTIONS_PER_SESSION` | 5 | Raised from 3 (search results are bounded) |
| `INJECTION_COOLDOWN_MS` | 30,000 | Reduced from 60s (less risk with bounded results) |
| `MAX_FILE_SIZE` | 5 MB | Max session file size to process |
| `MAX_TOTAL_READ` | 50 MB | Max total bytes to read across all files |
| `MAX_MESSAGE_LENGTH` | 4,000 | Truncate long messages |
| `SEARCH_TIMEOUT_MS` | 8,000 | Onelist search request timeout |
| `MAX_QUERY_LENGTH` | 500 | Max characters in search query |

## Environment Variables

The plugin respects these environment variables for path configuration:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_HOME` | `~/.openclaw` | OpenClaw installation directory |
| `HOME` / `USERPROFILE` | (system) | User home directory (fallback) |
| `XDG_CONFIG_HOME` | (none) | XDG config directory (Linux fallback) |
| `APPDATA` | (none) | Windows AppData directory (fallback) |

The plugin stores state at `$OPENCLAW_HOME/onelist-memory-state.json` and reads session files from `$OPENCLAW_HOME/agents/main/sessions/`.

### Custom Installation Location

If OpenClaw is installed in a non-standard location, set `OPENCLAW_HOME`:

```bash
export OPENCLAW_HOME=/custom/path/to/openclaw
```

## Requirements

- OpenClaw with plugin support (2026.1.x+)
- For smart retrieval: Onelist instance with Search API enabled
- For Livelog sync: Onelist API key with write permissions

## Troubleshooting

### No context injected

1. Check if injection limit reached (max 5 per session)
2. Check circuit breaker status (backs off after 5 consecutive failures)
3. Check if session file has messages (min 3 required for fallback)
4. Check API credentials if using smart retrieval

### Circuit breaker open

The plugin backs off exponentially on API failures:
- 5 failures: 1 minute backoff
- 6 failures: 2 minute backoff
- 7 failures: 4 minute backoff
- Max: 1 hour backoff

Reset by restarting OpenClaw or waiting for backoff to expire.

### Health logging

The plugin logs health stats hourly:

```
[onelist-memory] === HEALTH: v1.1.0 | Sessions: 3 | Injections: 42 | Searches: 100 | Hits: 85 | Fallbacks: 15 | CompactionRecoveries: 3 ===
```

## Development

Plugin structure:

```
~/.openclaw/workspace/extensions/onelist-memory/
├── openclaw.plugin.json   # Plugin manifest
├── index.ts               # Main plugin code (1,561 lines)
└── README.md              # This file
```

Install as workspace extension:

```bash
openclaw plugins install ./extensions/onelist-memory
```

## Changelog

### v1.1.0

- **NEW: Invisible Compaction Recovery** - `after_compaction` hook restores memories after context window compaction
- **NEW: Compaction Bypasses Rate Limits** - Critical recovery not subject to injection limits
- **NEW: Stats Tracking** - `totalCompactionRecoveries` tracked separately
- Bot never notices compaction - memories restored automatically and seamlessly
- All v1.0.0 functionality preserved

### v1.0.0

- **NEW: Smart Memory Retrieval** - Query-based context from Onelist Search API
- **NEW: Hybrid Search** - Semantic + keyword search for best results
- **NEW: Query Intent Extraction** - Analyzes conversation to build search queries
- **NEW: Relevance Threshold** - Filter memories by score
- **IMPROVED: Injection Limits** - Raised to 5 per session (search results are bounded)
- **IMPROVED: Cooldown** - Reduced to 30s (less risk with bounded results)
- **IMPROVED: Stats Tracking** - Search hits, fallbacks, total searches
- Kept all Livelog sync functionality from v0.5.7

### v0.5.7

- Main session filtering via `sessions.json`
- Telegram metadata extraction (user info, message IDs, reactions)
- Reaction sync via `/chat-stream/reaction`
- Message blocklist for system messages

### v0.5.x

- Circuit breaker for API resilience
- File locking for state persistence
- Session file recreation detection
- Health logging

### v0.2.0

- Auto-inject recovery via `before_agent_start` hook
- Local session file parsing
- Basic Livelog sync

### v0.1.0

- Initial release with Onelist sync functionality

---

*Maintained by Hydra, Chief Resilience Officer*
