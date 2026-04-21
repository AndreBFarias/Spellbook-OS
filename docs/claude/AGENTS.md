# docs/claude/AGENTS.md — Catálogo dos subagents

3 subagents opus, todos em `docs/claude/agents/` (symlinked em `~/.claude/agents/`).

## planejador-sprint

**Path**: `docs/claude/agents/planejador-sprint.md`
**Modelo**: opus
**Tools**: Read, Grep, Glob, Bash, Write

### Quando dispara

- `/planejar-sprint <ideia>` — dispatch explícito
- Fase 1 de `/sprint-ciclo` — dispatch automático
- Auto-dispatchado por executor-sprint quando detecta **achado colateral** (protocolo anti-débito) ou **task mal-dimensionada** (aritmética de refactor não fecha)

### Inputs

- `$ARGUMENTS`: ideia, bug, requisito ou prompt estruturado (quando dispatchado por executor)
- Raiz do repo: `git rev-parse --show-toplevel`
- BRIEF do projeto: `$CLAUDE_BRIEF_PATH` (exportado pelo `cca`)
- CLAUDE.md global: `~/.config/zsh/AI.md` (protocolo universal)

### Output

Spec em `~/.claude/plans/sprint-<ID>.md` ou `dev-journey/06-sprints/producao/<ID>.md` (se diretório existir no projeto). Estrutura obrigatória:

1. Contexto (por que a sprint existe)
2. Escopo + touches autorizados
3. Acceptance criteria
4. Invariantes a preservar
5. Plano de implementação (passos)
6. Testes com `FAIL_BEFORE` / `FAIL_AFTER`
7. Proof-of-work esperado (inclui comando runtime-real do BRIEF)
8. Riscos e não-objetivos

Se spec declara meta numérica (ex: `<800L`), obrigatoriamente cita a aritmética esperada.

### Regras

- Não implementa código
- Rejeita escopo monolítico; divide em sub-sprints com IDs próprios se necessário (lição 10)
- Evita inventar — todos os identificadores citados devem existir no codebase (grep confirma)

## executor-sprint

**Path**: `docs/claude/agents/executor-sprint.md`
**Modelo**: opus
**Tools**: Read, Grep, Glob, Bash, Write, Edit, MultiEdit, Skill

### Quando dispara

- `/executar-sprint [spec]` — dispatch explícito
- Fase 2 de `/sprint-ciclo` — automático após planejador terminar
- Retry em iteração 2/3 de `/sprint-ciclo` quando validador retorna REPROVADO (injeta achados CRÍTICOS como patch-brief)

### Passos

0.1 **Lê o BRIEF**. Se ausente, PARA e dispatcha validador-sprint em MODO BOOTSTRAP.
0.3 **Verifica hipótese do planejador**: `rg` pelos identificadores citados. Se 0 matches, PARA e REPORTA divergência com dados (lição 4).
0.4 **Valida aritmética de refactor**: se spec declara meta numérica, `wc -l` + projeção. Se não fecha, rejeita formalmente (ADR-06 Luna) e propõe nova sprint INFRA-NN (lição 7).
1. Valida spec integral (contexto + acceptance + touches).
2. Baseline: FAIL_BEFORE, `git status`, `git log --oneline -3`.
3. Implementa apenas em touches autorizados. Se detecta **achado colateral**, NÃO fixa inline — dispatcha planejador-sprint automaticamente com prompt pronto (lição 5).
4. Verifica incrementalmente.
5. **Proof-of-work runtime-real** (lê `Contratos de runtime` do BRIEF): smoke + unit tests + integração + gauntlet. Inclui output literal, exit code, duração. Skill `validacao-visual` é auto-invocada se diff toca UI (lições 1, 12).
6. **Varredura de acentuação periférica**: para cada arquivo modificado, `python3 ~/.config/zsh/scripts/validar-acentuacao.py`. Reporta violações como PONTO-CEGO (lição 3).
7. Retorno estruturado: Diff + FAIL_BEFORE/AFTER + checks + Runtime real + Validação visual + Acentuação.

### Regras

- Nunca `--force`, `--no-verify`, `reset --hard`
- Não faz commit sem instrução explícita (exceto quando chamado por /sprint-ciclo automático em APROVADO)
- Respeita `skipDangerousModePermissionPrompt`
- Protocolo anti-débito: achado colateral = sprint nova, nunca fix inline

## validador-sprint

