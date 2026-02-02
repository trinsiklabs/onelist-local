/**
 * Tests for buffer.js
 */

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Store original values
const originalHome = process.env.HOME;
let tempDir;

describe('Buffer Module', () => {
  beforeEach(() => {
    // Create temp directory for test config
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'onelist-test-'));
    process.env.HOME = tempDir;

    // Clear require cache to get fresh module with new HOME
    delete require.cache[require.resolve('../scripts/lib/buffer.js')];
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
    delete require.cache[require.resolve('../scripts/lib/buffer.js')];
    delete require.cache[require.resolve('../scripts/lib/config.js')];
  });

  describe('loadBuffer', () => {
    it('should return empty array when no buffer file exists', () => {
      const { loadBuffer } = require('../scripts/lib/buffer.js');
      const buffer = loadBuffer();

      assert.ok(Array.isArray(buffer));
      assert.equal(buffer.length, 0);
    });

    it('should load buffer from file', () => {
      const { loadBuffer, BUFFER_FILE } = require('../scripts/lib/buffer.js');
      const { ensureConfigDir } = require('../scripts/lib/config.js');

      ensureConfigDir();
      const testBuffer = [
        { timestamp: '2026-01-01T00:00:00Z', tool: 'Edit', content: 'test' },
        { timestamp: '2026-01-01T00:01:00Z', tool: 'Write', content: 'more' },
      ];
      fs.writeFileSync(BUFFER_FILE, JSON.stringify(testBuffer));

      const loaded = loadBuffer();

      assert.deepEqual(loaded, testBuffer);
    });

    it('should return empty array on invalid JSON', () => {
      const { loadBuffer, BUFFER_FILE } = require('../scripts/lib/buffer.js');
      const { ensureConfigDir } = require('../scripts/lib/config.js');

      ensureConfigDir();
      fs.writeFileSync(BUFFER_FILE, 'invalid json {{{');

      const loaded = loadBuffer();

      assert.ok(Array.isArray(loaded));
      assert.equal(loaded.length, 0);
    });
  });

  describe('saveBuffer', () => {
    it('should write buffer to file', () => {
      const { saveBuffer, BUFFER_FILE } = require('../scripts/lib/buffer.js');

      const testBuffer = [{ tool: 'Test', data: 'value' }];
      saveBuffer(testBuffer);

      const written = JSON.parse(fs.readFileSync(BUFFER_FILE, 'utf8'));
      assert.deepEqual(written, testBuffer);
    });

    it('should create config directory if needed', () => {
      const { saveBuffer, BUFFER_FILE } = require('../scripts/lib/buffer.js');
      const { CONFIG_DIR } = require('../scripts/lib/config.js');

      assert.ok(!fs.existsSync(CONFIG_DIR));

      saveBuffer([{ test: 'data' }]);

      assert.ok(fs.existsSync(CONFIG_DIR));
      assert.ok(fs.existsSync(BUFFER_FILE));
    });
  });

  describe('addToBuffer', () => {
    it('should add item with timestamp', () => {
      const { addToBuffer, loadBuffer } = require('../scripts/lib/buffer.js');

      const before = Date.now();
      addToBuffer({ tool: 'Edit', content: 'test content' });
      const after = Date.now();

      const buffer = loadBuffer();
      assert.equal(buffer.length, 1);
      assert.equal(buffer[0].tool, 'Edit');
      assert.equal(buffer[0].content, 'test content');
      assert.ok(buffer[0].timestamp);

      const ts = new Date(buffer[0].timestamp).getTime();
      assert.ok(ts >= before && ts <= after);
    });

    it('should append to existing buffer', () => {
      const { addToBuffer, loadBuffer } = require('../scripts/lib/buffer.js');

      addToBuffer({ tool: 'Edit', n: 1 });
      addToBuffer({ tool: 'Write', n: 2 });
      addToBuffer({ tool: 'Bash', n: 3 });

      const buffer = loadBuffer();
      assert.equal(buffer.length, 3);
      assert.equal(buffer[0].n, 1);
      assert.equal(buffer[1].n, 2);
      assert.equal(buffer[2].n, 3);
    });

    it('should return updated buffer', () => {
      const { addToBuffer } = require('../scripts/lib/buffer.js');

      const result1 = addToBuffer({ tool: 'First' });
      assert.equal(result1.length, 1);

      const result2 = addToBuffer({ tool: 'Second' });
      assert.equal(result2.length, 2);
    });
  });

  describe('clearBuffer', () => {
    it('should remove buffer file', () => {
      const { addToBuffer, clearBuffer, BUFFER_FILE } = require('../scripts/lib/buffer.js');

      addToBuffer({ tool: 'Test' });
      assert.ok(fs.existsSync(BUFFER_FILE));

      clearBuffer();
      assert.ok(!fs.existsSync(BUFFER_FILE));
    });

    it('should not throw if buffer file does not exist', () => {
      const { clearBuffer, BUFFER_FILE } = require('../scripts/lib/buffer.js');

      assert.ok(!fs.existsSync(BUFFER_FILE));
      assert.doesNotThrow(() => clearBuffer());
    });
  });

  describe('getBufferPath', () => {
    it('should return buffer file path', () => {
      const { getBufferPath, BUFFER_FILE } = require('../scripts/lib/buffer.js');

      assert.equal(getBufferPath(), BUFFER_FILE);
    });

    it('should include capture-buffer.json in path', () => {
      const { getBufferPath } = require('../scripts/lib/buffer.js');

      assert.ok(getBufferPath().endsWith('capture-buffer.json'));
    });
  });

  describe('getBufferSize', () => {
    it('should return 0 for empty buffer', () => {
      const { getBufferSize } = require('../scripts/lib/buffer.js');

      assert.equal(getBufferSize(), 0);
    });

    it('should return correct count', () => {
      const { addToBuffer, getBufferSize } = require('../scripts/lib/buffer.js');

      addToBuffer({ a: 1 });
      addToBuffer({ b: 2 });
      addToBuffer({ c: 3 });

      assert.equal(getBufferSize(), 3);
    });
  });
});
