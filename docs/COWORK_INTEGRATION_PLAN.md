# Onelist-Cowork Plugin Implementation Plan

## Overview

This plan details the integration of Onelist as a memory and GTD backend for Claude Cowork, Anthropic's macOS desktop application. The plugin enables Cowork and its sub-agents to participate in the multi-agent memory coordination framework alongside Claude Code and OpenClaw.

**Target**: Claude Cowork macOS Desktop App
**Plugin Name**: onelist-cowork
**Date**: 2026-02-02

---

## Prerequisites

- Multi-Agent Coordination V1 (source attribution, feedback loop prevention)
- Multi-Agent Coordination V2 (GTD integration, agent hierarchy)
- Onelist backend running with coordination endpoints

---

## Architecture

### Plugin Structure

```
onelist-cowork/
├── plugin.json                     # Plugin manifest for Cowork
├── package.json                    # Node.js dependencies
├── tsconfig.json                   # TypeScript configuration
│
├── mcp/
│   ├── server.ts                   # MCP server entry point
│   ├── tools/
│   │   ├── search.ts               # Search memories tool
│   │   ├── remember.ts             # Save memory tool
│   │   ├── tasks.ts                # GTD task tools
│   │   ├── projects.ts             # Project management tools
│   │   └── relationships.ts        # Entry relationship tools
│   └── resources/
│       ├── memories.ts             # Memory resource provider
│       └── context.ts              # Current context provider
│
├── prompts/
│   ├── system/
│   │   ├── memory-context.md       # Injected memory context
│   │   ├── gtd-awareness.md        # GTD methodology guidance
│   │   └── coordination.md         # Multi-agent awareness
│   ├── tasks/
│   │   ├── capture.md              # Inbox capture guidance
│   │   ├── clarify.md              # Task clarification
│   │   ├── organize.md             # Project/context assignment
│   │   └── review.md               # Review prompts
│   └── subagent/
│       ├── researcher.md           # Research sub-agent prompt
│       ├── coder.md                # Coding sub-agent prompt
│       └── writer.md               # Writing sub-agent prompt
│
├── slash-commands/
│   ├── capture.ts                  # /capture - quick inbox
│   ├── remember.ts                 # /remember - save insight
│   ├── tasks.ts                    # /tasks - show claimable
│   ├── complete.ts                 # /complete - finish task
│   ├── review.ts                   # /review - GTD review
│   ├── search.ts                   # /search - find memories
│   └── status.ts                   # /status - agent status
│
├── lib/
│   ├── api.ts                      # Onelist API client
│   ├── coordination.ts             # Coordination manager
│   ├── cache.ts                    # Local memory cache
│   ├── gtd.ts                      # GTD helpers
│   └── config.ts                   # Plugin configuration
│
├── subagents/
│   ├── base.ts                     # Base sub-agent class
│   ├── researcher.ts               # Research sub-agent
│   ├── coder.ts                    # Coding sub-agent
│   └── writer.ts                   # Writing sub-agent
│
└── tests/
    ├── mcp/
    ├── slash-commands/
    └── lib/
```

---

## Phase 1: Core Plugin Setup (Week 1)

### 1.1 Plugin Manifest

**File**: `plugin.json`

```json
{
  "name": "onelist-cowork",
  "displayName": "Onelist Memory & GTD",
  "version": "1.0.0",
  "description": "Connect Claude Cowork to Onelist for persistent memory and GTD task management",
  "author": "Trinsik",
  "homepage": "https://onelist.com",

  "capabilities": {
    "mcp": {
      "server": "./mcp/server.ts",
      "tools": true,
      "resources": true,
      "prompts": true
    },
    "slashCommands": true,
    "subagents": true,
    "settings": true
  },

  "settings": {
    "apiUrl": {
      "type": "string",
      "default": "https://api.onelist.com",
      "description": "Onelist API endpoint"
    },
    "apiKey": {
      "type": "string",
      "secret": true,
      "description": "Your Onelist API key"
    },
    "autoInjectMemories": {
      "type": "boolean",
      "default": true,
      "description": "Automatically inject relevant memories into context"
    },
    "gtdEnabled": {
      "type": "boolean",
      "default": true,
      "description": "Enable GTD task management features"
    },
    "memoryLimit": {
      "type": "number",
      "default": 10,
      "description": "Maximum memories to inject per conversation"
    }
  },

  "permissions": [
    "network",
    "filesystem:~/.onelist"
  ]
}
```

### 1.2 Configuration Module

**File**: `lib/config.ts`

