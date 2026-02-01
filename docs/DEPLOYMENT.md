# Onelist Deployment Guide

**Version:** 1.0.0
**Last Updated:** 2025-01-30

This guide covers deploying Onelist in three scenarios:
1. **Local Development** — Get running for development/testing
2. **Self-Hosted (Docker)** — Deploy alongside OpenClaw on your own infrastructure
3. **Fly.io (Cloud)** — Managed deployment with PostgreSQL and storage

---

## Prerequisites

All deployment methods require:
- PostgreSQL 15+ with pgvector extension
- Storage backend (local filesystem, S3-compatible, or GCS)
- OpenAI API key (for Searcher agent embeddings)

---

## 1. Local Development

### 1.1 System Requirements

- Elixir 1.14+ / Erlang 26+
- Node.js 20+
- PostgreSQL 15+ with pgvector
- 4GB RAM minimum

### 1.2 Install Dependencies

**macOS (Homebrew):**
```bash
brew install elixir node postgresql@15
brew install pgvector  # PostgreSQL extension
```

**Ubuntu/Debian:**
```bash
# Elixir
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt update
sudo apt install -y esl-erlang elixir

# Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# PostgreSQL with pgvector
sudo apt install -y postgresql-15 postgresql-15-pgvector
```

### 1.3 Database Setup

```bash
# Create database and user
sudo -u postgres psql <<EOF
CREATE USER onelist WITH PASSWORD 'onelist_dev';
CREATE DATABASE onelist_dev OWNER onelist;
\c onelist_dev
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOF
```

### 1.4 Application Setup

```bash
cd onelist-local

# Copy environment template
cp .env.example .env

# Edit .env with your values:
# - DATABASE_URL=ecto://onelist:onelist_dev@localhost/onelist_dev
# - SECRET_KEY_BASE=$(mix phx.gen.secret)
# - OPENAI_API_KEY=your_key_here

# Install dependencies
mix deps.get
npm install --prefix assets

# Setup database
mix ecto.setup

# Run the server
mix phx.server
```

Visit http://localhost:4000

---

## 2. Self-Hosted (Docker)

Ideal for running alongside OpenClaw on your own VPS.

### 2.1 System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 2 GB | 4 GB |
| CPU | 2 vCPU | 4 vCPU |
| Disk | 20 GB | 50 GB+ |
| OS | Ubuntu 22.04+ / Debian 12+ | |

### 2.2 Quick Start

```bash
# Clone the repository
git clone https://github.com/trinsiklabs/onelist.git
cd onelist

# Create production docker-compose
cat > docker-compose.prod.yml << 'EOF'
version: '3.8'

services:
  app:
    image: ghcr.io/onelist/onelist:latest
    # Or build locally:
    # build:
    #   context: .
    #   dockerfile: Dockerfile.prod
    ports:
      - "4000:4000"
    environment:
      - DATABASE_URL=ecto://onelist:${DB_PASSWORD}@db:5432/onelist_prod
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - PHX_HOST=${PHX_HOST:-localhost}
      - PHX_SERVER=true
      - PORT=4000
      - POOL_SIZE=10
      - STORAGE_BACKEND=local
      - STORAGE_LOCAL_PATH=/app/storage
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    volumes:
      - onelist_storage:/app/storage
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  db:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_USER=onelist
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=onelist_prod
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U onelist -d onelist_prod"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  onelist_storage:
EOF

# Create .env.prod
cat > .env.prod << EOF
DB_PASSWORD=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 64)
PHX_HOST=localhost
OPENAI_API_KEY=your_openai_api_key_here
EOF

# Start services
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d

# Run migrations
docker compose -f docker-compose.prod.yml exec app bin/onelist eval "Onelist.Release.migrate()"
```

### 2.3 Production Dockerfile

Create `Dockerfile.prod`:

```dockerfile
# Build stage
FROM elixir:1.16-otp-26-alpine AS builder

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Build assets
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm install --prefix assets

COPY priv priv
COPY assets assets
RUN mix assets.deploy

# Compile application
COPY lib lib
RUN mix compile

# Build release
COPY config/runtime.exs config/
RUN mix release

# Runtime stage
FROM alpine:3.19 AS runner

RUN apk add --no-cache libstdc++ openssl ncurses-libs curl

WORKDIR /app

RUN addgroup -g 1000 onelist && adduser -u 1000 -G onelist -s /bin/sh -D onelist

COPY --from=builder --chown=onelist:onelist /app/_build/prod/rel/onelist ./

USER onelist

ENV HOME=/app
ENV MIX_ENV=prod
ENV PHX_SERVER=true

# Create storage directory
RUN mkdir -p /app/storage

EXPOSE 4000

CMD ["bin/onelist", "start"]
```

