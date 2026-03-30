-- Migration: register agent board-mcp
-- Date: 2026-03-30

INSERT INTO board_agents (agent_code, slug, label, nickname, scope, repo)
VALUES ('005', 'board-mcp', 'Board MCP Server — LoomX Home', NULL, 'Server MCP per comunicazione inter-agente sul board', 'loomx-board-mcp');
