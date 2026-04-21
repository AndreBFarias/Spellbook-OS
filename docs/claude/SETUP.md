# Claude Code Setup — Spellbook-OS v2

Documentação canônica do setup Claude Code em `~/.config/zsh` (Spellbook-OS). Substitui o antigo `CLAUDE_SETUP.md` e incorpora a arquitetura v2 (docs versionadas em `docs/claude/`, symlinks, hooks de boot capacitado, ciclo de sprint automático).

## Visão geral

O Claude Code (CLI v2.1.114) foi estruturado ao redor do ciclo de sprint:

```
planejar -> executar -> validar
```

Cada etapa é um subagente Opus separado. A memória do validador vive em disco (`VALIDATOR_BRIEF.md` na raiz de cada repo), eliminando contexto volátil de sessão. Todo o ambiente dispara automaticamente via `santuario` + `cca` + hooks. Zero flags, zero comandos extras.

## Arquitetura v2

```
~/.config/zsh/docs/claude/        (origem canônica, versionada)
  agents/*.md                     (3 subagents opus)
  commands/*.md                   (4 slash commands)
  skills/validacao-visual/SKILL.md
  templates/bootstrap-*.md        (4 templates de projeto)
  hooks/*.py                      (guardian + session-start-briefing + post-plan-clear)
  scripts/                        (bootstrap-rico-brief.py)
  [docs navegáveis]               (este SETUP.md + AGENTS.md + HOOKS.md + ...)

~/.claude/                        (consumidor pelo Claude Code)
  agents/*.md       -> symlink    (para docs/claude/agents/)
  commands/*.md     -> symlink
  skills/           -> symlink
  templates/*.md    -> symlink
  hooks/*.py        -> symlink
  PLUGINS.md        -> symlink
  SETTINGS.md       -> symlink
  CLAUDE.md         -> symlink    (para ~/.config/zsh/AI.md)

~/.config/zsh/                    (scripts e integração shell)
  functions/sprint.zsh            (dispatcher sprint <sub>)
  functions/projeto.zsh           (santuario chama doctor_quick)
  cca/aliases_cca.zsh             (cca wrapper + exports CLAUDE_*)
  cca/aliases_sprint.zsh          (aliases curtos)
  scripts/bootstrap-rico-brief.py
  AI.md                           (CLAUDE.md global - Protocolo Universal v4.0)
```

## Componentes

### 1. Agents (em `docs/claude/agents/`)

| Agent | Modelo | Tools | Responsabilidade |
|---|---|---|---|
| `planejador-sprint` | opus | Read, Grep, Glob, Bash, Write | Recebe ideia, explora codebase, redige spec com acceptance + touches + proof-of-work esperado |
| `executor-sprint` | opus | Read, Grep, Glob, Bash, Write, Edit, MultiEdit, Skill | Lê BRIEF, valida hipótese via grep, valida aritmética de refactor, implementa, gera proof-of-work runtime-real, varre acentuação periférica |
| `validador-sprint` | opus | Read, Grep, Glob, Bash, Write, Edit | 3 modos (BOOTSTRAP genérico, BOOTSTRAP_RICO para projetos conhecidos, VALIDATE). Aplica 14 checks universais, emite veredicto com Edit-pronto ou sprint-ID |

Catálogo completo: [`AGENTS.md`](./AGENTS.md).

### 2. Slash commands (em `docs/claude/commands/`)

| Command | Propósito |
|---|---|
| `/planejar-sprint <ideia>` | Dispatcha `planejador-sprint` |
| `/executar-sprint [spec]` | Dispatcha `executor-sprint` |
| `/validar-sprint [plano]` | Dispatcha `validador-sprint` |
| `/sprint-ciclo <ideia>` | Ciclo automático (plan->exec->val) sem checkpoints; 3-retry; auto-commit/push/PR ao APROVADO |
| `/sprint-ciclo-manual <ideia>` | Opt-in: ciclo com checkpoints de aprovação entre fases |

### 3. Skill customizada (em `docs/claude/skills/`)

- `validacao-visual` — pipeline 3-tentativas (scrot/import -> claude-in-chrome MCP -> playwright MCP) para capturar evidência visual quando sprint toca UI/TUI/Web. Critério de sucesso: PNG + sha256 + descrição multimodal. Fallback "impossível" só aceito após 3 tentativas documentadas.

### 4. Templates de bootstrap (em `docs/claude/templates/`)

Prompts + estrutura para gerar `VALIDATOR_BRIEF.md` rico:

- `bootstrap-generico.md` — universal, com 14 checks
- `bootstrap-luna.md` — 15 armadilhas Luna + ADR-018 + modelos Ollama + TUI Textual
- `bootstrap-nyx-code.md` — 34 tools + 47 commands + ADRs 013/014 + check #13
- `bootstrap-ouroboros.md` — fases ALFA->ZETA + supervisor artesanal + SQLite

### 5. Hooks (em `docs/claude/hooks/`)

