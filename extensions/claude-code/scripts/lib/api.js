const https = require('https');
const http = require('http');
const { loadConfig } = require('./config');

class OnelistAPI {
  constructor(config = null) {
    const cfg = config || loadConfig();
    this.apiUrl = cfg.apiUrl;
    this.apiKey = cfg.apiKey;
  }

  async request(method, path, body = null) {
    const url = new URL(path, this.apiUrl);
    const protocol = url.protocol === 'https:' ? https : http;

    return new Promise((resolve, reject) => {
      const options = {
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        method,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        }
      };

      if (this.apiKey) {
        options.headers['Authorization'] = `Bearer ${this.apiKey}`;
      }

      const req = protocol.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            if (res.statusCode >= 400) {
              reject(new Error(parsed.error || parsed.message || `HTTP ${res.statusCode}`));
            } else {
              resolve(parsed);
            }
          } catch {
            if (res.statusCode >= 400) {
              reject(new Error(`HTTP ${res.statusCode}: ${data}`));
            } else {
              resolve(data);
            }
          }
        });
      });

      req.on('error', reject);

      if (body) {
        req.write(JSON.stringify(body));
      }

      req.end();
    });
  }

  // Search memories
  async search(query, options = {}) {
    const params = new URLSearchParams({
      q: query,
      limit: options.limit || 10,
    });
    if (options.type) params.set('entry_type', options.type);
    if (options.tag) params.set('tag', options.tag);

    return this.request('GET', `/api/v1/search?${params}`);
  }

  // Create entry
  async createEntry(entry) {
    return this.request('POST', '/api/v1/entries', entry);
  }

  // Get recent memories for context
  async getContextMemories(projectPath = null, limit = 20) {
    const params = new URLSearchParams({
      entry_type: 'memory',
      limit: limit.toString(),
    });
    if (projectPath) {
      params.set('tag', `project:${projectPath}`);
    }
    return this.request('GET', `/api/v1/entries?${params}`);
  }

  // Health check
  async ping() {
    return this.request('GET', '/api/v1/health');
  }

  // Get entry count
  async getStats() {
    try {
      const result = await this.request('GET', '/api/v1/entries?limit=1');
      return {
        connected: true,
        totalEntries: result.meta?.total || result.data?.length || 0,
      };
    } catch (err) {
      return {
        connected: false,
        error: err.message,
      };
    }
  }
}

module.exports = { OnelistAPI };
