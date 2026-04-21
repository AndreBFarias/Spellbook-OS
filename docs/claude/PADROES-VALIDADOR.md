# Padrões que o Validador Opus sempre pega — 14 lições empíricas

As lições abaixo vieram do workflow histórico de 2 abas (Opus-planejador/validador + Opus-executor) nos projetos Luna, Nyx-Code e protocolo-ouroboros. O validador-sprint as aplica como checks obrigatórios em qualquer projeto.

Fonte: memórias em `~/.claude/projects/-home-andrefarias-Desenvolvimento-{Luna,Nyx-Code}/memory/*.md` + sessões de validação que detectaram cada padrão.

---

## 1. Runtime real vs CLI single-thread

**Origem**: Luna 2026-04-01 (`feedback_always_test_tui.md`). CLI parser passava com exit 0; TUI completa (Textual) crashava por threading, queue drops, asyncio.Lock cross-thread, timeouts 31s. Falhamos em notar porque validamos apenas no CLI.

**Regra**: toda sprint que toca runtime (bridges, config, models, threads, IO) DEVE rodar na superfície de produção real. Em Luna: `./run_luna.sh` (TUI). Em Nyx: `./run.sh --smoke`. Em projetos Flask/FastAPI: requisição HTTP real. `pytest --cli` ou unit test isolado NÃO substitui.

**Como aplicar**: validador-sprint lê o BRIEF seção "Contratos de runtime" e exige evidência de execução real no proof-of-work. Se diff toca runtime e proof-of-work só tem pytest, REPROVADO.

## 2. Screenshots TUI/GUI/Web obrigatórios

**Origem**: Luna Sprint 09 (`feedback_screenshots_obrigatorios.md`). Plano original tratava screenshots como "se DISPLAY disponível". Usuário corrigiu: são parte integral da evidência.

**Regra**: toda sprint que afeta UI/entidades/comportamento visível DEVE capturar PNG + LER o PNG (Read multimodal) + validar contra critério + incluir PNG no relatório. Fallback "impossível" só aceito após provar 3 tentativas (CLI scrot + claude-in-chrome + playwright).

**Como aplicar**: validador auto-invoca skill `validacao-visual` se diff toca padrões (`*.tsx,*.jsx,*.vue,*.svelte,*.html,*.css,*.scss,src/ui/**,*textual*,*widget*,templates/**`) ou se projeto declara tipo TUI/GUI/Web no BRIEF.

## 3. Acentuação em linhas periféricas é ponto cego

**Origem**: Luna AUD-03 FEN-11 (`feedback_accent_in_peripheral_lines.md`). Revisor pegou 2 violações que passaram na auto-revisão: `Pragmatico` na citação filosófica (§12 CLAUDE.md) e `nao-SPRINT` em docstring de teste.

**Regra**: ao criar/editar arquivo PT-BR, varrer o arquivo INTEIRO antes de apresentar ao revisor, não só o core funcional. Lugares onde acentuação escapa:
- Citação filosófica final (CLAUDE.md §12)
- Docstrings de `test_*` / `*_test.py`
- Comentários ornamentais (blocos `# -----`)
- f-strings que não são input direto (mensagens de log)
- Mensagens em `__doc__` de módulos

**Como aplicar**: executor-sprint roda `python3 ~/.config/zsh/scripts/validar-acentuacao.py <arq>` em TODO arquivo modificado no passo 6. Validador categoriza violações como PONTO-CEGO (subtipo de IMPORTANTE, mas destacado).

## 4. Verificar hipótese do revisor empiricamente

**Origem**: Luna AUD-03 FEN-01d (`feedback_verify_reviewer_hypothesis.md`). Revisor hipotetizou que `sync.py` fazia strip accents via `unicodedata.normalize('NFKD').encode('ascii','ignore')`. Grep confirmou ZERO ocorrências de `unicodedata/NFKD/encode-ascii` em `scripts/`. Causa real estava nos YAMLs source (criados com `title:` sem acento). Ter implementado o fix hipotético teria adicionado código morto.

**Regra**: diagnóstico do revisor Opus é sugestão, não ordem. Antes de aplicar o fix, confirmar empiricamente que a causa hipotetizada existe. Se não existir, reportar divergência com dados (`grep ... -> 0 matches`) e oferecer diagnóstico alternativo.

