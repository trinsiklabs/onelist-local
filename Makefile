# Onelist Local - Makefile
# Your data, your machine, forever.

.PHONY: help setup start stop logs shell db-shell migrate seed reset clean init-env check-env status create-user

# Default target
help:
	@echo "Onelist Local Commands:"
	@echo ""
	@echo "  make setup       - First-time setup (build + migrate + create user)"
	@echo "  make start       - Start Onelist"
	@echo "  make stop        - Stop Onelist"
	@echo "  make status      - Show container status"
	@echo "  make logs        - View Onelist logs"
	@echo "  make logs-all    - View all logs (incl. database)"
	@echo "  make shell       - Open shell in Onelist container"
	@echo "  make db-shell    - Open PostgreSQL shell"
	@echo "  make create-user - Create initial user (if needed)"
	@echo "  make migrate     - Run database migrations"
	@echo "  make reset       - Reset everything (WARNING: deletes data)"
	@echo "  make clean       - Remove containers and images"
	@echo ""

# Auto-create .env.local if missing
init-env:
	@if [ ! -f .env.local ]; then \
		echo "📝 Creating .env.local from template..."; \
		cp .env.local.example .env.local; \
		SECRET=$$(openssl rand -hex 64); \
		if [ "$$(uname)" = "Darwin" ]; then \
			sed -i '' "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$$SECRET/" .env.local; \
		else \
			sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$$SECRET/" .env.local; \
		fi; \
		echo "✅ Generated SECRET_KEY_BASE"; \
		echo ""; \
		echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
		echo ""; \
		echo "  ⚠️  Please edit .env.local to add:"; \
		echo ""; \
		echo "     OPENAI_API_KEY=sk-...     (from https://platform.openai.com/api-keys)"; \
		echo "     INITIAL_USER_EMAIL=you@example.com"; \
		echo ""; \
		echo "  Then run 'make setup' again."; \
		echo ""; \
		echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
		exit 1; \
	fi

# Check required env vars
check-env: init-env
	@. ./.env.local 2>/dev/null || true; \
	if [ -z "$$SECRET_KEY_BASE" ]; then \
		echo "❌ SECRET_KEY_BASE not set in .env.local"; \
		echo ""; \
		echo "   Generate with: openssl rand -hex 64"; \
		exit 1; \
	fi; \
	if [ -z "$$OPENAI_API_KEY" ]; then \
		echo "❌ OPENAI_API_KEY not set in .env.local"; \
		echo ""; \
		echo "   Get one at: https://platform.openai.com/api-keys"; \
		echo "   This is required for semantic search (embeddings)."; \
		exit 1; \
	fi; \
	if [ -z "$$INITIAL_USER_EMAIL" ] || [ "$$INITIAL_USER_EMAIL" = "you@example.com" ]; then \
		echo "❌ INITIAL_USER_EMAIL not set in .env.local"; \
		echo ""; \
		echo "   Set this to your email address."; \
		exit 1; \
	fi

# First-time setup
setup: check-env
	@echo ""
	@echo "🌊 Setting up Onelist Local..."
	@echo ""
	@set -a && . ./.env.local && set +a && \
	docker compose -f docker-compose.local.yml build
	@echo ""
	@echo "📦 Starting database..."
	@set -a && . ./.env.local && set +a && \
	docker compose -f docker-compose.local.yml up -d db
	@echo "⏳ Waiting for database to be ready..."
	@sleep 10
	@echo ""
	@echo "🚀 Starting Onelist..."
	@set -a && . ./.env.local && set +a && \
	docker compose -f docker-compose.local.yml up -d onelist
	@echo "⏳ Waiting for Onelist to start (this may take a minute on first run)..."
	@sleep 20
	@echo ""
	@echo "🔧 Running database setup..."
	@set -a && . ./.env.local && set +a && \
	docker compose -f docker-compose.local.yml exec onelist bin/onelist eval "Onelist.Release.setup_local()" || \
		(echo "⚠️  Setup may have failed. Checking logs..." && \
		 docker compose -f docker-compose.local.yml logs onelist --tail 50)
	@echo ""
	@. ./.env.local && \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
	echo "" && \
	echo "  ✅ Onelist is running!" && \
	echo "" && \
	echo "  🌐 Open: http://localhost:$${PORT:-4000}" && \
	echo "" && \
	echo "  📝 Your login credentials were printed above." && \
	echo "     (scroll up to see the generated password)" && \
	echo "" && \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""

