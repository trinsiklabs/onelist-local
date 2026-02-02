#!/usr/bin/env node

const { loadConfig } = require('./lib/config');
const { addToBuffer, getBufferSize } = require('./lib/buffer');

async function main() {
  const config = loadConfig();

  if (!config.apiKey) {
    process.exit(0);
  }

  // Read tool use data from environment
  const toolName = process.env.TOOL_NAME;
  const toolResult = process.env.TOOL_RESULT;
  const filePath = process.env.FILE_PATH;

  if (!toolName) {
    process.exit(0);
  }

  // Skip tools we don't want to capture
  if (config.skipTools.includes(toolName)) {
    process.exit(0);
  }

  // Only capture tools we're interested in
  if (!config.captureTools.includes(toolName)) {
    process.exit(0);
  }

  // Add capture to buffer
  const capture = {
    tool: toolName,
    file: filePath || null,
    summary: summarizeResult(toolName, toolResult, filePath),
    cwd: process.cwd(),
  };

  const buffer = addToBuffer(capture);

  if (process.env.DEBUG) {
    console.error(`[onelist] Captured: ${capture.summary} (buffer: ${buffer.length})`);
  }

  // Note: We don't flush on threshold anymore - we wait for session end
  // This keeps the buffer local until the session completes
}

function summarizeResult(tool, result, file) {
  switch (tool) {
    case 'Edit':
      return `Edited ${file || 'file'}`;
    case 'Write':
      return `Created/wrote ${file || 'file'}`;
    case 'Bash':
      return `Ran shell command`;
    case 'Task':
      return `Spawned subagent task`;
    default:
      return `Used ${tool}`;
  }
}

main();
