#!/bin/bash
set -euo pipefail

# =============================================================================
# Quartz Build Script - Atomic Directory Swap
#
# Builds internal and external Quartz sites with zero-downtime deployment.
# Uses timestamped build directories and atomic symlink swaps.
#
# Environment:
#   INTERNAL_DOMAIN  - Base URL for internal site (default: brain.lab.unhash.me)
#   EXTERNAL_DOMAIN  - Base URL for external site (default: brain.unhash.me)
#   BUILDS_TO_KEEP   - Number of previous builds to retain (default: 5)
#
# Volumes:
#   /vault    - Source vault (read-only)
#   /output   - Build output directory
#   /staging  - Filtered content staging for external build
# =============================================================================

QUARTZ_DIR="/app/quartz"
VAULT_DIR="/vault"
OUTPUT_DIR="/output"
STAGING_DIR="/staging"
BUILDS_DIR="/output/builds"
BUILDS_TO_KEEP="${BUILDS_TO_KEEP:-5}"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[BUILD]${NC} $1"; }
log_success() { echo -e "${GREEN}[BUILD]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[BUILD]${NC} $1"; }
log_error()   { echo -e "${RED}[BUILD]${NC} $1"; }

# Validate vault has content
validate_vault() {
    local md_count
    md_count=$(find "$VAULT_DIR" -name "*.md" -type f | wc -l)
    if [ "$md_count" -eq 0 ]; then
        log_error "Vault is empty - no .md files found in $VAULT_DIR"
        exit 1
    fi
    log_info "Vault contains $md_count markdown files"
}

# Validate a build output directory
validate_build() {
    local build_dir="$1"
    local site_name="$2"

    if [ ! -f "$build_dir/index.html" ]; then
        log_error "$site_name build failed: no index.html generated"
        return 1
    fi

    local html_count
    html_count=$(find "$build_dir" -name "*.html" -type f | wc -l)
    if [ "$html_count" -lt 2 ]; then
        log_error "$site_name build suspect: only $html_count HTML files generated"
        return 1
    fi

    local build_size
    build_size=$(du -sh "$build_dir" | cut -f1)
    log_success "$site_name build valid: $html_count pages, $build_size total"
    return 0
}

# Atomic symlink swap - the key to zero-downtime deployment
# Uses relative paths so symlinks work from both host and container
atomic_swap() {
    local target="$1"
    local link_name="$2"

    # Use relative path (builds/ subdir relative to output/)
    local rel_target="builds/$(basename "$target")"

    # Create a temporary link, then atomically rename it over the real one
    local tmp_link="${link_name}.tmp.$$"
    ln -sfn "$rel_target" "$tmp_link"
    mv -Tf "$tmp_link" "$link_name"

    log_success "Swapped $(basename "$link_name") -> $rel_target"
}

# Prune old builds, keeping the N most recent
prune_old_builds() {
    local prefix="$1"
    local keep="$2"

    local current_target=""
    if [ -L "$OUTPUT_DIR/$prefix" ]; then
        current_target=$(readlink -f "$OUTPUT_DIR/$prefix" 2>/dev/null || echo "")
    fi

    # List build dirs matching the prefix, sorted oldest first
    local old_builds
    old_builds=$(find "$BUILDS_DIR" -maxdepth 1 -type d -name "${prefix}-*" | sort | head -n -"$keep" || true)

    for old_dir in $old_builds; do
        # Never delete the currently active build
        if [ "$(readlink -f "$old_dir")" = "$current_target" ]; then
            continue
        fi
        log_info "Pruning old build: $(basename "$old_dir")"
        rm -rf "$old_dir"
    done
}

# =========================================================================
# Main Build Process
# =========================================================================

log_info "=== Second Brain Build - $TIMESTAMP ==="

validate_vault

mkdir -p "$BUILDS_DIR"

# --- Internal Build (full vault) ---
log_info "--- Building Internal Site ---"

INTERNAL_BUILD_DIR="$BUILDS_DIR/internal-$TIMESTAMP"
mkdir -p "$INTERNAL_BUILD_DIR"

cd "$QUARTZ_DIR"

# Link vault as Quartz content
rm -rf content
ln -s "$VAULT_DIR" content

# Build internal site
if node --no-deprecation /app/quartz/quartz/bootstrap-cli.mjs build --output "$INTERNAL_BUILD_DIR" 2>&1; then
    if validate_build "$INTERNAL_BUILD_DIR" "Internal"; then
        atomic_swap "$INTERNAL_BUILD_DIR" "$OUTPUT_DIR/internal"
        log_success "Internal site deployed"
    else
        log_error "Internal build validation failed - keeping previous version"
        rm -rf "$INTERNAL_BUILD_DIR"
        INTERNAL_FAILED=true
    fi
else
    log_error "Internal Quartz build failed"
    rm -rf "$INTERNAL_BUILD_DIR"
    INTERNAL_FAILED=true
fi

# --- External Build (filtered vault) ---
log_info "--- Building External Site ---"

# Filter vault content for public publishing
/app/filter-external.sh

EXTERNAL_MD_COUNT=$(find "$STAGING_DIR" -name "*.md" -type f | wc -l)
if [ "$EXTERNAL_MD_COUNT" -eq 0 ]; then
    log_warn "No files marked publish: public - skipping external build"
else
    EXTERNAL_BUILD_DIR="$BUILDS_DIR/external-$TIMESTAMP"
    mkdir -p "$EXTERNAL_BUILD_DIR"

    # Switch content to staging directory
    rm -rf content
    ln -s "$STAGING_DIR" content

    # Swap to external config for build, then restore
    cp quartz.config.ts quartz.config.ts.bak
    cp quartz.config.external.ts quartz.config.ts
    if node --no-deprecation /app/quartz/quartz/bootstrap-cli.mjs build --output "$EXTERNAL_BUILD_DIR" 2>&1; then
        if validate_build "$EXTERNAL_BUILD_DIR" "External"; then
            atomic_swap "$EXTERNAL_BUILD_DIR" "$OUTPUT_DIR/external"
            log_success "External site deployed"
        else
            log_error "External build validation failed - keeping previous version"
            rm -rf "$EXTERNAL_BUILD_DIR"
        fi
    else
        log_error "External Quartz build failed"
        rm -rf "$EXTERNAL_BUILD_DIR"
    fi

    # Ensure config is always restored even on failure paths above
    [ -f quartz.config.ts.bak ] && mv quartz.config.ts.bak quartz.config.ts || true

    # Restore content link to vault
    rm -rf content
    ln -s "$VAULT_DIR" content
fi

# --- Cleanup ---
prune_old_builds "internal" "$BUILDS_TO_KEEP"
prune_old_builds "external" "$BUILDS_TO_KEEP"

if [ "${INTERNAL_FAILED:-false}" = true ]; then
    log_error "Build completed with errors - internal site was NOT updated"
    exit 1
fi

log_success "=== Build complete - $TIMESTAMP ==="
