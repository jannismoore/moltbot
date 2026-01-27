FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

CMD ["sh", "-c", "if [ -z \"${CLAWDBOT_GATEWAY_TOKEN:-}\" ]; then CLAWDBOT_GATEWAY_TOKEN=$(node -e \"console.log(require('node:crypto').randomBytes(32).toString('hex'))\"); export CLAWDBOT_GATEWAY_TOKEN; echo \"[moltbot] Generated gateway token: ${CLAWDBOT_GATEWAY_TOKEN}\"; fi; if [ -z \"${NODE_OPTIONS:-}\" ]; then export NODE_OPTIONS=\"--max-old-space-size=${CLAWDBOT_NODE_HEAP_MB:-448}\"; fi; node dist/entry.js gateway --allow-unconfigured --bind lan --port ${PORT:-18789}"]
