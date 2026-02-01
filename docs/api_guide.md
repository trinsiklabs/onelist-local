# Onelist REST API Guide

This guide documents the Onelist REST API (v1), which provides programmatic access to entries, tags, representations, and version history.

## Authentication

All API requests require authentication via API key. Include your API key in the `Authorization` header:

```
Authorization: Bearer ol_your_api_key_here
```

API keys can be created and managed in the Onelist web interface at `/app/api-keys`.

### Error Responses

| Status Code | Description |
|-------------|-------------|
| 401 | Missing or invalid API key |
| 401 | API key has been revoked |
| 401 | API key has expired |

## Base URL

All API endpoints are prefixed with `/api/v1`.

## Pagination

List endpoints support pagination via query parameters:

| Parameter | Description | Default | Max |
|-----------|-------------|---------|-----|
| `page` | Page number | 1 | - |
| `per_page` | Items per page | 20 | 100 |

Responses include a `meta` object with pagination info:

```json
{
  "data": [...],
  "meta": {
    "total": 100,
    "page": 1,
    "per_page": 20,
    "total_pages": 5
  }
}
```

## Entries

Entries are the core content units in Onelist.

### List Entries

```
GET /api/v1/entries
```

**Query Parameters:**

| Parameter | Description |
|-----------|-------------|
| `entry_type` | Filter by type: `note`, `memory`, `photo`, `video` |
| `source_type` | Filter by source: `manual`, `web_clip`, `api` |
| `public` | Filter by public status: `true`, `false` |
| `page` | Page number |
| `per_page` | Items per page |

**Response:**

```json
{
  "data": [
    {
      "id": "uuid",
      "public_id": "abc123",
      "title": "My Note",
      "entry_type": "note",
      "source_type": "api",
      "public": false,
      "version": 1,
      "content_created_at": "2025-01-28T12:00:00Z",
      "metadata": {},
      "inserted_at": "2025-01-28T12:00:00Z",
      "updated_at": "2025-01-28T12:00:00Z"
    }
  ],
  "meta": {...}
}
```

### Create Entry

```
POST /api/v1/entries
```

**Request Body:**

```json
{
  "entry": {
    "title": "My Note",
    "entry_type": "note",
    "source_type": "api",
    "public": false,
    "content": "# Hello World\n\nThis is markdown content.",
    "metadata": {}
  }
}
```

The `content` field creates a markdown representation automatically.

**Response:** Returns the created entry with status `201 Created`.

### Get Entry

```
GET /api/v1/entries/:id
```

**Response:** Returns the entry with its representations.

### Update Entry

```
PUT /api/v1/entries/:id
```

**Request Body:**

```json
{
  "entry": {
    "title": "Updated Title",
    "content": "Updated markdown content"
  }
}
```

### Delete Entry

```
DELETE /api/v1/entries/:id
```

**Response:** `204 No Content`

## Tags

### List Tags

```
GET /api/v1/tags
```

Returns all tags with entry counts.

**Response:**

```json
{
  "data": [
    {
      "id": "uuid",
      "name": "important",
      "entry_count": 5,
      "inserted_at": "2025-01-28T12:00:00Z",
      "updated_at": "2025-01-28T12:00:00Z"
    }
  ]
}
```

### Create Tag

```
POST /api/v1/tags
```

**Request Body:**

```json
{
  "tag": {
    "name": "new-tag"
  }
}
```

### Get Tag

```
GET /api/v1/tags/:id
```

### Update Tag

```
PUT /api/v1/tags/:id
```

**Request Body:**

```json
{
  "tag": {
    "name": "renamed-tag"
  }
}
```

### Delete Tag

```
DELETE /api/v1/tags/:id
```

## Entry Tags

Manage tags on entries.

### List Entry Tags

```
GET /api/v1/entries/:entry_id/tags
```

### Add Tag to Entry

```
POST /api/v1/entries/:entry_id/tags
```

**Request Body (by ID):**

```json
{
  "tag_id": "uuid"
}
```

**Request Body (by name - creates if not exists):**

```json
{
  "tag_name": "new-tag"
}
```

### Remove Tag from Entry

```
DELETE /api/v1/entries/:entry_id/tags/:tag_id
```

## Representations

Representations are different forms of an entry's content (markdown, plaintext, HTML, etc.).

### List Representations

```
GET /api/v1/entries/:entry_id/representations
```

### Get Representation

```
GET /api/v1/entries/:entry_id/representations/:id
```

### Update Representation

```
PUT /api/v1/entries/:entry_id/representations/:id
```

**Request Body:**

```json
{
  "representation": {
    "content": "Updated content"
  }
}
```

Updates create version history automatically.

## Version History

Track and restore previous versions of representations.

### List Versions

```
GET /api/v1/entries/:entry_id/representations/:representation_id/versions
```

**Query Parameters:**

| Parameter | Description | Default | Max |
|-----------|-------------|---------|-----|
| `limit` | Max versions to return | 50 | 100 |

**Response:**

```json
{
  "data": [
    {
      "id": "uuid",
      "version": 5,
      "version_type": "diff",
      "byte_size": 256,
      "inserted_at": "2025-01-28T12:00:00Z"
    }
  ]
}
```

### Get Content at Version

```
GET /api/v1/entries/:entry_id/representations/:representation_id/versions/:version
```

Reconstructs content at the specified version by applying diffs from snapshots.

**Response:**

```json
{
  "data": {
    "version": 5,
    "content": "Content at version 5..."
  }
}
```

### Revert to Version

```
POST /api/v1/entries/:entry_id/representations/:representation_id/versions/:version_id/revert
```

Reverts the representation to the specified version and creates a new version record.

**Response:**

```json
{
  "data": {
    "id": "uuid",
    "type": "markdown",
    "content": "Reverted content...",
    "version": 6,
    "updated_at": "2025-01-28T12:00:00Z"
  }
}
```

## Error Responses

All error responses follow this format:

```json
{
  "errors": {
    "detail": "Error message"
  }
}
```

### Validation Errors (422)

```json
{
  "errors": {
    "field_name": ["error message"]
  }
}
```

### Common Status Codes

| Code | Description |
|------|-------------|
| 200 | Success |
| 201 | Created |
| 204 | No Content (successful deletion) |
| 400 | Bad Request |
| 401 | Unauthorized |
| 404 | Not Found |
| 422 | Unprocessable Entity (validation errors) |
| 500 | Internal Server Error |

## Rate Limiting

API requests are subject to rate limiting. Current limits:

- 1000 requests per hour per API key

Rate limit headers are included in responses:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1706443200
```
