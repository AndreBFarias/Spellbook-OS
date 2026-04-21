# Manual rápido — Spellbook-OS Claude Code v2

Data: 2026-04-20. Versão Claude Code: 2.1.114.

Este manual descreve **o que mudou** no setup do Claude Code neste projeto. Para o índice completo de documentação, veja [`README.md`](./README.md).

## TL;DR — o que é novo

1. **Docs versionadas em `~/.config/zsh/docs/claude/`** — todos os artefatos Claude (agents, commands, skills, templates, hooks) agora vivem no repo Spellbook-OS. Em `~/.claude/` ficam só symlinks.
2. **Boot capacitado** — ao rodar `cca`, o hook `SessionStart` injeta no contexto da sessão: nome do projeto, status do BRIEF, capacidades visuais disponíveis (CLI + MCPs), regras específicas se for Luna/Nyx-Code/ouroboros, e ação automática para criar BRIEF se ausente.
3. **Auto-bootstrap do `VALIDATOR_BRIEF.md`** — no 1º acesso a qualquer repo git, se BRIEF não existe, Claude auto-dispara validador em MODO BOOTSTRAP (ou BOOTSTRAP_RICO para projetos conhecidos) antes de qualquer tarefa.
4. **Skill `validacao-visual`** — pipeline 3-tentativas (scrot → claude-in-chrome → playwright). Claude nunca mais diz "impossível" sem provar 3 tentativas com log literal.
5. **Ciclo automático `/sprint-ciclo`** — planejar → executar → validar em cadeia. 3 iterações de auto-correção se REPROVADO. Auto-commit + auto-push + auto-PR ao APROVADO.
6. **14 lições empíricas codificadas** — os padrões que o Opus-validador dos 3 projetos (Luna, Nyx-Code, protocolo-ouroboros) sempre pegava agora são checks obrigatórios no `validador-sprint`.
7. **Pré-autorização de CLI visuais** — `scrot`, `import`, `xdotool`, `wmctrl`, `ffmpeg`, `xclip`, `sha256sum` sem prompt de permissão.

## Comandos principais

### Ciclo de sprint

```bash
cca                            # abre Claude com boot capacitado (projeto, BRIEF, MCPs)
cca "/sprint-ciclo <ideia>"    # ciclo automático — plan → exec → val + auto-commit/push/PR
cca "/sprint-ciclo-manual <ideia>"  # mesmo ciclo com checkpoints (opt-in)
cca "/planejar-sprint <ideia>" # apenas planeja
cca "/executar-sprint [spec]"  # apenas executa
cca "/validar-sprint"          # apenas valida
```

Via aliases shell:

```bash
sciclo <ideia>    # = sprint ciclo → cca "/sprint-ciclo"
sciclom <ideia>   # = sprint ciclo-manual (opt-in, checkpoints)
splan <ideia>     # = sprint plan
sexec [spec]      # = sprint exec
sval [plano]      # = sprint val
```

### BRIEF (memória por projeto)

```bash
sbrief            # status do VALIDATOR_BRIEF.md do projeto atual
sbedit            # abre BRIEF no $EDITOR
sboot             # copia template de bootstrap pro clipboard (manual)
sbr               # sprint bootstrap --rich (auto-gera BRIEF rico a partir de memórias)
```

### Diagnóstico

```bash
sdoc              # sprint doctor completo (14 lições + setup v2)
SANTUARIO_DOCTOR_VERBOSE=1 santuario <projeto>   # doctor-quick verbose
```

## Fluxo de uso típico

### Abrindo um projeto

```bash
santuario Luna                 # setup do projeto (venv, git, emoji guardian)
cca                            # abre Claude com tudo pronto
```

No primeiro prompt dentro do Claude, ele já sabe:
- `[SANTUÁRIO READY]` — projeto, BRIEF status, tipo
- `[PROJETO ESPECIAL]` — regras específicas se Luna/Nyx/ouroboros
- `[CAPACIDADES VISUAIS]` — queries `ToolSearch` prontas para MCPs
- `[SPRINT CICLO]` — orçamento de retries
- `[AÇÃO AUTOMÁTICA]` — se BRIEF falta, dispara bootstrap antes da 1ª tarefa

### Rodando uma sprint

```bash
cca "/sprint-ciclo adicionar gauge de VRAM na TUI"
```

Fluxo interno (totalmente automático, sem intervenção):

