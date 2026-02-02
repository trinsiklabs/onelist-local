#!/usr/bin/env node

const { loadConfig } = require('./lib/config');
const { OnelistAPI } = require('./lib/api');

async function main() {
  const config = loadConfig();

  if (!config.apiKey) {
    console.error('[onelist] Not configured. Run /onelist:connect first.');
    process.exit(1);
  }

  const args = process.argv.slice(2);

  // Parse arguments
  let query = null;
  let limit = 10;
  let type = null;
  let tag = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--limit' && args[i + 1]) {
      limit = parseInt(args[++i], 10);
    } else if (args[i] === '--type' && args[i + 1]) {
      type = args[++i];
    } else if (args[i] === '--tag' && args[i + 1]) {
      tag = args[++i];
    } else if (!args[i].startsWith('--')) {
      query = args[i];
    }
  }

  if (!query) {
    console.log('Usage: node search.js <query> [--limit N] [--type TYPE] [--tag TAG]');
    console.log('');
    console.log('Examples:');
    console.log('  node search.js "authentication flow"');
    console.log('  node search.js "database migration" --limit 5');
    console.log('  node search.js "error handling" --type memory');
    process.exit(1);
  }

  const api = new OnelistAPI(config);

  try {
    const result = await api.search(query, { limit, type, tag });
    const entries = result.data || result;

    if (!entries || entries.length === 0) {
      console.log(`No results found for: "${query}"`);
      process.exit(0);
    }

    console.log(`Found ${entries.length} result(s) for: "${query}"\n`);

    for (const entry of entries) {
      console.log('---');
      console.log(`**${entry.title || entry.name || 'Untitled'}**`);
      if (entry.entry_type) console.log(`Type: ${entry.entry_type}`);
      if (entry.tags?.length) console.log(`Tags: ${entry.tags.join(', ')}`);
      if (entry.created_at) console.log(`Created: ${entry.created_at}`);
      console.log('');

      const content = entry.content || entry.body || '';
      // Show first 500 chars of content
      if (content.length > 500) {
        console.log(content.substring(0, 500) + '...');
      } else {
        console.log(content);
      }
      console.log('');
    }

  } catch (err) {
    console.error(`Search failed: ${err.message}`);
    process.exit(1);
  }
}

main();