**Como aplicar**: executor-sprint passo 0.3 roda `rg` pelos identificadores citados no plano antes de aplicar qualquer Edit. Se 0 matches, PARA e REPORTA.

## 5. Problema legado = fix inline OU sprint nova, nunca pular

**Origem**: Luna (`feedback_fix_inline_never_skip.md`). Executor dizia "pré-existente, não é relacionado às minhas mudanças" como justificativa para ignorar falhas do Gauntlet.

**Regra**: se Gauntlet falha durante sprint — mesmo por bug pré-existente — a sprint NÃO está concluída até todos resolvidos. Ou corrige inline ou promove para sprint separada com ID. Nunca silencia.

**Como aplicar**: executor-sprint detecta falha fora do escopo dos touches. Em vez de fixar silenciosamente ou dizer "pré-existente", dispatcha automaticamente `planejador-sprint` para criar sprint nova com o achado como input. Validador REPROVA qualquer sprint com "pré-existente fora escopo" no proof-of-work.

## 6. Zero follow-up acumulado

**Origem**: Luna sessão de validação (`feedback_zero_follow_up_acumulado.md`). Usuário não aceita "abrir issue depois" como output de code review. Prefere forçar o executor a resolver na origem.

**Regra**: cada achado no veredicto do validador DEVE ter:
- Edit exato (`old_string` / `new_string`) OU
- Bash exato (`sed -i '...'`) OU
- ID de sprint-nova (com prompt pronto para `/planejar-sprint`)

**PROIBIDO**: "abrir issue depois", "criar TODO", "seria bom revisar", "pré-existente fora escopo".

**Como aplicar**: validador-sprint tem essa proibição no seu prompt; se emitir qualquer dessas frases, viola sua própria diretiva e ele reescreve como Edit-pronto ou sprint-ID.

## 7. Aritmética de refactor antes de executar

**Origem**: Luna INFRA-83 ORFEU (`feedback_reject_task_promote_sprint.md`). Task 9 pedia refactor `system_instructions.py <800L` extraindo métodos via mixin. Aritmética não fechava (989L -> 963L, ainda >800). Refactor real exigia extrair 4 prompt templates (~715L) com TDD de propagação. Decisão: rejeitar Task 9, promover para INFRA-83 ORFEU com spec completa.

**Regra**: antes de executar task de refactor com meta numérica, validar aritmética: `wc -l <arquivo_atual>` + projeção da extração descrita. Se não fecha, rejeitar formalmente (ADR-06) e criar sprint nova. Registrar rejeição em `<!-- MANUAL_OVERRIDE -->` do `SPRINT_ORDER_MASTER.md`.

**Como aplicar**: executor-sprint passo 0.4 faz a aritmética antes de iniciar.

## 8. Planejar antes de cada sprint

**Origem**: Luna + Nyx (`feedback_plan_before_sprint.md`, `feedback_planejar_antes.md`).

**Regra**: nunca codar sem plano validado. O planejador gera spec com acceptance criteria, touches autorizados, proof-of-work esperado. Executor só inicia após aprovação do spec (ou no ciclo automático, após planejador retornar).

**Como aplicar**: `/executar-sprint` sem spec prévio PARA; pede ao usuário disparar `/planejar-sprint` ou passar path manualmente.

## 9. Nenhum débito fica para trás

**Origem**: Nyx (`feedback_nenhum_debito.md`). Itens "para depois" somem da vista se não tem ID.

**Regra**: toda pendência levantada vira sprint explícita em `dev-journey/06-sprints/producao/SPRINT_<ID>.md` + linha em `SPRINT_ORDER_MASTER.md`. Nunca TODO solto em comentário, nunca "débito técnico" implícito, nunca lista em relatório.

**Como aplicar**: validador rejeita proof-of-work com `TODO`, `XXX`, `FIXME` introduzidos. Sugere prompt pronto para `/planejar-sprint` sobre o item.

## 10. Sprints divididas e profundas

**Origem**: Luna (`feedback_split_sprints_deep.md`). Usuário prefere 4+ sprints separadas com máximo detalhe do que uma sprint monolítica.

**Regra**: planejador-sprint evita spec monolítico que toca >1 área arquitetural ou >N arquivos. Se necessário, divide em sub-sprints com IDs próprios.