```typescript
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

export interface CoworkConfig {
  apiUrl: string;
  apiKey: string;
  autoInjectMemories: boolean;
  gtdEnabled: boolean;
  memoryLimit: number;
  instanceId: string;
}

const CONFIG_DIR = join(homedir(), '.onelist');
const CONFIG_FILE = join(CONFIG_DIR, 'cowork-config.json');

const DEFAULTS: CoworkConfig = {
  apiUrl: 'https://api.onelist.com',
  apiKey: '',
  autoInjectMemories: true,
  gtdEnabled: true,
  memoryLimit: 10,
  instanceId: generateInstanceId(),
};

function generateInstanceId(): string {
  const hostname = require('os').hostname();
  return `cowork-${hostname}-${Date.now().toString(36)}`;
}

export function loadConfig(): CoworkConfig {
  if (!existsSync(CONFIG_FILE)) {
    return { ...DEFAULTS };
  }

  try {
    const saved = JSON.parse(readFileSync(CONFIG_FILE, 'utf8'));
    return { ...DEFAULTS, ...saved };
  } catch {
    return { ...DEFAULTS };
  }
}

export function saveConfig(config: Partial<CoworkConfig>): void {
  if (!existsSync(CONFIG_DIR)) {
    mkdirSync(CONFIG_DIR, { recursive: true });
  }

  const current = loadConfig();
  const updated = { ...current, ...config };
  writeFileSync(CONFIG_FILE, JSON.stringify(updated, null, 2));
}

export function getConfig(): CoworkConfig {
  return loadConfig();
}
```

### 1.3 API Client

**File**: `lib/api.ts`

```typescript
import { getConfig } from './config';

const AGENT_ID = 'cowork';
const AGENT_VERSION = '1.0.0';

export interface SearchOptions {
  limit?: number;
  type?: string;
  tag?: string;
  excludeAgents?: string[];
  includeAgents?: string[];
}

export interface Entry {
  id: string;
  title: string;
  content: string;
  entry_type: string;
  metadata?: Record<string, any>;
  attribution?: {
    agent_id: string;
    agent_version: string;
    created_at: string;
    derivation_depth: number;
  };
}

export interface TaskEntry extends Entry {
  metadata: {
    gtd_bucket?: 'inbox' | 'next_actions' | 'waiting_for' | 'someday_maybe';
    gtd_context?: string;
    due_date?: string;
    assigned_to?: string;
    claimed_by?: string;
  };
}

export class OnelistAPI {
  private apiUrl: string;
  private apiKey: string;
  private instanceId: string;
  private subagentId?: string;

  constructor(options?: { subagentId?: string }) {
    const config = getConfig();
    this.apiUrl = config.apiUrl;
    this.apiKey = config.apiKey;
    this.instanceId = config.instanceId;
    this.subagentId = options?.subagentId;
  }

  private getHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json',
      'X-Agent-Id': AGENT_ID,
      'X-Agent-Version': AGENT_VERSION,
      'X-Agent-Instance-Id': this.instanceId,
    };

    if (this.subagentId) {
      headers['X-Agent-Subagent-Id'] = this.subagentId;
    }

    return headers;
  }

  async request(method: string, path: string, body?: any): Promise<any> {
    const url = `${this.apiUrl}${path}`;
    const options: RequestInit = {
      method,
      headers: this.getHeaders(),
    };

    if (body) {
      options.body = JSON.stringify(body);
    }

    const response = await fetch(url, options);

    if (!response.ok) {
      throw new Error(`API error: ${response.status} ${response.statusText}`);
    }

    return response.json();
  }

  // Memory operations
  async search(query: string, options: SearchOptions = {}): Promise<{ data: Entry[]; meta: any }> {
    const params = new URLSearchParams({
      q: query,
      limit: String(options.limit || 10),
    });

    if (options.type) params.append('entry_type', options.type);
    if (options.tag) params.append('tag', options.tag);
    if (options.excludeAgents) params.append('exclude_agents', options.excludeAgents.join(','));
    if (options.includeAgents) params.append('include_agents', options.includeAgents.join(','));

    return this.request('GET', `/api/v1/search?${params}`);
  }

  async createEntry(entry: Partial<Entry>): Promise<Entry> {
    return this.request('POST', '/api/v1/entries', entry);
  }

  async createMemory(content: string, metadata?: Record<string, any>): Promise<Entry> {
    return this.createEntry({
      title: content.slice(0, 100),
      content,
      entry_type: 'memory',
      metadata,
    });
  }

  // GTD operations
  async getClaimableTasks(): Promise<TaskEntry[]> {
    const response = await this.request('GET', '/api/v1/claimable-tasks');
    return response.data;
  }

  async claimTask(taskId: string): Promise<TaskEntry> {
    return this.request('POST', `/api/v1/claim/${taskId}`);
  }

  async completeTask(taskId: string, evidence?: string): Promise<TaskEntry> {
    return this.request('POST', `/api/v1/complete/${taskId}`, { evidence });
  }

  async createInboxItem(content: string): Promise<TaskEntry> {
    return this.createEntry({
      title: content.slice(0, 100),
      content,
      entry_type: 'task',
      metadata: {
        gtd_bucket: 'inbox',
      },
    }) as Promise<TaskEntry>;
  }

  // Relationships
  async createRelationship(fromId: string, toId: string, type: string): Promise<any> {
    return this.request('POST', '/api/v1/relationships', {
      from_entry_id: fromId,
      to_entry_id: toId,
      relationship_type: type,
    });
  }

  // Agent registration
  async registerAgent(): Promise<any> {
    return this.request('POST', '/api/v1/agents/register', {
      agent_type: AGENT_ID,
      instance_id: this.instanceId,
      subagent_id: this.subagentId,
      capabilities: ['memory', 'gtd', 'code', 'research', 'writing'],
      subagent_support: true,
    });
  }

  async heartbeat(): Promise<any> {
    return this.request('POST', '/api/v1/heartbeat', {
      status: 'healthy',
    });
  }

  // Health check
  async ping(): Promise<boolean> {
    try {
      await this.request('GET', '/api/v1/health');
      return true;
    } catch {
      return false;
    }
  }
}

export const api = new OnelistAPI();
```

