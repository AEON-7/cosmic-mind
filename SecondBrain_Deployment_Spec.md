# Second Brain — Deployment Specification (Revised)
# Infrastructure: onyx (192.168.1.80) | brain.lab.unhash.me (internal) | brain.unhash.me (external)
---

## PROJECT OVERVIEW

### Vision
A self-hosted, AI-augmented "second brain" knowledge management system that:
- Stores all knowledge as plain Markdown files in a Git-backed Obsidian vault
- Renders two Quartz v4 static sites: internal (full vault) and external (curated public wiki)
- Provides semantic search via Quartz built-in FlexSearch + Claude Code native vault access
- Connects to OpenClaw (Qwen 3.5 9B) and Claude Code for AI enrichment
- Serves as a shared memory repository for all AI interactions
- Syncs across devices via Syncthing
- Automates build/deploy via file watcher with atomic directory swaps
- Follows the resilience patterns from frombottlestobruh (validation, backup, rollback)

### Architecture
```
VAULT (/srv/appdata/secondbrain/vault/ - Git-backed .md files)
    |
    +---> Quartz Builder (ephemeral container)
    |         |---> Internal build → Caddy file_server → brain.lab.unhash.me
    |         +---> External build (filtered) → Caddy file_server → brain.unhash.me
    |
    +---> Vault Watcher (polls for changes, auto-commits, triggers builds)
    |
    +---> Syncthing (real-time sync to desktop/mobile Obsidian)
    |
    +---> GitHub (private repo, version control)
    |
    +---> Claude Code (direct filesystem search/write)
    |
    +---> OpenClaw API (AI enrichment via n8n workflows)
    |
    +---> n8n (optional: enrichment pipelines, inbox processing)
```

### Key Design Decisions

1. **Caddy serves static files directly** — No Nginx. Quartz builds to `/srv/appdata/secondbrain/output/` which is volume-mounted into Caddy. Caddy's `file_server` is optimal for static content with built-in compression and caching.

2. **Cloudflare tunnels for external access** — `brain.unhash.me` routes through the existing Cloudflare Zero Trust tunnel to Caddy. No direct port exposure.

3. **Atomic directory swap for zero-downtime deploys** — Builds output to timestamped directories. A symlink swap (`ln -sfn`) is atomic at the filesystem level. Caddy follows the symlink with no restart needed.

4. **No local LLM (Ollama removed)** — AI enrichment uses OpenClaw (Qwen 3.5 9B) via API calls from n8n. Claude Code has direct filesystem access to the vault for search and authoring.

5. **No Khoj** — Vault search is handled by Quartz's built-in FlexSearch (web UI) and Claude Code's native Grep/Glob tools (CLI). No vector database needed at launch.

6. **Frontmatter-gated publishing** — Only files with `publish: public` are included in the external build. This is safer than repository-level separation (no fork needed).

7. **Obsidian as primary editor** — Quartz v4 is Obsidian-native. The vault is plain .md files synced via Syncthing.

---

## INFRASTRUCTURE CONVENTIONS (Onyx Server)

| Convention | Path |
|-----------|------|
| Stack compose files | `/opt/stacks/secondbrain/` |
| Persistent data | `/srv/appdata/secondbrain/` |
| Secrets | `/opt/stacks/secondbrain/.env` (chmod 600, gitignored) |
| Reverse proxy | Caddy at `/opt/stacks/proxy/` with config at `/srv/appdata/proxy/Caddyfile` |
| External access | Cloudflare Zero Trust tunnel via `cloudflared` |
| Authentication | Authentik SSO via Caddy `forward_auth` snippet |
| Database isolation | `secondbrain-internal` network (private to stack) |

---

## PHASE 1: VAULT AND GIT (COMPLETED)

Structure created at `/srv/appdata/secondbrain/vault/`:
```
vault/
├── index.md
├── CLAUDE.md                  # AI instructions for vault interaction
├── .gitignore
├── philosophy/{hermetic,gnostic,vedanta,christian-mysticism,personal-gnosis,jungian}/
├── technology/
├── cybersecurity/
├── concepts/
├── sources/
├── projects/
├── skills/
├── ai-generated/
├── ai-interactions/           # Journal of AI conversations
├── daily-notes/
├── people/
├── inbox/                     # Drop zone for AI processing
├── public/                    # Explicitly public content
└── templates/{concept,source,daily-note,ai-interaction,project}.md
```

### Remaining: Initialize git and push to GitHub
```bash
cd /srv/appdata/secondbrain/vault
git init -b main
git add -A
git commit -m "Initial vault structure"
git remote add origin git@github.com:USERNAME/secondbrain-vault.git
git push -u origin main
```

