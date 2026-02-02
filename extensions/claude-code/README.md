# Onelist Claude Code Plugin

Integrates [Onelist](https://onelist.my) persistent memory with [Claude Code](https://claude.ai/claude-code) CLI.

## Features

- **Context Injection**: Automatically injects relevant memories at session start
- **Session Capture**: Records file edits and actions during your session
- **Session Summary**: Creates a memory entry summarizing what was done when you stop
- **Memory Search**: Search your Onelist memories from within Claude Code

## Installation

1. Navigate to your project directory
2. Link or copy this plugin:

```bash
# Option 1: Symlink (recommended for development)
ln -s /path/to/onelist-local/extensions/claude-code ~/.claude/plugins/onelist

# Option 2: Copy
cp -r /path/to/onelist-local/extensions/claude-code ~/.claude/plugins/onelist
```

3. Configure your connection:

```bash
cd ~/.claude/plugins/onelist
npm install  # if needed
node scripts/connect.js --url http://localhost:4000 --key YOUR_API_KEY
```

## Commands

### `/onelist:connect`

Set up your Onelist connection. Prompts for:
- API URL (default: http://localhost:4000)
- API Key

### `/onelist:search <query>`

Search your Onelist memories.

Options:
- `--limit <n>` - Max results (default: 10)
- `--type <type>` - Filter by entry type
- `--tag <tag>` - Filter by tag

### `/onelist:status`

Check connection status and see:
- Configuration details
- Connection health
- Pending captures in buffer
- Recent memories for current project

## How It Works

### Session Start Hook

When Claude Code starts, the plugin:
1. Checks if configured (has API key)
2. Fetches relevant memories scoped to the current project
3. Injects them as context in `<onelist-context>` tags

### Post-Tool Capture Hook

After Edit, Write, Bash, or Task tools:
1. Captures the action (tool name, file path)
2. Buffers locally in `~/.onelist-claude/capture-buffer.json`
3. Does NOT upload during session (preserves locality)

### Stop Hook

When Claude Code session ends:
1. Generates session summary from buffer
2. Creates a memory entry in Onelist with:
   - Actions performed
   - Files modified
   - Project context
   - Timestamps
3. Clears the buffer

## Configuration

Config stored in `~/.onelist-claude/settings.json`:

```json
{
  "apiUrl": "http://localhost:4000",
  "apiKey": "ol_...",
  "captureTools": ["Edit", "Write", "Bash", "Task"],
  "skipTools": ["Read", "Glob", "Grep", "LS"],
  "autoInject": true,
  "maxContextTokens": 4000,
  "bufferThreshold": 10
}
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `apiUrl` | `http://localhost:4000` | Onelist API endpoint |
| `apiKey` | `null` | Your Onelist API key |
| `captureTools` | `["Edit", "Write", "Bash", "Task"]` | Tools to capture |
| `skipTools` | `["Read", "Glob", "Grep", "LS"]` | Tools to ignore |
| `autoInject` | `true` | Inject context at session start |
| `maxContextTokens` | `4000` | Max tokens for injected context |
| `bufferThreshold` | `10` | (Reserved for future use) |

## Memory Search Skill

The plugin includes an automatic skill that Claude can use when you ask about:
- Previous work: "What did we do last time..."
- Decisions: "Why did we choose..."
- Context: "What's the status of..."

Claude will search your Onelist memories automatically.

## Requirements

- Node.js 18+
- Running Onelist instance (local or cloud)
- Onelist API key

## Troubleshooting

### "Not configured" error

Run `/onelist:connect` to set up your API key.

### Connection fails

1. Check Onelist is running: `curl http://localhost:4000/api/v1/health`
2. Verify your API key is valid
3. Check firewall/network settings

### No context injected

1. Run `/onelist:status` to check configuration
2. Verify `autoInject` is `true`
3. Check you have memories tagged with the current project

### Buffer not uploading

The buffer only uploads when Claude Code session ends (stop hook). If you kill the process, the buffer persists for next session.

## Development

```bash
# Run with debug output
DEBUG=1 node scripts/context-hook.js

# Test search
node scripts/search.js "test query"

# Check status
node scripts/status.js
```

## License

MIT