---

## Phase 2: MCP Server (Week 2)

### 2.1 MCP Server Entry Point

**File**: `mcp/server.ts`

```typescript
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

import { searchTool, searchHandler } from './tools/search';
import { rememberTool, rememberHandler } from './tools/remember';
import { taskTools, taskHandlers } from './tools/tasks';
import { projectTools, projectHandlers } from './tools/projects';
import { memoriesResource, memoriesHandler } from './resources/memories';
import { contextResource, contextHandler } from './resources/context';
import { memoryContextPrompt, gtdAwarenessPrompt } from './prompts';

const server = new Server(
  {
    name: 'onelist-cowork',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
      resources: {},
      prompts: {},
    },
  }
);

// Tools
const allTools = [
  searchTool,
  rememberTool,
  ...taskTools,
  ...projectTools,
];

const allHandlers: Record<string, (args: any) => Promise<any>> = {
  'onelist_search': searchHandler,
  'onelist_remember': rememberHandler,
  ...taskHandlers,
  ...projectHandlers,
};

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: allTools,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const handler = allHandlers[name];

  if (!handler) {
    throw new Error(`Unknown tool: ${name}`);
  }

  try {
    const result = await handler(args);
    return {
      content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
    };
  } catch (error) {
    return {
      content: [{ type: 'text', text: `Error: ${error.message}` }],
      isError: true,
    };
  }
});

// Resources
server.setRequestHandler(ListResourcesRequestSchema, async () => ({
  resources: [memoriesResource, contextResource],
}));

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  if (uri === 'onelist://memories') {
    return memoriesHandler();
  }
  if (uri === 'onelist://context') {
    return contextHandler();
  }

  throw new Error(`Unknown resource: ${uri}`);
});

// Prompts
server.setRequestHandler(ListPromptsRequestSchema, async () => ({
  prompts: [memoryContextPrompt, gtdAwarenessPrompt],
}));

server.setRequestHandler(GetPromptRequestSchema, async (request) => {
  const { name } = request.params;

  if (name === 'memory-context') {
    return memoryContextPrompt.getPrompt();
  }
  if (name === 'gtd-awareness') {
    return gtdAwarenessPrompt.getPrompt();
  }

  throw new Error(`Unknown prompt: ${name}`);
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Onelist MCP server running');
}

main().catch(console.error);
```

### 2.2 Search Tool

**File**: `mcp/tools/search.ts`

```typescript
import { api } from '../../lib/api';

export const searchTool = {
  name: 'onelist_search',
  description: 'Search your Onelist memory for relevant information, past conversations, decisions, and context',
  inputSchema: {
    type: 'object',
    properties: {
      query: {
        type: 'string',
        description: 'Search query - what are you looking for?',
      },
      limit: {
        type: 'number',
        description: 'Maximum results to return (default: 10)',
        default: 10,
      },
      type: {
        type: 'string',
        enum: ['memory', 'task', 'note', 'project', 'person'],
        description: 'Filter by entry type',
      },
      excludeSelf: {
        type: 'boolean',
        description: 'Exclude memories created by this Cowork instance',
        default: true,
      },
    },
    required: ['query'],
  },
};

export async function searchHandler(args: {
  query: string;
  limit?: number;
  type?: string;
  excludeSelf?: boolean;
}): Promise<any> {
  const options: any = {
    limit: args.limit || 10,
  };

  if (args.type) {
    options.type = args.type;
  }

  if (args.excludeSelf !== false) {
    options.excludeAgents = ['cowork'];
  }

  const results = await api.search(args.query, options);

  return {
    query: args.query,
    total: results.meta?.total || results.data.length,
    results: results.data.map((entry) => ({
      id: entry.id,
      title: entry.title,
      content: entry.content,
      type: entry.entry_type,
      attribution: entry.attribution,
      relevance: entry.metadata?.score,
    })),
  };
}
```