### 2.4 OpenClaw Integration

Add to your OpenClaw configuration to use Onelist as memory backend:

```yaml
# ~/.openclaw/config.yaml (example)
memory:
  backend: onelist
  onelist:
    url: http://localhost:4000/api/v1
    api_key: ${ONELIST_API_KEY}
```

Generate an API key in Onelist:
```bash
docker compose -f docker-compose.prod.yml exec app bin/onelist eval "
  user = Onelist.Accounts.get_user_by_email!(\"your@email.com\")
  {:ok, key, _} = Onelist.ApiKeys.create_api_key(user)
  IO.puts(key)
"
```

### 2.5 Nginx Reverse Proxy (Optional)

```nginx
upstream onelist {
    server 127.0.0.1:4000;
}

server {
    listen 80;
    server_name onelist.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name onelist.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/onelist.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/onelist.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://onelist;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## 3. Fly.io Deployment

### 3.1 Prerequisites

- [Fly.io CLI](https://fly.io/docs/hands-on/install-flyctl/) installed
- Fly.io account with payment method

### 3.2 Initial Setup

```bash
cd onelist-local

# Login to Fly.io
fly auth login

# Create app (choose a unique name)
fly apps create onelist-yourname

# Create PostgreSQL database with pgvector
fly postgres create --name onelist-yourname-db --region iad --vm-size shared-cpu-1x --volume-size 10

# Attach database to app
fly postgres attach onelist-yourname-db --app onelist-yourname
```

### 3.3 Create fly.toml

```toml
# fly.toml
app = "onelist-yourname"
primary_region = "iad"
kill_signal = "SIGTERM"
kill_timeout = "5s"

[build]
  dockerfile = "Dockerfile.prod"

[env]
  PHX_HOST = "onelist-yourname.fly.dev"
  PORT = "8080"
  PHX_SERVER = "true"
  POOL_SIZE = "2"
  STORAGE_BACKEND = "s3"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1
  processes = ["app"]

  [http_service.concurrency]
    type = "connections"
    hard_limit = 1000
    soft_limit = 1000

[[vm]]
  memory = "512mb"
  cpu_kind = "shared"
  cpus = 1

[checks]
  [checks.health]
    grace_period = "30s"
    interval = "30s"
    method = "GET"
    path = "/health"
    port = 8080
    timeout = "5s"
    type = "http"
```

### 3.4 Configure Secrets

```bash
# Generate secret key
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) --app onelist-yourname

# OpenAI API key (required for Searcher agent)
fly secrets set OPENAI_API_KEY=your_openai_api_key --app onelist-yourname

# S3-compatible storage (Cloudflare R2 recommended)
fly secrets set AWS_ACCESS_KEY_ID=your_access_key --app onelist-yourname
fly secrets set AWS_SECRET_ACCESS_KEY=your_secret_key --app onelist-yourname
fly secrets set S3_BUCKET=onelist-storage --app onelist-yourname
fly secrets set S3_REGION=auto --app onelist-yourname
fly secrets set S3_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com --app onelist-yourname
```

### 3.5 Deploy

```bash
# Deploy the application
fly deploy

# Run migrations
fly ssh console -C "/app/bin/onelist eval 'Onelist.Release.migrate()'"

# Check logs
fly logs
```

### 3.6 Custom Domain (Optional)

```bash
# Add custom domain
fly certs create onelist.yourdomain.com

