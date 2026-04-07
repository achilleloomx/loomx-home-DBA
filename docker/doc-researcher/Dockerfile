# Dockerfile.doc-researcher — POC Fase 1 RLS (D-019, D-021)
# Hardening 4.4 (sandboxing per-agente). bw EU vault (D-014).
FROM node:20-bookworm-slim

ARG BW_VERSION=2024.10.0

# Tools: psql client, python (smoke tests), bw CLI, curl/unzip, ca-certs, gosu
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip jq postgresql-client python3 python3-pip gosu \
    && rm -rf /var/lib/apt/lists/*

# Bitwarden CLI (linux x64 binary)
RUN curl -fsSL -o /tmp/bw.zip "https://github.com/bitwarden/clients/releases/download/cli-v${BW_VERSION}/bw-linux-${BW_VERSION}.zip" \
    && unzip /tmp/bw.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/bw \
    && rm /tmp/bw.zip

# Claude Code CLI (npm global)
RUN npm install -g @anthropic-ai/claude-code

# Non-root user — reuse the stock `node` user (uid 1000) shipped by node:20-bookworm-slim
RUN mkdir -p /work /runtime \
    && chown -R node:node /work /runtime

WORKDIR /work

# Runtime dir is tmpfs-mounted to keep secrets off disk
ENV RUNTIME_DIR=/runtime \
    BW_NOINTERACTION=true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh
USER node
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
