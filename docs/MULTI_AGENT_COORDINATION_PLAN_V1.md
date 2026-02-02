# Multi-Agent Memory Coordination Implementation Plan

## Version 1.0 - External API Agents Focus

**Scope**: Claude Code + OpenClaw plugins sharing Onelist via API
**Date**: 2026-02-02

---

## Overview

This plan addresses coordination challenges when multiple external API clients (Claude Code, OpenClaw, and potentially other agents) share Onelist as their memory backend. All agents connect via the REST API using Bearer token authentication.

## Repositories Involved

- **onelist.com** - Main Onelist backend (Elixir/Phoenix)
- **onelist-local** - Plugin extensions (TypeScript/JavaScript)

---

## Phase 1: Source Attribution (Foundation) - Week 1-2

**Goal**: Every memory knows which agent created it.

### 1.1 Onelist Backend

**New Migration**: `priv/repo/migrations/YYYYMMDD_add_agent_attribution.exs`

```sql
-- entries table
ALTER TABLE entries ADD COLUMN agent_id VARCHAR(64);
ALTER TABLE entries ADD COLUMN agent_version VARCHAR(32);
ALTER TABLE entries ADD COLUMN agent_instance_id VARCHAR(64);

-- memories table
ALTER TABLE memories ADD COLUMN source_agent_id VARCHAR(64);
ALTER TABLE memories ADD COLUMN derivation_depth INTEGER DEFAULT 0;
ALTER TABLE memories ADD COLUMN derived_from_memory_id UUID REFERENCES memories(id);
ALTER TABLE memories ADD COLUMN content_hash VARCHAR(64);

-- api_keys table (for Phase 5 prep)
ALTER TABLE api_keys ADD COLUMN agent_id VARCHAR(64);
ALTER TABLE api_keys ADD COLUMN scopes VARCHAR(255)[] DEFAULT '{}';

-- Indexes
CREATE INDEX idx_entries_agent_id ON entries(agent_id);
CREATE INDEX idx_memories_source_agent_id ON memories(source_agent_id);
CREATE INDEX idx_memories_content_hash ON memories(content_hash);
```

**Schema Updates**:
- `lib/onelist/entries/entry.ex` - Add `agent_id`, `agent_version`, `agent_instance_id` fields
- `lib/onelist/reader/memory.ex` - Add `source_agent_id`, `derivation_depth`, `derived_from_memory_id`, `content_hash`

**API Plug Enhancement**: `lib/onelist_web/plugs/api_authenticate.ex`
- Extract `X-Agent-Id`, `X-Agent-Version`, `X-Agent-Instance-Id` headers
- Assign to `conn.assigns[:agent_info]`

**Search Enhancement**: `lib/onelist_web/controllers/api/v1/search_controller.ex`
- Add `exclude_agents` and `include_agents` filter params
- Return `attribution` object in results

### 1.2 onelist-memory Plugin

**File**: `extensions/onelist-memory/index.ts`

```typescript
const AGENT_ID = 'onelist-memory';
const AGENT_VERSION = '1.0.0';

// Add to all fetch() calls:
headers: {
  'X-Agent-Id': AGENT_ID,
  'X-Agent-Version': AGENT_VERSION,
  'X-Agent-Instance-Id': state.instanceId,
}

// Update search to exclude own memories:
payload.exclude_agents = [AGENT_ID];
```

### 1.3 claude-code Plugin

**File**: `extensions/claude-code/scripts/lib/api.js`

```javascript
const AGENT_ID = 'claude-code';
const AGENT_VERSION = '1.0.0';

// Add headers to all requests
headers['X-Agent-Id'] = AGENT_ID;
headers['X-Agent-Version'] = AGENT_VERSION;
headers['X-Agent-Instance-Id'] = instanceId;
```

---

## Phase 2: Feedback Loop Prevention - Week 3

**Goal**: Prevent memories from degrading through re-interpretation.

### 2.1 New Onelist Module

**File**: `lib/onelist/memory_lineage.ex`

```elixir
defmodule Onelist.MemoryLineage do
  @max_derivation_depth 3

  def check_derivation(content, source_agent_id, user_id)
  def calculate_derivation_depth(derived_from_id, source_agent_id)
  def validate_depth(depth)
end
```

