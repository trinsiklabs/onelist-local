---
name: onelist:search
description: Search your Onelist memories
arguments:
  - name: query
    description: Search query
    required: true
---

# Search Onelist

Search your memories stored in Onelist.

## Usage

```
/onelist:search <query>
```

## Instructions for Claude

When the user runs this command:

1. Execute the search:

```bash
node scripts/search.js "<query>"
```

2. Display the results to the user in a readable format.

3. If results are relevant to the current task, offer to use them as context.

## Options

- `--limit <n>` - Maximum number of results (default: 10)
- `--type <type>` - Filter by entry type (memory, note, bookmark, etc.)
- `--tag <tag>` - Filter by tag
