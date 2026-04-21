# docs/claude/ — Índice

Documentação canônica do setup Claude Code em Spellbook-OS. Todos os arquivos aqui são versionados no repo `~/.config/zsh` e espelhados via symlink em `~/.claude/`.

## Índice de leitura

| Arquivo | Quando ler |
|---|---|
| [`SETUP.md`](./SETUP.md) | Ponto de entrada. Visão geral + fluxo end-to-end. |
| [`AGENTS.md`](./AGENTS.md) | Entender os 3 subagents opus (planejador/executor/validador) |
| [`HOOKS.md`](./HOOKS.md) | Debug de hooks (guardian, session-start-briefing, post-plan-clear, plugins) |
| [`CAPACIDADES-VISUAIS.md`](./CAPACIDADES-VISUAIS.md) | Screenshot / validação visual (CLI + claude-in-chrome + playwright) |
| [`SPRINT-WORKFLOW.md`](./SPRINT-WORKFLOW.md) | Ciclo automático, 3-retry, anti-débito, auto-commit/push/PR |
| [`PADROES-VALIDADOR.md`](./PADROES-VALIDADOR.md) | 14 lições empíricas — o que o validador sempre pega |
| [`MEMORIA.md`](./MEMORIA.md) | Como auto-memory funciona em `~/.claude/projects/*/memory/` |
| [`PLUGINS.md`](./PLUGINS.md) | Catálogo dos 12 plugins oficiais |
| [`SETTINGS.md`](./SETTINGS.md) | Organização settings.json vs local + regras de higiene |
| [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) | MCP deferred, Chrome pairing, cold start |
| [`BRIEF-POR-PROJETO.md`](./BRIEF-POR-PROJETO.md) | Catálogo de VALIDATOR_BRIEF.md ativos |
| [`SPECIAL_PROJECTS.json`](./SPECIAL_PROJECTS.json) | Mapa canônico Luna/Nyx/ouroboros (lido por hook + script) |
| [`VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md`](./VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md) | Template base de BRIEF por projeto |

## Subdiretórios

| Path | Conteúdo |
|---|---|
| `agents/` | 3 subagents opus (validador-sprint.md, executor-sprint.md, planejador-sprint.md) |
| `commands/` | 5 slash commands (planejar / executar / validar / sprint-ciclo / sprint-ciclo-manual) |
| `skills/validacao-visual/` | Skill customizada de captura e validação visual |
| `templates/` | 4 bootstraps (genérico, luna, nyx-code, ouroboros) |
| `hooks/` | 3 hooks (guardian, session-start-briefing, post-plan-clear) |
| `scripts/` | bootstrap-rico-brief.py |

## Convenções

- Tudo em PT-BR direto, sem emojis, acentuação obrigatória.
- Paths absolutos sempre que referenciar outro arquivo.
- Arquivos são origem canônica; symlinks em `~/.claude/` apontam para cá.
- Autosync do Spellbook-OS captura mudanças automaticamente no `zshexit`.
