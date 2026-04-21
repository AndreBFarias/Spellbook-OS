# docs/claude/MEMORIA.md — Sistema de auto-memory

## Visão geral

O Claude Code tem memória persistente em `~/.claude/projects/-home-andrefarias*/memory/`. Esta memória é consultada em sessões futuras (cross-session) e é automaticamente carregada no contexto pelo harness.

Existem 3 granularidades:

| Local | Escopo | Conteúdo |
|---|---|---|
| `~/.claude/projects/-home-andrefarias/memory/` | Global (todo o usuário) | Feedbacks gerais, user profile, sistema |
| `~/.claude/projects/-home-andrefarias-Desenvolvimento-<Projeto>/memory/` | Por projeto | Armadilhas, padrões, decisões específicas daquele workspace |
| `~/.claude/projects/-home-andrefarias--config-zsh/memory/` | Por projeto (zsh) | Memórias do próprio Spellbook-OS |

## Formato dos arquivos

Cada memória é um `.md` com frontmatter YAML:

```markdown
---
name: Título curto
description: Descrição de uma linha (usada para decidir relevância)
type: user | feedback | project | reference
---

Corpo da memória. Pode ter qualquer estrutura. Para feedback/project, preferir:

**Why:** [motivo da regra ou fato]
**How to apply:** [como aplicar em situações futuras]
```

## 4 tipos

### `user`

Informação sobre o perfil, role, preferências, conhecimento do usuário.

Quando salvar: ao aprender detalhe de perfil / responsabilidade / preferência.

Exemplo: `user_sistema.md` com specs da máquina.

### `feedback`

Guidance que o usuário deu sobre como abordar trabalho.

Quando salvar: após correção OU confirmação de abordagem não-óbvia. Registrar **por que** (motivo) e **como aplicar**.

Exemplo: `feedback_acentuacao.md` — obrigatoriedade de acentos em PT-BR.

### `project`

Informação sobre trabalho em andamento, goals, incidentes.

Quando salvar: ao aprender quem/o-que/por-que/quando. Incluir datas absolutas (converter "ontem" -> "2026-04-19").

Exemplo: `project_validador_universal.md` — estado do sistema de sprints.

### `reference`

Pointers para informação externa (Linear, Slack, Grafana, docs).

Quando salvar: ao aprender sobre sistema externo e seu propósito.

Exemplo: `reference_spellbook_autosync.md` — como o auto-pull/push funciona.

## MEMORY.md (índice)

Cada pasta memory/ tem um `MEMORY.md` que é o índice:

```markdown
# Memória do projeto: <nome>

## Seção A
- [Título](file.md) — uma linha de hook

## Seção B
- [Título](outro.md) — hook
```

Limite: 200 linhas (harness trunca depois disso). Cada entrada é uma linha <~150 chars. Organizado semanticamente, não cronologicamente.

## Fluxo de escrita

1. Nova sessão: harness carrega MEMORY.md automaticamente no contexto.
2. Claude vê MEMORY.md e decide quais memórias individuais ler (Read).
3. Durante trabalho, Claude detecta novo fato relevante.
4. Escreve arquivo novo: `Write ~/.claude/projects/.../memory/novo.md` com frontmatter completo.
5. Atualiza MEMORY.md (adiciona linha apontando pro novo).

## O que NÃO salvar em memória

Mesmo se o usuário pedir, não salvar:
- Padrões de código, convenções, arquitetura, paths — são deriváveis lendo o projeto.
- Git history — `git log` / `git blame` são autoritativos.
- Soluções de bug específicas — estão no código + commit message.
- Qualquer coisa em CLAUDE.md.
- Detalhes efêmeros de tarefa em andamento.

Se o usuário pede para salvar algo dessa categoria, perguntar o que foi **surpreendente** ou **não-óbvio** — essa é a parte que vale persistir.

## Stale memory handling

Memórias podem envelhecer. Antes de agir com base em uma memória:
- Se cita função/arquivo/flag: `rg` confirma que ainda existe.
- Se é resumo de estado: `git log` ou leitura direta sobrepõe.

Se memória está obsoleta, atualizar ou remover — não acumular verdades-em-data-fixa.

## Memórias ativas (snapshot 2026-04-20)

### `~/.claude/projects/-home-andrefarias/memory/` (global)

- MEMORY.md
- user_santuario_function.md
- user_sistema.md
- feedback_acentuacao.md
- feedback_modelo_luna.md
- feedback_cca_wrapper.md
- project_icones_dracula_fix.md
- project_validador_universal.md
- reference_dracula_icones_tema.md
- reference_spellbook_autosync.md

Após v2 deste setup, serão adicionadas:
- feedback_ciclo_automatico.md
- feedback_auto_bootstrap_brief.md
- feedback_boot_capacitado.md
- project_spellbook_claude_setup_v2.md

### `~/.claude/projects/-home-andrefarias-Desenvolvimento-Luna/memory/` (Luna)

65+ arquivos. Entre os mais densos:
- MEMORY.md (166 linhas, índice organizado)
- 15 armadilhas críticas em corpo
- feedback_opus_review_center, feedback_opus_reviewer_role, feedback_trust_ai_execution
- feedback_screenshots_obrigatorios, feedback_always_test_tui
- feedback_fix_inline_never_skip, feedback_zero_follow_up_acumulado
- project_gauntlet_audit_2026_03_31, project_aud_01a_rc1_2026_04_19
- Diversos project_sprint_* e project_session_*

### `~/.claude/projects/-home-andrefarias-Desenvolvimento-Nyx-Code/memory/` (Nyx-Code)

13 arquivos:
- MEMORY.md
- feedback_sem_agentes, feedback_planejar_antes, feedback_integracao_obrigatoria
- feedback_nenhum_debito, feedback_smoke_boot
- project_nyx_overview, project_state_* (3 datas), project_port_openclaude, project_proxy_think, project_infra_gauntlet_01_prep

### `~/.claude/projects/-home-andrefarias-Desenvolvimento-protocolo-ouroboros/memory/` (ouroboros)

Vazio. Após v2, o BRIEF será criado em MODO BOOTSTRAP convencional (sem bootstrap-rico) e memórias virão organicamente conforme uso.

## Integração com o VALIDATOR_BRIEF

O VALIDATOR_BRIEF.md vive na **raiz do repo-alvo** (Luna, Nyx-Code, etc.) — NÃO em `~/.claude/projects/.../memory/`.

Por que separado:
- BRIEF é artefato do PROJETO — versionado no repo-alvo junto com código.
- Memórias em `~/.claude/` são **pessoais** (como o Claude aprendeu, o que o usuário falou).
- BRIEF é **compartilhável** (outros devs abrindo o repo veem).

O script `bootstrap-rico-brief.py` lê memórias do `~/.claude/projects/.../memory/` e as usa para pré-popular o BRIEF. Uma vez populado, o BRIEF evolui por si só (validador enriquece), independente das memórias.

## Convenções para novas memórias

- Nome do arquivo em snake_case, com prefixo de tipo: `user_*`, `feedback_*`, `project_*`, `reference_*`.
- Extensão `.md`.
- Frontmatter completo (name, description, type).
- Corpo objetivo. Para feedback/project, usar **Why:** + **How to apply:**.
- Em PT-BR, com acentuação correta.
- Adicionar linha em `MEMORY.md` da mesma pasta.
- Se supersede memória antiga, atualizar a antiga ou removê-la.