| Hook | Tipo | Propósito |
|---|---|---|
| `guardian.py` | PreToolUse(Write\|Edit\|MultiEdit) | Bloqueia emoji e atribuição a IA |
| `session-start-briefing.py` | SessionStart(*) | Coração do "boot capacitado" — injeta additionalContext + auto-dispatch BRIEF se ausente |
| `post-plan-clear.py` | UserPromptSubmit(*) | Sugere /clear após aprovação de plan (sutil, não força) |

Detalhes: [`HOOKS.md`](./HOOKS.md).

### 6. Statusline (em `~/.claude/statusline.sh`)

Formato: `projeto | branch | modelo | $custo | brief:NL | cca:Nreq`.

### 7. Integração shell

#### `santuario <projeto>` (em `functions/projeto.zsh`)

Entra no projeto, resolve venv/git/gh, roda `__sprint_doctor_quick` (silencioso se OK), detecta BRIEF (status only).

#### `cca` (em `cca/aliases_cca.zsh`)

Wrapper do `claude --dangerously-skip-permissions`:
1. `cca_guard.sh before` — warm sudo + pré-check quota.
2. **EXPORT variáveis** novas: `CLAUDE_PROJECT_ROOT`, `CLAUDE_PROJECT_NAME`, `CLAUDE_BRIEF_PATH`, `CLAUDE_BRIEF_STATUS`, `CLAUDE_PROJECT_KIND`, `CLAUDE_SANTUARIO_READY`, `CLAUDE_VISUAL_TOOLS_EXPECTED`, `CLAUDE_SPRINT_CICLO_MAX_RETRIES`.
3. `exec claude --dangerously-skip-permissions "$@"`.
4. `unset` das variáveis após saída.
5. `cca_guard.sh after` — registra tokens estimados.

#### `sprint <sub>` dispatcher (em `functions/sprint.zsh`)

| Sub | Expande para |
|---|---|
| `sprint plan <ideia>` | `cca "/planejar-sprint <ideia>"` |
| `sprint exec [spec]` | `cca "/executar-sprint [spec]"` |
| `sprint val [plano]` | `cca "/validar-sprint [plano]"` |
| `sprint ciclo <ideia>` | `cca "/sprint-ciclo <ideia>"` |
| `sprint brief` | status do VALIDATOR_BRIEF.md |
| `sprint brief-edit` | abre BRIEF no $EDITOR |
| `sprint bootstrap [--rich]` | copia template ou dispara `bootstrap-rico-brief.py` |
| `sprint doctor` | health check completo (14 lições + setup) |

Aliases curtos: `splan sexec sval sciclo sciclom sbrief sbedit sboot sbr sdoc`.

## Fluxo end-to-end

```
[zsh] santuario Luna
   -> venv + git + emoji_guardian
   -> __sprint_doctor_quick (silencioso)
   -> detecta BRIEF (status)

[zsh] cca
   -> cca_guard.sh before
   -> export CLAUDE_PROJECT_ROOT + CLAUDE_BRIEF_PATH + CLAUDE_PROJECT_KIND ...
   -> claude --dangerously-skip-permissions

[Claude Code] SessionStart hooks (paralelos):
   -> superpowers/run-hook.cmd (plugin)
   -> learning-output-style/session-start.sh (plugin)
   -> session-start-briefing.py (custom, injeta additionalContext):
        [SANTUÁRIO READY] projeto, BRIEF status, branch, modelo
        [PROJETO ESPECIAL] regras específicas se Luna/Nyx/ouroboros
        [CAPACIDADES VISUAIS] CLI + MCPs + queries ToolSearch
        [SPRINT CICLO] auto com 3-retry + auto-commit/push/PR
        [AÇÃO AUTOMÁTICA] se BRIEF ausente: dispatch validador BOOTSTRAP

[Claude Code] sessão pronta. Primeiro prompt já tem conhecimento completo.

[Claude Code] UserPromptSubmit hook:
   -> post-plan-clear.py (sugere /clear se detecta aprovação plan)

Ciclo /sprint-ciclo:
   planejador-sprint (subagent opus, contexto isolado)
      -> gera spec
   executor-sprint (subagent opus, contexto isolado)
      -> lê BRIEF, verifica hipótese via rg, valida aritmética,
         implementa, proof-of-work runtime-real, varre acentuação
   validador-sprint (subagent opus, contexto isolado)
      -> 14 checks + skill validacao-visual se UI
      -> veredicto APROVADO / APROVADO_COM_RESSALVAS / REPROVADO
   Se REPROVADO: auto-dispatch executor com patch-brief (até 3 iterações)
   Se APROVADO: dispatch /commit-push-pr (auto)
```

## Workflow típico

### Primeiro acesso a um projeto novo

```bash
cd ~/Desenvolvimento/repo-novo
santuario repo-novo
cca
# Hook SessionStart detecta BRIEF ausente e projeto genérico ->
# dispatcha validador em MODO BOOTSTRAP automaticamente.
# Após exploração exaustiva, VALIDATOR_BRIEF.md é criado.
```