1. Planejador-sprint (subagent Opus) redige spec → salva em `~/.claude/plans/sprint-<ID>.md`.
2. Executor-sprint (subagent Opus) lê BRIEF + spec → verifica hipóteses via `rg` → valida aritmética de refactor → implementa → proof-of-work runtime-real → varre acentuação periférica.
3. Validador-sprint (subagent Opus) aplica 14 checks universais + skill `validacao-visual` se diff toca UI → veredicto.
4. Se REPROVADO: auto-dispatch executor com patch-brief (até 3 iterações).
5. Se APROVADO: auto-commit + auto-push + auto-PR (via `/commit-push-pr`).

Só pausa em:
- Ambiguidade no spec.
- REPROVADO após 3 iterações.
- Hipótese do planejador divergente (executor não acha identificadores via `rg`).

## As 14 lições empíricas (checks obrigatórios)

1. **Runtime real** — TUI/Gauntlet completo, não pytest puro.
2. **Screenshot UI** — skill `validacao-visual` auto-invocada.
3. **Acentuação periférica** — varre arquivo inteiro (citações, docstrings, f-strings).
4. **Hipótese empírica** — `rg` antes de aplicar fix sugerido.
5. **Fix inline ou sprint nova** — nunca "pré-existente fora escopo".
6. **Zero follow-up** — Edit-pronto OU sprint-ID; nunca "issue depois".
7. **Aritmética de refactor** — se spec tem meta numérica, `wc -l` + projeção antes.
8. **Plano antes de código** — `/executar-sprint` sem spec → PARA.
9. **Nenhum débito** — pendência vira sprint em `SPRINT_ORDER_MASTER.md`.
10. **Sprints divididas** — rejeitar monolitos; propor lista de sub-sprints.
11. **Integração obrigatória** — `test_*.py` solto → REPROVA.
12. **Smoke boot real** — `./run.sh --smoke` como check #13.
13. **Gauntlet como critério** — sprint CONCLUÍDA exige relatório Gauntlet.
14. **Opus centro** — o próprio validador-sprint é esse check.

Detalhes empíricos em [`PADROES-VALIDADOR.md`](./PADROES-VALIDADOR.md).

## Capacidades visuais (não diga "impossível" sem tentar)

Pipeline de 3 tentativas documentado em [`CAPACIDADES-VISUAIS.md`](./CAPACIDADES-VISUAIS.md).

### Tentativa 1 — CLI X11 (mais rápido)

Pré-autorizado em `~/.claude/settings.json`:

```bash
scrot /tmp/<projeto>_<area>_<ts>.png                 # full / seleção
import -window $(xdotool search --name "<app>" | head -1) /tmp/<file>.png
wmctrl -lx                                           # listar janelas GUI
ffmpeg -f x11grab -video_size 1920x1080 -t 5 out.mp4 # screencast
sha256sum /tmp/<file>.png                            # hash pro proof-of-work
```

### Tentativa 2 — claude-in-chrome MCP (Chrome rodando)

```
ToolSearch select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__navigate
```

### Tentativa 3 — playwright MCP (dev local headless)

```
ToolSearch select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_take_screenshot
```

## Arquitetura de arquivos (origem canônica vs symlinks)

```
ORIGEM (versionada no Spellbook-OS):
  ~/.config/zsh/docs/claude/
    agents/{planejador,executor,validador}-sprint.md
    commands/{planejar,executar,validar,sprint-ciclo,sprint-ciclo-manual}.md
    skills/validacao-visual/SKILL.md
    templates/bootstrap-{generico,luna,nyx-code,ouroboros}.md
    hooks/{guardian,session-start-briefing,post-plan-clear}.py
    SETUP.md, AGENTS.md, HOOKS.md, CAPACIDADES-VISUAIS.md, ...
    SPECIAL_PROJECTS.json
    VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md
  ~/.config/zsh/scripts/bootstrap-rico-brief.py

CONSUMO (symlinks em ~/.claude/):
  ~/.claude/agents/*       → docs/claude/agents/
  ~/.claude/commands/*     → docs/claude/commands/
  ~/.claude/skills/*       → docs/claude/skills/
  ~/.claude/templates/*    → docs/claude/templates/
  ~/.claude/hooks/*        → docs/claude/hooks/
  ~/.claude/PLUGINS.md     → docs/claude/PLUGINS.md
  ~/.claude/SETTINGS.md    → docs/claude/SETTINGS.md
  ~/.claude/CLAUDE.md      → ~/.config/zsh/AI.md (já existia)
```

