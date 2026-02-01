#!/bin/bash
# Onelist Local Installer
# 
# Usage:
#   curl -fsSL https://get.onelist.my/local | bash
#   
# Options:
#   --with-openclaw   Install OpenClaw + Reader + Searcher agents
#   --all-agents      Install all available agents (River, etc.)
#   --web             Install web UI (LiveView dashboard)
#   --help            Show this help
#
# Examples:
#   # Base install (API only)
#   curl -fsSL https://get.onelist.my/local | bash
#
#   # With OpenClaw integration (recommended)
#   curl -fsSL https://get.onelist.my/local | bash -s -- --with-openclaw
#
#   # Full stack
#   curl -fsSL https://get.onelist.my/local | bash -s -- --with-openclaw --web --all-agents

set -e

# ===========================================
# Parse flags
# ===========================================
WITH_OPENCLAW=false
ALL_AGENTS=false
WITH_WEB=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --with-openclaw)
            WITH_OPENCLAW=true
            shift
            ;;
        --all-agents)
            ALL_AGENTS=true
            shift
            ;;
        --web)
            WITH_WEB=true
            shift
            ;;
        --help)
            echo "Onelist Local Installer"
            echo ""
            echo "Usage: curl -fsSL https://get.onelist.my/local | bash -s -- [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --with-openclaw   Install OpenClaw + Reader + Searcher agents"
            echo "  --all-agents      Install all available agents"
            echo "  --web             Install web UI"
            echo "  --help            Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Config
INSTALL_DIR="${ONELIST_DIR:-$HOME/.onelist}"
BASE_URL="https://raw.githubusercontent.com/onelist/onelist-local/main/docker"

# Determine which compose files to download
COMPOSE_FILES="docker-compose.yml"
if [ "$WITH_OPENCLAW" = true ]; then
    COMPOSE_FILES="$COMPOSE_FILES docker-compose.openclaw.yml"
fi
if [ "$ALL_AGENTS" = true ]; then
    COMPOSE_FILES="$COMPOSE_FILES docker-compose.agents.yml"
fi
if [ "$WITH_WEB" = true ]; then
    COMPOSE_FILES="$COMPOSE_FILES docker-compose.web.yml"
fi

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   🌊 Onelist Local Installer                              ║"
echo "║      AI with real memory, running on your machine         ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ===========================================
# Prerequisites check
# ===========================================

echo -e "${YELLOW}Checking prerequisites...${NC}"

# Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found.${NC}"
    echo "   Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "${GREEN}✓ Docker installed${NC}"

# Docker Compose
if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose not found.${NC}"
    echo "   Install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose installed${NC}"

# Docker running
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker daemon not running.${NC}"
    echo "   Start Docker and try again."
    exit 1
fi
echo -e "${GREEN}✓ Docker daemon running${NC}"

echo ""

# ===========================================
# Installation directory
# ===========================================

echo -e "${YELLOW}Setting up installation directory...${NC}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
echo -e "${GREEN}✓ Directory: $INSTALL_DIR${NC}"

# ===========================================
# Download docker-compose files
# ===========================================

echo -e "${YELLOW}Downloading Onelist configuration...${NC}"

# Always download base
curl -fsSL "$BASE_URL/docker-compose.yml" -o docker-compose.yml
echo -e "${GREEN}✓ Base configuration${NC}"

# Download optional components
if [ "$WITH_OPENCLAW" = true ]; then
    curl -fsSL "$BASE_URL/docker-compose.openclaw.yml" -o docker-compose.openclaw.yml
    echo -e "${GREEN}✓ OpenClaw integration${NC}"
fi

if [ "$ALL_AGENTS" = true ]; then
    curl -fsSL "$BASE_URL/docker-compose.agents.yml" -o docker-compose.agents.yml
    echo -e "${GREEN}✓ All agents${NC}"
fi

if [ "$WITH_WEB" = true ]; then
    curl -fsSL "$BASE_URL/docker-compose.web.yml" -o docker-compose.web.yml
    echo -e "${GREEN}✓ Web UI${NC}"
