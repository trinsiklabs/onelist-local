---
name: memory-search
description: Search user's Onelist memories for relevant context
trigger: automatic
---

# Memory Search Skill

When the user asks about previous work, decisions, or context that might be stored in their Onelist memories, use this skill to search and retrieve relevant information.

## When to Use

- User references past work: "What did we do last time..."
- User asks about decisions: "Why did we choose..."
- User needs context: "What's the status of..."
- Codebase questions that might have documented answers
- User mentions something they "remember" but can't find

## How to Use

Search for relevant memories:

```bash
node scripts/search.js "<relevant query>"
```

## Query Tips

- Use specific keywords from the user's question
- Try variations if first search doesn't yield results
- Combine project name with topic for better results
- Search for file names if discussing specific code

## Result Handling

- Present relevant memories concisely
- Quote key information directly
- Offer to search with different terms if results aren't helpful
- Note when memories might be outdated
