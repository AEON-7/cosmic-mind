#!/bin/sh
set -eu

# =============================================================================
# Vault Watcher - Change detection and auto-build trigger
#
# Runs in a lightweight Alpine container. Polls the vault for changes
# using git status. When changes are detected:
#   1. Auto-commits to the local git repo
#   2. Triggers a Quartz build (internal + external)
#
# This replaces inotifywait with simple polling to avoid inotify limits
# and works reliably with Syncthing's sync patterns.
#
# Environment:
#   WATCH_INTERVAL   - Seconds between checks (default: 60)
#   BUILDS_TO_KEEP   - Previous builds to retain (default: 5)
# =============================================================================

VAULT_DIR="/vault"
QUARTZ_DIR="/app/quartz"
OUTPUT_DIR="/output"
STAGING_DIR="/staging"
WATCH_INTERVAL="${WATCH_INTERVAL:-60}"
BUILDS_TO_KEEP="${BUILDS_TO_KEEP:-5}"
LAST_HASH_FILE="/tmp/.last-vault-hash"

apk add --no-cache git nodejs npm bash curl patch > /dev/null 2>&1

# Configure git for auto-commits
git config --global user.email "secondbrain@onyx.local"
git config --global user.name "SecondBrain Watcher"
git config --global --add safe.directory /vault

echo "[WATCHER] Starting vault watcher (interval: ${WATCH_INTERVAL}s)"

# Initialize Quartz engine if needed (first run after volume creation)
if [ ! -f "$QUARTZ_DIR/package.json" ]; then
    echo "[WATCHER] Initializing Quartz engine..."
    cd /tmp
    git clone --depth 1 https://github.com/jackyzha0/quartz.git quartz-init
    cp -a quartz-init/. "$QUARTZ_DIR/"
    rm -rf quartz-init
    cd "$QUARTZ_DIR"
    npm ci
    echo "[WATCHER] Quartz engine initialized"
fi

# Copy configs if not present
[ -f "$QUARTZ_DIR/quartz.config.ts" ] || cp /scripts/../quartz.config.ts "$QUARTZ_DIR/" 2>/dev/null || true
[ -f "$QUARTZ_DIR/quartz.config.external.ts" ] || cp /scripts/../quartz.config.external.ts "$QUARTZ_DIR/" 2>/dev/null || true

# Compute a hash of vault state
vault_hash() {
    cd "$VAULT_DIR"
    # Hash file list + modification times for change detection
    find . -name "*.md" -type f -exec stat -c '%n %Y' {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1
}

# Build function (mirrors build.sh logic but inline for the watcher)
do_build() {
    echo "[WATCHER] Changes detected - starting build at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
    BUILDS_DIR="$OUTPUT_DIR/builds"
    mkdir -p "$BUILDS_DIR"

    cd "$QUARTZ_DIR"

    # --- Internal build ---
    # Swap in branded OG image for internal site
    [ -f /static-assets/og-image-internal.png ] && cp /static-assets/og-image-internal.png "$QUARTZ_DIR/quartz/static/og-image.png"

    rm -rf content
    ln -s "$VAULT_DIR" content

    INTERNAL_BUILD_DIR="$BUILDS_DIR/internal-$TIMESTAMP"
    mkdir -p "$INTERNAL_BUILD_DIR"

    if node --no-deprecation /app/quartz/quartz/bootstrap-cli.mjs build --output "$INTERNAL_BUILD_DIR" 2>&1; then
        if [ -f "$INTERNAL_BUILD_DIR/index.html" ]; then
            # Symlink swap (relative path)
            ln -sfn "builds/$(basename "$INTERNAL_BUILD_DIR")" "$OUTPUT_DIR/internal"
            echo "[WATCHER] Internal site rebuilt successfully"
        else
            echo "[WATCHER] ERROR: Internal build produced no index.html"
            rm -rf "$INTERNAL_BUILD_DIR"
        fi
    else
        echo "[WATCHER] ERROR: Internal Quartz build failed"
        rm -rf "$INTERNAL_BUILD_DIR"
    fi

    # --- External build (filtered) ---
    /scripts/filter-external.sh 2>/dev/null || /bin/bash /scripts/filter-external.sh

    external_count=$(find "$STAGING_DIR" -name "*.md" -type f 2>/dev/null | wc -l)
    if [ "$external_count" -gt 0 ]; then
        rm -rf content
        ln -s "$STAGING_DIR" content

        # Swap in branded OG image for external site
        [ -f /static-assets/og-image-external.png ] && cp /static-assets/og-image-external.png "$QUARTZ_DIR/quartz/static/og-image.png"

        # Swap to external config for build
        cp quartz.config.ts quartz.config.ts.bak
        cp quartz.config.external.ts quartz.config.ts

        EXTERNAL_BUILD_DIR="$BUILDS_DIR/external-$TIMESTAMP"
        mkdir -p "$EXTERNAL_BUILD_DIR"

        if node --no-deprecation /app/quartz/quartz/bootstrap-cli.mjs build --output "$EXTERNAL_BUILD_DIR" 2>&1; then
            if [ -f "$EXTERNAL_BUILD_DIR/index.html" ]; then
                ln -sfn "builds/$(basename "$EXTERNAL_BUILD_DIR")" "$OUTPUT_DIR/external"
                echo "[WATCHER] External site rebuilt successfully"
            else
                rm -rf "$EXTERNAL_BUILD_DIR"
            fi
        else
            rm -rf "$EXTERNAL_BUILD_DIR"
        fi

        # Restore internal config and content link
        [ -f quartz.config.ts.bak ] && mv quartz.config.ts.bak quartz.config.ts || true
        rm -rf content
        ln -s "$VAULT_DIR" content
    fi

    # Prune old builds
    for prefix in internal external; do
        old_builds=$(find "$BUILDS_DIR" -maxdepth 1 -type d -name "${prefix}-*" 2>/dev/null | sort | head -n -"$BUILDS_TO_KEEP" || true)
        for old_dir in $old_builds; do
            echo "[WATCHER] Pruning old build: $(basename "$old_dir")"
            rm -rf "$old_dir"
        done
    done

    echo "[WATCHER] Build complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Auto-commit changes
auto_commit() {
    cd "$VAULT_DIR"
    if [ -d .git ]; then
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            git add -A
            git commit -m "auto: vault update $(date -u +%Y-%m-%dT%H:%M:%SZ)" --allow-empty-message 2>/dev/null || true
            echo "[WATCHER] Auto-committed vault changes"
        fi
    fi
}

# Initial hash
echo "initial" > "$LAST_HASH_FILE"

# Initial build on startup (if vault has content)
md_count=$(find "$VAULT_DIR" -name "*.md" -type f | wc -l)
if [ "$md_count" -gt 0 ]; then
    echo "[WATCHER] Running initial build ($md_count files in vault)..."
    auto_commit
    do_build
    vault_hash > "$LAST_HASH_FILE"
fi

# Main loop
while true; do
    sleep "$WATCH_INTERVAL"

    current_hash=$(vault_hash)
    last_hash=$(cat "$LAST_HASH_FILE")

    if [ "$current_hash" != "$last_hash" ]; then
        auto_commit
        do_build
        echo "$current_hash" > "$LAST_HASH_FILE"
    fi
done
