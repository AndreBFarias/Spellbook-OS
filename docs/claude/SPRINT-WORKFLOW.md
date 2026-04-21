# docs/claude/SPRINT-WORKFLOW.md — Ciclo de sprint detalhado

Contrato do ciclo `planejar -> executar -> validar` ponta a ponta, com foco nas regras anti-débito, auto-correção (3-retry) e auto-commit/push/PR ao APROVADO.

## Conceito central

Cada sprint é uma unidade atômica de mudança com:
- **Spec** (escrito pelo planejador): contexto, escopo, acceptance, touches autorizados, proof-of-work esperado
- **Implementação** (executor): diff dentro dos touches, rodando runtime-real
- **Veredicto** (validador): 14 checks + achados com fix-pronto ou sprint-ID

O VALIDATOR_BRIEF.md é memória em disco — lê-se no início de cada sprint, enriquece-se no final.

## Dois modos

### Modo automático (default): `/sprint-ciclo <ideia>`

Sem checkpoints. Dispatch em cadeia. Auto-correção até 3 iterações. Auto-commit+push+PR ao APROVADO.

### Modo manual (opt-in): `/sprint-ciclo-manual <ideia>`

Checkpoints de aprovação entre planejar->executar->validar. Para quando usuário quer revisar passo a passo.

Alias: `sciclom` no shell.

## Fluxo automático completo

```
/sprint-ciclo "adicionar gauge VRAM na TUI"
  |
  +-- Etapa 1: planejador-sprint (subagent opus, contexto isolado)
  |   - Lê BRIEF + CLAUDE.md + exploração do codebase
  |   - Redige spec em ~/.claude/plans/sprint-<ID>.md
  |   - Retorna path do spec
  |
  +-- Etapa 2: executor-sprint (subagent opus, contexto isolado)
  |   - PRÉ-0: Lê BRIEF (se ausente, dispatch validador BOOTSTRAP e PARA)
  |   - 0.3: Verifica hipótese via rg (se divergente, PARA e REPORTA)
  |   - 0.4: Se meta numérica em refactor, valida aritmética (rejeita formal se não fecha)
  |   - 1: Valida spec
  |   - 2: Baseline (FAIL_BEFORE + git status)
  |   - 3: Implementa nos touches autorizados
  |         - Achado colateral -> auto-dispatch planejador-sprint (NÃO fixa inline)
  |   - 4: Verifica incrementalmente
  |   - 5: Proof-of-work runtime-real (do BRIEF)
  |         - Smoke + unit + integração + gauntlet
  |         - Skill validacao-visual auto-invocada se diff toca UI
  |   - 6: Varredura de acentuação periférica em todos arquivos modificados
  |   - 7: Retorno estruturado
  |
  +-- Etapa 3: validador-sprint (subagent opus, contexto isolado)
  |   - Lê BRIEF + CLAUDE.md + spec + diff + proof-of-work
  |   - Aplica 14 checks universais
  |   - Confere skill validacao-visual se UI
  |   - Varre acentuação periférica (check #3)
  |   - Confere aritmética de refactor (check #7) se aplicável
  |   - Emite veredicto: APROVADO / APROVADO_COM_RESSALVAS / REPROVADO
  |   - Cada achado tem Edit-pronto OU sprint-ID (zero follow-up)
  |   - Atualiza BRIEF se detectou padrão novo
  |
  +-- Decisão:
        APROVADO: dispatch /commit-push-pr com mensagem derivada do spec
        APROVADO_COM_RESSALVAS: mesmo, mas lista as ressalvas no PR body
        REPROVADO e iteração < 3: auto-dispatch executor com patch-brief
        REPROVADO e iteração = 3: PARA e apresenta estado ao usuário
```

## Orçamento de iterações

Default: `CLAUDE_SPRINT_CICLO_MAX_RETRIES=3`. Configurável via variável de ambiente.

Em cada iteração de retry:
1. Achados CRÍTICOS + PONTO-CEGO do validador são empacotados como "patch-brief".
2. Executor recebe patch-brief + diff atual + instrução "corrija apenas os achados; não expanda escopo".
3. Executor implementa correção, gera novo proof-of-work.
4. Validador re-valida.

Achados MINÚCIA NÃO são corrigidos inline na iteração — viram sprints futuras (protocolo anti-débito).

## Protocolo anti-débito

### Achado colateral (bug fora do escopo da sprint)

**NUNCA fix inline** no executor. Em vez disso:
- Executor detecta via diff / runtime / proof-of-work
- Dispatcha planejador-sprint com prompt pronto:
  ```
  Nova sprint derivada da sprint <ID> em execução.
  Achado: <descrição detalhada>
  Arquivo: <path:linha>
  Evidência: <grep/stacktrace/repro>
  Proponha spec completo.
  ```