---

## PHASE 2: DOCKER COMPOSE STACK (COMPLETED)

Stack at `/opt/stacks/secondbrain/docker-compose.yml`:

| Service | Purpose | Network |
|---------|---------|---------|
| `quartz-builder` | Ephemeral build service (profile: build) | secondbrain-internal |
| `syncthing` | Real-time vault sync | secondbrain-internal + core_net |
| `vault-watcher` | Change detection + auto-build | secondbrain-internal |

### Start the stack
```bash
cd /opt/stacks/secondbrain
cp .env.example .env && chmod 600 .env
# Edit .env with your values

# Start Syncthing and watcher (builder runs on-demand)
docker compose up -d syncthing vault-watcher

# Manual build (one-shot)
docker compose run --rm quartz-builder

# Manual deploy with backup + validation
./scripts/deploy.sh
```

---

## PHASE 3: CADDY CONFIGURATION (MANUAL STEP)

### Step 3.1: Add volume mount to Caddy container

Edit `/opt/stacks/proxy/docker-compose.yml` and add this volume to the caddy service:
```yaml
volumes:
  # ... existing volumes ...
  - /srv/appdata/secondbrain/output:/srv/secondbrain:ro
```

### Step 3.2: Add site blocks to Caddyfile

Add to `/srv/appdata/proxy/Caddyfile`:

```caddyfile
# =============================================================================
# SECOND BRAIN - Internal (full vault, Authentik-protected)
# =============================================================================

brain.lab.unhash.me {
	import cloudflare_tls
	import encode
	import security_headers
	import forward_auth

	root * /srv/secondbrain/internal
	try_files {path} {path}.html {path}/index.html
	file_server

	header Cache-Control "public, max-age=3600"

	handle_errors {
		@404 expression {http.error.status_code} == 404
		rewrite @404 /404.html
		file_server
	}
}

# =============================================================================
# SECOND BRAIN - External public wiki (The Open Mind)
# No auth - content is pre-filtered to publish: public only
# =============================================================================

brain.unhash.me {
	tls {
		dns cloudflare {env.CLOUDFLARE_API_TOKEN}
		resolvers 1.1.1.1 1.0.0.1
	}
	import encode
	import security_headers

	root * /srv/secondbrain/external
	try_files {path} {path}.html {path}/index.html
	file_server

	header Cache-Control "public, max-age=3600"
	header Strict-Transport-Security "max-age=31536000; includeSubDomains"

	handle_errors {
		@404 expression {http.error.status_code} == 404
		rewrite @404 /404.html
		file_server
	}
}

# Syncthing Web UI - protected
sync.lab.unhash.me {
	import cloudflare_tls
	import encode
	import security_headers
	import forward_auth

	reverse_proxy secondbrain-syncthing:8384 {
		transport http {
			tls_insecure_skip_verify
		}
	}
}
```

### Step 3.3: Restart Caddy
```bash
docker compose -f /opt/stacks/proxy/docker-compose.yml restart caddy
```

---

## PHASE 4: CLOUDFLARE TUNNEL CONFIGURATION (MANUAL STEP)

### For brain.lab.unhash.me
Already covered by the `*.lab.unhash.me` wildcard tunnel routing. No action needed.

### For brain.unhash.me (external public site)
In Cloudflare Zero Trust dashboard:
1. Go to Networks → Tunnels → select the main lab tunnel
2. Add a Public Hostname:
   - Subdomain: (blank for bare domain, or "brain" if using brain.unhash.me)
   - Domain: `unhash.me`
   - Service: `http://caddy:80`
3. Ensure the `cloudflared` container can reach Caddy (both accessible via Docker networking)

**Note**: If `cloudflared` is on `tunnel-net` and Caddy is on `core_net`, you may need to add Caddy to `tunnel-net` or configure the tunnel to route to Caddy's `core_net` IP. The simplest fix: add `tunnel-net` to Caddy's networks in the proxy compose file.

---

## PHASE 5: SYNCTHING CONFIGURATION (MANUAL STEP)

After `docker compose up -d syncthing`:

1. Access Syncthing UI at `sync.lab.unhash.me` (after Caddy config applied)
   or temporarily at `http://onyx:8384` (not exposed by default - access via Portainer exec or add a temp port)
2. Add folder: path=/vault, ID=secondbrain-vault, watch=enabled
3. Ignore patterns: `.git`, `.obsidian/workspace*.json`, `.trash`
4. On client devices: install Syncthing, add server as remote device, share `secondbrain-vault` folder
5. Set local path to where Obsidian opens the vault on each device

---

## PHASE 6: AI INTEGRATION