**Path**: `docs/claude/agents/validador-sprint.md`
**Modelo**: opus
**Tools**: Read, Grep, Glob, Bash, Write, Edit

### Modos

#### MODO BOOTSTRAP (projeto genérico sem BRIEF)

Exploração exaustiva read-only:
- CLAUDE.md local + global
- README.md, CHANGELOG.md, CONTRIBUTING.md, GSD.md
- Manifesto: pyproject.toml, package.json, Cargo.toml, go.mod, requirements*.txt
- Build: Makefile, Justfile, install.sh, run.sh, run_luna.sh
- 2 níveis de estrutura (Glob)
- Diretórios especiais: `dev-journey/`, `docs/`, `adr/`, `docs/adr/`, `.claude/`, `scripts/`, `hooks/`, `.github/workflows/`
- Detecta tipo-de-projeto: `tui | gui | web | cli | lib | docs`

Grava `VALIDATOR_BRIEF.md` completo na raiz (usando `VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md`).

#### MODO BOOTSTRAP_RICO (projeto conhecido + memórias)

Se `SPECIAL_PROJECTS.json` casa kind (luna/nyx-code/protocolo-ouroboros) E memórias existem em `~/.claude/projects/-home-andrefarias-Desenvolvimento-<Dir>/memory/*.md`:

Invoca `python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto <kind> --saida <root>/VALIDATOR_BRIEF.md`. BRIEF pré-populado com todas as lições empíricas daquele projeto + template específico.

#### MODO VALIDATE (BRIEF presente + sprint ativa)

1. Lê: BRIEF + CLAUDE.md + plano + diff + proof-of-work do executor.
2. Valida contra matriz das 14 lições (ver `PADROES-VALIDADOR.md`). Cada check ativado segundo o BRIEF.
3. Aciona skill `validacao-visual` automaticamente se diff toca UI.
4. Varre acentuação periférica em arquivos modificados.
5. Confere aritmética de refactor se spec tem meta numérica.
6. **Protocolo anti-débito enforceado**: nenhum achado pode sair como "abrir issue depois". Cada achado tem:
   - Edit exato (`old_string` / `new_string`)
   - Bash exato (`sed -i '...'`)
   - ID sprint-nova (com prompt pronto para `/planejar-sprint`)
7. Atualiza BRIEF quando detecta padrão novo recorrente.
8. Emite veredicto.

### Severidades

- **CRÍTICO**: quebra sistema ou introduz regressão
- **IMPORTANTE**: viola contrato/convenção
- **PONTO-CEGO**: escapa da auto-revisão (acentuação periférica, docstrings ornamentais) — sobrepõe IMPORTANTE
- **MINÚCIA**: cosmético

### Output

```
# Veredicto — SPRINT <ID>
## Status: APROVADO | APROVADO_COM_RESSALVAS | REPROVADO
## Iteração: <N>/3
## Achados
### CRÍTICO / PONTO-CEGO / IMPORTANTE / MINÚCIA
## Evidência visual (PNG + sha256 + descrição)
## Checks universais ativados vs passados (tabela)
## BRIEF atualizado? (sim/não + resumo)
## Próximo passo automático (commit OU retry OU pausa)
```

### Regras

- Nunca `--force`, nunca destrói estado
- BRIEF é versionado — grava no repo-alvo, não no Spellbook-OS
- PROIBIDO: "abrir issue depois", "criar TODO", "seria bom revisar", "pré-existente fora escopo"

## Como os agents se chamam

```
/sprint-ciclo
    -> planejador-sprint (subagent isolado)
    -> executor-sprint (subagent isolado)
         -> se achado colateral: auto-dispatch planejador-sprint (sub-sub-agent)
    -> validador-sprint (subagent isolado)
         -> skill validacao-visual (se UI)
    -> (se REPROVADO) auto-dispatch executor-sprint (iteração 2/3)
    -> (se APROVADO) dispatch /commit-push-pr
```

Cada subagent tem contexto **isolado** — não herda a conversa principal. Esse é o mecanismo que economiza tokens e evita alucinação em projetos grandes.

## Quando NÃO usar

- Tarefa trivial (renomear variável, corrigir typo): usar Read/Edit direto, não dispatch de sprint-ciclo.
- Exploração / aprendizado / perguntas: usar Read/Grep/Glob ou Agent do tipo Explore direto.
- Diagnóstico de bug pontual: superpowers `systematic-debugging` pode ser mais apropriado.