fi

# ===========================================
# Environment setup
# ===========================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Configuration${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check for existing .env
if [ -f .env ]; then
    echo -e "${YELLOW}Found existing .env file. Use it? [Y/n]${NC}"
    read -r USE_EXISTING
    if [[ "$USE_EXISTING" =~ ^[Nn] ]]; then
        rm .env
    fi
fi

if [ ! -f .env ]; then
    # Generate secret key
    SECRET_KEY=$(openssl rand -hex 32)
    
    # Database password
    DB_PASSWORD=$(openssl rand -hex 16)
    
    echo "SECRET_KEY_BASE=$SECRET_KEY" >> .env
    echo "DB_PASSWORD=$DB_PASSWORD" >> .env
    
    # OpenAI API key (for embeddings) - always needed
    echo ""
    echo -e "${YELLOW}OpenAI API Key (required for embeddings):${NC}"
    read -r OPENAI_KEY
    if [ -n "$OPENAI_KEY" ]; then
        echo "OPENAI_API_KEY=$OPENAI_KEY" >> .env
    else
        echo -e "${RED}⚠ Warning: Embeddings won't work without OpenAI key${NC}"
    fi
    
    # Only ask for Anthropic/Telegram if installing OpenClaw
    if [ "$WITH_OPENCLAW" = true ]; then
        echo ""
        echo -e "${YELLOW}Anthropic API Key (required for OpenClaw AI agent):${NC}"
        read -r ANTHROPIC_KEY
        if [ -n "$ANTHROPIC_KEY" ]; then
            echo "ANTHROPIC_API_KEY=$ANTHROPIC_KEY" >> .env
        else
            echo -e "${RED}⚠ Warning: OpenClaw won't work without Anthropic key${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}Telegram Bot Token (optional - press Enter to skip):${NC}"
        read -r TELEGRAM_TOKEN
        if [ -n "$TELEGRAM_TOKEN" ]; then
            echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN" >> .env
        fi
    fi
    
    echo -e "${GREEN}✓ Configuration saved to .env${NC}"
fi

# ===========================================
# Start services
# ===========================================

echo ""
echo -e "${YELLOW}Starting Onelist...${NC}"
echo ""

# Build compose command with all files
COMPOSE_CMD="docker compose -f docker-compose.yml"
if [ "$WITH_OPENCLAW" = true ] && [ -f docker-compose.openclaw.yml ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.openclaw.yml"
fi
if [ "$ALL_AGENTS" = true ] && [ -f docker-compose.agents.yml ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.agents.yml"
fi
if [ "$WITH_WEB" = true ] && [ -f docker-compose.web.yml ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.web.yml"
fi

# Run setup first
$COMPOSE_CMD run --rm setup 2>/dev/null || true

# Start main services
$COMPOSE_CMD up -d

# Save compose command for future use
echo "COMPOSE_CMD=\"$COMPOSE_CMD\"" >> .env

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Onelist is running!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Onelist:  ${BLUE}http://localhost:4000${NC}"
echo -e "  OpenClaw: ${BLUE}http://localhost:18789${NC}"
echo ""
echo -e "  Installation directory: $INSTALL_DIR"
echo ""
echo -e "  Commands:"
echo -e "    ${YELLOW}cd $INSTALL_DIR && docker compose logs -f${NC}  # View logs"
echo -e "    ${YELLOW}cd $INSTALL_DIR && docker compose down${NC}     # Stop"
echo -e "    ${YELLOW}cd $INSTALL_DIR && docker compose up -d${NC}    # Start"
echo ""
echo -e "  Talk to your AI:"
echo -e "    Open Telegram and message your bot, or"
echo -e "    Visit ${BLUE}http://localhost:4000/app/river${NC}"
echo ""

# Try to open browser
if command -v open &> /dev/null; then
    open "http://localhost:4000"
elif command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:4000"
fi

echo -e "${GREEN}Happy remembering! 🌊${NC}"
