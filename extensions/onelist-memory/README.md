# Onelist Memory Sync Plugin

Streams OpenClaw chat messages to Onelist for persistent memory extraction, with **automatic context recovery** on session start.

## Features

### 1. Auto-Inject Recovery (NEW in v0.2.0)

**Zero-action context continuity.** When a session starts, this plugin automatically:
1. Reads recent session transcript files
2. Extracts the last N messages (configurable, default 50)
3. Injects them into the agent's context via the `before_agent_start` hook

This means after compaction, agents automatically have recent conversation context without needing to:
- Remember to run recovery scripts
- Manually read recovery files
- Lose continuity due to context limits

### 2. Onelist Sync

Watches session files and streams messages to Onelist for persistent memory extraction:
1. **Watches session files** - Monitors the OpenClaw sessions directory for changes
2. **Parses new messages** - Extracts user and assistant messages from JSONL
3. **Streams to Onelist** - POSTs messages to `/api/v1/chat-stream/append`
4. **Memory extraction** - Onelist's Reader agent extracts memories from chat logs

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
          
          // Auto-inject recovery settings
          "autoInjectEnabled": true,
          "autoInjectMessageCount": 50,
          "autoInjectHoursBack": 24,
          "autoInjectMinMessages": 5,
          
          // Onelist sync settings (optional)
          "apiUrl": "http://localhost:4000",
          "apiKey": "your-onelist-api-key"
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
| `autoInjectEnabled` | boolean | `true` | Auto-inject recovered context on session start |
| `autoInjectMessageCount` | number | `50` | Number of recent messages to inject |
| `autoInjectHoursBack` | number | `24` | How many hours back to look for messages |
| `autoInjectMinMessages` | number | `5` | Minimum messages required to trigger injection |
| `apiUrl` | string | - | Onelist API base URL (required for sync) |
| `apiKey` | string | - | Onelist API key (required for sync) |
| `sessionId` | string | - | Custom session identifier for grouping |

## How Auto-Inject Works

When OpenClaw starts a new agent turn, this plugin:

1. **Scans session files** in `~/.openclaw/agents/main/sessions/`
2. **Filters by time** - only files modified within `autoInjectHoursBack`
3. **Parses JSONL** - extracts user and assistant messages
4. **Sorts chronologically** - most recent messages last
5. **Formats context** - creates a readable summary block
6. **Injects via hook** - uses `before_agent_start` to prepend to context

The injected context looks like:

```markdown
## 🔄 Recovered Conversation Context

**Auto-injected:** 2024-02-04T10:30:00Z
**Coverage:** Last 24 hours (50 messages)

This context was automatically recovered from recent session transcripts...

---

**USER** (2024-02-04T10:00:00Z):
[message content]

**ASSISTANT** (2024-02-04T10:00:30Z):
[response content]

...

---

*End of recovered context. Continue the conversation naturally.*
```

## Minimal Setup (Auto-Inject Only)

If you only want auto-inject recovery without Onelist sync:

```json
{
  "plugins": {
    "entries": {
      "onelist-memory": {
        "enabled": true,
        "config": {
          "autoInjectEnabled": true,
          "autoInjectMessageCount": 50
        }
      }
    }
  }
}
```

No API credentials needed - it works purely from local session files.

## Manual Recovery (Still Available)

The manual recovery script at `~/skills/memory-recovery/` still works for explicit recovery:

```bash
cd ~/skills/memory-recovery && ./recover-context.sh 24
```

This creates `memory/RECOVERED_CONTEXT.md` which can be read manually.

## Session File Location

Session transcripts live at:
```
~/.openclaw/agents/main/sessions/*.jsonl
```

Each file contains JSONL-formatted messages with timestamps.

## Requirements

- OpenClaw with plugin support (2026.1.x+)
- Session files being written to the sessions directory
- For Onelist sync: valid Onelist API key with write permissions

## Resilience

This plugin is **critical infrastructure** for agent continuity:

- **Graceful degradation** - If recovery fails, the agent still starts normally
- **No blocking** - Recovery happens in the hook; errors don't prevent session
- **Configurable thresholds** - Adjust message counts based on your needs
- **Works offline** - Auto-inject uses local files, no network required

## Development

Plugin structure:
```
~/.openclaw/workspace/extensions/onelist-memory/
├── openclaw.plugin.json   # Plugin manifest
├── index.ts               # Main plugin code
└── README.md              # This file
```

Install as workspace extension or globally:
```bash
openclaw plugins install ./extensions/onelist-memory
```

## Changelog

### v0.2.0
- Added auto-inject recovery via `before_agent_start` hook
- New config options: `autoInjectEnabled`, `autoInjectMessageCount`, `autoInjectHoursBack`, `autoInjectMinMessages`
- Onelist sync now optional (auto-inject works without API credentials)

### v0.1.0
- Initial release with Onelist sync functionality

---
*Maintained by Hydra, Chief Resilience Officer*