### 2.3 Remember Tool

**File**: `mcp/tools/remember.ts`

```typescript
import { api } from '../../lib/api';

export const rememberTool = {
  name: 'onelist_remember',
  description: 'Save important information, decisions, or insights to Onelist memory for future reference',
  inputSchema: {
    type: 'object',
    properties: {
      content: {
        type: 'string',
        description: 'The information to remember',
      },
      tags: {
        type: 'array',
        items: { type: 'string' },
        description: 'Tags to categorize this memory (e.g., ["project:alpha", "decision"])',
      },
      projectId: {
        type: 'string',
        description: 'Link this memory to a specific project',
      },
    },
    required: ['content'],
  },
};

export async function rememberHandler(args: {
  content: string;
  tags?: string[];
  projectId?: string;
}): Promise<any> {
  const metadata: Record<string, any> = {};

  if (args.tags) {
    metadata.tags = args.tags;
  }

  const entry = await api.createMemory(args.content, metadata);

  // Create project relationship if specified
  if (args.projectId) {
    await api.createRelationship(entry.id, args.projectId, 'belongs_to_project');
  }

  return {
    success: true,
    id: entry.id,
    message: 'Memory saved successfully',
  };
}
```

### 2.4 Task Tools

**File**: `mcp/tools/tasks.ts`

```typescript
import { api } from '../../lib/api';

export const taskTools = [
  {
    name: 'onelist_inbox_capture',
    description: 'Capture a quick thought or task to your GTD inbox for later processing',
    inputSchema: {
      type: 'object',
      properties: {
        content: {
          type: 'string',
          description: 'What needs to be captured?',
        },
      },
      required: ['content'],
    },
  },
  {
    name: 'onelist_get_tasks',
    description: 'Get tasks available to claim and work on',
    inputSchema: {
      type: 'object',
      properties: {
        context: {
          type: 'string',
          description: 'Filter by GTD context (e.g., @computer, @phone)',
        },
        bucket: {
          type: 'string',
          enum: ['inbox', 'next_actions', 'waiting_for', 'someday_maybe'],
          description: 'Filter by GTD bucket',
        },
      },
    },
  },
  {
    name: 'onelist_claim_task',
    description: 'Claim a task to work on it',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: {
          type: 'string',
          description: 'ID of the task to claim',
        },
      },
      required: ['taskId'],
    },
  },
  {
    name: 'onelist_complete_task',
    description: 'Mark a task as complete, optionally with evidence of completion',
    inputSchema: {
      type: 'object',
      properties: {
        taskId: {
          type: 'string',
          description: 'ID of the task to complete',
        },
        evidence: {
          type: 'string',
          description: 'Description or link to evidence of completion',
        },
      },
      required: ['taskId'],
    },
  },
];

export const taskHandlers: Record<string, (args: any) => Promise<any>> = {
  onelist_inbox_capture: async (args: { content: string }) => {
    const entry = await api.createInboxItem(args.content);
    return {
      success: true,
      id: entry.id,
      message: 'Added to inbox',
    };
  },

  onelist_get_tasks: async (args: { context?: string; bucket?: string }) => {
    const tasks = await api.getClaimableTasks();

    let filtered = tasks;
    if (args.context) {
      filtered = filtered.filter(t => t.metadata.gtd_context === args.context);
    }
    if (args.bucket) {
      filtered = filtered.filter(t => t.metadata.gtd_bucket === args.bucket);
    }

    return {
      total: filtered.length,
      tasks: filtered.map(t => ({
        id: t.id,
        title: t.title,
        bucket: t.metadata.gtd_bucket,
        context: t.metadata.gtd_context,
        dueDate: t.metadata.due_date,
      })),
    };
  },

  onelist_claim_task: async (args: { taskId: string }) => {
    const task = await api.claimTask(args.taskId);
    return {
      success: true,
      task: {
        id: task.id,
        title: task.title,
        content: task.content,
      },
      message: 'Task claimed - you are now working on it',
    };
  },

  onelist_complete_task: async (args: { taskId: string; evidence?: string }) => {
    const task = await api.completeTask(args.taskId, args.evidence);
    return {
      success: true,
      id: task.id,
      message: 'Task marked as complete',
    };
  },
};
```

---

## Phase 3: Slash Commands (Week 3)

### 3.1 Capture Command

**File**: `slash-commands/capture.ts`

```typescript
import { api } from '../lib/api';

export const command = {
  name: 'capture',
  description: 'Quick capture to GTD inbox',
  usage: '/capture <thought or task>',
};

export async function execute(args: string): Promise<string> {
  if (!args.trim()) {
    return 'Usage: /capture <thought or task>\n\nCaptures anything to your GTD inbox for later processing.';
  }

  try {
    const entry = await api.createInboxItem(args);
    return `Captured to inbox: "${args.slice(0, 50)}${args.length > 50 ? '...' : ''}"`;
  } catch (error) {
    return `Failed to capture: ${error.message}`;
  }
}
```

