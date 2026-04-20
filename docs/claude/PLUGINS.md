# Plugins Claude Code instalados

> Referência rápida dos 8 plugins ativos neste setup. Atualize quando adicionar/remover plugin em `plugins/config.json`.

| Plugin | Função | Quando invocar |
|---|---|---|
| `commit-commands` | Helpers de commit (git + PR) | `/commit`, `/commit-push-pr`, `/clean_gone` |
| `learning-output-style` | Modo de aprendizado interativo | Já ativo como output style; explica decisões enquanto codifica |
| `frontend-design` | UI production-grade, evita estética genérica de IA | Componentes/páginas novas, dashboards, landing pages |
| `code-review` | Review estruturada de PR | `/code-review` após commits; skill também acessível via Skill tool |
| `playwright` | Automação de browser (Chromium) | Testes E2E, scraping, validação visual de UI |
| `superpowers` | Skills de workflow (TDD, planning, debugging, brainstorming, code review, etc.) | Auto-ativa conforme contexto; `/using-superpowers` pra manual |
| `context7` | Docs atualizadas de libs/frameworks | Antes de codar contra lib externa (React, Prisma, Next, etc.) |
| `feature-dev` | Dev guiada de features com análise de codebase | Features grandes com múltiplos arquivos, refactors amplos |

## Skills do superpowers mais úteis no dia-a-dia

| Skill | Uso |
|---|---|
| `superpowers:brainstorming` | Antes de qualquer criação (features, componentes). Explora intenção antes de codar |
| `superpowers:writing-plans` | Tarefa multi-step com spec clara, antes de tocar código |
| `superpowers:executing-plans` | Executar plano escrito com checkpoints de review |
| `superpowers:test-driven-development` | Implementar feature/bugfix — escreve teste RED primeiro |
| `superpowers:systematic-debugging` | Bug, falha de teste, comportamento inesperado |
| `superpowers:verification-before-completion` | Antes de claim "pronto/passando/corrigido" |
| `superpowers:requesting-code-review` | Completar tarefa; obter review antes de merge |
| `superpowers:dispatching-parallel-agents` | 2+ tarefas independentes sem estado compartilhado |
| `superpowers:using-git-worktrees` | Feature que precisa isolamento do workspace atual |

## Custom (não-plugin)

### Agentes

| Agente | Path | Função |
|---|---|---|
| `planejador-sprint` | `~/.claude/agents/planejador-sprint.md` | Opus. Redige spec de sprint a partir de ideia/bug/requisito |
| `executor-sprint` | `~/.claude/agents/executor-sprint.md` | Opus. Implementa sprint com proof-of-work rigoroso; respeita touches autorizados e protocolo anti-débito |
| `validador-sprint` | `~/.claude/agents/validador-sprint.md` | Opus. Valida sprint com rigor; auto-inicializa `VALIDATOR_BRIEF.md` no primeiro uso; enriquece BRIEF com padrões novos |

### Slash Commands

| Command | Função |
|---|---|
| `/planejar-sprint <ideia>` | Dispatcha planejador-sprint |
| `/executar-sprint [spec]` | Dispatcha executor-sprint com spec aprovado |
| `/validar-sprint [plano]` | Dispatcha validador-sprint com diff + proof-of-work |
| `/sprint-ciclo <ideia>` | Fluxo completo plan→execute→validate com checkpoints de aprovação |

### Hooks

| Hook | Evento | Ação |
|---|---|---|
| `~/.claude/hooks/guardian.py` | PreToolUse (Write/Edit/MultiEdit) | Bloqueia emojis e atribuições explícitas a IA (regras CLAUDE.md #2 e #3) |

### Templates e suporte

| Recurso | Path |
|---|---|
| Templates bootstrap | `~/.claude/templates/bootstrap-{generico,luna,nyx-code,ouroboros}.md` |
| Statusline | `~/.claude/statusline.sh` |
| Keybindings | `~/.claude/keybindings.json` |

## Hooks de plugins (auto-ativos)

Hooks definidos em `plugin/hooks/hooks.json` de cada plugin são **auto-carregados** quando o plugin está em `settings.json → enabledPlugins`. Não precisa registrar em `settings.json → hooks` separadamente.

Seus plugins ativos têm:

| Plugin | Hook ativo | Evento |
|---|---|---|
| `superpowers` | `run-hook.cmd session-start` | SessionStart (startup, clear, compact) |
| `learning-output-style` | (próprio) | SessionStart |

Os demais (commit-commands, frontend-design, code-review, playwright, context7, feature-dev) não registram hooks.

## Plugins disponíveis no marketplace oficial (não instalados)

Vale avaliar conforme necessidade:

| Plugin | Valor para seu workflow |
|---|---|
| `skill-creator` | Ajuda a criar skills custom (ex.: evoluir `validador-sprint` pra skill completa) |
| `hookify` | Criar hooks custom via arquivos `.local.md` sem editar `settings.json` |
| `security-guidance` | Hook `PreToolUse` em Edit/Write/MultiEdit — avisa sobre secrets/vulnerabilidades |
| `claude-code-setup` | Inclui `claude-automation-recommender` — analisa padrões e sugere automações |
| `claude-md-management` | Gestão estruturada de `CLAUDE.md` (seu é symlink pra AI.md — talvez skip) |
| `code-simplifier` | Skill pra simplificar código (o `simplify` core já cobre o básico) |
| `ralph-loop` | Self-referential loops (específico, provavelmente skip) |
| `explanatory-output-style` | Output style alternativo ao `learning` (já usa learning) |
| `mcp-server-dev` | Se for construir MCP servers próprios |
| `agent-sdk-dev` | Se for construir com Agent SDK |

## Instalar / remover plugins

- Listar instalados: `cat ~/.claude/plugins/installed_plugins.json`
- Listar marketplace: `ls ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/`
- Path raiz: `~/.claude/plugins/`
- Comando: `/plugin install <nome>` ou via settings
