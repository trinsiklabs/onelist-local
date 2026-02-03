# OpenClaw Session Import Guide

Import historical OpenClaw session transcripts into Onelist.

## Overview

The OpenClaw Session Importer allows you to import existing chat session files from an OpenClaw installation into Onelist. This enables:

- Migrating historical conversations when adopting Onelist
- Preserving memory chain integrity for imported sessions
- Bulk importing multiple sessions in chronological order

**Key Design Principles:**
- No OpenClaw runtime required - reads `.jsonl` files directly
- Original timestamps preserved for accurate historical records
- Sequential processing maintains memory chain integrity
- Idempotent imports - re-importing the same file is safe

## File Format

OpenClaw stores sessions at:
```
~/.openclaw/agents/{agent_id}/sessions/{session_id}.jsonl
```

Each line is a JSON object:
```json
{"role": "user", "content": "Hello", "timestamp": "2026-01-30T10:00:00Z"}
{"role": "assistant", "content": "Hi!", "timestamp": "2026-01-30T10:00:05Z", "tool_calls": [...]}
```

Supported message fields:
- `role` - user, assistant, system, or tool
- `content` - Message text
- `timestamp` - ISO 8601 timestamp
- `tool_calls` - Optional array of tool invocations

## API Endpoints

### Preview Import

List sessions that would be imported without actually importing them.

```bash
GET /api/v1/openclaw/import/preview?path=~/.openclaw
```

Query parameters:
- `path` - OpenClaw directory path (required)
- `agent_id` - Filter to specific agent (optional)

Response:
```json
{
  "sessions": [
    {
      "path": "/home/user/.openclaw/agents/main/sessions/cli-001.jsonl",
      "agent_id": "main",
      "session_id": "cli-001",
      "earliest_timestamp": "2026-01-30T08:00:00Z",
      "message_count": 42
    }
  ],
  "total": 1
}
```

### Import Directory

Import all sessions from an OpenClaw directory.

```bash
POST /api/v1/openclaw/import
Content-Type: application/json

{
  "path": "~/.openclaw",
  "options": {
    "agent_id": "main",
    "after": "2026-01-01T00:00:00Z",
    "before": "2026-02-01T00:00:00Z"
  }
}
```

Options:
- `agent_id` - Filter to specific agent
- `after` - Only import sessions after this datetime
- `before` - Only import sessions before this datetime
- `dry_run` - Return what would be imported without importing

Response:
```json
{
  "ok": true,
  "imported_count": 15,
  "failed_count": 0,
  "total": 15
}
```

### Import Single File

Import a specific session file.

```bash
POST /api/v1/openclaw/import/file
Content-Type: application/json

{
  "path": "/home/user/.openclaw/agents/main/sessions/cli-001.jsonl"
}
```

Response:
```json
{
  "ok": true,
  "entry_id": "550e8400-e29b-41d4-a716-446655440000",
  "message_count": 42,
  "session_id": "openclaw:main:cli-001"
}
```

## Programmatic Usage

### Import from IEx

```elixir
alias Onelist.OpenClaw.SessionImporter

# List available sessions
{:ok, sessions} = SessionImporter.list_sessions("~/.openclaw")

# Dry run - see what would be imported
{:ok, result} = SessionImporter.import_directory(user, "~/.openclaw", dry_run: true)
# => %{dry_run: true, would_import: 15, sessions: [...]}

# Import all sessions
{:ok, result} = SessionImporter.import_directory(user, "~/.openclaw")
# => %{imported_count: 15, failed_count: 0, total: 15}

# Import with filters
{:ok, result} = SessionImporter.import_directory(user, "~/.openclaw",
  agent_id: "main",
  after: ~U[2026-01-01 00:00:00Z]
)

# Import single file
{:ok, result} = SessionImporter.import_session_file(user, "/path/to/session.jsonl")
```

### CLI Progress Bar

For interactive imports, use the built-in progress reporter:

```elixir
alias Onelist.OpenClaw.{SessionImporter, Progress}

# Import with CLI progress bar
{:ok, result} = SessionImporter.import_directory(user, "~/.openclaw",
  progress: &Progress.cli_reporter/3
)
```

This displays a live-updating progress bar:
```
[████████████░░░░░░░░░░░░░░░░░░] (15 of 92) 16% importing cli-042...
```