### 3.2 Remember Command

**File**: `slash-commands/remember.ts`

```typescript
import { api } from '../lib/api';

export const command = {
  name: 'remember',
  description: 'Save an insight or decision to memory',
  usage: '/remember <what to remember>',
};

export async function execute(args: string): Promise<string> {
  if (!args.trim()) {
    return 'Usage: /remember <important information>\n\nSaves information to Onelist for future reference.';
  }

  try {
    const entry = await api.createMemory(args);
    return `Remembered: "${args.slice(0, 50)}${args.length > 50 ? '...' : ''}"`;
  } catch (error) {
    return `Failed to save: ${error.message}`;
  }
}
```

### 3.3 Tasks Command

**File**: `slash-commands/tasks.ts`

```typescript
import { api } from '../lib/api';

export const command = {
  name: 'tasks',
  description: 'Show claimable tasks',
  usage: '/tasks [context]',
};

export async function execute(args: string): Promise<string> {
  try {
    const tasks = await api.getClaimableTasks();

    if (tasks.length === 0) {
      return 'No claimable tasks available.';
    }

    // Filter by context if provided
    let filtered = tasks;
    if (args.trim()) {
      const context = args.startsWith('@') ? args : `@${args}`;
      filtered = tasks.filter(t => t.metadata.gtd_context === context);
    }

    const lines = ['**Claimable Tasks**\n'];

    for (const task of filtered.slice(0, 10)) {
      const context = task.metadata.gtd_context || '';
      const due = task.metadata.due_date ? ` (due: ${task.metadata.due_date})` : '';
      lines.push(`- [${task.id.slice(0, 8)}] ${task.title} ${context}${due}`);
    }

    if (filtered.length > 10) {
      lines.push(`\n...and ${filtered.length - 10} more`);
    }

    return lines.join('\n');
  } catch (error) {
    return `Failed to fetch tasks: ${error.message}`;
  }
}
```

### 3.4 Complete Command

**File**: `slash-commands/complete.ts`

```typescript
import { api } from '../lib/api';

export const command = {
  name: 'complete',
  description: 'Mark a task as complete',
  usage: '/complete <task-id> [evidence]',
};

export async function execute(args: string): Promise<string> {
  const parts = args.split(' ');
  const taskId = parts[0];
  const evidence = parts.slice(1).join(' ');

  if (!taskId) {
    return 'Usage: /complete <task-id> [evidence]\n\nMarks a task as complete.';
  }

  try {
    await api.completeTask(taskId, evidence || undefined);
    return `Task ${taskId.slice(0, 8)} marked as complete.`;
  } catch (error) {
    return `Failed to complete task: ${error.message}`;
  }
}
```

### 3.5 Search Command

**File**: `slash-commands/search.ts`

```typescript
import { api } from '../lib/api';

export const command = {
  name: 'search',
  description: 'Search Onelist memories',
  usage: '/search <query>',
};

export async function execute(args: string): Promise<string> {
  if (!args.trim()) {
    return 'Usage: /search <query>\n\nSearch your Onelist memories.';
  }

  try {
    const results = await api.search(args, { limit: 5 });

    if (results.data.length === 0) {
      return `No results found for "${args}"`;
    }

    const lines = [`**Search Results for "${args}"**\n`];

    for (const entry of results.data) {
      const preview = entry.content.slice(0, 100).replace(/\n/g, ' ');
      const agent = entry.attribution?.agent_id || 'unknown';
      lines.push(`- **${entry.title}** (${agent})`);
      lines.push(`  ${preview}${entry.content.length > 100 ? '...' : ''}\n`);
    }

    return lines.join('\n');
  } catch (error) {
    return `Search failed: ${error.message}`;
  }
}
```

### 3.6 Status Command

**File**: `slash-commands/status.ts`

```typescript
import { api } from '../lib/api';
import { getConfig } from '../lib/config';

export const command = {
  name: 'status',
  description: 'Show Onelist connection status',
  usage: '/status',
};

export async function execute(): Promise<string> {
  const config = getConfig();
  const connected = await api.ping();

  const lines = [
    '**Onelist Status**\n',
    `Connected: ${connected ? 'Yes' : 'No'}`,
    `API URL: ${config.apiUrl}`,
    `Instance ID: ${config.instanceId}`,
    `Auto-inject: ${config.autoInjectMemories ? 'Enabled' : 'Disabled'}`,
    `GTD: ${config.gtdEnabled ? 'Enabled' : 'Disabled'}`,
  ];

  return lines.join('\n');
}
```

---

## Phase 4: Coordination Integration (Week 4)

### 4.1 Coordination Manager

**File**: `lib/coordination.ts`

