#!/usr/bin/env node

const { loadConfig, saveConfig, getConfigPath } = require('./lib/config');
const { OnelistAPI } = require('./lib/api');

async function main() {
  const args = process.argv.slice(2);

  let url = null;
  let key = null;

  // Parse arguments
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--url' && args[i + 1]) {
      url = args[++i];
    } else if (args[i] === '--key' && args[i + 1]) {
      key = args[++i];
    }
  }

  if (!url && !key) {
    console.log('Usage: node connect.js --url <api_url> --key <api_key>');
    console.log('');
    console.log('Example:');
    console.log('  node connect.js --url http://localhost:4000 --key ol_abc123...');
    console.log('');
    console.log(`Config file: ${getConfigPath()}`);
    process.exit(1);
  }

  const config = loadConfig();

  if (url) config.apiUrl = url;
  if (key) config.apiKey = key;

  // Test connection before saving
  const api = new OnelistAPI(config);

  console.log(`Testing connection to ${config.apiUrl}...`);

  try {
    await api.ping();
    console.log('Connection successful!');

    // Save config
    saveConfig(config);
    console.log(`Configuration saved to ${getConfigPath()}`);

    // Get some stats
    const stats = await api.getStats();
    if (stats.connected) {
      console.log(`Total entries: ${stats.totalEntries}`);
    }

  } catch (err) {
    console.error(`Connection failed: ${err.message}`);
    console.log('');
    console.log('Configuration NOT saved. Please check:');
    console.log('  1. Is Onelist running at the specified URL?');
    console.log('  2. Is your API key correct?');
    process.exit(1);
  }
}

main();
