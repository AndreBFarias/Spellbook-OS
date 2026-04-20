---
description: Valida sprint atual disparando subagente Opus validador (auto-inicializa VALIDATOR_BRIEF.md se não existir no projeto)
argument-hint: [caminho-do-plano-opcional]
---

Valide a sprint em execução neste projeto disparando o subagente `validador-sprint`.

## Passos

### 1. Detectar raiz do repo

Execute `git rev-parse --show-toplevel`. Se não está em repositório git, pare e avise o usuário.

### 2. Coletar contexto

- **Diff:** `git diff HEAD~1` (ou desde o último commit relevante conforme hint do proof-of-work na conversa).
- **Plano:** use `$ARGUMENTS` se fornecido. Caso contrário, detecte automaticamente o plano mais provável:
  - Último `.md` modificado em `dev-journey/06-sprints/producao/` (Nyx-Code, Luna)
  - Último `.md` em `dev-journey/06-sprints/` em qualquer subdir
  - Último `.md` em `docs/sprints/`
  - Último arquivo em `~/.claude/plans/`
  - O que existir primeiro na ordem acima.
- **Proof-of-work:** últimas 80 linhas relevantes da conversa atual (diff aplicado, output de checks, mensagens do executor).

### 3. Rodar checks automáticos (detecção heurística)

Detecte no projeto e execute o que for aplicável. Capture as últimas linhas + exit code de cada:

- Se existe `./run.sh` com flag `--smoke`: rodar `./run.sh --smoke`
- Se existe `scripts/sprint_invariants.sh`: rodar
- Se existe `Makefile` com alvo `test`: rodar `make test`
- Se existe `pyproject.toml` com pytest configurado e `./venv/bin/pytest`: rodar `./venv/bin/pytest -q`
- Se existe `pyproject.toml` sem venv local mas com pytest: rodar `pytest -q`
- Se existe `package.json` com script `test`: rodar `npm test` (com timeout reduzido se suspeitar de testes lentos)

Se nada for detectado, anote "nenhum check automático aplicável" e siga.

### 4. Dispatchar subagente

Use o tool `Agent` com `subagent_type: validador-sprint`, `model: opus`. Prompt estruturado:

```
Raiz do repo: <path absoluto>
BRIEF path: <raiz>/VALIDATOR_BRIEF.md (existe? sim/não)

Plano referenciado:
<conteúdo do plano>

Diff completo:
<output de git diff>

Proof-of-work (últimas linhas relevantes):
<resumo estruturado>

Checks automáticos executados:
<output + exit codes de cada check>

Execute o protocolo completo conforme suas instruções (decidir modo, validar, retornar veredicto estruturado).
```

### 5. Apresentar veredicto

Ao receber resposta do subagente:

- Mostre o status (`APROVADO` / `REPROVADO` / `APROVADO_COM_RESSALVAS`) em destaque
- Liste achados agrupados por severidade (`CRÍTICO` / `IMPORTANTE` / `MINÚCIA`)
- Se `REPROVADO`, apresente sugestões concretas e **aguarde decisão** do usuário antes de tentar corrigir
- Se o BRIEF foi atualizado, mostre resumo de 2-3 linhas do que mudou + path do arquivo

Não tome ações corretivas sem aprovação explícita do usuário quando o status for `REPROVADO`.