```typescript
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import { getConfig } from './config';

const COORDINATION_DIR = join(homedir(), '.onelist', 'coordination');
const STATE_FILE = join(COORDINATION_DIR, 'state.json');
const LOCK_FILE = join(COORDINATION_DIR, 'state.lock');

const AGENT_ID = 'cowork';
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const RATE_LIMIT_MAX = 30; // 30 writes per minute
const CIRCUIT_BREAKER_THRESHOLD = 5;
const CIRCUIT_BREAKER_RESET = 30000; // 30 seconds

interface CoordinationState {
  version: number;
  globalCircuitBreaker: {
    consecutiveFailures: number;
    backoffUntil: number;
  };
  agentRateLimits: {
    [agentId: string]: {
      writesInWindow: number;
      windowStart: number;
    };
  };
  agentHealth: {
    [agentId: string]: {
      lastSeen: number;
      status: 'healthy' | 'degraded' | 'unhealthy';
    };
  };
}

export class CoordinationManager {
  private instanceId: string;
  private subagentId?: string;

  constructor(options?: { subagentId?: string }) {
    const config = getConfig();
    this.instanceId = config.instanceId;
    this.subagentId = options?.subagentId;
    this.ensureDir();
  }

  private ensureDir(): void {
    if (!existsSync(COORDINATION_DIR)) {
      mkdirSync(COORDINATION_DIR, { recursive: true });
    }
  }

  private getAgentKey(): string {
    if (this.subagentId) {
      return `${AGENT_ID}:${this.instanceId}:${this.subagentId}`;
    }
    return `${AGENT_ID}:${this.instanceId}`;
  }

  private readState(): CoordinationState {
    if (!existsSync(STATE_FILE)) {
      return this.defaultState();
    }

    try {
      return JSON.parse(readFileSync(STATE_FILE, 'utf8'));
    } catch {
      return this.defaultState();
    }
  }

  private writeState(state: CoordinationState): void {
    writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  }

  private defaultState(): CoordinationState {
    return {
      version: 1,
      globalCircuitBreaker: {
        consecutiveFailures: 0,
        backoffUntil: 0,
      },
      agentRateLimits: {},
      agentHealth: {},
    };
  }

  canWrite(): { allowed: boolean; reason?: string; waitMs?: number } {
    const state = this.readState();
    const now = Date.now();
    const agentKey = this.getAgentKey();

    // Check circuit breaker
    if (state.globalCircuitBreaker.backoffUntil > now) {
      return {
        allowed: false,
        reason: 'Circuit breaker open',
        waitMs: state.globalCircuitBreaker.backoffUntil - now,
      };
    }

    // Check rate limit
    const limit = state.agentRateLimits[agentKey];
    if (limit) {
      if (now - limit.windowStart < RATE_LIMIT_WINDOW) {
        if (limit.writesInWindow >= RATE_LIMIT_MAX) {
          return {
            allowed: false,
            reason: 'Rate limit exceeded',
            waitMs: RATE_LIMIT_WINDOW - (now - limit.windowStart),
          };
        }
      }
    }

    return { allowed: true };
  }

  recordWrite(): void {
    const state = this.readState();
    const now = Date.now();
    const agentKey = this.getAgentKey();

    // Reset window if expired
    if (!state.agentRateLimits[agentKey] ||
        now - state.agentRateLimits[agentKey].windowStart >= RATE_LIMIT_WINDOW) {
      state.agentRateLimits[agentKey] = {
        writesInWindow: 0,
        windowStart: now,
      };
    }

    state.agentRateLimits[agentKey].writesInWindow++;

    // Reset circuit breaker on success
    state.globalCircuitBreaker.consecutiveFailures = 0;

    this.writeState(state);
  }

  recordFailure(error: string): void {
    const state = this.readState();

    state.globalCircuitBreaker.consecutiveFailures++;

    if (state.globalCircuitBreaker.consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
      state.globalCircuitBreaker.backoffUntil = Date.now() + CIRCUIT_BREAKER_RESET;
    }

    this.writeState(state);
  }

  updateHealth(status: 'healthy' | 'degraded' | 'unhealthy'): void {
    const state = this.readState();
    const agentKey = this.getAgentKey();

    state.agentHealth[agentKey] = {
      lastSeen: Date.now(),
      status,
    };

    this.writeState(state);
  }
}

export const coordinator = new CoordinationManager();
```

### 4.2 Local Cache

**File**: `lib/cache.ts`