For custom progress reporting, provide your own callback:

```elixir
my_reporter = fn current, total, context ->
  IO.puts("[\#{current}/\#{total}] \#{context.status}: \#{context.session_id}")
end

SessionImporter.import_directory(user, path, progress: my_reporter)
```

The callback receives:
- `current` - Current session number (1-indexed)
- `total` - Total number of sessions
- `context` - Map with `:file_path`, `:session_id`, `:status` (`:importing`, `:complete`, `:failed`)

### Background Import via Oban

For large imports, use the worker to process files in the background:

```elixir
alias Onelist.OpenClaw.Workers.ImportSessionWorker

# Queue all sessions for background import
{:ok, result} = ImportSessionWorker.queue_directory_import(user, "~/.openclaw")
# => %{queued: 15, total: 15, sessions: [...]}

# Sessions are processed sequentially (concurrency=1) to maintain
# memory chain integrity
```

## Memory Chain Integrity

When TrustedMemory is enabled, imported sessions integrate with the memory chain:

1. Sessions are sorted by earliest message timestamp
2. Oban queue processes one session at a time (concurrency=1)
3. Each session creates a `chat_log` entry with `source_type: "openclaw_import"`
4. ProcessEntryWorker extracts memories and chains them via `TrustedMemory.chain_memories_r1/3`

### Verify Chain After Import

```elixir
# Verify the memory chain is intact
TrustedMemory.verify_reader_chain(user_id)
# => {:ok, :verified}
```

## Entry Metadata

Imported sessions create entries with this metadata structure:

```elixir
%{
  "session_id" => "openclaw:main:cli-001",      # Unique identifier
  "agent_id" => "main",                          # OpenClaw agent
  "original_session_id" => "cli-001",            # Original filename
  "started_at" => "2026-01-30T08:00:00Z",        # First message time
  "last_message_at" => "2026-01-30T09:30:00Z",   # Last message time
  "message_count" => 42,                         # Total messages
  "status" => "imported",                        # Import status
  "imported_at" => "2026-02-03T10:00:00Z",       # When imported
  "source_file" => "/path/to/session.jsonl"      # Original file
}
```

## Idempotency

The importer is idempotent - importing the same file twice will not create duplicates. The `session_id` (combination of agent_id and original session filename) is used to detect existing imports:

```elixir
# First import creates the entry
{:ok, %{entry_id: id1}} = SessionImporter.import_session_file(user, path)

# Second import returns the existing entry
{:ok, %{entry_id: id2, already_existed: true}} = SessionImporter.import_session_file(user, path)

# Same entry
id1 == id2  # => true
```

## Error Handling

The importer handles errors gracefully:

- **Malformed JSON lines** - Skipped, valid lines still imported
- **Missing timestamps** - Messages imported without timestamp ordering
- **File not found** - Returns `{:error, :file_not_found}`
- **Invalid path format** - Returns `{:error, :invalid_path_format}`
- **Non-existent directory** - Returns `{:error, :directory_not_found}`

Partial failures in directory import are reported:
```elixir
{:ok, %{imported_count: 14, failed_count: 1, total: 15, results: [...]}}
```

## Configuration

### Oban Queue

The import queue is configured for sequential processing:

```elixir
# config/config.exs
config :onelist, Oban,
  queues: [
    default: 10,
    reader: 5,
    openclaw_import: 1  # Sequential for chain integrity
  ]
```

### Environment Variables

```bash
# Default OpenClaw directory (can be overridden per-request)
OPENCLAW_HOME=~/.openclaw

# Enable/disable import API (default: true for local)
OPENCLAW_IMPORT_ENABLED=true
```

## Troubleshooting

### Import Appears Stuck

Check Oban job status:
```elixir
import Ecto.Query
Oban.Job
|> where([j], j.queue == "openclaw_import")
|> where([j], j.state in ["available", "executing", "retryable"])
|> Onelist.Repo.all()
```

### Memory Chain Verification Fails

If chain verification fails after import, check for:
1. Concurrent imports (should use concurrency=1)
2. Manual entry modifications during import
3. Entries created outside the import process

### Large Directory Performance

For directories with hundreds of sessions:
1. Use time filters (`after`/`before`) to batch imports
2. Use `queue_directory_import/3` for background processing
3. Monitor Oban dashboard for progress

---

*Last updated: 2026-02-03*
