const fs = require('fs');
const path = require('path');

const CONFIG_DIR = path.join(process.env.HOME, '.onelist-claude');
const CONFIG_FILE = path.join(CONFIG_DIR, 'settings.json');

const DEFAULTS = {
  apiUrl: 'http://localhost:4000',
  apiKey: null,
  captureTools: ['Edit', 'Write', 'Bash', 'Task'],
  skipTools: ['Read', 'Glob', 'Grep', 'LS'],
  autoInject: true,
  maxContextTokens: 4000,
  bufferThreshold: 10,  // Flush buffer after N captures
};

function ensureConfigDir() {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
  }
}

function loadConfig() {
  if (!fs.existsSync(CONFIG_FILE)) {
    return { ...DEFAULTS };
  }
  try {
    const userConfig = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    return { ...DEFAULTS, ...userConfig };
  } catch (err) {
    console.error(`[onelist] Error loading config: ${err.message}`);
    return { ...DEFAULTS };
  }
}

function saveConfig(config) {
  ensureConfigDir();
  const toSave = { ...DEFAULTS, ...config };
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(toSave, null, 2));
  return toSave;
}

function getConfigPath() {
  return CONFIG_FILE;
}

module.exports = {
  loadConfig,
  saveConfig,
  getConfigPath,
  ensureConfigDir,
  CONFIG_DIR,
  CONFIG_FILE,
  DEFAULTS
};