```typescript
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const CACHE_DIR = join(homedir(), '.onelist', 'cache');
const CACHE_FILE = join(CACHE_DIR, 'cowork-memory-cache.json');
const MAX_AGE = 24 * 60 * 60 * 1000; // 24 hours
const MAX_ENTRIES = 100;

interface CachedEntry {
  id: string;
  title: string;
  content: string;
  entry_type: string;
  cachedAt: number;
  query: string;
}

interface Cache {
  entries: CachedEntry[];
}

export class LocalMemoryCache {
  constructor() {
    this.ensureDir();
  }

  private ensureDir(): void {
    if (!existsSync(CACHE_DIR)) {
      mkdirSync(CACHE_DIR, { recursive: true });
    }
  }

  private readCache(): Cache {
    if (!existsSync(CACHE_FILE)) {
      return { entries: [] };
    }

    try {
      return JSON.parse(readFileSync(CACHE_FILE, 'utf8'));
    } catch {
      return { entries: [] };
    }
  }

  private writeCache(cache: Cache): void {
    writeFileSync(CACHE_FILE, JSON.stringify(cache, null, 2));
  }

  cacheSearchResults(query: string, results: any[]): void {
    const cache = this.readCache();
    const now = Date.now();

    // Add new entries
    for (const result of results) {
      const existing = cache.entries.findIndex(e => e.id === result.id);
      if (existing >= 0) {
        cache.entries[existing] = { ...result, cachedAt: now, query };
      } else {
        cache.entries.push({ ...result, cachedAt: now, query });
      }
    }

    // Prune old entries
    cache.entries = cache.entries
      .filter(e => now - e.cachedAt < MAX_AGE)
      .slice(-MAX_ENTRIES);

    this.writeCache(cache);
  }

  getCachedResults(query: string, limit: number = 10): CachedEntry[] {
    const cache = this.readCache();
    const now = Date.now();
    const queryLower = query.toLowerCase();

    // Simple fuzzy matching
    return cache.entries
      .filter(e => now - e.cachedAt < MAX_AGE)
      .filter(e =>
        e.query.toLowerCase().includes(queryLower) ||
        e.title.toLowerCase().includes(queryLower) ||
        e.content.toLowerCase().includes(queryLower)
      )
      .slice(0, limit);
  }
}

export const memoryCache = new LocalMemoryCache();
```

---

## Phase 5: Sub-Agent Support (Week 5)

### 5.1 Base Sub-Agent

**File**: `subagents/base.ts`

```typescript
import { OnelistAPI } from '../lib/api';
import { CoordinationManager } from '../lib/coordination';

export interface SubAgentConfig {
  id: string;
  name: string;
  description: string;
  capabilities: string[];
}

export abstract class BaseSubAgent {
  protected api: OnelistAPI;
  protected coordinator: CoordinationManager;
  protected config: SubAgentConfig;

  constructor(config: SubAgentConfig) {
    this.config = config;
    this.api = new OnelistAPI({ subagentId: config.id });
    this.coordinator = new CoordinationManager({ subagentId: config.id });
  }

  async initialize(): Promise<void> {
    await this.api.registerAgent();
    this.coordinator.updateHealth('healthy');
  }

  async heartbeat(): Promise<void> {
    await this.api.heartbeat();
    this.coordinator.updateHealth('healthy');
  }

  async remember(content: string, metadata?: Record<string, any>): Promise<any> {
    const canWrite = this.coordinator.canWrite();
    if (!canWrite.allowed) {
      throw new Error(`Cannot write: ${canWrite.reason}`);
    }

    try {
      const result = await this.api.createMemory(content, {
        ...metadata,
        subagent: this.config.id,
      });
      this.coordinator.recordWrite();
      return result;
    } catch (error) {
      this.coordinator.recordFailure(error.message);
      throw error;
    }
  }

  async search(query: string, options?: any): Promise<any> {
    return this.api.search(query, options);
  }

  abstract getSystemPrompt(): string;
}
```

### 5.2 Researcher Sub-Agent

**File**: `subagents/researcher.ts`

```typescript
import { BaseSubAgent, SubAgentConfig } from './base';

const config: SubAgentConfig = {
  id: 'researcher',
  name: 'Research Assistant',
  description: 'Conducts research and synthesizes information',
  capabilities: ['research', 'summarize', 'analyze'],
};

export class ResearcherSubAgent extends BaseSubAgent {
  constructor() {
    super(config);
  }

  getSystemPrompt(): string {
    return `You are a research assistant with access to Onelist memory.

Your role:
- Search existing memories for relevant information
- Synthesize findings from multiple sources
- Save important research discoveries
- Track research progress and findings

When researching:
1. First search Onelist for existing knowledge
2. Note what sources contributed (attribution)
3. Save new findings with proper tags
4. Create relationships between related findings

Available tools:
- onelist_search: Find relevant memories
- onelist_remember: Save research findings
- onelist_inbox_capture: Note follow-up research needed`;
  }
}
```

### 5.3 Coder Sub-Agent

**File**: `subagents/coder.ts`

