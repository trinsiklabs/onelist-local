# Onelist Local + OpenClaw Docker Setup

One-command deployment for self-hosted AI with persistent memory.

## Quick Start

```bash
curl -fsSL https://get.onelist.my/local | bash
```

That's it. The installer will:
1. Check Docker is installed
2. Download the configuration
3. Prompt for API keys (OpenAI, Anthropic, Telegram)
4. Start everything
5. Open your browser

## What Gets Installed

| Service | Port | Purpose |
|---------|------|---------|
| Onelist | 4000 | Memory system + River agent |
| PostgreSQL | 5432 | Database with pgvector |
| OpenClaw | 18789 | AI agent runtime |

## Requirements

- Docker & Docker Compose
- 2GB RAM minimum
- API keys:
  - **Anthropic** (required for AI agent)
  - **OpenAI** (required for embeddings)
  - **Telegram** (optional, for chat interface)

## Manual Installation

If you prefer to set things up manually:

```bash
# Create directory
mkdir -p ~/.onelist && cd ~/.onelist

# Download compose file
curl -fsSL https://raw.githubusercontent.com/onelist/onelist/main/docker/docker-compose.local.yml -o docker-compose.yml

# Create .env file
cat > .env << EOF
SECRET_KEY_BASE=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 16)
ANTHROPIC_API_KEY=your-key-here
OPENAI_API_KEY=your-key-here
TELEGRAM_BOT_TOKEN=your-token-here  # optional
EOF

# Start
docker compose up -d
```

## Usage

### Talk to River (Web)
Open http://localhost:4000/app/river

### Talk via Telegram
Message your bot (if you configured TELEGRAM_BOT_TOKEN)

### API Access
```bash
curl http://localhost:4000/api/v1/river/chat \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"message": "hello river"}'
```

## Commands

```bash
cd ~/.onelist

# View logs
docker compose logs -f

# Stop
docker compose down

# Start
docker compose up -d

# Update
docker compose pull && docker compose up -d

# Reset (WARNING: deletes data)
docker compose down -v
```

## Troubleshooting

### "Port 4000 already in use"
```bash
# Change the port in docker-compose.yml or stop the conflicting service
lsof -i :4000
```

### "Database connection failed"
```bash
# Check postgres is healthy
docker compose ps
docker compose logs postgres
```

### "OpenClaw can't connect to Onelist"
```bash
# Verify both services are running
docker compose ps
# Check the network
docker network inspect onelist-network
```

## Pricing

This is the **free, self-hosted** version. You manage your own infrastructure.

For managed hosting, visit https://onelist.my/pricing

| Tier | Price | What You Get |
|------|-------|--------------|
| Self-hosted | Free | This setup, your hardware |
| Cloud | $5/mo | We manage everything |
| VPS Guided | $20/mo + $20 setup | We help you set up |
| VPS Done-for-you | $20/mo + $100 setup | We do it all |

## Support

- GitHub Issues: https://github.com/onelist/onelist/issues
- Discord: https://discord.gg/onelist
- Email: support@onelist.my

---

*Your memories should outlive any single AI model.* 🌊
