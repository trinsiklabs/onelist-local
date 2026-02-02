const fs = require('fs');
const path = require('path');
const { CONFIG_DIR, ensureConfigDir } = require('./config');

const BUFFER_FILE = path.join(CONFIG_DIR, 'capture-buffer.json');

function loadBuffer() {
  if (!fs.existsSync(BUFFER_FILE)) {
    return [];
  }
  try {
    return JSON.parse(fs.readFileSync(BUFFER_FILE, 'utf8'));
  } catch (err) {
    console.error(`[onelist] Error loading buffer: ${err.message}`);
    return [];
  }
}

function saveBuffer(buffer) {
  ensureConfigDir();
  fs.writeFileSync(BUFFER_FILE, JSON.stringify(buffer, null, 2));
}

function addToBuffer(capture) {
  const buffer = loadBuffer();
  buffer.push({
    timestamp: new Date().toISOString(),
    ...capture,
  });
  saveBuffer(buffer);
  return buffer;
}

function clearBuffer() {
  if (fs.existsSync(BUFFER_FILE)) {
    fs.unlinkSync(BUFFER_FILE);
  }
}

function getBufferPath() {
  return BUFFER_FILE;
}

function getBufferSize() {
  const buffer = loadBuffer();
  return buffer.length;
}

module.exports = {
  loadBuffer,
  saveBuffer,
  addToBuffer,
  clearBuffer,
  getBufferPath,
  getBufferSize,
  BUFFER_FILE,
};
