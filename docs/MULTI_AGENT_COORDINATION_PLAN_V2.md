# Multi-Agent Memory Coordination Implementation Plan

## Version 2.0 - GTD Integration & Full Agent Hierarchy

**Scope**: External API agents (Claude Code, OpenClaw) with GTD-based task management, project binding, and full agent hierarchy support
**Date**: 2026-02-02
**Builds On**: V1 (Source Attribution, Feedback Loop Prevention, Coordination Layer)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [V1 Recap](#2-v1-recap)
3. [Agents as Person Entries](#3-agents-as-person-entries)
4. [Dynamic Entry Relationships](#4-dynamic-entry-relationships)
5. [GTD Integration](#5-gtd-integration)
6. [Project Discovery & Binding](#6-project-discovery--binding)
7. [Sprint Support via Entry Groups](#7-sprint-support-via-entry-groups)
8. [Progressive GTD Adoption](#8-progressive-gtd-adoption)
9. [Completion Verification](#9-completion-verification)
10. [Extension Implementation](#10-extension-implementation)
11. [API Additions](#11-api-additions)
12. [Database Schema](#12-database-schema)
13. [Implementation Phases](#13-implementation-phases)
14. [Testing Plan](#14-testing-plan)

---

## 1. Executive Summary

V2 extends the multi-agent coordination framework to integrate with Onelist's GTD-based River Agent system. External agents (Claude Code, OpenClaw, and their subagents) become first-class participants in the user's productivity system:

- **Agents as Persons**: Each agent type, instance, and subagent can be represented as a `person` entry, enabling task assignment at any granularity level
- **Dynamic Relationships**: Typed entry relationships (`depends_on`, `blocked_by`, `assigned_to`, etc.) enable rich task coordination
- **Project Binding**: Sessions automatically bind to projects with smart discovery
- **Sprint Support**: Entry groups serve as sprints for time-boxed work organization
- **Progressive Adoption**: Users choose how much GTD structure they want

---

## 2. V1 Recap

V1 established the foundation for multi-agent coordination:

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Source Attribution (agent_id on entries/memories) | Foundation |
| 2 | Feedback Loop Prevention (derivation depth, content hashing) | Foundation |
| 3 | Coordination Layer (shared state, global circuit breaker) | Foundation |
| 4 | Resilience & Fallback (local cache, offline mode) | Foundation |
| 5 | Security Hardening (scoped API keys, audit logging) | Foundation |
| 6 | Opportunity Enablement (synthesis API, unified timeline) | Foundation |

V2 builds on this foundation, assuming V1 features are in place.

---

## 3. Agents as Person Entries

### 3.1 Granularity Options

Users configure how granularly agents are represented as person entries:

```elixir
%Entry{
  entry_type: "config",
  metadata: %{
    "config_type" => "agent_person_granularity",

    # Granularity level
    "granularity" => "full",
    # Options:
    # "type_only"  → Only "Claude Code", "OpenClaw" (assignments to any instance)
    # "instances"  → Types + each instance (Claude Code - MacBook Pro)
    # "full"       → Types + instances + subagents (all levels assignable)

    # Naming preferences
    "instance_naming" => "machine_name",  # machine_name, user_chosen, auto_numbered
    "subagent_naming" => "role_parent"    # "Researcher (Clawbot-Home)" vs just "Researcher"
  }
}
```

### 3.2 Full Hierarchy Example

```
Person: Claude Code                           [assignable - any instance picks up]
├── Person: Claude Code - MacBook Pro         [assignable - specific machine]
├── Person: Claude Code - Work Laptop         [assignable - specific machine]
└── Person: Claude Code - Home Server         [assignable - specific machine]

Person: OpenClaw                              [assignable - any clawbot]
├── Person: Clawbot - Home Server             [assignable - specific clawbot]
│   ├── Person: Researcher (Home Server)      [assignable - specific subagent]
│   ├── Person: Writer (Home Server)          [assignable - specific subagent]
│   └── Person: Analyst (Home Server)         [assignable - specific subagent]
└── Person: Clawbot - VPS                     [assignable - specific clawbot]
    └── Person: Researcher (VPS)              [assignable - specific subagent]
```

### 3.3 Person Entry Structures

**Agent Type (Top Level)**

```elixir
%Entry{
  entry_type: "person",
  title: "Claude Code",
  content: "AI coding assistant for terminal environments",
  metadata: %{
    "person_type" => "artificial",
    "agent_level" => "type",
    "agent_id" => "claude-code",
    "capabilities" => ["coding", "debugging", "refactoring", "documentation"],
    "preferred_contexts" => ["@computer"]
  }
}
```

**Agent Instance**

```elixir
%Entry{
  entry_type: "person",
  title: "Claude Code - MacBook Pro",
  content: "Claude Code instance on Bryan's MacBook Pro",
  metadata: %{
    "person_type" => "artificial",
    "agent_level" => "instance",
    "agent_id" => "claude-code",
    "instance_id" => "macbook-pro-2024",
    "instance_name" => "MacBook Pro",
    "parent_person_id" => "claude-code-type-uuid",

    # Instance details
    "machine_identifier" => "Bryans-MacBook-Pro.local",
    "working_directories" => [
      "/Users/user/projects/onelist.com",
      "/Users/user/projects/onelist-local"
    ],
    "last_seen" => "2026-02-02T10:30:00Z",
    "status" => "active"
  }
}
```

**Subagent**

```elixir
%Entry{
  entry_type: "person",
  title: "Researcher (Home Server)",
  content: "Research-focused subagent for deep analysis tasks",
  metadata: %{
    "person_type" => "artificial",
    "agent_level" => "subagent",
    "agent_id" => "openclaw",
    "instance_id" => "clawbot-home",
    "subagent_name" => "researcher",
    "parent_person_id" => "clawbot-home-uuid",

    # Execution context
    "execution_context" => %{
      "parent_instance" => "clawbot-home-server",
      "spawned_on_demand" => true
    },

    "capabilities" => ["web_search", "deep_analysis", "report_generation"]
  }
}
```

### 3.4 Instance Registration Flow

```typescript
async function registerInstance(api: OnelistAPI): Promise<PersonEntry> {
  const machineId = getMachineIdentifier();
  const prefs = await getGranularityPreferences();

  // Check if instance already registered
  const existing = await api.search({
    entry_type: 'person',
    metadata: {
      agent_id: AGENT_ID,
      machine_identifier: machineId
    }
  });

  if (existing.length > 0) {
    // Update last_seen, return existing
    return await api.updateEntry(existing[0].id, {
      metadata: {
        last_seen: new Date().toISOString(),
        status: 'active'
      }
    });
  }

  // Ensure agent type person exists (if granularity includes types)
  let agentTypePerson = null;
  if (prefs.granularity !== 'type_only') {
    agentTypePerson = await ensureAgentTypePerson(api);
  }

  // Get instance name based on preference
  const instanceName = await getInstanceName(machineId, prefs.instance_naming);

  // Create instance person entry
  return await api.createEntry({
    entry_type: 'person',
    title: `${AGENT_DISPLAY_NAME} - ${instanceName}`,
    content: `${AGENT_DISPLAY_NAME} instance on ${instanceName}`,
    metadata: {
      person_type: 'artificial',
      agent_level: 'instance',
      agent_id: AGENT_ID,
      instance_id: generateInstanceId(),
      instance_name: instanceName,
      parent_person_id: agentTypePerson?.id,
      machine_identifier: machineId,
      working_directories: [process.cwd()],
      last_seen: new Date().toISOString(),
      status: 'active'
    }
  });
}

async function getInstanceName(machineId: string, naming: string): Promise<string> {
  switch (naming) {
    case 'machine_name':
      return os.hostname().replace('.local', '');
    case 'user_chosen':
      return await promptForInstanceName(machineId);
    case 'auto_numbered':
      const count = await getInstanceCount();
      return `Instance ${count + 1}`;
    default:
      return machineId;
  }
}
```

### 3.5 Subagent Registration (OpenClaw)

```typescript
async function registerSubagent(
  api: OnelistAPI,
  parentInstanceId: string,
  subagentName: string
): Promise<PersonEntry> {
  const prefs = await getGranularityPreferences();

  if (prefs.granularity !== 'full') {
    // Subagents not tracked as persons at this granularity
    return null;
  }

  const parentInstance = await api.getEntry(parentInstanceId);
  const displayName = formatSubagentName(subagentName, parentInstance, prefs);

  // Check if already registered
  const existing = await api.search({
    entry_type: 'person',
    metadata: {
      agent_level: 'subagent',
      parent_person_id: parentInstanceId,
      subagent_name: subagentName
    }
  });

  if (existing.length > 0) {
    return existing[0];
  }

  return await api.createEntry({
    entry_type: 'person',
    title: displayName,
    metadata: {
      person_type: 'artificial',
      agent_level: 'subagent',
      agent_id: AGENT_ID,
      instance_id: parentInstance.metadata.instance_id,
      subagent_name: subagentName,
      parent_person_id: parentInstanceId,
      execution_context: {
        parent_instance: parentInstance.metadata.instance_name,
        spawned_on_demand: true
      }
    }
  });
}

function formatSubagentName(name: string, parent: Entry, prefs: Preferences): string {
  if (prefs.subagent_naming === 'role_parent') {
    return `${capitalize(name)} (${parent.metadata.instance_name})`;
  }
  return capitalize(name);
}
```

---

## 4. Dynamic Entry Relationships

### 4.1 Relationship Type Taxonomy

#### Task Sequencing & Dependencies

| Relationship | Inverse | Transitive | Description |
|-------------|---------|------------|-------------|
| `depends_on` | `blocks` | Yes | Task cannot start until dependency completes |
| `soft_depends_on` | `soft_blocks` | Yes | Preferred order, not strictly blocking |
| `subtask_of` | `has_subtask` | No | Hierarchical task breakdown |
| `follows` | `precedes` | Yes | Temporal sequence (not blocking) |
| `supersedes` | `superseded_by` | No | New task replaces old one |
| `duplicate_of` | `has_duplicate` | No | Deduplication tracking |

#### Assignment & Delegation

| Relationship | Inverse | Description |
|-------------|---------|-------------|
| `assigned_to` | `assigned_tasks` | Task → Person/Agent assignment |
| `delegated_to` | `delegated_from` | Explicit delegation chain |
| `waiting_on` | `blocking_tasks_for` | Waiting for person's action |
| `created_by` | `created` | Authorship tracking |
| `completed_by` | `completions` | Who finished the task |
| `reviewed_by` | `reviews` | Review/approval tracking |
| `claimed_by` | `claimed_tasks` | Instance task claiming |
| `handed_off_to` | `received_from` | Cross-agent handoff |
| `spawned_for` | `spawned_tasks` | Subagent task creation |
| `verified_by` | `verifications` | Completion verification |

#### Project & Organization

| Relationship | Inverse | Description |
|-------------|---------|-------------|
| `belongs_to_project` | `project_tasks` | Task → Project membership |
| `milestone_of` | `has_milestones` | Key deliverable marking |
| `contributes_to` | `contributions` | Memory/note → Project link |
| `part_of` | `contains` | Project hierarchy (sub-projects) |
| `shared_with_domain` | `shared_items` | Cross-domain visibility |

#### Sprint & Time Management

| Relationship | Inverse | Description |
|-------------|---------|-------------|
| `scheduled_in` | `scheduled_tasks` | Task → Sprint assignment |
| `deferred_to` | `deferred_from` | Moved to future sprint |
| `carried_over_from` | `carried_to` | Incomplete task tracking |
| `time_blocked_for` | `time_blocks` | Calendar block → Task link |

#### Knowledge & Memory

| Relationship | Inverse | Description |
|-------------|---------|-------------|
| `derived_from` | `source_of` | Memory derivation (from V1) |
| `references` | `referenced_by` | Citation/link |
| `summarizes` | `summarized_by` | Summary relationship |
| `supports` | `supported_by` | Evidence chain |
| `contradicts` | `contradicted_by` | Conflict detection |
| `elaborates` | `elaborated_by` | Adds detail to existing entry |
| `context_for` | `has_context` | Background/context link |

#### Template & Reuse

| Relationship | Inverse | Description |
|-------------|---------|-------------|
| `cloned_from` | `clones` | Template instantiation |
| `template_for` | `instances` | Reusable patterns |

### 4.2 Relationship Type Registry

```elixir
%Entry{
  entry_type: "config",
  title: "Relationship Type Registry",
  metadata: %{
    "config_type" => "relationship_types",

    "types" => %{
      "depends_on" => %{
        "inverse" => "blocks",
        "applicable_to" => ["task"],
        "target_types" => ["task"],
        "transitive" => true,
        "description" => "Task cannot start until dependency completes",
        "system" => true
      },
      "assigned_to" => %{
        "inverse" => "assigned_tasks",
        "applicable_to" => ["task"],
        "target_types" => ["person"],
        "transitive" => false,
        "description" => "Task is assigned to a person or agent",
        "system" => true
      },
      "belongs_to_project" => %{
        "inverse" => "project_tasks",
        "applicable_to" => ["task", "memory", "decision", "note"],
        "target_types" => ["project"],
        "transitive" => false,
        "description" => "Entry belongs to a project",
        "system" => true
      },
      "scheduled_in" => %{
        "inverse" => "scheduled_tasks",
        "applicable_to" => ["task"],
        "target_types" => ["entry_group"],
        "transitive" => false,
        "description" => "Task is scheduled in a sprint",
        "system" => true
      }
      # Users can add custom types with system: false
    }
  }
}
```

### 4.3 Relationship Creation API

```javascript
// Create a dependency
POST /api/v1/relationships
{
  "source_entry_id": "task-1-uuid",
  "target_entry_id": "task-2-uuid",
  "relationship_type": "depends_on",
  "metadata": {
    "reason": "Need API design before implementation",
    "created_by_agent": "claude-code"
  }
}

// Assign task to specific agent instance
POST /api/v1/relationships
{
  "source_entry_id": "task-uuid",
  "target_entry_id": "claude-code-macbook-uuid",
  "relationship_type": "assigned_to",
  "metadata": {
    "assigned_by": "user",
    "priority": "high"
  }
}

// Link memory to project
POST /api/v1/relationships
{
  "source_entry_id": "memory-uuid",
  "target_entry_id": "project-uuid",
  "relationship_type": "contributes_to"
}
```

### 4.4 Relationship Queries

```javascript
// Get all relationships for an entry
GET /api/v1/entries/{id}/relationships

// Get relationships of specific type
GET /api/v1/entries/{id}/relationships?type=depends_on

// Get blocking chain (transitive closure)
GET /api/v1/entries/{id}/relationships/blocking-chain

// Get all assigned tasks for an agent (including child instances/subagents)
GET /api/v1/persons/{id}/assigned-tasks?include_children=true

// Get inverse relationships
GET /api/v1/entries/{id}/relationships?direction=inbound&type=assigned_to
```

---

## 5. GTD Integration

### 5.1 Tasks as Entries

Tasks are `entry_type: "task"` with GTD metadata:

```elixir
%Entry{
  entry_type: "task",
  title: "Refactor authentication module",
  content: "Extract OAuth logic into separate service",
  metadata: %{
    # GTD fields
    "bucket" => "next_actions",    # inbox, next_actions, waiting_for, someday_maybe
    "context" => "@computer",       # @phone, @computer, @home, @errands, @energy:high
    "status" => "open",             # open, in_progress, completed, cancelled

    # Scheduling
    "due_date" => "2026-02-05",
    "effort_estimate" => "m",       # xs, s, m, l, xl

    # Assignment (via relationships preferred, but quick assignment supported)
    "quick_assigned_to" => "claude-code-macbook-uuid",

    # Source tracking
    "source_agent" => "claude-code",
    "source_context" => %{
      "conversation_id" => "conv-uuid",
      "working_directory" => "/Users/user/projects/onelist.com"
    }
  }
}
```

### 5.2 GTD Buckets

| Bucket | Description | Agent Behavior |
|--------|-------------|----------------|
| `inbox` | Unclarified items | Agents can add here; needs processing |
| `next_actions` | Ready to work | Agents can claim and work on |
| `waiting_for` | Blocked on external | Agents create when blocked |
| `someday_maybe` | Future consideration | Low priority, not actionable |

### 5.3 GTD Contexts

| Context | Description | Agent Relevance |
|---------|-------------|-----------------|
| `@computer` | Requires computer | Natural for Claude Code |
| `@phone` | Requires phone calls | Usually human-only |
| `@home` | Location-specific | Usually human-only |
| `@errands` | Out and about | Usually human-only |
| `@energy:high` | Requires focus | Complex analysis tasks |
| `@energy:low` | Can do when tired | Simple tasks |
| `@agent:{id}` | Specific agent | Direct agent targeting |

### 5.4 Agent Task Operations

```typescript
// Create a task
async function createTask(title: string, options: TaskOptions = {}): Promise<Entry> {
  const projectId = state.currentProjectId;

  const task = await api.createEntry({
    entry_type: 'task',
    title: title,
    content: options.description || '',
    metadata: {
      bucket: options.bucket || 'inbox',
      context: options.context || '@computer',
      status: 'open',
      due_date: options.dueDate,
      effort_estimate: options.effort,
      source_agent: AGENT_ID,
      source_context: {
        conversation_id: state.conversationId,
        working_directory: process.cwd()
      }
    }
  });

  // Link to project if bound
  if (projectId) {
    await api.createRelationship({
      source_entry_id: task.id,
      target_entry_id: projectId,
      relationship_type: 'belongs_to_project'
    });
  }

  return task;
}

// Complete a task
async function completeTask(taskId: string, evidence?: Evidence): Promise<Entry> {
  const verificationMode = await getVerificationMode(taskId);

  const update = {
    metadata: {
      status: 'completed',
      completed_at: new Date().toISOString(),
      completed_by_agent: AGENT_ID,
      completed_by_instance: state.instancePersonId
    }
  };

  if (evidence) {
    update.metadata.completion_evidence = evidence;
  }

  const task = await api.updateEntry(taskId, update);

  // Create completion relationship
  await api.createRelationship({
    source_entry_id: taskId,
    target_entry_id: state.instancePersonId,
    relationship_type: 'completed_by',
    metadata: { evidence }
  });

  // Handle verification if needed
  if (verificationMode === 'manual') {
    await notifyForVerification(taskId);
  }

  return task;
}

// Create blocking dependency
async function markBlockedBy(taskId: string, blockerId: string, reason: string): Promise<void> {
  await api.createRelationship({
    source_entry_id: taskId,
    target_entry_id: blockerId,
    relationship_type: 'depends_on',
    metadata: { reason, created_by_agent: AGENT_ID }
  });

  // Move to waiting_for bucket
  await api.updateEntry(taskId, {
    metadata: { bucket: 'waiting_for' }
  });
}

// Claim a task assigned to agent type
async function claimTask(taskId: string): Promise<boolean> {
  const task = await api.getEntry(taskId);
  const assignments = await api.getRelationships(taskId, { type: 'assigned_to' });

  // Check if assigned to our type or no assignment
  const canClaim = assignments.length === 0 ||
    assignments.some(a => isOurAgentType(a.target_entry_id));

  if (!canClaim) {
    return false;
  }

  // Optimistic claim with coordination lock
  const claimed = await coordination.tryClaimTask(taskId, state.instancePersonId);

  if (claimed) {
    // Update assignment to specific instance
    await api.createRelationship({
      source_entry_id: taskId,
      target_entry_id: state.instancePersonId,
      relationship_type: 'claimed_by',
      metadata: { claimed_at: new Date().toISOString() }
    });

    await api.updateEntry(taskId, {
      metadata: { status: 'in_progress' }
    });
  }

  return claimed;
}
```

---

## 6. Project Discovery & Binding

### 6.1 Session Start Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│  SESSION START PROMPT                                                    │
│                                                                         │
│  "What are you working on today?"                                       │
│                                                                         │
│  SUGGESTED (based on working directory / recent activity):              │
│  ● Auth System Refactor (Personal > Onelist)         [Select]          │
│                                                                         │
│  YOUR ACTIVE PROJECTS:                                                  │
│  ○ Website Redesign (Business: Acme)                 [Select]          │
│  ○ API Documentation (Personal > Onelist)            [Select]          │
│  ○ Tax Planning (Personal > Finance)                 [Select]          │
│                                                                         │
│  OTHER OPTIONS:                                                         │
│  ○ Browse projects in other domains...               [Expand]          │
│  ○ Start a new project                               [Create]          │
│  ○ No project (general work)                         [Skip]            │
│                                                                         │
│  ☐ Don't show this prompt again for this directory                     │
│  ☐ Never prompt me (I'll say "project: X" when needed)                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Project Discovery Logic

```typescript
interface ProjectSuggestion {
  project: Entry;
  score: number;
  reason: 'directory_binding' | 'git_remote' | 'name_match' | 'recent_usage';
}

async function discoverProject(context: SessionContext): Promise<Project | null> {
  const prefs = await getProjectPreferences();

  // Check prompt preferences
  if (prefs.projectPromptBehavior === 'never') {
    return null;  // User will specify manually
  }

  const suggestions = await gatherProjectSuggestions(context);

  // Strong match with auto-bind setting
  if (suggestions.strongMatch && prefs.projectPromptBehavior === 'suggest') {
    const binding = prefs.directoryProjectBindings[context.workingDirectory];
    if (binding?.skipPrompt) {
      return suggestions.strongMatch;
    }
  }

  // Show prompt
  return await promptProjectSelection({
    suggested: suggestions.strongMatch,
    projects: suggestions.ranked,
    showOtherDomains: prefs.showOtherDomains,
    allowCreate: true
  });
}

async function gatherProjectSuggestions(context: SessionContext): Promise<Suggestions> {
  const [
    directoryBinding,
    gitRemoteMatch,
    nameMatches,
    recentProjects
  ] = await Promise.all([
    checkDirectoryBinding(context.workingDirectory),
    matchProjectByGitRemote(context.gitRemote),
    searchProjectsByName(path.basename(context.workingDirectory)),
    getRecentProjectsForDirectory(context.workingDirectory)
  ]);

  const suggestions: ProjectSuggestion[] = [
    directoryBinding && { project: directoryBinding, score: 1.0, reason: 'directory_binding' },
    gitRemoteMatch && { project: gitRemoteMatch, score: 0.9, reason: 'git_remote' },
    ...nameMatches.map(p => ({ project: p, score: 0.7, reason: 'name_match' })),
    ...recentProjects.map(p => ({ project: p, score: 0.5, reason: 'recent_usage' }))
  ].filter(Boolean);

  const ranked = suggestions.sort((a, b) => b.score - a.score);
  const strongMatch = ranked[0]?.score >= 0.85 ? ranked[0].project : null;

  return { ranked, strongMatch };
}
```

### 6.3 Project Binding Preferences

```elixir
%Entry{
  entry_type: "config",
  metadata: %{
    "config_type" => "project_binding_preferences",
    "agent_id" => "claude-code",

    # Domain visibility
    "showOtherDomains" => "ask",  # ask, always, never

    # Prompt behavior
    "projectPromptBehavior" => "suggest",  # always, suggest, never

    # Directory bindings (remembered choices)
    "directoryProjectBindings" => %{
      "/Users/user/projects/onelist.com" => %{
        "projectId" => "project-uuid",
        "skipPrompt" => true
      },
      "/Users/user/projects/client-work" => %{
        "projectId" => "client-project-uuid",
        "skipPrompt" => false  # Still prompt but pre-select
      }
    }
  }
}
```

### 6.4 Creating New Projects

```typescript
async function createProject(name: string, options: ProjectOptions = {}): Promise<Entry> {
  const project = await api.createEntry({
    entry_type: 'project',  # Or 'task' with project metadata
    title: name,
    content: options.description || '',
    metadata: {
      status: 'active',
      domain: options.domain || 'personal',
      scope: options.scope,
      created_by_agent: AGENT_ID,
      git_remote: options.gitRemote || await getGitRemote()
    }
  });

  // Bind current directory
  if (options.bindDirectory !== false) {
    await saveDirectoryBinding(process.cwd(), project.id);
  }

  return project;
}
```

---

## 7. Sprint Support via Entry Groups

### 7.1 Sprint as Entry Group

```elixir
%Entry{
  entry_type: "entry_group",
  title: "Sprint 2026-W05",
  content: "Focus: Auth refactor and Reader MVP",
  metadata: %{
    "group_type" => "sprint",
    "sprint_number" => 5,
    "start_date" => "2026-01-27",
    "end_date" => "2026-02-09",
    "status" => "active",  # planned, active, completed, cancelled

    # Goals
    "goals" => [
      "Complete auth refactor",
      "Ship reader agent MVP",
      "Fix critical bugs from backlog"
    ],

    # Velocity tracking
    "velocity_target" => 21,
    "velocity_completed" => 13,

    # Cross-project sprint (optional)
    "project_ids" => ["project-1-uuid", "project-2-uuid"]
  }
}
```

### 7.2 Task-Sprint Relationship

```javascript
// Schedule task in sprint
POST /api/v1/relationships
{
  "source_entry_id": "task-uuid",
  "target_entry_id": "sprint-uuid",
  "relationship_type": "scheduled_in",
  "metadata": {
    "story_points": 3,
    "scheduled_by": "user"
  }
}

// Defer task to next sprint
POST /api/v1/relationships
{
  "source_entry_id": "task-uuid",
  "target_entry_id": "next-sprint-uuid",
  "relationship_type": "deferred_to",
  "metadata": {
    "from_sprint_id": "current-sprint-uuid",
    "reason": "Blocked by external dependency"
  }
}
```

### 7.3 Sprint Queries

```javascript
// Get current sprint with tasks
GET /api/v1/sprints/current

// Get sprint burndown
GET /api/v1/sprints/{id}/burndown

// Get tasks carried over from previous sprint
GET /api/v1/sprints/{id}/carried-over

// Get sprint velocity history
GET /api/v1/sprints/velocity?count=10
```

---

## 8. Progressive GTD Adoption

### 8.1 Feature Levels

| Level | Features | Default For |
|-------|----------|-------------|
| **Minimal** | Basic task creation, no buckets/contexts | New users |
| **Standard** | Buckets, basic contexts, project binding | Opted-in users |
| **Full** | All buckets, contexts, reviews, sprints, proactive prompts | Power users |

### 8.2 Preferences Storage

```elixir
%Entry{
  entry_type: "config",
  metadata: %{
    "config_type" => "agent_gtd_preferences",
    "agent_id" => "claude-code",

    # Feature adoption level
    "gtd_level" => "standard",

    # Individual prompt preferences
    "prompts" => %{
      "project_selection" => "suggest",      # always, suggest, never
      "task_clarification" => true,          # "What's the next action?"
      "bucket_suggestions" => true,          # Suggest appropriate bucket
      "context_suggestions" => false,        # Suggest @contexts
      "review_reminders" => false,           # Weekly review prompts
      "sprint_planning" => false             # Sprint assignment prompts
    },

    # Dismissed prompts (don't show again)
    "dismissed_prompts" => [
      "weekly_review_intro",
      "context_explanation",
      "gtd_upgrade_offer"
    ],

    # Feature-specific settings
    "auto_assign_context" => true,           # Auto-add @computer to coding tasks
    "default_bucket" => "inbox",             # Where new tasks go
    "show_effort_prompts" => false           # Ask for effort estimates
  }
}
```

### 8.3 Progressive Prompting Pattern

```typescript
async function maybePrompt<T>(
  promptType: string,
  content: () => Promise<PromptContent>
): Promise<T | null> {
  const prefs = await getGTDPreferences();

  // Check if dismissed
  if (prefs.dismissedPrompts.includes(promptType)) {
    return null;
  }

  // Check if feature level allows
  if (!featureLevelAllows(prefs.gtdLevel, promptType)) {
    return null;
  }

  // Check specific prompt setting
  const promptSetting = prefs.prompts[promptType];
  if (promptSetting === false || promptSetting === 'never') {
    return null;
  }

  // Show prompt with dismiss option
  const promptContent = await content();
  const response = await showPromptWithDismissOption(promptType, promptContent);

  if (response.dismissed) {
    await dismissPrompt(promptType);
    return null;
  }

  if (response.neverShowAgain) {
    await updatePromptPreference(promptType, 'never');
  }

  return response.value;
}

// Example usage
async function maybePromptForContext(task: Task): Promise<string | null> {
  return maybePrompt('context_suggestions', async () => ({
    title: 'Add Context?',
    message: `Would you like to add a context to "${task.title}"?`,
    options: [
      { label: '@computer', value: '@computer' },
      { label: '@phone', value: '@phone' },
      { label: '@energy:high', value: '@energy:high' },
      { label: 'Skip', value: null }
    ],
    dismissOption: "Don't suggest contexts"
  }));
}
```

### 8.4 GTD Level Upgrade Flow

```typescript
// Offer upgrade when user shows interest
async function maybeOfferGTDUpgrade(trigger: string): Promise<void> {
  const prefs = await getGTDPreferences();

  if (prefs.gtdLevel === 'full') return;
  if (prefs.dismissedPrompts.includes('gtd_upgrade_offer')) return;

  const nextLevel = prefs.gtdLevel === 'minimal' ? 'standard' : 'full';
  const features = getNewFeaturesForLevel(nextLevel);

  const response = await showPrompt({
    title: `Unlock ${nextLevel} GTD Features?`,
    message: `Based on your usage, you might benefit from:\n${features.join('\n')}`,
    options: [
      { label: 'Enable', value: 'enable' },
      { label: 'Not now', value: 'later' },
      { label: "Don't ask again", value: 'dismiss' }
    ]
  });

  if (response === 'enable') {
    await updateGTDLevel(nextLevel);
  } else if (response === 'dismiss') {
    await dismissPrompt('gtd_upgrade_offer');
  }
}
```

---

## 9. Completion Verification

### 9.1 Verification Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `manual` | Agent marks complete, user must confirm | Critical projects |
| `auto_simple` | Agent marks complete, auto-confirmed | Personal/low-stakes |
| `auto_with_evidence` | Agent provides evidence, auto-confirmed if valid | Default |

### 9.2 Hierarchical Settings

```elixir
# Global user setting
%Entry{
  entry_type: "config",
  metadata: %{
    "config_type" => "completion_verification",
    "scope" => "global",

    "default_mode" => "auto_with_evidence",

    # Override by task characteristics
    "require_confirmation_for" => [
      "high_priority",
      "has_dependencies",
      "external_deliverable"
    ],

    # Auto-confirm for low-stakes
    "auto_confirm_contexts" => ["@energy:low"],
    "auto_confirm_efforts" => ["xs", "s"]
  }
}

# Project-specific override
%Entry{
  entry_type: "config",
  metadata: %{
    "config_type" => "completion_verification",
    "scope" => "project",
    "project_id" => "client-project-uuid",

    "mode" => "manual",
    "reason" => "Critical client project - all completions need review"
  }
}
```

### 9.3 Evidence Structure

```typescript
interface CompletionEvidence {
  type: 'code_change' | 'test_results' | 'documentation' | 'manual' | 'other';

  // For code changes
  files_modified?: string[];
  lines_added?: number;
  lines_removed?: number;
  commit_sha?: string;

  // For test results
  tests_passed?: boolean;
  test_count?: number;
  coverage_delta?: number;

  // For any type
  summary?: string;
  artifacts?: string[];  // Links to relevant entries/files
  confidence?: number;   // 0.0-1.0
}

// Example completion with evidence
await api.completeTask(taskId, {
  evidence: {
    type: 'code_change',
    files_modified: ['src/auth/oauth.ts', 'tests/auth/oauth.test.ts'],
    lines_added: 145,
    lines_removed: 89,
    commit_sha: 'abc123def',
    tests_passed: true,
    test_count: 12,
    summary: 'Extracted OAuth logic into separate service with full test coverage',
    confidence: 0.95
  }
});
```

### 9.4 Verification Resolution

```typescript
async function getVerificationMode(taskId: string): Promise<VerificationMode> {
  const task = await api.getEntry(taskId);

  // Check project override first
  const projectRelation = await api.getRelationships(taskId, { type: 'belongs_to_project' });
  if (projectRelation.length > 0) {
    const projectConfig = await getVerificationConfig('project', projectRelation[0].target_entry_id);
    if (projectConfig) {
      return projectConfig.mode;
    }
  }

  // Check global settings
  const globalConfig = await getVerificationConfig('global');

  // Check if task matches override conditions
  if (globalConfig.require_confirmation_for.includes('high_priority') &&
      task.metadata.priority === 'high') {
    return 'manual';
  }

  if (globalConfig.auto_confirm_contexts.includes(task.metadata.context)) {
    return 'auto_simple';
  }

  if (globalConfig.auto_confirm_efforts.includes(task.metadata.effort_estimate)) {
    return 'auto_simple';
  }

  return globalConfig.default_mode;
}
```

---

## 10. Extension Implementation

### 10.1 New Shared Package

**Location**: `extensions/shared/`

```
extensions/shared/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts                    # Main exports
│   ├── coordination.ts             # File-based coordination (from V1)
│   ├── api-client.ts               # Common API wrapper with headers
│   ├── instance-registry.ts        # Person entry management
│   ├── task-assignment.ts          # Task claiming logic
│   ├── gtd.ts                      # GTD utilities
│   ├── relationships.ts            # Entry relationship helpers
│   ├── project-discovery.ts        # Project binding logic
│   ├── preferences.ts              # GTD preferences management
│   └── types.ts                    # Shared TypeScript types
└── tests/
    ├── coordination.test.ts
    ├── instance-registry.test.ts
    ├── task-assignment.test.ts
    └── gtd.test.ts
```

**package.json**:

```json
{
  "name": "@onelist/agent-shared",
  "version": "1.0.0",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "test": "vitest"
  },
  "dependencies": {
    "proper-lockfile": "^4.1.2"
  },
  "devDependencies": {
    "typescript": "^5.3.0",
    "vitest": "^1.2.0"
  }
}
```

### 10.2 Claude Code Extension Updates

**Updated file structure**:

```
extensions/claude-code/
├── package.json                    # UPDATED: Add shared dependency
├── hooks.json                      # UPDATED: New hooks
├── scripts/
│   └── lib/
│       ├── api.js                  # UPDATED: Uses shared/api-client
│       ├── config.js               # UPDATED: Instance config
│       ├── buffer.js               # Existing
│       ├── gtd.js                  # NEW: GTD operations
│       ├── project.js              # NEW: Project binding
│       ├── instance.js             # NEW: Instance management
│       ├── relationships.js        # NEW: Relationship creation
│       └── preferences.js          # NEW: GTD preferences
├── commands/
│   ├── project.js                  # NEW: /project command
│   ├── task.js                     # NEW: /task command
│   └── sprint.js                   # NEW: /sprint command
├── skills/
│   └── gtd.js                      # NEW: GTD natural language skill
└── tests/
    ├── api.test.js                 # Existing
    ├── buffer.test.js              # Existing
    ├── config.test.js              # Existing
    ├── gtd.test.js                 # NEW
    ├── project.test.js             # NEW
    └── instance.test.js            # NEW
```

**Updated hooks.json**:

```json
{
  "hooks": [
    {
      "event": "session_start",
      "script": "./scripts/session-start.js"
    },
    {
      "event": "post_tool_use",
      "script": "./scripts/post-tool-use.js"
    },
    {
      "event": "stop",
      "script": "./scripts/session-end.js"
    }
  ],
  "commands": [
    {
      "name": "project",
      "description": "Manage project binding",
      "script": "./commands/project.js"
    },
    {
      "name": "task",
      "description": "Create or manage tasks",
      "script": "./commands/task.js"
    },
    {
      "name": "sprint",
      "description": "View or manage current sprint",
      "script": "./commands/sprint.js"
    }
  ]
}
```

**New session-start.js**:

```javascript
const { registerInstance } = require('./lib/instance');
const { discoverProject, promptProjectSelection } = require('./lib/project');
const { getGTDPreferences } = require('./lib/preferences');

module.exports = async function sessionStart(context) {
  const { api, state } = context;

  // 1. Register/update instance person entry
  const instance = await registerInstance(api);
  state.instancePersonId = instance.id;
  state.instanceName = instance.metadata.instance_name;

  // 2. Discover and bind project
  const prefs = await getGTDPreferences(api);

  if (prefs.projectPromptBehavior !== 'never') {
    const project = await discoverProject(api, {
      workingDirectory: process.cwd(),
      gitRemote: await getGitRemote(),
      preferences: prefs
    });

    if (project) {
      state.currentProjectId = project.id;
      state.currentProjectName = project.title;
      console.log(`📁 Bound to project: ${project.title}`);
    }
  }

  // 3. Check for assigned tasks
  const assignedTasks = await getAssignedTasks(api, state.instancePersonId);
  if (assignedTasks.length > 0) {
    console.log(`📋 You have ${assignedTasks.length} assigned task(s)`);
  }

  return state;
};
```

### 10.3 OpenClaw Extension Updates

**Updated file structure**:

```
extensions/onelist-memory/
├── package.json                    # UPDATED: Add shared dependency
├── openclaw.plugin.json            # Existing
├── src/
│   ├── index.ts                    # UPDATED: Instance registration
│   ├── gtd.ts                      # NEW: GTD integration
│   ├── project.ts                  # NEW: Project binding
│   ├── subagents.ts                # NEW: Subagent registry
│   └── relationships.ts            # NEW: Relationship creation
├── vitest.config.ts                # Existing
└── tests/
    ├── index.test.ts               # Existing
    ├── gtd.test.ts                 # NEW
    └── subagents.test.ts           # NEW
```

**New subagents.ts**:

```typescript
import { OnelistAPI } from '@onelist/agent-shared';

export async function registerSubagent(
  api: OnelistAPI,
  parentInstanceId: string,
  subagentName: string
): Promise<Entry | null> {
  const prefs = await api.getConfig('agent_person_granularity');

  if (prefs?.granularity !== 'full') {
    return null;
  }

  const existing = await api.search({
    entry_type: 'person',
    metadata: {
      agent_level: 'subagent',
      parent_person_id: parentInstanceId,
      subagent_name: subagentName
    }
  });

  if (existing.data.length > 0) {
    return existing.data[0];
  }

  const parent = await api.getEntry(parentInstanceId);
  const displayName = formatSubagentName(subagentName, parent, prefs);

  return await api.createEntry({
    entry_type: 'person',
    title: displayName,
    metadata: {
      person_type: 'artificial',
      agent_level: 'subagent',
      agent_id: 'openclaw',
      instance_id: parent.metadata.instance_id,
      subagent_name: subagentName,
      parent_person_id: parentInstanceId,
      execution_context: {
        parent_instance: parent.metadata.instance_name,
        spawned_on_demand: true
      }
    }
  });
}

export async function trackSubagentTask(
  api: OnelistAPI,
  subagentPersonId: string,
  taskId: string
): Promise<void> {
  await api.createRelationship({
    source_entry_id: taskId,
    target_entry_id: subagentPersonId,
    relationship_type: 'spawned_for',
    metadata: {
      spawned_at: new Date().toISOString()
    }
  });
}
```

---

## 11. API Additions

### 11.1 Relationship Endpoints

```
POST   /api/v1/relationships                    # Create relationship
GET    /api/v1/relationships/:id                # Get relationship
DELETE /api/v1/relationships/:id                # Delete relationship
PATCH  /api/v1/relationships/:id                # Update relationship metadata

GET    /api/v1/entries/:id/relationships        # List relationships for entry
GET    /api/v1/entries/:id/relationships/blocking-chain  # Transitive dependencies
```

### 11.2 Person/Agent Endpoints

```
GET    /api/v1/persons                          # List all persons
GET    /api/v1/persons/:id                      # Get person details
GET    /api/v1/persons/:id/children             # Get instances/subagents
GET    /api/v1/persons/:id/assigned-tasks       # Get assigned tasks
POST   /api/v1/persons/:id/heartbeat            # Update last_seen

POST   /api/v1/agents/register                  # Register agent instance
POST   /api/v1/agents/:id/claim-task/:task_id   # Claim task for instance
```

### 11.3 Sprint Endpoints

```
GET    /api/v1/sprints                          # List sprints
GET    /api/v1/sprints/current                  # Get current sprint
GET    /api/v1/sprints/:id                      # Get sprint details
GET    /api/v1/sprints/:id/tasks                # Get sprint tasks
GET    /api/v1/sprints/:id/burndown             # Get burndown data
GET    /api/v1/sprints/velocity                 # Get velocity history

POST   /api/v1/sprints                          # Create sprint
POST   /api/v1/sprints/:id/schedule-task        # Add task to sprint
POST   /api/v1/sprints/:id/defer-task           # Defer task to next sprint
```

### 11.4 GTD Endpoints

```
GET    /api/v1/gtd/inbox                        # Get inbox items
GET    /api/v1/gtd/next-actions                 # Get next actions (filterable by context)
GET    /api/v1/gtd/waiting-for                  # Get waiting-for items
GET    /api/v1/gtd/someday-maybe                # Get someday/maybe items

POST   /api/v1/tasks/:id/complete               # Complete with optional evidence
POST   /api/v1/tasks/:id/move-bucket            # Change GTD bucket
POST   /api/v1/tasks/:id/set-context            # Set GTD context
```

---

## 12. Database Schema

### 12.1 Entry Relationships Table

```sql
CREATE TABLE entry_relationships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_entry_id UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  target_entry_id UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  relationship_type VARCHAR(64) NOT NULL,

  -- Relationship metadata
  metadata JSONB DEFAULT '{}',

  -- For assignment relationships
  assigned_at TIMESTAMPTZ,
  assigned_by_person_id UUID REFERENCES entries(id),

  -- For completion/verification
  completed_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  verified_by_person_id UUID REFERENCES entries(id),

  -- Audit
  created_by_agent_id VARCHAR(64),
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Prevent duplicate relationships
  UNIQUE(source_entry_id, target_entry_id, relationship_type)
);

CREATE INDEX idx_entry_relationships_source ON entry_relationships(source_entry_id);
CREATE INDEX idx_entry_relationships_target ON entry_relationships(target_entry_id);
CREATE INDEX idx_entry_relationships_type ON entry_relationships(relationship_type);
CREATE INDEX idx_entry_relationships_source_type ON entry_relationships(source_entry_id, relationship_type);
```

### 12.2 Migration for V1 Fields (if not already present)

```sql
-- Ensure entries table has agent attribution (from V1)
ALTER TABLE entries ADD COLUMN IF NOT EXISTS agent_id VARCHAR(64);
ALTER TABLE entries ADD COLUMN IF NOT EXISTS agent_version VARCHAR(32);
ALTER TABLE entries ADD COLUMN IF NOT EXISTS agent_instance_id VARCHAR(64);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_entries_agent_id ON entries(agent_id);
CREATE INDEX IF NOT EXISTS idx_entries_entry_type_metadata ON entries(entry_type)
  WHERE entry_type IN ('task', 'project', 'person', 'config', 'entry_group');
```

---

## 13. Implementation Phases

### Phase 2.1: Foundation (Week 1)

| Task | Effort | Priority |
|------|--------|----------|
| Create `extensions/shared/` package | 2 days | HIGH |
| Implement coordination.ts (port from onelist-memory) | 1 day | HIGH |
| Implement api-client.ts with agent headers | 1 day | HIGH |
| Update claude-code to use shared package | 1 day | HIGH |
| Update onelist-memory to use shared package | 1 day | HIGH |

### Phase 2.2: Person Entries (Week 2)

| Task | Effort | Priority |
|------|--------|----------|
| Add entry_relationships table migration | 0.5 day | HIGH |
| Implement instance-registry.ts | 1 day | HIGH |
| Add person entry creation for agents | 1 day | HIGH |
| Implement granularity preferences | 1 day | MEDIUM |
| Add subagent registration (OpenClaw) | 1 day | HIGH |
| Instance heartbeat and status | 0.5 day | MEDIUM |

### Phase 2.3: Relationships (Week 3)

| Task | Effort | Priority |
|------|--------|----------|
| Implement relationship API endpoints | 2 days | HIGH |
| Implement relationship type registry | 1 day | MEDIUM |
| Add transitive closure queries | 1 day | HIGH |
| Implement relationships.ts in shared | 1 day | HIGH |

### Phase 2.4: GTD Integration (Week 4)

| Task | Effort | Priority |
|------|--------|----------|
| Implement gtd.ts in shared | 1 day | HIGH |
| Add task creation/completion with evidence | 1 day | HIGH |
| Implement bucket/context management | 1 day | MEDIUM |
| Add /task and /project commands | 1 day | HIGH |
| Implement GTD preferences | 1 day | MEDIUM |

### Phase 2.5: Project Discovery (Week 5)

| Task | Effort | Priority |
|------|--------|----------|
| Implement project-discovery.ts | 1 day | HIGH |
| Add project binding preferences | 0.5 day | MEDIUM |
| Session start project prompt | 1 day | HIGH |
| Directory binding persistence | 0.5 day | MEDIUM |
| Git remote matching | 0.5 day | LOW |

### Phase 2.6: Sprints (Week 6)

| Task | Effort | Priority |
|------|--------|----------|
| Sprint entry group support | 1 day | MEDIUM |
| Sprint API endpoints | 1 day | MEDIUM |
| Task-sprint relationships | 0.5 day | MEDIUM |
| /sprint command | 0.5 day | LOW |
| Burndown/velocity queries | 1 day | LOW |

### Phase 2.7: Progressive Adoption & Polish (Week 7)

| Task | Effort | Priority |
|------|--------|----------|
| Implement preferences.ts | 1 day | MEDIUM |
| Progressive prompting pattern | 1 day | MEDIUM |
| Completion verification hierarchy | 1 day | MEDIUM |
| GTD level upgrade flow | 0.5 day | LOW |
| Documentation and README updates | 1 day | HIGH |

---

## 14. Testing Plan

### 14.1 Unit Tests

**Shared Package Tests**:

```typescript
// tests/instance-registry.test.ts
describe('Instance Registry', () => {
  it('should create agent type person on first registration');
  it('should create instance person under type');
  it('should update last_seen on re-registration');
  it('should respect granularity preferences');
  it('should format instance names correctly');
});

// tests/task-assignment.test.ts
describe('Task Assignment', () => {
  it('should claim task assigned to agent type');
  it('should not claim task assigned to different instance');
  it('should use coordination lock for claiming');
  it('should handle concurrent claim attempts');
});

// tests/relationships.test.ts
describe('Relationships', () => {
  it('should create depends_on relationship');
  it('should compute transitive blocking chain');
  it('should create assigned_to relationship');
  it('should query inverse relationships');
});
```

### 14.2 Integration Tests

```bash
# Test multi-instance coordination
1. Start Claude Code instance A (MacBook)
2. Start Claude Code instance B (Work Laptop)
3. Create task assigned to "Claude Code" (type level)
4. Verify only one instance claims it
5. Create task assigned to "Claude Code - MacBook"
6. Verify only instance A can work on it

# Test GTD flow
1. Create task in inbox via agent
2. Process task to next_actions with context
3. Claim and complete task with evidence
4. Verify completion creates relationships

# Test project binding
1. Start session in project directory
2. Verify project discovery prompt appears
3. Select/create project
4. Create task, verify project relationship
5. Restart session, verify binding persists
```

### 14.3 Test Commands

```bash
# Shared package
cd extensions/shared && npm test

# Claude Code
cd extensions/claude-code && npm test

# OpenClaw
cd extensions/onelist-memory && npm test

# Integration tests (requires running Onelist)
cd extensions && npm run test:integration
```

---

## Appendix A: Relationship Type Quick Reference

| Type | Inverse | Category | Description |
|------|---------|----------|-------------|
| `depends_on` | `blocks` | Task | Cannot start until dependency completes |
| `soft_depends_on` | `soft_blocks` | Task | Preferred order, not strict |
| `subtask_of` | `has_subtask` | Task | Hierarchical breakdown |
| `follows` | `precedes` | Task | Temporal sequence |
| `supersedes` | `superseded_by` | Task | Replaces old task |
| `duplicate_of` | `has_duplicate` | Task | Deduplication |
| `assigned_to` | `assigned_tasks` | Assignment | Task → Person |
| `delegated_to` | `delegated_from` | Assignment | Delegation chain |
| `waiting_on` | `blocking_tasks_for` | Assignment | Waiting for person |
| `created_by` | `created` | Assignment | Authorship |
| `completed_by` | `completions` | Assignment | Who finished |
| `reviewed_by` | `reviews` | Assignment | Review tracking |
| `claimed_by` | `claimed_tasks` | Agent | Instance claiming |
| `handed_off_to` | `received_from` | Agent | Cross-agent handoff |
| `spawned_for` | `spawned_tasks` | Agent | Subagent task |
| `verified_by` | `verifications` | Agent | Completion verify |
| `belongs_to_project` | `project_tasks` | Project | Task → Project |
| `milestone_of` | `has_milestones` | Project | Key deliverable |
| `contributes_to` | `contributions` | Project | Entry → Project |
| `part_of` | `contains` | Project | Hierarchy |
| `shared_with_domain` | `shared_items` | Project | Cross-domain |
| `scheduled_in` | `scheduled_tasks` | Sprint | Task → Sprint |
| `deferred_to` | `deferred_from` | Sprint | Future sprint |
| `carried_over_from` | `carried_to` | Sprint | Incomplete tracking |
| `time_blocked_for` | `time_blocks` | Sprint | Calendar → Task |
| `derived_from` | `source_of` | Knowledge | Derivation (V1) |
| `references` | `referenced_by` | Knowledge | Citation |
| `summarizes` | `summarized_by` | Knowledge | Summary |
| `supports` | `supported_by` | Knowledge | Evidence |
| `contradicts` | `contradicted_by` | Knowledge | Conflict |
| `elaborates` | `elaborated_by` | Knowledge | Adds detail |
| `context_for` | `has_context` | Knowledge | Background |
| `cloned_from` | `clones` | Template | Instantiation |
| `template_for` | `instances` | Template | Reusable pattern |

---

## Appendix B: Migration from V1

If V1 is already deployed, V2 adds:

1. **New table**: `entry_relationships` (no migration of existing data needed)
2. **New entry types used**: `person` entries for agents (created on first use)
3. **New config entries**: Preferences stored as `entry_type: "config"`
4. **Backward compatible**: All V1 functionality continues to work

Existing agents continue working without changes. V2 features activate when:
- Agent updates to new extension version
- User enables GTD features via preferences
- First relationship is created

---

## Appendix C: V1 → V2 Feature Matrix

| Feature | V1 | V2 |
|---------|----|----|
| Agent headers on requests | ✓ | ✓ |
| Source attribution | ✓ | ✓ |
| Derivation tracking | ✓ | ✓ |
| Coordination layer | ✓ | ✓ (enhanced) |
| Circuit breaker | ✓ | ✓ |
| Local cache fallback | ✓ | ✓ |
| Scoped API keys | ✓ | ✓ |
| Audit logging | ✓ | ✓ |
| **Agents as person entries** | - | ✓ |
| **Instance/subagent hierarchy** | - | ✓ |
| **Dynamic relationships** | - | ✓ |
| **GTD task management** | - | ✓ |
| **Project discovery/binding** | - | ✓ |
| **Sprint support** | - | ✓ |
| **Progressive adoption** | - | ✓ |
| **Completion verification** | - | ✓ |