Para recriar os symlinks (se algum quebrar):

```bash
bash ~/.config/zsh/install.sh --relink
```

## Variáveis de ambiente exportadas pelo `cca`

Lidas pelo hook `session-start-briefing.py` e pelos subagents:

| Var | Conteúdo |
|---|---|
| `CLAUDE_PROJECT_ROOT` | raiz git do CWD |
| `CLAUDE_PROJECT_NAME` | basename do root |
| `CLAUDE_BRIEF_PATH` | `$CLAUDE_PROJECT_ROOT/VALIDATOR_BRIEF.md` |
| `CLAUDE_BRIEF_STATUS` | `exists` ou `missing` |
| `CLAUDE_PROJECT_KIND` | `luna`, `nyx-code`, `protocolo-ouroboros`, ou `generic` |
| `CLAUDE_SANTUARIO_READY` | `1` se em repo git |
| `CLAUDE_VISUAL_TOOLS_EXPECTED` | `1` (sempre) |
| `CLAUDE_SPRINT_CICLO_MAX_RETRIES` | `3` (override: `export CLAUDE_SPRINT_CICLO_MAX_RETRIES=5` antes do `cca`) |

## Hooks ativos em `~/.claude/settings.json`

| Hook | Quando | O que faz |
|---|---|---|
| `guardian.py` | `PreToolUse` Write/Edit/MultiEdit | Bloqueia emojis + atribuições a IA |
| `session-start-briefing.py` | `SessionStart` (startup, resume, clear, compact) | Injeta `additionalContext` com [SANTUÁRIO READY] + capacidades + ação automática |
| `post-plan-clear.py` | `UserPromptSubmit` | Sugere `/clear` quando detecta aprovação de plan (sutil) |

## Os 3 projetos conhecidos (SPECIAL_PROJECTS.json)

| Kind | Memórias | Tipo | Smoke | Gauntlet |
|---|---|---|---|---|
| `luna` | 65 | tui | `./run_luna.sh --cli-health` | `./run_luna.sh --gauntlet` |
| `nyx-code` | 13 | cli | `./run.sh --smoke` | `./run.sh --gauntlet` |
| `protocolo-ouroboros` | 0 (vazio) | cli | `./run.sh --smoke` | `bash scripts/finish_sprint.sh` |

BRIEFs pré-gerados em cada repo-alvo após a implantação v2:

```
/home/andrefarias/Desenvolvimento/Luna/VALIDATOR_BRIEF.md              (206 linhas)
/home/andrefarias/Desenvolvimento/Nyx-Code/VALIDATOR_BRIEF.md          (151 linhas)
/home/andrefarias/Desenvolvimento/protocolo-ouroboros/VALIDATOR_BRIEF.md (125 linhas)
```

Cada um com seções `[CORE]` preenchidas + checks universais marcados + contratos de runtime + regras especiais do projeto.

## Documentação detalhada

| Tema | Ler |
|---|---|
| Visão geral | [`SETUP.md`](./SETUP.md) |
| 3 subagents Opus | [`AGENTS.md`](./AGENTS.md) |
| Hooks (custom + plugins) | [`HOOKS.md`](./HOOKS.md) |
| Screenshot / validação visual | [`CAPACIDADES-VISUAIS.md`](./CAPACIDADES-VISUAIS.md) |
| Ciclo automático detalhado | [`SPRINT-WORKFLOW.md`](./SPRINT-WORKFLOW.md) |
| 14 lições empíricas | [`PADROES-VALIDADOR.md`](./PADROES-VALIDADOR.md) |
| Auto-memory | [`MEMORIA.md`](./MEMORIA.md) |
| Plugins e settings | [`PLUGINS.md`](./PLUGINS.md), [`SETTINGS.md`](./SETTINGS.md) |
| Problemas conhecidos | [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) |
| Catálogo de BRIEFs ativos | [`BRIEF-POR-PROJETO.md`](./BRIEF-POR-PROJETO.md) |

## Validação rápida

Para confirmar que tudo está funcionando após a implantação, rode [`VALIDACAO-V2.md`](./VALIDACAO-V2.md) — checklist executável passo a passo.

---

*"Memória em disco, não em contexto. Ciclo em uma janela. Rigor de duas abas."*
