# Quartz v4 Builder
# Builds static HTML from an Obsidian vault using Quartz v4.
# Designed as an ephemeral build container: run, build, exit.
#
# Usage: docker compose run --rm quartz-builder
# Or from vault-watcher for automated builds.

FROM node:22-alpine AS builder

RUN apk add --no-cache git bash curl

WORKDIR /app

# Clone Quartz v4 from our customized fork (cosmic-mind branch)
# All UI customizations are proper commits — no runtime patching needed
RUN git clone --depth 1 --branch cosmic-mind https://github.com/AEON-7/quartz.git quartz \
    && cd quartz \
    && npm ci

# Copy build configs and scripts
COPY quartz.config.ts /app/quartz/quartz.config.ts
COPY quartz.config.external.ts /app/quartz/quartz.config.external.ts
COPY scripts/build.sh /app/build.sh
COPY scripts/filter-external.sh /app/filter-external.sh
RUN chmod +x /app/build.sh /app/filter-external.sh

ENTRYPOINT ["/app/build.sh"]