# Start services
start:
	@if [ ! -f .env.local ]; then \
		echo "❌ No .env.local found. Run 'make setup' first."; \
		exit 1; \
	fi
	@set -a && . ./.env.local && set +a && \
	docker compose -f docker-compose.local.yml up -d
	@. ./.env.local && \
	echo "🌊 Onelist running at http://localhost:$${PORT:-4000}"

# Stop services
stop:
	@docker compose -f docker-compose.local.yml down
	@echo "⏹️  Onelist stopped"

# View logs
logs:
	@docker compose -f docker-compose.local.yml logs -f onelist

# View all logs
logs-all:
	@docker compose -f docker-compose.local.yml logs -f

# Shell into onelist container
shell:
	@docker compose -f docker-compose.local.yml exec onelist /bin/sh

# PostgreSQL shell
db-shell:
	@docker compose -f docker-compose.local.yml exec db psql -U onelist -d onelist_local

# Run migrations
migrate:
	@docker compose -f docker-compose.local.yml exec onelist bin/onelist eval "Onelist.Release.migrate()"

# Create initial user (if not already created)
create-user:
	@set -a && . ./.env.local && set +a && \
	docker compose -f docker-compose.local.yml exec onelist bin/onelist eval "Onelist.Release.setup_initial_user()"

# Status check
status:
	@docker compose -f docker-compose.local.yml ps

# Reset everything (WARNING: deletes all data)
reset:
	@echo "⚠️  This will delete ALL your Onelist data."
	@echo "   Type 'yes' to confirm:"
	@read -r confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled." && exit 1)
	@docker compose -f docker-compose.local.yml down -v
	@echo "🗑️  Data deleted. Run 'make setup' to start fresh."

# Clean build artifacts
clean:
	@docker compose -f docker-compose.local.yml down --rmi local -v
	@echo "🧹 Cleaned up"

# Doctor - diagnose common issues
doctor:
	@echo "🩺 Running Onelist diagnostics..."
	@echo ""
	@echo "📋 Checking prerequisites..."
	@command -v docker >/dev/null 2>&1 && echo "  ✓ Docker installed" || echo "  ✗ Docker not found"
	@docker compose version >/dev/null 2>&1 && echo "  ✓ Docker Compose available" || echo "  ✗ Docker Compose not found"
	@docker info >/dev/null 2>&1 && echo "  ✓ Docker daemon running" || echo "  ✗ Docker daemon not running"
	@echo ""
	@echo "📋 Checking configuration..."
	@test -f .env.local && echo "  ✓ .env.local exists" || echo "  ✗ .env.local missing (run 'make setup')"
	@if [ -f .env.local ]; then \
		. ./.env.local; \
		[ -n "$$SECRET_KEY_BASE" ] && echo "  ✓ SECRET_KEY_BASE set" || echo "  ✗ SECRET_KEY_BASE empty"; \
		[ -n "$$OPENAI_API_KEY" ] && echo "  ✓ OPENAI_API_KEY set" || echo "  ✗ OPENAI_API_KEY empty"; \
		[ -n "$$INITIAL_USER_EMAIL" ] && echo "  ✓ INITIAL_USER_EMAIL set" || echo "  ✗ INITIAL_USER_EMAIL empty"; \
	fi
	@echo ""
	@echo "📋 Checking containers..."
	@docker compose -f docker-compose.local.yml ps 2>/dev/null || echo "  (no containers running)"
	@echo ""
	@echo "📋 Checking health..."
	@curl -sf http://localhost:4000/health >/dev/null 2>&1 && echo "  ✓ Onelist responding" || echo "  ✗ Onelist not responding (is it running?)"
	@echo ""