### Claude Code (Direct Access)
Claude Code has native filesystem access to the vault:
- Read: `Read /srv/appdata/secondbrain/vault/concepts/example.md`
- Search: `Grep "pattern" /srv/appdata/secondbrain/vault/`
- Write: `Write /srv/appdata/secondbrain/vault/concepts/new-concept.md`

The vault's `CLAUDE.md` file provides instructions for AI interaction conventions.

### OpenClaw (Qwen 3.5 9B via API)
Configure in `.env`:
```
OPENCLAW_API_URL=http://openclaw:8080/v1
OPENCLAW_API_KEY=your-key
```

n8n workflows call the OpenClaw API for:
- Inbox processing (categorize, tag, suggest links)
- Weekly link suggestions between loosely related notes
- Summarization of source materials

### n8n Workflows (Optional Enhancement)

**Workflow 1: AI Inbox Processor** (schedule: every 10 min)
1. Find files in `/srv/appdata/secondbrain/vault/inbox/`
2. For each file, send content to OpenClaw API
3. Parse response: extract tags, concepts, suggested folder
4. Move file to target folder, update frontmatter
5. Create concept stubs for new `[[wikilinks]]`

**Workflow 2: Weekly Link Suggester** (schedule: Sunday 3 AM)
1. Find notes with < 3 outgoing wikilinks
2. Send to OpenClaw with list of existing concept names
3. Append suggestions to `ai-generated/link-suggestions-YYYY-MM-DD.md`

---

## PHASE 7: DEPLOYMENT SCRIPTS

All scripts in `/opt/stacks/secondbrain/scripts/`:

| Script | Purpose |
|--------|---------|
| `build.sh` | Quartz build with atomic directory swap (runs in builder container) |
| `filter-external.sh` | Filters vault to `publish: public` content for external build |
| `deploy.sh` | Full deploy: pull, backup, build, validate, push |
| `rollback.sh` | Interactive rollback to previous build |
| `backup-vault.sh` | Manual vault backup with GitHub push option |
| `watch.sh` | Change detection loop (runs in vault-watcher container) |

### Deploy flow (mirrors frombottlestobruh resilience pattern)
```
git pull → backup vault → build internal → validate → atomic swap
                        → filter external → build external → validate → atomic swap
                        → prune old builds → push to GitHub
                        ↓ (on failure)
                        → automatic rollback to previous build
```

---

## PHASE 8: VERIFICATION CHECKLIST

Execute in order, verify at each step:

- [ ] Vault structure exists at `/srv/appdata/secondbrain/vault/`
- [ ] Git initialized, pushed to private GitHub repo
- [ ] `docker compose up -d syncthing vault-watcher` starts successfully
- [ ] `docker compose run --rm quartz-builder` builds without errors
- [ ] `/srv/appdata/secondbrain/output/internal/index.html` exists
- [ ] Caddy volume mount added, Caddyfile updated, Caddy restarted
- [ ] `curl -I https://brain.lab.unhash.me` returns 200
- [ ] Authentik forward_auth redirects to login, then serves the site
- [ ] Cloudflare tunnel route added for `brain.unhash.me`
- [ ] `curl -I https://brain.unhash.me` returns 200 (public, no auth)
- [ ] Syncthing UI accessible, vault folder shared
- [ ] Client device syncs a test file to the server
- [ ] Watcher detects the new file and triggers rebuild
- [ ] `./scripts/deploy.sh` completes successfully
- [ ] `./scripts/rollback.sh --list` shows previous builds
- [ ] `./scripts/rollback.sh --previous` restores previous build

---

## NETWORK TOPOLOGY

```
                    Internet
                       |
                 Cloudflare Edge
                       |
              Cloudflare Tunnel
                       |
                  cloudflared (tunnel-net)
                       |
                    Caddy (core_net)
                   /        \
    brain.lab.unhash.me    brain.unhash.me
    (forward_auth)         (public, no auth)
         |                      |
    file_server             file_server
    /srv/secondbrain/       /srv/secondbrain/
    internal/ (symlink)     external/ (symlink)
         |                      |
    builds/internal-*       builds/external-*
         |                      |
    Full vault HTML         Filtered public HTML


    Syncthing (secondbrain-internal + core_net)
    ← peer sync → Desktop/Mobile Obsidian
         |
    /srv/appdata/secondbrain/vault/ (source of truth)
         |
    Git → GitHub (private repo)
```

---

*Revised: March 13, 2026 | For onyx homelab server*
*Replaces original spec: corrected for Caddy (not Nginx), Cloudflare tunnels, OpenClaw AI (not Ollama/Khoj), server conventions*
