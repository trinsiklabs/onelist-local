#!/usr/bin/env node

const { OnelistAPI } = require('./lib/api');
const { loadConfig } = require('./lib/config');

async function main() {
  const config = loadConfig();

  if (!config.apiKey) {
    // Not configured - silent exit
    process.exit(0);
  }

  if (!config.autoInject) {
    process.exit(0);
  }

  const api = new OnelistAPI(config);

  try {
    // Get current working directory for project scoping
    const projectPath = process.cwd();

    // Fetch relevant memories
    const result = await api.getContextMemories(projectPath);
    const memories = result.data || result;

    if (!memories || memories.length === 0) {
      process.exit(0);
    }

    // Format for context injection
    const context = formatContextBlock(memories, config.maxContextTokens);

    // Output to stdout for Claude Code to pick up
    console.log(context);

  } catch (err) {
    // Silent failure - don't block Claude Code startup
    if (process.env.DEBUG) {
      console.error(`[onelist] Context fetch failed: ${err.message}`);
    }
    process.exit(0);
  }
}

function formatContextBlock(memories, maxTokens) {
  let output = `\n<onelist-context>\n`;
  output += `## Relevant Memories from Onelist\n\n`;

  let tokenEstimate = 0;
  const tokensPerChar = 0.25; // rough estimate

  for (const memory of memories) {
    const title = memory.title || memory.name || 'Memory';
    const content = memory.content || memory.body || '';
    const entry = `### ${title}\n${content}\n\n`;
    const entryTokens = entry.length * tokensPerChar;

    if (tokenEstimate + entryTokens > maxTokens) break;

    output += entry;
    tokenEstimate += entryTokens;
  }

  output += `</onelist-context>\n`;
  return output;
}

main();