- Planejador-sprint gera spec com ID novo `INFRA-<número-incremental>`
- Registra em `SPRINT_ORDER_MASTER.md` (bloco `<!-- MANUAL_OVERRIDE -->`)
- Executor continua na sprint original

### Achado dentro do escopo (bug nos touches autorizados)

Executor corrige **inline**, documenta no proof-of-work.

### Task mal-dimensionada (aritmética de refactor não fecha)

Executor **rejeita formalmente** (ADR-06 Luna):
- Output:
  ```
  Task rejeitada (ADR-06). Aritmética não fecha.
  Atual=<N>L, extração=<E>L, projetado=<P>L, meta=<M>L.
  Dispatch /planejar-sprint INFRA-NN com TDD detalhado.
  Prompt pronto: <prompt longo sugerido>
  ```
- NÃO implementa
- Registra rejeição em `SPRINT_ORDER_MASTER.md` (bloco `<!-- MANUAL_OVERRIDE -->`)

## Auto-commit + auto-push + auto-PR

Quando validador retorna APROVADO ou APROVADO_COM_RESSALVAS:

1. Extrair mensagem de commit do spec (título + 1-3 bullets).
2. Dispatch do slash command `/commit-push-pr` (plugin `commit-commands`):
   - `git add` nos arquivos modificados
   - `git commit -m "<msg>"` — sem menção a IA, sem emoji (guardian.py trata)
   - Se upstream não configurado: `git push -u origin <branch>`
   - Senão: `git push origin <branch>`
   - `gh pr create --title "<título do spec>" --body "<context + test plan + link BRIEF>"`
3. PR title = título do spec.
4. PR body:
   - Seção Summary (do spec)
   - Seção Test plan (do spec)
   - Ressalvas (se APROVADO_COM_RESSALVAS)
   - Link para VALIDATOR_BRIEF.md atualizado
5. Retorna URL do PR ao usuário.

**Risco declarado**: auto-push/PR publica mudanças sem revisão humana adicional. Mitigação:
- Validador com 14 checks rigorosos.
- Se algo passou, pode ser revertido via `git revert <hash>` + `gh pr close`.
- Usuário autorizou explicitamente em D10 do plano.

## Exceções que pausam o ciclo automático

- **Ambiguidade no spec** (campo [ambíguo]): pausa e pede clarificação. Ambiguidade é blocker.
- **BRIEF ausente**: executor dispatcha validador BOOTSTRAP antes de tudo. Após BRIEF criado, ciclo retoma.
- **Hipótese divergente** (check #4 falha): executor PARA e REPORTA. Usuário decide se spec precisa ajuste.
- **Aritmética não fecha** (check #7): executor rejeita formalmente. Usuário decide se promove sprint nova.
- **REPROVADO após 3 iterações**: ciclo pausa. Usuário revisa estado acumulado.

## Como `/sprint-ciclo` resolve o "plan-clear-execute"

Versões anteriores do Claude Code limpavam contexto via `/clear` ao aprovar plan mode. Hoje a opção existe mas às vezes some (issues #45034, #38071, #39665).

**Solução adotada neste setup**: **subagents já resolvem isso naturalmente**.
- `planejador-sprint` roda em contexto próprio isolado.
- `executor-sprint` idem — não herda nada de planejador.
- `validador-sprint` idem — não herda nada de executor (recebe só diff + proof-of-work).

A conversa principal nunca carrega os contextos internos dos subagents. Logo, mesmo em projetos grandes, a sessão principal permanece enxuta.

Complemento: hook `post-plan-clear.py` sugere `/clear` sutilmente se detecta aprovação de plan fora do ciclo `/sprint-ciclo` (ex: usuário planeja feature pequena em plan mode e executa na conversa principal).

## Métricas de sucesso

| Métrica | Alvo |
|---|---|
| Tempo médio de um ciclo (plan+exec+val) | < 10min em sprint média |
| Tokens por ciclo | < 50k (maioria em subagent-isolated, economiza no principal) |
| Taxa de APROVADO na iteração 1 | > 60% |
| Taxa de APROVADO em até 3 iterações | > 95% |
| Falsos positivos do validador | < 5% |
| Follow-ups acumulados ("issue depois") | 0 (zero-tolerance) |

## Ver também

- [`AGENTS.md`](./AGENTS.md) — detalhes de cada subagent
- [`PADROES-VALIDADOR.md`](./PADROES-VALIDADOR.md) — 14 lições empíricas
- [`CAPACIDADES-VISUAIS.md`](./CAPACIDADES-VISUAIS.md) — pipeline da skill validacao-visual
