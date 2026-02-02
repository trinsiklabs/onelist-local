/**
 * Tests for config.js
 */

const { describe, it, beforeEach, afterEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Store original values
const originalHome = process.env.HOME;
let tempDir;

describe('Config Module', () => {
  beforeEach(() => {
    // Create temp directory for test config
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'onelist-test-'));
    process.env.HOME = tempDir;

    // Clear require cache to get fresh module with new HOME
    delete require.cache[require.resolve('../scripts/lib/config.js')];
  });

  afterEach(() => {
    // Restore HOME
    process.env.HOME = originalHome;

    // Cleanup temp directory
    if (tempDir && fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }

    // Clear cache again
    delete require.cache[require.resolve('../scripts/lib/config.js')];
  });

  describe('DEFAULTS', () => {
    it('should have sensible default values', () => {
      const { DEFAULTS } = require('../scripts/lib/config.js');

      assert.equal(DEFAULTS.apiUrl, 'http://localhost:4000');
      assert.equal(DEFAULTS.apiKey, null);
      assert.equal(DEFAULTS.autoInject, true);
      assert.equal(DEFAULTS.maxContextTokens, 4000);
      assert.equal(DEFAULTS.bufferThreshold, 10);
      assert.ok(Array.isArray(DEFAULTS.captureTools));
      assert.ok(Array.isArray(DEFAULTS.skipTools));
    });

    it('should include Edit and Write in captureTools', () => {
      const { DEFAULTS } = require('../scripts/lib/config.js');

      assert.ok(DEFAULTS.captureTools.includes('Edit'));
      assert.ok(DEFAULTS.captureTools.includes('Write'));
    });

    it('should include Read and Grep in skipTools', () => {
      const { DEFAULTS } = require('../scripts/lib/config.js');

      assert.ok(DEFAULTS.skipTools.includes('Read'));
      assert.ok(DEFAULTS.skipTools.includes('Grep'));
    });
  });

  describe('loadConfig', () => {
    it('should return defaults when no config file exists', () => {
      const { loadConfig, DEFAULTS } = require('../scripts/lib/config.js');
      const config = loadConfig();

      assert.deepEqual(config, DEFAULTS);
    });

    it('should merge user config with defaults', () => {
      const { loadConfig, CONFIG_DIR, DEFAULTS } = require('../scripts/lib/config.js');

      // Create config directory and file
      fs.mkdirSync(CONFIG_DIR, { recursive: true });
      const configFile = path.join(CONFIG_DIR, 'settings.json');
      fs.writeFileSync(configFile, JSON.stringify({
        apiUrl: 'https://custom.example.com',
        apiKey: 'test-key-123',
      }));

      // Clear cache and reload
      delete require.cache[require.resolve('../scripts/lib/config.js')];
      const { loadConfig: loadConfigFresh } = require('../scripts/lib/config.js');
      const config = loadConfigFresh();

      assert.equal(config.apiUrl, 'https://custom.example.com');
      assert.equal(config.apiKey, 'test-key-123');
      // Should still have defaults for unspecified values
      assert.equal(config.autoInject, DEFAULTS.autoInject);
      assert.deepEqual(config.captureTools, DEFAULTS.captureTools);
    });

    it('should return defaults when config file is invalid JSON', () => {
      const { CONFIG_DIR, DEFAULTS } = require('../scripts/lib/config.js');

      // Create invalid config file
      fs.mkdirSync(CONFIG_DIR, { recursive: true });
      const configFile = path.join(CONFIG_DIR, 'settings.json');
      fs.writeFileSync(configFile, 'not valid json {{{');

      // Clear cache and reload
      delete require.cache[require.resolve('../scripts/lib/config.js')];
      const { loadConfig: loadConfigFresh } = require('../scripts/lib/config.js');
      const config = loadConfigFresh();

      assert.deepEqual(config, DEFAULTS);
    });
  });

  describe('saveConfig', () => {
    it('should create config directory if it does not exist', () => {
      const { saveConfig, CONFIG_DIR } = require('../scripts/lib/config.js');

      assert.ok(!fs.existsSync(CONFIG_DIR));

      saveConfig({ apiUrl: 'https://test.com' });

      assert.ok(fs.existsSync(CONFIG_DIR));
    });

    it('should write config to file', () => {
      const { saveConfig, CONFIG_FILE } = require('../scripts/lib/config.js');

      saveConfig({ apiUrl: 'https://saved.com', apiKey: 'saved-key' });

      const written = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
      assert.equal(written.apiUrl, 'https://saved.com');
      assert.equal(written.apiKey, 'saved-key');
    });

    it('should merge with defaults when saving', () => {
      const { saveConfig, CONFIG_FILE, DEFAULTS } = require('../scripts/lib/config.js');

      saveConfig({ apiUrl: 'https://partial.com' });

      const written = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
      assert.equal(written.apiUrl, 'https://partial.com');
      assert.equal(written.autoInject, DEFAULTS.autoInject);
    });

    it('should return the merged config', () => {
      const { saveConfig, DEFAULTS } = require('../scripts/lib/config.js');

      const result = saveConfig({ customField: 'value' });

      assert.equal(result.customField, 'value');
      assert.equal(result.apiUrl, DEFAULTS.apiUrl);
    });
  });

  describe('ensureConfigDir', () => {
    it('should create config directory', () => {
      const { ensureConfigDir, CONFIG_DIR } = require('../scripts/lib/config.js');

      assert.ok(!fs.existsSync(CONFIG_DIR));

      ensureConfigDir();

      assert.ok(fs.existsSync(CONFIG_DIR));
    });

    it('should not throw if directory already exists', () => {
      const { ensureConfigDir, CONFIG_DIR } = require('../scripts/lib/config.js');

      fs.mkdirSync(CONFIG_DIR, { recursive: true });

      assert.doesNotThrow(() => ensureConfigDir());
    });
  });

  describe('getConfigPath', () => {
    it('should return the config file path', () => {
      const { getConfigPath, CONFIG_FILE } = require('../scripts/lib/config.js');

      assert.equal(getConfigPath(), CONFIG_FILE);
    });

    it('should include settings.json in path', () => {
      const { getConfigPath } = require('../scripts/lib/config.js');

      assert.ok(getConfigPath().endsWith('settings.json'));
    });
  });
});