**Functions**:
- `check_derivation/3` - Detect exact duplicates via content_hash, high similarity
- `calculate_derivation_depth/2` - Increment depth when different agent re-processes
- `validate_depth/1` - Enforce max depth of 3

### 2.2 Integration Points

- Update `Onelist.Reader.create_memory/3` to call lineage checks
- Reject memories that exceed derivation depth
- Return warnings for high-similarity content

### 2.3 New API Endpoint

`POST /api/v1/memories/check-derivation` - Pre-flight check before writing

---

## Phase 3: Coordination Layer - Week 4-5

**Goal**: Multiple plugin instances coordinate to avoid races.

### 3.1 Shared Coordination File

**Location**: `~/.onelist/coordination/state.json`

```typescript
interface CoordinationState {
  version: number;
  globalCircuitBreaker: {
    consecutiveFailures: number;
    backoffUntil: number;
  };
  agentRateLimits: {
    [agentId: string]: {
      writesInWindow: number;
      windowStart: number;
    };
  };
  agentHealth: {
    [agentId: string]: {
      lastSeen: number;
      status: 'healthy' | 'degraded' | 'unhealthy';
    };
  };
}
```

### 3.2 New Shared Module

**File**: `extensions/onelist-memory/coordination.ts` (shared between plugins)

```typescript
export class CoordinationManager {
  constructor(agentId: string)
  canWrite(): { allowed: boolean; reason?: string; waitMs?: number }
  recordWrite(): void
  recordFailure(error: string): void
  updateHealth(status: string): void
}
```

**Features**:
- File-based locking (5s timeout, 50ms retry)
- Global circuit breaker (shared across all agents)
- Per-agent rate limiting (30 writes/minute)
- Health aggregation

### 3.3 Plugin Integration

- onelist-memory: Replace local circuit breaker with CoordinationManager
- claude-code: Add CoordinationManager (currently has no rate limiting)

---

## Phase 4: Resilience & Fallback - Week 6

**Goal**: Plugins work even when Onelist unavailable.

### 4.1 Local Cache Layer

**New File**: `extensions/onelist-memory/local-cache.ts`

```typescript
export class LocalMemoryCache {
  constructor(agentId: string)
  cacheSearchResults(query: string, results: CachedMemory[]): void
  getCachedResults(query: string, limit: number): CachedMemory[]
}
```

**Features**:
- Cache location: `~/.onelist/cache/{agent}-memory-cache.json`
- Max age: 24 hours
- Fuzzy query matching for cache hits
- Auto-pruning of old entries

### 4.2 Fallback Strategy

```typescript
async function retrieveRelevantMemories() {
  if (circuitBreakerOpen) {
    return tryLocalCache(query);  // Offline mode
  }

  try {
    const results = await searchOnelist(query);
    memoryCache.cacheSearchResults(query, results);  // Cache for later
    return results;
  } catch {
    return tryLocalCache(query);  // Fallback on error
  }
}
```

### 4.3 Health Check

**New Endpoint**: `GET /api/v1/health`
- Returns component status (database, embeddings)
- Plugins check periodically (every 5 min)
- Update coordination state with health

---

## Phase 5: Security Hardening - Week 7-8

**Goal**: Per-agent API keys, audit logging, anomaly detection.

### 5.1 Scoped API Keys

**Schema**: Already added in Phase 1 (`agent_id`, `scopes` fields)

**Scopes**: `read`, `write`, `search`, `inject`, `admin`

**Enforcement**: Update `ApiAuthenticate` plug to check scope for action

### 5.2 Audit Logging

**New Migration**: `priv/repo/migrations/YYYYMMDD_create_audit_logs.exs`

```sql
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  api_key_id UUID REFERENCES api_keys(id),
  agent_id VARCHAR(64),
  action VARCHAR(100) NOT NULL,
  resource_type VARCHAR(50),
  resource_id UUID,
  request_ip VARCHAR(45),
  request_path VARCHAR(255),
  metadata JSONB DEFAULT '{}',
  inserted_at TIMESTAMPTZ DEFAULT NOW()
);
```

