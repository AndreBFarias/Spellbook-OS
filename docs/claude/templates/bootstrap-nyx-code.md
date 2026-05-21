# Bootstrap — Nyx-Code

> Cole o bloco abaixo da linha `---` na sessão Claude viva que revisou as sprints do Nyx-Code.
>
> Alternativa automatizada: `python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto nyx-code --saida /home/andrefarias/Desenvolvimento/Nyx-Code/VALIDATOR_BRIEF.md`

---

Bootstrap VALIDATOR_BRIEF.md — Nyx-Code

Quero capturar TUDO que você aprendeu sobre o projeto Nyx-Code. Escreva em `/home/andrefarias/Desenvolvimento/Nyx-Code/VALIDATOR_BRIEF.md` seguindo o template em `~/.config/zsh/docs/claude/VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md`.

## Contexto do projeto

Nyx-Code é agente local-first baseado em Claude Code portado (`openclaud`). Stack: Python, local models via Ollama. Integração obrigatória em `ToolRegistry`, `@nyx_command`, services. Testes exclusivamente via Gauntlet — nada de `test_*.py` solto.

## Inventário atual

- 34 tools registradas em `nyx/agent/tools/registry.py` (`ToolRegistry`)
- 47 commands registrados via `@nyx_command` em `commands.py`
- 10 services em `nyx/agent/services/`
- Limpeza PROD feita (conforme `project_state_2026_04_09.md`)

## Proxy think adaptativo

- Com tools no prompt → `think=true` (qwen3 precisa)
- Sem tools → `think=false` (senão qwen3 responde vazio)
- Regra em `nyx/llm/proxy.py`

## Contratos de runtime Nyx-Code

- Smoke: `./run.sh --smoke` (retorna "boot ok" em <5s) — **check #13 em `scripts/sprint_invariants.sh`**
- Gauntlet completo: `./run.sh --gauntlet`
- Gauntlet por fase: `./run.sh --only <fase>` (ex: `rapido`, `interface`, `tools`)
- Sprint invariants: `bash scripts/sprint_invariants.sh` (13 checks)
- Unit tests: PROIBIDO. Deletar qualquer `test_*.py` solto — ADR-014.

## Arquivos críticos

- `nyx/agent/tools/registry.py` — ToolRegistry (source of truth de tools)
- `nyx/cli.py:29` — `sys.path.insert` ANTES de qualquer `from nyx.*` (BOOT-FIX-01 armadilha)
- `scripts/sprint_invariants.sh` — 13 checks invariáveis
- `SPRINT_ORDER_MASTER.md` — bloco `<!-- MANUAL_OVERRIDE -->` preserva decisões manuais de `sync.py`
- `scripts/gauntlet/nyx_gauntlet.py` — único local de testes

## ADRs críticos

- ADR-013 — Integração obrigatória (nada solto)
- ADR-014 — Testes via Gauntlet (proibido pytest direto)
- ADR-06 — Escopo atômico (rejeitar task mal-dimensionada, promover sprint nova)

## Protocolos conhecidos

- **BOOT-FIX-01**: smoke obrigatório em `sprint_invariants.sh` check #13. Gauntlet pytest-like não pega `ModuleNotFoundError` no entry point real.
- **Nenhum débito fica para trás**: pendência vira sprint com ID em `SPRINT_ORDER_MASTER.md`.
- **Sem subagentes**: usar Read/Grep/Glob direto, não delegar para Agent tool (feedback_sem_agentes).

## Arquivos periféricos (acentuação)

- Docstrings de teste (se existirem apesar da proibição)
- Citações filosóficas em arquivos README
- Comentários em `nyx/core/**/*.py`

## Regras de escrita

- Seja concreto: arquivo, função, linha quando lembrar.
- Não invente. Se não lembra, omita ou marque `<a preencher>`.
- PT-BR direto. Zero emojis. Acentuação correta obrigatória.
- Rodapé: `*Atualizado em <ISO timestamp> por bootstrap-rico (sessão Nyx-Code)*`