```typescript
import { BaseSubAgent, SubAgentConfig } from './base';

const config: SubAgentConfig = {
  id: 'coder',
  name: 'Coding Assistant',
  description: 'Helps with code, reviews, and technical tasks',
  capabilities: ['code', 'review', 'debug', 'refactor'],
};

export class CoderSubAgent extends BaseSubAgent {
  constructor() {
    super(config);
  }

  getSystemPrompt(): string {
    return `You are a coding assistant with access to Onelist memory.

Your role:
- Recall past coding decisions and patterns
- Remember debugging solutions
- Track technical decisions for the project
- Claim and complete coding tasks

When coding:
1. Search for similar past solutions
2. Check for project coding conventions
3. Save important decisions/patterns
4. Complete tasks with evidence (PR links, etc.)

Available tools:
- onelist_search: Find past solutions and decisions
- onelist_remember: Save coding patterns and decisions
- onelist_claim_task: Take ownership of a coding task
- onelist_complete_task: Mark task done with evidence`;
  }
}
```

---

## Phase 6: Testing & Documentation (Week 6)

### 6.1 API Tests

**File**: `tests/lib/api.test.ts`

```typescript
import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';

describe('OnelistAPI', () => {
  describe('search', () => {
    it('should include agent headers', async () => {
      // Test implementation
    });

    it('should exclude own agent by default', async () => {
      // Test implementation
    });
  });

  describe('createMemory', () => {
    it('should check coordination before write', async () => {
      // Test implementation
    });
  });

  describe('GTD operations', () => {
    it('should claim task successfully', async () => {
      // Test implementation
    });

    it('should complete task with evidence', async () => {
      // Test implementation
    });
  });
});
```

### 6.2 Coordination Tests

**File**: `tests/lib/coordination.test.ts`

```typescript
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { CoordinationManager } from '../../lib/coordination';

describe('CoordinationManager', () => {
  describe('canWrite', () => {
    it('should allow write when under rate limit', () => {
      // Test implementation
    });

    it('should block write when circuit breaker open', () => {
      // Test implementation
    });
  });

  describe('recordFailure', () => {
    it('should open circuit breaker after threshold', () => {
      // Test implementation
    });
  });
});
```

### 6.3 Slash Command Tests

**File**: `tests/slash-commands/capture.test.ts`

```typescript
import { describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import { execute } from '../../slash-commands/capture';

describe('/capture command', () => {
  it('should show usage when no args', async () => {
    const result = await execute('');
    assert.ok(result.includes('Usage:'));
  });

  it('should capture to inbox', async () => {
    // Mock API and test
  });
});
```

---

## Critical Files Summary

| File | Purpose |
|------|---------|
| `plugin.json` | Plugin manifest and settings |
| `lib/api.ts` | Onelist API client with agent headers |
| `lib/coordination.ts` | Multi-agent coordination |
| `lib/cache.ts` | Offline memory cache |
| `lib/config.ts` | Plugin configuration |
| `mcp/server.ts` | MCP server entry point |
| `mcp/tools/*.ts` | MCP tool implementations |
| `slash-commands/*.ts` | Slash command handlers |
| `subagents/*.ts` | Sub-agent implementations |

---

## Integration with V1/V2 Plans

### From V1 (Source Attribution)

- Agent ID: `cowork`
- Headers: `X-Agent-Id`, `X-Agent-Version`, `X-Agent-Instance-Id`, `X-Agent-Subagent-Id`
- Search exclusion: Exclude own agent by default

### From V2 (GTD Integration)

- Person entries for Cowork instance and sub-agents
- Task claiming and completion
- Relationship creation (belongs_to_project, etc.)
- Inbox capture and processing

### Shared Components

The following can be shared with claude-code and onelist-memory plugins:

```
shared/
├── api-client.ts       # Base API client
├── coordination.ts     # Coordination manager
├── cache.ts           # Local cache
└── types.ts           # Shared type definitions
```

---

## Rollout Schedule

| Week | Phase | Deliverables |
|------|-------|--------------|
| 1 | Core Setup | plugin.json, config, api client |
| 2 | MCP Server | Tools, resources, prompts |
| 3 | Slash Commands | /capture, /remember, /tasks, /complete, /search, /status |
| 4 | Coordination | Rate limiting, circuit breaker, caching |
| 5 | Sub-Agents | Base class, researcher, coder sub-agents |
| 6 | Testing & Docs | Full test suite, documentation |

---

## Dependencies

### npm packages

```json
{
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "@types/node": "^20.0.0"
  }
}
```

### Prerequisites

- Node.js 20+
- Claude Cowork installed
- Onelist account with API key
- V1/V2 coordination endpoints deployed

---

## Future Enhancements

1. **Rich UI Integration** - Leverage Cowork's GUI for memory visualization
2. **Voice Commands** - If Cowork adds voice, integrate `/capture` via voice
3. **File Watcher** - Auto-capture from watched folders
4. **Notification Center** - Surface task assignments via macOS notifications
5. **Spotlight Integration** - Search Onelist from Spotlight
