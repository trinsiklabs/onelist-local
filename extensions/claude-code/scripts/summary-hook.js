#!/usr/bin/env node

const path = require('path');
const { OnelistAPI } = require('./lib/api');
const { loadConfig } = require('./lib/config');
const { loadBuffer, clearBuffer } = require('./lib/buffer');

async function main() {
  const config = loadConfig();

  if (!config.apiKey) {
    process.exit(0);
  }

  const api = new OnelistAPI(config);
  const buffer = loadBuffer();

  if (buffer.length === 0) {
    // No captures in this session
    process.exit(0);
  }

  try {
    // Create session summary entry
    const summary = generateSummary(buffer);
    const projectName = path.basename(process.cwd());

    await api.createEntry({
      entry_type: 'memory',
      title: `Claude Code Session - ${projectName} - ${new Date().toISOString().split('T')[0]}`,
      content: summary,
      metadata: {
        source: 'claude-code-plugin',
        session_type: 'claude_code',
        project_path: process.cwd(),
        project_name: projectName,
        captures_count: buffer.length,
        started_at: buffer[0]?.timestamp,
        ended_at: buffer[buffer.length - 1]?.timestamp,
      },
      tags: ['claude-session', `project:${projectName}`]
    });

    // Clear buffer on success
    clearBuffer();

    console.log(`[onelist] Session saved (${buffer.length} actions captured)`);

  } catch (err) {
    console.error(`[onelist] Failed to save session: ${err.message}`);
    // Don't delete buffer on failure - preserve for retry
  }
}

function generateSummary(buffer) {
  const files = [...new Set(buffer.filter(b => b.file).map(b => b.file))];
  const tools = buffer.reduce((acc, b) => {
    acc[b.tool] = (acc[b.tool] || 0) + 1;
    return acc;
  }, {});

  let summary = `## Session Summary\n\n`;

  if (buffer.length > 0) {
    const start = buffer[0]?.timestamp;
    const end = buffer[buffer.length - 1]?.timestamp;
    summary += `**Duration:** ${start} to ${end}\n`;
  }

  summary += `**Project:** ${process.cwd()}\n\n`;

  summary += `### Actions\n`;
  for (const [tool, count] of Object.entries(tools)) {
    summary += `- ${tool}: ${count}\n`;
  }

  if (files.length > 0) {
    summary += `\n### Files Modified\n`;
    for (const file of files.slice(0, 20)) {
      summary += `- ${file}\n`;
    }
    if (files.length > 20) {
      summary += `- ... and ${files.length - 20} more\n`;
    }
  }

  summary += `\n### Activity Log\n`;
  for (const capture of buffer.slice(-10)) {
    summary += `- ${capture.timestamp}: ${capture.summary}\n`;
  }
  if (buffer.length > 10) {
    summary += `- ... and ${buffer.length - 10} earlier actions\n`;
  }

  return summary;
}

main();