**Como aplicar**: planejador-sprint, ao receber ideia que cruzaria múltiplas áreas, propõe SPRINT_ORDER como lista de 2+ specs em vez de 1 grande. Usuário vê a lista e aprova o conjunto.

## 11. Integração obrigatória — nada solto

**Origem**: Nyx (`feedback_integracao_obrigatoria.md`, ADR-013 + ADR-014).

**Regra**: nenhum script solto no projeto. Todo código funcional está integrado:
- Tools -> registradas em `ToolRegistry` (`nyx/agent/tools/registry.py`)
- Commands -> registrados com `@nyx_command` em `commands.py`
- Services -> em `nyx/agent/services/`
- Testes -> exclusivamente no Gauntlet (`scripts/gauntlet/nyx_gauntlet.py`)

**Como aplicar**: validador detecta `test_*.py` solto -> REPROVA com Edit pronto para deletar. Detecta classe/função nova em `nyx/` sem registro -> REPROVA com path de onde adicionar.

## 12. Smoke boot real obrigatório

**Origem**: Nyx BOOT-FIX-01 2026-04-19 (`feedback_smoke_boot.md`). Bloco 2.5 inteiro (8 sprints) shippou com `./run.sh` crashando por `ModuleNotFoundError: No module named 'nyx'` em `nyx/cli.py:29` — `sys.path.insert` ficou na linha 35 (após primeiro `from nyx.*`). Gauntlet `--only <fase>` rodava imports via pytest-like e não invocava o entry point real. Falha descoberta durante VALIDATE-ONDA-20 quando usuário tentou validar visual.

**Regra**: toda sprint que toca qualquer módulo Python de `nyx/` (ou entry point equivalente em outro projeto) DEVE passar `{{SMOKE_CMD}}` (boot ok < 5s) antes de ser marcada CONCLUÍDA. Virou check #13 em `scripts/sprint_invariants.sh`. Smoke é camada DIFERENTE de gauntlet — não substitui.

**Como aplicar**: executor passo 5 inclui output literal do smoke comando (do BRIEF) no proof-of-work. Validador exige ver `exit 0` + duração < 5s.

## 13. Sprint CONCLUÍDA exige Gauntlet

**Origem**: Luna ADR-017 (`feedback_sprint_status_gauntlet.md`).

**Regra**: Gauntlet é sistema de regressão contínua. Sprint só é marcada CONCLUÍDA com anexo de relatório Gauntlet recente.

**Como aplicar**: validador lê check_gauntlet_freshness equivalente; se gauntlet não foi rodado na sprint (ou o output é anterior ao primeiro commit da sprint), REPROVA.

## 14. Opus como centro de inteligência

**Origem**: Luna (`feedback_opus_review_center.md`, `feedback_opus_reviewer_role.md`).

**Regra**: Opus (este modelo) é o centro. Planeja sprints profundas. Valida execução de qualquer IA (ou da própria implementação recente). Detecta "migué" — atalhos, workarounds, código incompleto. Dá prompts de correção exatos.

**Como aplicar**: validador-sprint é a encarnação desse princípio. Cada um dos 3 subagentes (planejador/executor/validador) usa modelo opus declarado no frontmatter.

---

## Categorias de severidade no veredicto

| Severidade | Significado | Exemplo |
|---|---|---|
| CRÍTICO | Quebra sistema ou introduz regressão | `./run.sh --smoke` falha |
| IMPORTANTE | Viola contrato ou convenção chave | Arquivo não registrado no ToolRegistry |
| PONTO-CEGO | Escapa da auto-revisão por natureza | Acentuação em citação filosófica |
| MINÚCIA | Cosmético ou estilo | Espaçamento inconsistente |

PONTO-CEGO sobrepõe IMPORTANTE automaticamente (usuário quer rigor 100% em acentuação periférica).

---

## Como o validador aplica

1. Lê o BRIEF (checks ativados + contratos de runtime).
2. Lê o diff + proof-of-work do executor.
3. Para cada check ativo, verifica se evidência está no proof-of-work.
4. Se falta evidência -> achado com Edit/sprint-ID pronto.
5. Emite veredicto APROVADO / APROVADO_COM_RESSALVAS / REPROVADO.
6. Se detecta padrão novo (não coberto pelos 14), propõe nova entrada no BRIEF e, se validado, atualiza-o.

---

*"Coisa pequena que sempre trava projeto futuramente passa quando o validador dorme. Ele não dorme aqui."*
