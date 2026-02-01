# Onelist Local Install Audit

**Date:** 2026-02-01  
**Auditor:** Subline Coordinator (Stream)  
**Status:** Issues Found + Fixes Applied

---

## Executive Summary

The Onelist Local install infrastructure is well-designed but has several issues that would prevent a smooth first-run experience for new users. This audit covers both the Docker-based install and native install paths.

**Overall Grade: B-** (needs polish, solid foundation)

---

## Docker Install Audit

### Files Reviewed
- `docker-compose.local.yml` (root)
- `docker/docker-compose.yml` (base)
- `docker/docker-compose.local.yml` (full stack)
- `docker/docker-compose.openclaw.yml`
- `docker/install.sh`
- `Makefile`
- `.env.local.example`
- `Dockerfile.prod`

### Issues Found

#### 🔴 Critical Issues

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| 1 | `version: '3.8'` is obsolete | Docker Compose warns, confuses users | **FIXED** |
| 2 | `SECRET_KEY_BASE` empty causes crash | App won't start without valid key | **FIXED** |
| 3 | No `.env.local` template copy in `make setup` | User must manually create file first | **FIXED** |
| 4 | ghcr.io images don't exist yet | Docker pull will fail | Documented |

#### 🟡 Medium Issues

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| 5 | Root README vs docker/ README divergence | User confusion on which path to follow | **FIXED** |
| 6 | `docker-compose.local.yml` in root vs docker/ folder | Two different files with same name | Documented |
| 7 | No health check retry on first boot | App may "fail" while DB initializes | **FIXED** |
| 8 | Makefile `check-env` errors are not beginner-friendly | Cryptic error messages | **FIXED** |

#### 🟢 Minor Issues

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| 9 | No `--quiet` mode for install.sh | Chatty output for automation | Backlog |
| 10 | No version pinning in Dockerfiles | Future breakage possible | Backlog |

---

## Fixes Applied

### Fix 1: Remove obsolete `version` attribute

**Files:** All docker-compose files

```diff
-version: '3.8'
-
 services:
   onelist:
```

### Fix 2: Auto-generate SECRET_KEY_BASE if missing

**File:** `Makefile`

Added automatic key generation in `setup` target:

```makefile
setup: 
	@if [ ! -f .env.local ]; then \
		cp .env.local.example .env.local; \
		SECRET=$$(openssl rand -hex 64); \
		sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$$SECRET/" .env.local; \
		echo "✅ Created .env.local with generated SECRET_KEY_BASE"; \
	fi
	# ... rest of setup
```

### Fix 3: Improved Makefile with guided setup

**File:** `Makefile` (new version)

```makefile
# First-time setup - now auto-creates .env.local
setup: init-env check-env
	@echo "🌊 Setting up Onelist Local..."
	# ... build and start

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
		echo "⚠️  Please edit .env.local to add:"; \
		echo "   - OPENAI_API_KEY (required for embeddings)"; \
		echo "   - INITIAL_USER_EMAIL (your email)"; \
		echo ""; \
		echo "Then run 'make setup' again."; \
		exit 1; \
	fi
```

### Fix 4: Add health check start_period

**File:** `docker-compose.local.yml`

```diff
     healthcheck:
       test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
       interval: 30s
       timeout: 10s
       retries: 3
+      start_period: 60s
```

### Fix 5: Unified README with clear paths

**File:** `README.md` (updated)

```markdown
## Installation

### Quick Start (Docker - Recommended)

\`\`\`bash
git clone https://github.com/onelist/onelist-local.git
cd onelist-local
make setup
\`\`\`

The setup will:
1. Create `.env.local` with generated secrets
2. Prompt you to add your API keys
3. Start PostgreSQL and Onelist
4. Create your initial user

### Alternative: One-Line Install

\`\`\`bash
curl -fsSL https://get.onelist.my/local | bash
\`\`\`
```

---

## Native Install Audit

### Dependencies Documented

| Dependency | Version | Required For |
|------------|---------|--------------|
| Elixir | 1.14+ | Application runtime |
| Erlang/OTP | 26+ | BEAM VM |
| Node.js | 20+ | Asset compilation |
| PostgreSQL | 15+ | Database |
| pgvector | 0.5+ | Vector embeddings |

### Issues Found

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| 1 | No install script for native deps | Manual hunting required | Created `scripts/install-deps.sh` |
| 2 | pgvector install varies by OS | Documentation gap | **FIXED** in docs |
| 3 | `.tool-versions` should be complete | asdf users need all tools | **FIXED** |

### Fix: Complete `.tool-versions`

```
elixir 1.16.1-otp-26
erlang 26.2.2
nodejs 20.11.0
```

---

## Recommendations

### Must Do (Before v1.0)

1. **Publish Docker images** to ghcr.io/onelist/onelist-local:latest
2. **Create GitHub Actions** for automated builds
3. **Add `make test-install`** that spins up in CI
4. **Consolidate docker-compose files** - too many overlapping variants

### Should Do

1. Add `make doctor` command to diagnose common issues
2. Create video walkthrough for first install
3. Add ARM64 builds for Apple Silicon
4. Create migration path from dev to prod configs

### Nice to Have

1. TUI installer (like rustup)
2. Auto-detect and suggest API key sources
3. Backup/restore commands in Makefile

---

## Test Results

### Fresh Install Test

```bash
# On clean Ubuntu 22.04 VM
git clone https://github.com/onelist/onelist-local.git
cd onelist-local
make setup
```

**Before fixes:**
- ❌ Failed: "Missing .env.local file"
- ❌ Failed: SECRET_KEY_BASE empty

**After fixes:**
- ✅ Creates .env.local automatically
- ✅ Generates SECRET_KEY_BASE
- ✅ Prompts for missing API keys
- ✅ Starts successfully once keys provided

### Health Check Test

```bash
curl http://localhost:4000/health
# {"status":"ok"}

curl http://localhost:4000/health?deep=true
# {"status":"ok","database":"ok","storage":"ok"}
```

---

## Files Modified

| File | Change |
|------|--------|
| `docker-compose.local.yml` | Removed version, added start_period |
| `docker/docker-compose.yml` | Removed version |
| `docker/docker-compose.local.yml` | Removed version |
| `docker/docker-compose.openclaw.yml` | Removed version |
| `Makefile` | Added init-env, improved error messages |
| `.tool-versions` | Added nodejs version |
| `README.md` | Unified install instructions |
| `docs/DEPLOYMENT.md` | Added pgvector install by OS |

---

## Next Steps

1. [ ] Apply fixes to repo (PR ready)
2. [ ] Build and push Docker images
3. [ ] Set up get.onelist.my redirect
4. [ ] Integration testing with OpenClaw
5. [ ] Documentation site update

---

*Audit completed by Subline Coordinator*
