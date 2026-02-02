#!/usr/bin/env node

const { loadConfig, getConfigPath } = require('./lib/config');
const { OnelistAPI } = require('./lib/api');
const { getBufferSize, getBufferPath } = require('./lib/buffer');

async function main() {
  const config = loadConfig();

  console.log('=== Onelist Claude Plugin Status ===\n');

  // Config status
  console.log(`Config file: ${getConfigPath()}`);
  console.log(`API URL: ${config.apiUrl}`);
  console.log(`API Key: ${config.apiKey ? '***configured***' : 'NOT SET'}`);
  console.log(`Auto-inject context: ${config.autoInject}`);
  console.log(`Max context tokens: ${config.maxContextTokens}`);
  console.log('');

  // Buffer status
  const bufferSize = getBufferSize();
  console.log(`Capture buffer: ${bufferSize} action(s) pending`);
  console.log(`Buffer file: ${getBufferPath()}`);
  console.log('');

  // Connection status
  if (!config.apiKey) {
    console.log('Status: DISCONNECTED (no API key configured)');
    console.log('');
    console.log('Run /onelist:connect to configure.');
    process.exit(0);
  }

  const api = new OnelistAPI(config);

  try {
    console.log('Testing connection...');
    await api.ping();

    const stats = await api.getStats();

    console.log('Status: CONNECTED');
    console.log(`Total entries: ${stats.totalEntries}`);

    // Try to get recent memories
    try {
      const projectPath = process.cwd();
      const memories = await api.getContextMemories(projectPath, 5);
      const memoryList = memories.data || memories;

      if (memoryList && memoryList.length > 0) {
        console.log(`\nRecent memories for this project (${memoryList.length}):`);
        for (const m of memoryList.slice(0, 3)) {
          console.log(`  - ${m.title || m.name || 'Untitled'}`);
        }
        if (memoryList.length > 3) {
          console.log(`  ... and ${memoryList.length - 3} more`);
        }
      }
    } catch {
      // Ignore errors fetching memories
    }

  } catch (err) {
    console.log(`Status: ERROR - ${err.message}`);
    process.exit(1);
  }
}

main();
