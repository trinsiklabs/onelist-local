# Onelist Local - Makefile
# Your data, your machine, forever.

.PHONY: help setup start stop logs shell db-shell migrate seed reset clean

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

# First-time setup
setup: check-env
	@echo "🌊 Setting up Onelist Local..."
	@set -a && . ./.env.local && set +a && \
	docker-compose -f docker-compose.local.yml build
	@set -a && . ./.env.local && set +a && \
	docker-compose -f docker-compose.local.yml up -d db
	@echo "⏳ Waiting for database..."
	@sleep 8
	@set -a && . ./.env.local && set +a && \
	docker-compose -f docker-compose.local.yml up -d onelist
	@echo "⏳ Waiting for Onelist to start..."
	@sleep 15
	@echo "🔧 Running setup..."
	@set -a && . ./.env.local && set +a && \
	docker-compose -f docker-compose.local.yml exec onelist bin/onelist eval "Onelist.Release.setup_local()"
	@echo ""
	@echo "✅ Onelist is running at http://localhost:$${PORT:-4000}"
	@echo ""

# Check required env vars
check-env:
	@if [ ! -f .env.local ]; then \
		echo "❌ Missing .env.local file"; \
		echo "   Copy .env.local.example to .env.local and fill in values"; \
		exit 1; \
	fi
	@export $$(cat .env.local | grep -v '^#' | xargs) && \
	if [ -z "$$SECRET_KEY_BASE" ]; then \
		echo "❌ SECRET_KEY_BASE not set in .env.local"; \
		echo "   Generate with: openssl rand -hex 64"; \
		exit 1; \
	fi && \
	if [ -z "$$OPENAI_API_KEY" ]; then \
		echo "❌ OPENAI_API_KEY not set in .env.local"; \
		echo "   Get one at: https://platform.openai.com/api-keys"; \
		exit 1; \
	fi

# Start services
start:
	@set -a && . ./.env.local && set +a && \
	docker-compose -f docker-compose.local.yml up -d
	@echo "🌊 Onelist running at http://localhost:$${PORT:-4000}"

# Stop services
stop:
	@docker-compose -f docker-compose.local.yml down
	@echo "⏹️  Onelist stopped"

# View logs
logs:
	@docker-compose -f docker-compose.local.yml logs -f onelist

# View all logs
logs-all:
	@docker-compose -f docker-compose.local.yml logs -f

# Shell into onelist container
shell:
	@docker-compose -f docker-compose.local.yml exec onelist /bin/sh

# PostgreSQL shell
db-shell:
	@docker-compose -f docker-compose.local.yml exec db psql -U onelist -d onelist_local

# Run migrations
migrate:
	@docker-compose -f docker-compose.local.yml exec onelist bin/onelist eval "Onelist.Release.migrate()"

# Create initial user (if not already created)
create-user:
	@set -a && . ./.env.local && set +a && \
	docker-compose -f docker-compose.local.yml exec onelist bin/onelist eval "Onelist.Release.setup_initial_user()"

# Status check
status:
	@docker-compose -f docker-compose.local.yml ps

# Reset everything (WARNING: deletes all data)
reset:
	@echo "⚠️  This will delete ALL your data. Are you sure? [y/N]"
	@read -r confirm && [ "$$confirm" = "y" ] || exit 1
	@docker-compose -f docker-compose.local.yml down -v
	@echo "🗑️  Data deleted. Run 'make setup' to start fresh."

# Clean build artifacts
clean:
	@docker-compose -f docker-compose.local.yml down --rmi local -v
	@echo "🧹 Cleaned up"