**New Module**: `lib/onelist/audit_log.ex`
- `log(conn, action, resource_type, resource_id, metadata)`
- Integrate with entry/memory create/update actions

### 5.3 Anomaly Detection

**New Module**: `lib/onelist/security/anomaly_detector.ex`
- Track request rates per agent
- Flag rate spikes (3x baseline)
- Check content for injection patterns

---

## Phase 6: Opportunity Enablement - Week 9-10

**Goal**: Enable collective intelligence features.

### 6.1 Enhanced Search Attribution

Return in search results:
```json
{
  "attribution": {
    "agent_id": "claude-code",
    "agent_version": "1.0.0",
    "created_at": "2026-02-01T10:00:00Z",
    "derivation_depth": 0
  }
}
```

### 6.2 Knowledge Synthesis API

**New Endpoint**: `POST /api/v1/synthesis`

```json
{
  "topic": "project alpha deadlines",
  "include_agents": ["claude-code", "onelist-memory"],
  "time_range": {"from": "2026-01-01", "to": "2026-02-01"}
}
```

**Returns**: Aggregated view by agent, timeline, summary

### 6.3 Unified Timeline API

**New Endpoint**: `GET /api/v1/timeline`

Query params: `from`, `to`, `agents`, `limit`

Returns chronological events across all agents.

---

## Critical Files Summary

### Onelist Backend (onelist.com)
| File | Changes |
|------|---------|
| `lib/onelist/entries/entry.ex` | Add agent_id, agent_version, agent_instance_id |
| `lib/onelist/reader/memory.ex` | Add derivation tracking fields |
| `lib/onelist/api_keys/api_key.ex` | Add agent_id, scopes |
| `lib/onelist_web/plugs/api_authenticate.ex` | Extract agent headers, scope validation |
| `lib/onelist_web/controllers/api/v1/search_controller.ex` | Agent filtering |
| `lib/onelist/memory_lineage.ex` | NEW: Feedback loop prevention |
| `lib/onelist/audit_log.ex` | NEW: Audit logging |
| `lib/onelist/synthesis.ex` | NEW: Knowledge synthesis |

### Plugins (onelist-local)
| File | Changes |
|------|---------|
| `extensions/onelist-memory/index.ts` | Agent headers, coordination integration |
| `extensions/onelist-memory/coordination.ts` | NEW: Shared coordination |
| `extensions/onelist-memory/local-cache.ts` | NEW: Offline cache |
| `extensions/claude-code/scripts/lib/api.js` | Agent headers |
| `extensions/claude-code/scripts/lib/coordination.js` | NEW: Coordination |

---

## Verification Plan

### Phase 1 Testing
```bash
# Backend
mix test test/onelist/entries_test.exs
mix test test/onelist_web/controllers/api/v1/entry_controller_test.exs

# Plugins
cd extensions/onelist-memory && npm test
cd extensions/claude-code && npm test
```

### Integration Testing
1. Start Onelist locally
2. Run claude-code with agent headers → verify entries have agent_id
3. Run onelist-memory with agent headers → verify search excludes own agent
4. Stop Onelist → verify fallback to cache works

### Multi-Agent Testing
1. Run 2 claude-code instances simultaneously
2. Verify coordination state updates correctly
3. Verify rate limiting applies across instances
4. Verify no duplicate memories created

---

## Rollout Order

| Week | Phase | Focus |
|------|-------|-------|
| 1-2 | 1 | Source Attribution (backend + plugins) |
| 3 | 2 | Feedback Loop Prevention |
| 4-5 | 3 | Coordination Layer |
| 6 | 4 | Resilience/Fallback |
| 7-8 | 5 | Security Hardening |
| 9-10 | 6 | Opportunity Enablement |

All phases are backward compatible - existing data and API clients continue to work.

---

## V1 Scope Boundaries

**In Scope (V1)**:
- External API agents (Claude Code, OpenClaw)
- REST API coordination via headers
- File-based local coordination between plugins
- Single Onelist instance

**Out of Scope (V2 candidates)**:
- Internal Onelist agents (Reader, Feeder, River, etc.)
- WebSocket/real-time coordination
- Distributed Onelist deployment
- Agent-to-agent direct communication
- MCP server integration
- Browser extension agents
- Mobile app agents
