# VALIDATOR_BRIEF — {{NOME_PROJETO}}

> Memória acumulada do validador. Versionada no repo. Atualizada pelo subagente `validador-sprint` quando detecta padrão novo. Não editar manualmente sem registrar no rodapé.

## [CORE] Identidade

- Nome: {{NOME_PROJETO}}
- Linguagem principal: {{LINGUAGEM}}
- Framework/stack: {{FRAMEWORK}}
- Propósito (1 linha): {{PROPOSITO}}
- Tipo-de-projeto (para validação visual): {{TIPO}} <!-- tui | gui | web | cli | lib | docs -->

## [CORE] Como rodar

- Smoke (boot ok <5s): `{{SMOKE_CMD}}`
- Testes unitários: `{{UNIT_CMD}}`
- Integração / gauntlet (se existir): `{{GAUNTLET_CMD}}`
- Lint / format: `{{LINT_CMD}}`
- TUI / GUI run (se aplicável): `{{RUN_CMD}}`

## [CORE] Arquitetura essencial

<!-- 5-10 componentes. Nome + responsabilidade em 1 linha + arquivo principal. Ex:
- AgentLoop — loop principal de inferência, `src/agent/loop.py`
- ToolRegistry — registro central de tools, `src/tools/registry.py`
-->

## [CORE] Checks universais ativados

Matriz das 14 lições empíricas dos 3 projetos (Luna, Nyx-Code, protocolo-ouroboros). Marque "sim/não" por check, conforme aplicável a este projeto. O validador usa esta tabela para decidir o que validar.

| # | Check | Origem | Aplicável aqui? | Comando de teste |
|---|---|---|---|---|
| 1 | Runtime real (não CLI/pytest puro) | Luna feedback_always_test_tui | {{SIM_NAO}} | `{{SMOKE_CMD}}` |
| 2 | Screenshot UI automático | Luna Sprint 09 | {{SIM_NAO}} | skill validacao-visual |
| 3 | Acentuação periférica | Luna AUD-03 FEN-11 | sim (PT-BR) | `python3 ~/.config/zsh/scripts/validar-acentuacao.py` |
| 4 | Hipótese do revisor empírica | Luna AUD-03 FEN-01d | sim | `rg` antes de aplicar fix |
| 5 | Fix inline vs pular | Luna feedback_fix_inline_never_skip | sim | protocolo explícito |
| 6 | Zero follow-up | Luna + Nyx | sim | Edit-pronto OU sprint-ID |
| 7 | Aritmética de refactor | Luna INFRA-83 ORFEU | {{SIM_NAO}} | `wc -l` + projeção |
| 8 | Plano antes de código | Luna + Nyx feedback_plan_before_sprint | sim | `/planejar-sprint` sempre |
| 9 | Nenhum débito fica pra trás | Nyx feedback_nenhum_debito | sim | `SPRINT_ORDER_MASTER.md` |
| 10 | Sprints divididas e profundas | Luna feedback_split_sprints_deep | sim | rejeitar monolítica |
| 11 | Integração obrigatória (nada solto) | Nyx ADR-013/014 | {{SIM_NAO}} | registry/command/service |
| 12 | Smoke boot real | Nyx BOOT-FIX-01 check #13 | {{SIM_NAO}} | `{{SMOKE_CMD}}` |
| 13 | Sprint CONCLUÍDA = Gauntlet | Luna ADR-017 | {{SIM_NAO}} | gauntlet por fase |
| 14 | Opus centro de inteligência | Luna feedback_opus_review_center | sim | validador-sprint é esse |

## [CORE] Contratos de runtime

Comandos canônicos (existem e foram testados neste projeto):

- Smoke: `{{SMOKE_CMD}}`
- Unit tests: `{{UNIT_CMD}}`
- Integração: `{{INTEGRACAO_CMD}}`
- Gauntlet: `{{GAUNTLET_CMD}}`
- Validar acentuação: `python3 ~/.config/zsh/scripts/validar-acentuacao.py <arq>`
- Lint: `{{LINT_CMD}}`

## [CORE] Arquivos periféricos (onde acentuação escapa)

Paths onde acentuação historicamente escapa da auto-revisão. O validador (check #3) varre esses além do core funcional.

- `<path:linha>` — citação filosófica (CLAUDE.md §12)
- `<glob>` — docstrings de teste (ex: `tests/**/*.py`)
- `<glob>` — comentários ornamentais
- `<glob>` — f-strings que não são input direto

## [CORE] Heurísticas de aritmética

- Meta de linhas por arquivo: {{LIMITE_LINHAS}} (ex: 800)
- Exceções autorizadas: {{EXCECOES}} (ex: config/, testes/, registries/)
- Comando de verificação: `find src -name '*.py' -exec wc -l {} \\; | awk '$1>{{LIMITE_LINHAS}}'`

## [CORE] Capacidades visuais aplicáveis

- Tipo-de-projeto: {{TIPO_VISUAL}} (TUI/GUI/Web/CLI)
- Stack visual: {{STACK_VISUAL}} (ex: Textual, GTK, React, etc.)
- Como capturar screenshot:
  - Ferramenta primária: `{{CAPTURE_CMD}}` (ex: `bash scripts/tui_tests/capture.sh`)
  - Fallback secundário: {{FALLBACK_TOOL}} (scrot / claude-in-chrome MCP / playwright MCP)
- Critérios de validação (se há): `{{CRITERIA_PATH}}`

## [OPCIONAL] Padrões recorrentes de bug

<!-- Omitir se vazio. Preencher quando validador detectar padrão nas revisões. -->

## [OPCIONAL] Invariantes não-óbvios

<!-- Omitir se vazio. -->

## [OPCIONAL] Decisões arquiteturais chave

<!-- ADRs, decisões de design que não estão documentadas em ADR. -->

## [OPCIONAL] Gambiarras conhecidas / antipatterns

<!-- Com justificativa histórica do porquê estão lá. -->

## [OPCIONAL] Cheiros específicos do projeto

<!-- Sinais de alerta típicos. -->

## [OPCIONAL] Histórico de sprints relevantes

<!-- ID + 1 linha. Ex: SPRINT-042 — Refactor do parser JSON (preservou 4 níveis de fallback). -->

## [OPCIONAL] Perfis / ambientes

<!-- Ex: Ryzen 5 7535HS + RTX 3050 4GB para Luna (limites de VRAM). -->

---
*Atualizado em {{ISO_TIMESTAMP}} por {{AUTOR}} (modo {{MODO}})*
