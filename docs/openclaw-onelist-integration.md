# OpenClaw + Onelist Integration Architecture

**Version:** 1.0  
**Date:** 2026-02-01  
**Author:** Subline Coordinator (Stream)

---

## Overview

This document describes how OpenClaw integrates with Onelist Local as its memory backend, enabling AI agents to have persistent, semantic memory that survives across sessions.

```
┌──────────────────────────────────────────────────────────────┐
│                         OpenClaw                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   Gateway    │  │    Agent     │  │  Memory Plugin   │   │
│  │   (18789)    │  │   Runtime    │  │  (onelist-mem)   │   │
│  └──────────────┘  └──────────────┘  └────────┬─────────┘   │
│                                                │              │
└────────────────────────────────────────────────│──────────────┘
                                                 │
                                    POST /api/v1/chat-stream
                                                 │
                                                 ▼
┌──────────────────────────────────────────────────────────────┐
│                         Onelist                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │  Chat Stream │  │   Reader     │  │    Searcher      │   │
│  │     API      │──│   Agent      │──│     Agent        │   │
│  └──────────────┘  └──────────────┘  └──────────────────┘   │
│                           │                    │             │
│                           ▼                    ▼             │
│                    ┌───────────────────────────────┐         │
│                    │     PostgreSQL + pgvector     │         │
│                    │   (entries, embeddings, etc)  │         │
│                    └───────────────────────────────┘         │
└──────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### 1. Chat Message Flow

```
User → Telegram → OpenClaw → onelist-memory plugin → Onelist Chat Stream API
                                                            │
                                                            ▼
                                                      Reader Agent
                                                            │
                                                            ▼
                                                    Entry + Embeddings
```

1. **User sends message** via Telegram (or other channel)
2. **OpenClaw Gateway** receives and routes to agent
3. **Agent processes** and generates response
4. **Session transcript** is written to JSONL file
5. **onelist-memory plugin** watches session files
6. **New messages** are POSTed to Onelist's `/api/v1/chat-stream/append`
7. **Reader Agent** extracts memories from accumulated chat
8. **Memories stored** as Onelist entries with vector embeddings

### 2. Memory Retrieval Flow

```
Agent needs context → memory_search tool → Onelist Searcher API → Semantic results
                                                                        │
                                                                        ▼
                                                              Injected into prompt
```

1. **Agent invokes** `memory_search` tool (or automatic context injection)
2. **Query sent** to Onelist's `/api/v1/search` with embedding
3. **Searcher Agent** finds semantically similar entries
4. **Results returned** with relevance scores
5. **Context injected** into agent's prompt

---

## Installation Variants

### Variant A: Standalone OpenClaw (add Onelist later)

```bash
# Install OpenClaw normally
curl -fsSL https://get.openclaw.ai | bash

# Later: add Onelist integration
openclaw plugins install onelist-memory
openclaw config set plugins.entries.onelist-memory.enabled true
openclaw config set plugins.entries.onelist-memory.config.apiUrl "http://localhost:4000"
openclaw config set plugins.entries.onelist-memory.config.apiKey "YOUR_KEY"
```

### Variant B: OpenClaw with Onelist from Start (Recommended)

```bash
# One command installs both, pre-configured
curl -fsSL https://get.onelist.my/local | bash -s -- --with-openclaw
```

This:
- Installs Onelist + PostgreSQL
- Installs OpenClaw
- Generates API key automatically
- Configures memory plugin
- Starts everything

### Variant C: Docker Compose (Production)

```bash
cd onelist-local
docker compose \
  -f docker/docker-compose.yml \
  -f docker/docker-compose.openclaw.yml \
  up -d
