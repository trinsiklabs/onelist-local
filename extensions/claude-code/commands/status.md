---
name: onelist:status
description: Check Onelist connection status
---

# Onelist Status

Shows the current status of your Onelist connection.

## Usage

```
/onelist:status
```

## Instructions for Claude

When the user runs this command:

1. Run the status check:

```bash
node scripts/status.js
```

2. Display to the user:
   - Connection status (connected/disconnected)
   - API URL configured
   - Recent memory count (if connected)
   - Current session captures buffered
   - Any errors or warnings
