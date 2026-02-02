---
name: onelist:connect
description: Connect to your Onelist instance
---

# Connect to Onelist

Set up your Onelist connection for persistent memory.

## Usage

Run this command and provide:
1. Your Onelist API URL (e.g., http://localhost:4000 or https://api.onelist.my)
2. Your API key

The plugin will store these in ~/.onelist-claude/settings.json

## Instructions for Claude

When the user runs this command:

1. Ask for their Onelist API URL (default: http://localhost:4000)
2. Ask for their API key
3. Run the following to save the configuration:

```bash
node scripts/connect.js --url "<api_url>" --key "<api_key>"
```

4. Test the connection by running:

```bash
node scripts/status.js
```

5. Report success or any errors to the user.
