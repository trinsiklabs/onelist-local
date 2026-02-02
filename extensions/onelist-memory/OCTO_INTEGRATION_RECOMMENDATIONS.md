# OCTO Integration Recommendations

**Analysis Date:** 2026-02-02

This document analyzes the [trinsiklabs/octo](https://github.com/trinsiklabs/octo) repository and recommends how its error recovery patterns should integrate with the onelist-memory OpenClaw plugin.

## OCTO Architecture Summary

OCTO (OpenClaw Token Optimizer) provides a multi-layer error recovery and health monitoring system:

```
┌─────────────────────────────────────────────────────────────────┐
│                    OCTO Monitoring Stack                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────┐ │
│  │ Bloat Sentinel   │   │ Session Monitor  │   │ Watchdog     │ │
│  │ (Real-time)      │   │ (Python)         │   │ (Cron)       │ │
│  │                  │   │                  │   │              │ │
│  │ • Multi-layer    │   │ • Token est.     │   │ • Gateway    │ │
│  │   detection      │   │ • Context util   │   │   health     │ │
│  │ • Nested blocks  │   │ • Growth rate    │   │ • Auto-bump  │ │
│  │ • Rapid growth   │   │ • JSON output    │   │ • Archival   │ │
│  └──────────────────┘   └──────────────────┘   └──────────────┘ │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                    Surgery Script                            ││
│  │  Interactive recovery with diagnostics and notifications     ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                 PG Health Check (Onelist)                    ││
│  │  Database monitoring for Onelist deployments                 ││
│  └──────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Key OCTO Error Recovery Components

### 1. Bloat Sentinel (`bloat-sentinel.sh`)

**Multi-layer detection with tuned thresholds:**

| Layer | Detection | Confidence | Action |
|-------|-----------|------------|--------|
| 1 | Nested injection BLOCKS in single message | DEFINITIVE | Clean + restart |
| 2 | Rapid growth (>1MB/min) WITH injection markers | STRONG | Clean + restart |
| 3 | Size >10MB WITH multiple markers | MODERATE | Clean + restart |
| 4 | Total markers >10 | MONITOR | Log only |

**Key insight:** Layer 2 requires BOTH rapid growth AND injection markers to avoid false positives on legitimate large sessions.

### 2. Watchdog Service (`openclaw-watchdog.sh`)

**Cron-based health monitoring:**
- Runs every minute
- Checks gateway process
- Detects bloated sessions (>10MB)
- Counts overflow errors in logs
- Auto-bumps on critical issues
- Archives bloated sessions before restart

### 3. Surgery Script (`bump-openclaw-bot.sh`)

**Interactive/self-bump recovery:**
- Comprehensive health check
- Gateway memory monitoring (Linux only)
- Session analysis (size, injection markers)
- Rate limit error tracking from logs
- Diagnostic logging for post-mortem
- Notification file for agent awareness

### 4. Session Monitor (`session_monitor.py`)

**Python-based detailed analysis:**
- Token estimation (~4 chars per token)
- Context utilization tracking
- Growth rate calculation (KB/min over 5-minute window)
- Status categorization (HEALTHY/WARNING/CRITICAL)

## Recommendations for onelist-memory Plugin

### 1. Coordinate Injection Counting with OCTO

**Current state:** Both systems count injection markers independently.

**Recommendation:** Standardize the injection marker format and share counts:

```typescript
// In index.ts - Update header format to be OCTO-compatible
const INJECTION_MARKER = `[INJECTION-DEPTH:${depth}]`;  // Already compatible!

// Add OCTO coordination function
async function reportToOcto(sessionId: string, injectionCount: number): Promise<void> {
  // Write to shared state file that OCTO can read
  const octoStateFile = `${OCTO_HOME}/onelist-memory-state.json`;
  // ... coordinate with OCTO's state tracking
}
```

**Why:** OCTO's bloat sentinel already looks for `[INJECTION-DEPTH:]` markers. The onelist-memory plugin should either:
- Use a different marker format to avoid double-counting, OR
- Coordinate with OCTO to share injection counts

### 2. Add OCTO-Compatible Health Reporting

**Recommendation:** Add endpoint/file for OCTO to query plugin health:

```typescript
// New function to export plugin health for OCTO
function exportHealthForOcto(): {
  lastInjectionTime: number;
  totalInjections: number;
  totalSearches: number;
  searchHitRate: number;
  circuitBreakerOpen: boolean;
  backoffRemaining: number;
} {
  const state = loadPersistentState();
  return {
    lastInjectionTime: state.lastInjectionTime,
    totalInjections: state.stats.totalInjections,
    totalSearches: state.stats.totalSearches,
    searchHitRate: state.stats.totalSearchHits / state.stats.totalSearches,
    circuitBreakerOpen: shouldSkipOnelist(),
    backoffRemaining: Math.max(0, onelistCircuitBreaker.backoffUntil - Date.now()),
  };
}
```

### 3. Integrate with OCTO's PG Health Check

**Current state:** OCTO has `pg-health-check.sh` for Onelist database monitoring.

**Recommendation:** The onelist-memory plugin should check Onelist health before making API calls:

```typescript
// Before calling Onelist API, check if OCTO reports database issues
async function checkOnelistHealth(): Promise<boolean> {
  const healthFile = `${OCTO_HOME}/onelist-health.json`;
  try {
    if (fs.existsSync(healthFile)) {
      const health = JSON.parse(fs.readFileSync(healthFile, 'utf-8'));
      if (health.status === 'CRITICAL') {
        logger.warn('Onelist database health is CRITICAL - skipping API calls');
        return false;
      }
    }
  } catch {
    // Ignore - proceed with API call
  }
  return true;
}
```

### 4. Add Self-Bump Awareness

**Current state:** When OCTO bumps the gateway, the plugin loses state.

**Recommendation:** Check for OCTO bump notifications on startup:

```typescript
// In register() function
const BUMP_NOTIFY_FILE = `${OPENCLAW_HOME}/workspace/.surgery-bump-notice`;
const WATCHDOG_NOTIFY_FILE = `${OPENCLAW_HOME}/workspace/.watchdog-bump-notice`;

function checkForBumpNotification(logger: Logger): void {
  for (const notifyFile of [BUMP_NOTIFY_FILE, WATCHDOG_NOTIFY_FILE]) {
    if (fs.existsSync(notifyFile)) {
      try {
        const content = fs.readFileSync(notifyFile, 'utf-8');
        logger.info(`Post-bump recovery: Found ${path.basename(notifyFile)}`);
        logger.info(`Reason: ${content.match(/\*\*Reason:\*\* (.+)/)?.[1] || 'Unknown'}`);
        // Reset plugin state after bump
        resetState();
        // Delete notification after processing
        fs.unlinkSync(notifyFile);
      } catch (err) {
        logger.error(`Failed to process bump notification: ${String(err)}`);
      }
    }
  }
}
```

### 5. Coordinate Archival Paths

**Current state:** Both systems archive sessions to different locations.

| System | Archive Path |
|--------|-------------|
| OCTO Watchdog | `~/.openclaw/workspace/session-archives/watchdog/YYYY-MM-DD/` |
| OCTO Surgery | `~/.openclaw/workspace/session-archives/surgery/YYYY-MM-DD/` |
| OCTO Sentinel | `~/.openclaw/workspace/session-archives/bloated/YYYY-MM-DD/` |
| onelist-memory | N/A (doesn't archive) |

**Recommendation:** If onelist-memory ever needs to archive, use consistent paths:
```typescript
const ARCHIVE_BASE = `${OPENCLAW_HOME}/workspace/session-archives`;
const PLUGIN_ARCHIVE = `${ARCHIVE_BASE}/onelist-memory/${date}/`;
```

## Missing Components to Add to onelist-memory

### 1. Growth Rate Tracking

OCTO tracks session growth rate. The plugin should do the same for Onelist API:

```typescript
interface APIGrowthMetrics {
  requestsPerMinute: number;
  tokensPerMinute: number;
  errorRate: number;
}
```

### 2. Diagnostic Export

OCTO's surgery script creates detailed diagnostic reports. The plugin should support this:

```typescript
function exportDiagnostics(): string {
  const state = loadPersistentState();
  return `
# onelist-memory Plugin Diagnostics

## State
- Version: ${STATE_VERSION}
- Total injections: ${state.stats.totalInjections}
- Total searches: ${state.stats.totalSearches}
- Search hit rate: ${(state.stats.totalSearchHits / state.stats.totalSearches * 100).toFixed(1)}%
- Fallback rate: ${(state.stats.totalFallbacks / state.stats.totalInjections * 100).toFixed(1)}%

## Circuit Breaker
- Status: ${shouldSkipOnelist() ? 'OPEN' : 'CLOSED'}
- Consecutive failures: ${onelistCircuitBreaker.consecutiveFailures}
- Total failures: ${onelistCircuitBreaker.totalFailures}
- Total successes: ${onelistCircuitBreaker.totalSuccesses}

## Sessions
${Object.entries(state.sessionInjectionCounts).map(([id, data]) =>
  `- ${id.slice(0, 8)}: ${data.count} injections, last: ${new Date(data.lastUpdated).toISOString()}`
).join('\n')}
`;
}
```

### 3. Log Aggregation

OCTO's watchdog scans OpenClaw logs for errors. The plugin should write to a format OCTO can parse:

```typescript
// Structured logging for OCTO compatibility
function logStructured(level: string, event: string, data: Record<string, any>): void {
  const entry = {
    timestamp: new Date().toISOString(),
    component: 'onelist-memory',
    level,
    event,
    ...data,
  };
  // Write to both console and structured log file
  console.log(`[onelist-memory] ${level}: ${event}`);
  fs.appendFileSync(
    `${OCTO_HOME}/logs/onelist-memory.log`,
    JSON.stringify(entry) + '\n'
  );
}
```

## What Should Be in Onelist Repo vs OCTO Repo

### Keep in Onelist Repo (onelist-local)
- onelist-memory plugin (OpenClaw integration)
- claude-code plugin (Claude Code integration)
- Onelist API client code
- Memory extraction logic

### Keep in OCTO Repo
- Bloat sentinel
- Watchdog service
- Surgery script
- Session monitor
- PG health check
- Cost estimation
- Model tiering

### Should Be Shared/Coordinated
- Injection marker format
- Session archive paths
- Health state files
- Log formats

## Installation Integration

**Current state:** OCTO and onelist-memory are installed separately.

**Recommendation:** The final Onelist installer should:

1. Install Onelist server
2. Install OCTO monitoring suite
3. Install onelist-memory plugin
4. Configure coordination between them

```bash
#!/bin/bash
# onelist-full-install.sh

# 1. Install Onelist server
curl -fsSL https://onelist.my/install.sh | bash

# 2. Install OCTO for monitoring
curl -fsSL https://raw.githubusercontent.com/trinsiklabs/octo/main/install.sh | bash

# 3. Install onelist-memory plugin
openclaw plugins install https://github.com/trinsiklabs/onelist-local/extensions/onelist-memory

# 4. Configure integration
cat > ~/.octo/config.json << EOF
{
  "onelist_integration": true,
  "onelist_api_url": "http://localhost:4000",
  "coordinate_injection_counts": true
}
EOF

# 5. Start services
octo sentinel daemon
octo watchdog install
```

## Priority Order for Implementation

1. **High Priority:**
   - Coordinate injection marker format with OCTO
   - Add bump notification awareness
   - Add diagnostic export function

2. **Medium Priority:**
   - Add OCTO-compatible health reporting
   - Integrate with PG health check
   - Add structured logging

3. **Low Priority:**
   - Growth rate tracking
   - Full installation integration

---

*This analysis is based on OCTO commit state as of 2026-02-02*
