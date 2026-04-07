# Dockerfile.doc-researcher — POC Fase 1 RLS (D-019, D-021, D-022)
# Hardening 4.4 (sandboxing per-agente). Design C: il container NON parla con
# Bitwarden — il launcher sull'host inietta DB_PASSWORD via env.
FROM node:20-bookworm-slim

# Tools: psql client, python3 (smoke + tooling), ca-certs
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates postgresql-client python3 \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI (npm global)
RUN npm install -g @anthropic-ai/claude-code

# Non-root user — reuse the stock `node` user (uid 1000) shipped by node:20-bookworm-slim
RUN mkdir -p /work /runtime \
    && chown -R node:node /work /runtime

WORKDIR /work

# Runtime dir is tmpfs-mounted to keep secrets off disk
ENV RUNTIME_DIR=/runtime

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh
USER node
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
