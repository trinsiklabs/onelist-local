/**
 * Tests for api.js
 */

const { describe, it, beforeEach, afterEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Store original values
const originalHome = process.env.HOME;
let tempDir;

describe('OnelistAPI Module', () => {
  beforeEach(() => {
    // Create temp directory for test config
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'onelist-test-'));
    process.env.HOME = tempDir;

    // Clear require cache
    delete require.cache[require.resolve('../scripts/lib/api.js')];
    delete require.cache[require.resolve('../scripts/lib/config.js')];
  });

  afterEach(() => {
    // Restore HOME
    process.env.HOME = originalHome;

    // Cleanup temp directory
    if (tempDir && fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }

    // Clear cache
    delete require.cache[require.resolve('../scripts/lib/api.js')];
    delete require.cache[require.resolve('../scripts/lib/config.js')];
  });

  describe('Constructor', () => {
    it('should use default config when none provided', () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');
      const { DEFAULTS } = require('../scripts/lib/config.js');

      const api = new OnelistAPI();

      assert.equal(api.apiUrl, DEFAULTS.apiUrl);
      assert.equal(api.apiKey, DEFAULTS.apiKey);
    });

    it('should use provided config', () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'https://custom.api.com',
        apiKey: 'custom-key-123',
      });

      assert.equal(api.apiUrl, 'https://custom.api.com');
      assert.equal(api.apiKey, 'custom-key-123');
    });

    it('should load saved config from file', () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');
      const { saveConfig } = require('../scripts/lib/config.js');

      saveConfig({
        apiUrl: 'https://saved.api.com',
        apiKey: 'saved-key',
      });

      // Clear and reload to pick up saved config
      delete require.cache[require.resolve('../scripts/lib/api.js')];
      delete require.cache[require.resolve('../scripts/lib/config.js')];
      const { OnelistAPI: FreshAPI } = require('../scripts/lib/api.js');

      const api = new FreshAPI();

      assert.equal(api.apiUrl, 'https://saved.api.com');
      assert.equal(api.apiKey, 'saved-key');
    });
  });

  describe('Search method', () => {
    it('should construct search URL correctly', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      // Mock the request method to capture the path
      let capturedPath;
      api.request = async (method, path) => {
        capturedPath = path;
        return { data: [], meta: { total: 0 } };
      };

      await api.search('test query', { limit: 5 });

      assert.ok(capturedPath.includes('/api/v1/search'));
      assert.ok(capturedPath.includes('q=test+query'));
      assert.ok(capturedPath.includes('limit=5'));
    });

    it('should include optional filters', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      let capturedPath;
      api.request = async (method, path) => {
        capturedPath = path;
        return { data: [], meta: { total: 0 } };
      };

      await api.search('query', { type: 'memory', tag: 'project:test' });

      assert.ok(capturedPath.includes('entry_type=memory'));
      assert.ok(capturedPath.includes('tag=project'));
    });

    it('should default limit to 10', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      let capturedPath;
      api.request = async (method, path) => {
        capturedPath = path;
        return { data: [] };
      };

      await api.search('query');

      assert.ok(capturedPath.includes('limit=10'));
    });
  });

  describe('CreateEntry method', () => {
    it('should POST to entries endpoint', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      let capturedMethod, capturedPath, capturedBody;
      api.request = async (method, path, body) => {
        capturedMethod = method;
        capturedPath = path;
        capturedBody = body;
        return { id: '123', success: true };
      };

      const entry = {
        title: 'Test Entry',
        content: 'Test content',
        entry_type: 'memory',
      };
      await api.createEntry(entry);

      assert.equal(capturedMethod, 'POST');
      assert.equal(capturedPath, '/api/v1/entries');
      assert.deepEqual(capturedBody, entry);
    });
  });

  describe('GetContextMemories method', () => {
    it('should request memory type entries', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      let capturedPath;
      api.request = async (method, path) => {
        capturedPath = path;
        return { data: [] };
      };

      await api.getContextMemories();

      assert.ok(capturedPath.includes('entry_type=memory'));
    });

    it('should include project tag when provided', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      let capturedPath;
      api.request = async (method, path) => {
        capturedPath = path;
        return { data: [] };
      };

      await api.getContextMemories('/path/to/project', 10);

      assert.ok(capturedPath.includes('tag=project'));
    });

    it('should use custom limit', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      let capturedPath;
      api.request = async (method, path) => {
        capturedPath = path;
        return { data: [] };
      };

      await api.getContextMemories(null, 50);

      assert.ok(capturedPath.includes('limit=50'));
    });
  });

  describe('Ping method', () => {
    it('should call health endpoint', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      let capturedPath;
      api.request = async (method, path) => {
        capturedPath = path;
        return { status: 'ok' };
      };

      await api.ping();

      assert.equal(capturedPath, '/api/v1/health');
    });
  });

  describe('GetStats method', () => {
    it('should return connected status on success', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      api.request = async () => ({
        data: [{}, {}, {}],
        meta: { total: 100 },
      });

      const stats = await api.getStats();

      assert.equal(stats.connected, true);
      assert.equal(stats.totalEntries, 100);
    });

    it('should return disconnected status on error', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      api.request = async () => {
        throw new Error('Connection refused');
      };

      const stats = await api.getStats();

      assert.equal(stats.connected, false);
      assert.ok(stats.error);
    });

    it('should handle response without meta', async () => {
      const { OnelistAPI } = require('../scripts/lib/api.js');

      const api = new OnelistAPI({
        apiUrl: 'http://localhost:4000',
        apiKey: 'test',
      });

      api.request = async () => ({
        data: [{}, {}],
      });

      const stats = await api.getStats();

      assert.equal(stats.connected, true);
      assert.equal(stats.totalEntries, 2);
    });
  });
});