### Primeiro acesso aos 3 projetos conhecidos

```bash
cd ~/Desenvolvimento/Luna
santuario Luna
cca
# Hook detecta kind=luna + memórias existentes ->
# dispatcha bootstrap-rico-brief.py (lê 65 memórias históricas) ->
# VALIDATOR_BRIEF.md rico gerado na primeira abertura.
```

### Ciclo de sprint rotineiro

```bash
santuario Luna
cca "/sprint-ciclo adicionar gauge de VRAM na TUI"
# Planejador gera spec -> Executor implementa -> Validador veredicta
# Se APROVADO: auto-commit + auto-push + auto-PR
# Se REPROVADO: 3 iterações automáticas
```

### Validação sem ciclo

```bash
# Após implementar manualmente:
sval
```

## Settings

### `~/.claude/settings.json` (global)

- 12 plugins ativos (commit-commands, learning-output-style, frontend-design, code-review, playwright, superpowers, context7, feature-dev, skill-creator, security-guidance, hookify, claude-code-setup).
- `language`: Português Brasileiro
- `effortLevel`: high
- `defaultMode`: acceptEdits
- `skipDangerousModePermissionPrompt`: true
- `statusLine`: `~/.claude/statusline.sh`
- `hooks.SessionStart`: `session-start-briefing.py` (timeout 10s)
- `hooks.UserPromptSubmit`: `post-plan-clear.py` (timeout 5s)
- `hooks.PreToolUse`: `guardian.py` matcher `Write|Edit|MultiEdit` (timeout 5s)
- `permissions.allow` (ampliada v2): + `Bash(scrot:*)`, `Bash(import:*)`, `Bash(xdotool:*)`, `Bash(wmctrl:*)`, `Bash(ffmpeg:*)`, `Bash(xclip:*)`, `Bash(xsel:*)`, `Bash(sha256sum:*)`, `Bash(python3 /home/andrefarias/.config/zsh/scripts/*)`.

### `~/.claude/settings.local.json` (local, não-versionado)

Permissões diárias: git, cp/rm/mv/rsync/mkdir, Luna venvs.

## Health check

```bash
sprint doctor
```

Verifica:
- 3 agents em `~/.claude/agents/` (via symlink)
- 4 commands + 1 manual em `~/.claude/commands/`
- Templates: 4 arquivos
- Hooks: guardian.py + session-start-briefing.py + post-plan-clear.py
- `cca` e `santuario` carregados
- `settings.json` válido
- 14 lições ativas (verificação das flags no validador/executor)

## Memória persistente

`~/.claude/projects/-home-andrefarias/memory/` — MEMORY.md + feedbacks + projects + references.

Por projeto: `~/.claude/projects/-home-andrefarias-Desenvolvimento-<Nome>/memory/` — memórias específicas daquele workspace.

Detalhes: [`MEMORIA.md`](./MEMORIA.md).

## Docs relacionadas

- [`AGENTS.md`](./AGENTS.md) — catálogo detalhado dos 3 subagents
- [`HOOKS.md`](./HOOKS.md) — todos os hooks (custom + plugins)
- [`CAPACIDADES-VISUAIS.md`](./CAPACIDADES-VISUAIS.md) — browser MCPs + CLI X11 + pipeline 3-tentativas
- [`SPRINT-WORKFLOW.md`](./SPRINT-WORKFLOW.md) — ciclo automático detalhado + 3-retry + anti-débito
- [`PADROES-VALIDADOR.md`](./PADROES-VALIDADOR.md) — as 14 lições empíricas
- [`MEMORIA.md`](./MEMORIA.md) — sistema de auto-memory
- [`PLUGINS.md`](./PLUGINS.md) — 12 plugins oficiais
- [`SETTINGS.md`](./SETTINGS.md) — organização settings.json vs local
- [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) — problemas conhecidos e workarounds
- [`BRIEF-POR-PROJETO.md`](./BRIEF-POR-PROJETO.md) — catálogo de BRIEFs ativos

## Manutenção

- Adicionar permissão após prompt repetido: `~/.claude/settings.local.json`.
- Atualizar BRIEF manualmente: `sbedit`.
- Ativar modo manual do ciclo: `sciclom` (usa `sprint-ciclo-manual`).
- Health check: `sdoc`.
- Plugin novo: `/plugin install <nome>` ou editar `enabledPlugins`.
- Atualizar Claude Code: `claude update`.

## Versão e referências

- Claude Code: **2.1.114** (latest estável). `stable: 2.1.98`, `next: 2.1.116`.
- Plano-mestre original: `~/.claude/plans/estude-as-sprints-de-cozy-island.md`.
- Plano v1 (antecessor): `~/.claude/plans/faz-assim-me-d-greedy-cerf.md`.
- Repo: `~/.config/zsh` = `~/Desenvolvimento/Spellbook-OS` (GitHub: AndreBFarias/Spellbook-OS).

---

*"Memória em disco, não em contexto. Zero flags, zero comandos extras. Ciclo em uma janela. Rigor de duas abas."*
