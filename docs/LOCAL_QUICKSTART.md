# Onelist Local - 5-Minute Quickstart

> Your data, your machine, forever.

Onelist is **self-hosted first**. Run it on your own hardware, keep your memories under your control, no subscription required. Cloud sync is optional.

## Requirements

- Docker & Docker Compose
- OpenAI API key (for semantic search & Reader agent)

## Setup

### 1. Clone and configure

```bash
git clone https://github.com/onelist/onelist.git
cd onelist

# Copy the config template
cp .env.local.example .env.local
```

### 2. Edit `.env.local`

Only two things required:

```bash
# Generate a secret key
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Your OpenAI API key from https://platform.openai.com/api-keys
OPENAI_API_KEY=sk-...

# Your email (creates your initial account)
INITIAL_USER_EMAIL=you@example.com
```

### 3. Start Onelist

```bash
make setup
```

That's it! Open http://localhost:4000

## Commands

```bash
make start    # Start Onelist
make stop     # Stop Onelist
make logs     # View logs
make shell    # Shell into container
make db-shell # PostgreSQL shell
make reset    # Reset everything (deletes data!)
```

## What's Included

- **Full Onelist** - Entries, tags, search, the works
- **Reader Agent** - Automatically processes URLs, PDFs, documents
- **Searcher Agent** - Semantic search across all your memories
- **Asset Enrichment** - Extracts and indexes media content
- **PostgreSQL + pgvector** - Vector embeddings for AI-powered search

## Data Location

Your data lives in Docker volumes:
- `postgres_data` - Database
- `onelist_storage` - Uploaded files

Back these up to keep your memories safe.

## Cloud Sync (Optional)

When Onelist cloud launches, you can optionally connect your local instance:

1. Create a cloud account at onelist.my
2. Add your cloud credentials to `.env.local`
3. Choose: sync existing local data or start fresh in cloud

Local remains fully functional either way. Cloud adds:
- Sync across devices
- Mobile access
- Automatic backups
- (Coming) Collaboration features

## Troubleshooting

### Port already in use
```bash
# Change port in .env.local
PORT=4001
make start
```

### Database connection issues
```bash
# Check if db is running
docker-compose -f docker-compose.local.yml ps

# View db logs
docker-compose -f docker-compose.local.yml logs db
```

### Reset everything
```bash
make reset
make setup
```

## Support

- Docs: https://docs.onelist.my
- Discord: [coming soon]
- Issues: https://github.com/onelist/onelist/issues

---

*Built with 🌊 by the Onelist team*