# Update DNS: CNAME onelist.yourdomain.com -> onelist-yourname.fly.dev
```

---

## 4. Storage Configuration

### 4.1 Local Storage

Best for self-hosted deployments:

```bash
STORAGE_BACKEND=local
STORAGE_LOCAL_PATH=/app/storage
```

### 4.2 Cloudflare R2 (Recommended for Cloud)

Zero egress fees, S3-compatible:

```bash
STORAGE_BACKEND=s3
AWS_ACCESS_KEY_ID=your_r2_access_key
AWS_SECRET_ACCESS_KEY=your_r2_secret_key
S3_BUCKET=onelist-storage
S3_REGION=auto
S3_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
```

### 4.3 AWS S3

```bash
STORAGE_BACKEND=s3
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key
S3_BUCKET=onelist-storage
S3_REGION=us-east-1
```

### 4.4 Backblaze B2

```bash
STORAGE_BACKEND=s3
AWS_ACCESS_KEY_ID=your_b2_application_key_id
AWS_SECRET_ACCESS_KEY=your_b2_application_key
S3_BUCKET=onelist-storage
S3_REGION=us-west-004
S3_ENDPOINT=https://s3.us-west-004.backblazeb2.com
```

### 4.5 Storage Mirroring

Enable mirroring for redundancy:

```bash
STORAGE_MIRRORS=s3  # Mirror to S3 from local primary
```

### 4.6 E2EE Storage

Enable client-side encryption:

```bash
STORAGE_E2EE_ENABLED=true
```

---

## 5. Environment Variables Reference

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | Phoenix secret (64+ chars) | `mix phx.gen.secret` |
| `PHX_HOST` | Public hostname | `onelist.yourdomain.com` |

### Storage

| Variable | Description | Default |
|----------|-------------|---------|
| `STORAGE_BACKEND` | `local`, `s3`, or `gcs` | `local` |
| `STORAGE_LOCAL_PATH` | Path for local storage | `/app/storage` |
| `AWS_ACCESS_KEY_ID` | S3/R2/B2 access key | - |
| `AWS_SECRET_ACCESS_KEY` | S3/R2/B2 secret key | - |
| `S3_BUCKET` | Bucket name | - |
| `S3_REGION` | AWS region or `auto` | `us-east-1` |
| `S3_ENDPOINT` | Custom S3 endpoint | - |
| `STORAGE_E2EE_ENABLED` | Enable encryption | `false` |
| `STORAGE_MIRRORS` | Comma-separated backends | - |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP port | `4000` |
| `POOL_SIZE` | Database pool size | `10` |
| `OPENAI_API_KEY` | For Searcher embeddings | - |
| `PHX_SERVER` | Enable server | `true` in prod |

### OAuth (Optional)

| Variable | Description |
|----------|-------------|
| `GITHUB_CLIENT_ID` | GitHub OAuth client ID |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth secret |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth secret |

---

## 6. Health Checks

Onelist exposes a health endpoint:

```bash
curl http://localhost:4000/health
# Returns: {"status":"ok"}
```

For deeper checks:
```bash
curl http://localhost:4000/health?deep=true
# Returns: {"status":"ok","database":"ok","storage":"ok"}
```

---

## 7. Backup & Recovery

### Database Backup

```bash
# Docker
docker compose exec db pg_dump -U onelist onelist_prod > backup.sql

# Fly.io
fly postgres connect -a onelist-yourname-db
# Then: \copy (SELECT * FROM entries) TO '/tmp/entries.csv' CSV HEADER
```

### Database Restore

```bash
# Docker
docker compose exec -T db psql -U onelist onelist_prod < backup.sql

# Fly.io
fly postgres connect -a onelist-yourname-db
# Then: \i /path/to/backup.sql
```

### Storage Backup

For S3-compatible storage, use rclone or aws-cli:
```bash
aws s3 sync s3://onelist-storage ./backup/storage --endpoint-url $S3_ENDPOINT
```

---

## 8. Troubleshooting

### Database Connection Failed

```bash
# Check if PostgreSQL is running
docker compose ps db
# Or: fly postgres list

# Verify connection string
echo $DATABASE_URL

# Test connection
psql $DATABASE_URL -c "SELECT 1"
```

### Migrations Failed

```bash
# Docker
docker compose exec app bin/onelist eval "Onelist.Release.migrate()"

# Fly.io
fly ssh console -C "/app/bin/onelist eval 'Onelist.Release.migrate()'"

# If pgvector missing:
psql $DATABASE_URL -c "CREATE EXTENSION IF NOT EXISTS vector"
```

### Storage Upload Failed

```bash
# Check storage config
echo $STORAGE_BACKEND
echo $S3_BUCKET

# Test S3 connectivity
aws s3 ls s3://$S3_BUCKET --endpoint-url $S3_ENDPOINT
```

### Application Won't Start

```bash
# Check logs
docker compose logs app
# Or: fly logs

# Verify environment
docker compose exec app env | grep -E "(DATABASE|SECRET|STORAGE)"
```

---

## 9. Next Steps

After deployment:

1. **Create an account** — Visit your Onelist URL and sign up
2. **Generate API key** — Settings → API Keys → Create
3. **Test the API** — `curl -H "Authorization: Bearer YOUR_KEY" https://your-onelist/api/v1/entries`
4. **Integrate with OpenClaw** — Configure memory backend
5. **Enable agents** — Set `OPENAI_API_KEY` for Searcher

---

## Support

- Documentation: https://onelist.my/docs
- GitHub Issues: https://github.com/trinsiklabs/onelist/issues
- Community: https://onelist.my/community