```

---

## Configuration

### OpenClaw Side

The `onelist-memory` plugin requires configuration in `~/.openclaw/openclaw.json`:

```json
{
  "plugins": {
    "load": {
      "paths": ["/root/.openclaw/workspace/extensions/onelist-memory"]
    },
    "entries": {
      "onelist-memory": {
        "enabled": true,
        "config": {
          "apiUrl": "http://localhost:4000",
          "apiKey": "ol_live_xxxxxxxxxxxx",
          "enabled": true
        }
      }
    }
  }
}
```

### Onelist Side

Enable the chat-stream API and agents:

```bash
# .env.local or environment
ONELIST_CHAT_STREAM_ENABLED=true
ONELIST_READER_ENABLED=true
ONELIST_SEARCHER_ENABLED=true
ONELIST_OBAN_QUEUES=default,reader,searcher
```

---

## API Endpoints Used

### Chat Stream API

**Append message to stream:**
```
POST /api/v1/chat-stream/append
Authorization: Bearer {api_key}
Content-Type: application/json

{
  "session_id": "telegram:main:12345",
  "message": {
    "role": "user",
    "content": "Remember that I prefer dark roast coffee",
    "timestamp": "2026-02-01T00:00:00Z",
    "message_id": "abc123"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "stream_id": "cs_xxxxx",
  "message_count": 42
}
```

### Search API

**Semantic search:**
```
GET /api/v1/search?q=coffee+preferences&limit=5
Authorization: Bearer {api_key}
```

**Response:**
```json
{
  "results": [
    {
      "id": "entry_xxx",
      "content": "User prefers dark roast coffee, especially Ethiopian single-origin",
      "similarity": 0.92,
      "created_at": "2026-01-15T..."
    }
  ]
}
```

---

## Memory Extraction Pipeline

When the Reader Agent processes chat streams:

```
Chat Messages (raw)
       │
       ▼
┌──────────────────┐
│  Aggregation     │  ← Groups messages by session/time
└──────────────────┘
       │
       ▼
┌──────────────────┐
│  Entity Extract  │  ← Names, places, preferences, facts
└──────────────────┘
       │
       ▼
┌──────────────────┐
│  Deduplication   │  ← Merges with existing memories
└──────────────────┘
       │
       ▼
┌──────────────────┐
│  Embedding Gen   │  ← OpenAI text-embedding-3-small
└──────────────────┘
       │
       ▼
┌──────────────────┐
│  Entry Storage   │  ← PostgreSQL + pgvector
└──────────────────┘
```

### Memory Types Extracted

| Type | Example | Storage |
|------|---------|---------|
| **Facts** | "User lives in Berlin" | Entry with `#memory #fact` |
| **Preferences** | "Prefers dark mode" | Entry with `#memory #preference` |
| **Events** | "Met with Sarah on Tuesday" | Entry with date + `#memory #event` |
| **Tasks** | "Need to review PR tomorrow" | Entry with `#todo` tag |
| **Relationships** | "Sarah is the project lead" | Entry with `#memory #relationship` |

---

## Session ID Convention

The `session_id` field follows this format:

```
{channel}:{agent}:{user_or_group_id}
```

Examples:
- `telegram:main:123456789` — Telegram DM with user
- `telegram:main:-1001234567` — Telegram group
- `cli:main:local` — Local CLI session
- `api:river:user_abc` — API session with River agent

This allows:
- Grouping related conversations
- Per-user memory isolation
- Cross-session context retrieval

---

## Automatic Context Injection

When OpenClaw starts a new turn, it can automatically query Onelist for relevant context:

### Agent Prompt Injection (future)

```markdown
## Relevant Memories

Based on recent conversation, these memories may be relevant:

- User prefers dark roast coffee (similarity: 0.92)
- User is vegetarian (similarity: 0.87)
- Last coffee shop visited was Blue Bottle in SF (similarity: 0.84)
```

### Implementation Options

1. **Pre-turn hook** — Query Onelist before each turn, inject into system prompt
2. **Tool-based** — Agent explicitly calls `memory_search` when needed
3. **Hybrid** — Automatic for high-relevance, tool for deep searches

---

## Security Considerations

### API Key Scoping

Onelist API keys should be scoped:

```json
{
  "key": "ol_live_xxxxx",
  "scopes": ["chat-stream:write", "search:read"],
  "rate_limit": 100,  // per minute
  "allowed_sessions": ["telegram:*", "cli:*"]
}
```

### Data Isolation

- Each OpenClaw instance should have its own API key
- Shared instances should use separate Onelist accounts
- Group chats should have consent before memory extraction

### Encryption

- API keys should be stored encrypted in OpenClaw config
- Onelist supports E2EE for sensitive memories
- Network should use HTTPS in production

---

## Deployment Topologies

### Topology 1: Same Machine (Recommended for personal use)

```
┌─────────────────────────────┐
│         Your VPS            │
│  ┌─────────┐  ┌──────────┐  │
│  │OpenClaw │←→│ Onelist  │  │
│  │ :18789  │  │  :4000   │  │
│  └─────────┘  └──────────┘  │
│              ↓              │
│        ┌──────────┐         │
│        │PostgreSQL│         │
│        │  :5432   │         │
│        └──────────┘         │
└─────────────────────────────┘
```

### Topology 2: Separate Containers (Docker)

```
┌─────────────────────────────────────────┐
│              Docker Network             │
│                                         │
│  ┌─────────┐  ┌──────────┐  ┌────────┐ │
│  │openclaw │  │ onelist  │  │postgres│ │
│  └────┬────┘  └────┬─────┘  └────┬───┘ │
│       │            │             │      │
│       └────────────┴─────────────┘      │
│               onelist-network            │
└─────────────────────────────────────────┘
```

### Topology 3: Multi-Machine (Team use)

```
┌───────────────┐     ┌───────────────┐
│  User 1 VPS   │     │  User 2 VPS   │
│  ┌─────────┐  │     │  ┌─────────┐  │
│  │OpenClaw │  │     │  │OpenClaw │  │
│  └────┬────┘  │     │  └────┬────┘  │
└───────│───────┘     └───────│───────┘
        │                     │
        └──────────┬──────────┘
                   │
         ┌─────────▼─────────┐
         │  Shared Onelist   │
         │   (cloud/VPS)     │
         └───────────────────┘
```

---

## Troubleshooting

### Plugin Not Syncing

```bash
# Check plugin is loaded
openclaw logs | grep onelist-memory

# Verify config
openclaw config get plugins.entries.onelist-memory

# Test API manually
curl -H "Authorization: Bearer $API_KEY" http://localhost:4000/api/health
```

### Memories Not Being Extracted

```bash
# Check Reader agent queue
curl http://localhost:4000/api/admin/oban/queues

# Force reprocess
curl -X POST http://localhost:4000/api/v1/chat-stream/reprocess \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"session_id": "telegram:main:12345"}'
```

### Search Not Finding Memories

```bash
# Check embeddings were generated
psql onelist_local -c "SELECT COUNT(*) FROM entry_embeddings"

# Verify vector index
psql onelist_local -c "SELECT * FROM pg_indexes WHERE indexname LIKE '%vector%'"
```

---

## Future Enhancements

1. **Bi-directional sync** — Onelist entries → OpenClaw workspace files
2. **Memory consolidation** — Periodic merging of similar memories
3. **Forgetting** — Automatic pruning of stale/irrelevant memories
4. **Cross-agent memory** — Shared memories between OpenClaw agents
5. **Memory attribution** — Track which agent created each memory
6. **Export/import** — Portable memory format (JSON-LD, Markdown)

---

## Related Documents

- [LOCAL_QUICKSTART.md](./LOCAL_QUICKSTART.md) — Quick start guide
- [DEPLOYMENT.md](./DEPLOYMENT.md) — Full deployment guide
- [api_guide.md](./api_guide.md) — API reference

---

*Integration designed by Subline Coordinator*
