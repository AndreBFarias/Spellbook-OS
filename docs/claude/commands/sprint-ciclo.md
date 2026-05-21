---
description: Ciclo automático de sprint (planejar → executar → validar) sem checkpoints. Até 3 iterações de auto-correção se REPROVADO. Auto-commit + auto-push + auto-PR ao APROVADO.
argument-hint: <ideia-da-sprint>
---

Execute o ciclo completo de uma sprint de forma **totalmente automática**. Só pause para intervenção do usuário em REPROVADO após 3 iterações ou em ambiguidade explícita do spec.

## Fluxo automático (zero checkpoints de aprovação)

**Etapa 1 — Planejamento**

1. Dispatche `planejador-sprint` (subagent, model: opus) com `$ARGUMENTS`.
2. Capture o path do spec gerado (retorno do subagent).
3. Se planejador reporta **ambiguidade** na ideia, PAUSE e peça clarificação ao usuário. Ambiguidade é blocker.
4. Senão, siga IMEDIATAMENTE para Etapa 2 — sem mostrar o spec ao usuário (se quiser revisar, usuário pode rodar `/sprint-ciclo-manual` em vez).

**Etapa 2 — Execução**

1. Dispatche `executor-sprint` (subagent, model: opus) com o spec path.
2. Executor aplica o protocolo v2 (passos PRÉ-0, 0.3, 0.4, 1-7).
3. Se executor retorna **bloqueador** (hipótese divergente via rg, aritmética não fecha, touches fora do escopo), PAUSE e apresente ao usuário.
4. Senão, siga IMEDIATAMENTE para Etapa 3.

**Etapa 3 — Validação**

1. Dispatche `validador-sprint` (subagent, model: opus) com spec + diff + proof-of-work.
2. Capture veredicto: `APROVADO` / `APROVADO_COM_RESSALVAS` / `REPROVADO`.

## Protocolo anti-REPROVADO (auto-correção)

Lê orçamento de retries de `$CLAUDE_SPRINT_CICLO_MAX_RETRIES` (default 3).

- **Iteração 1** (após primeira validação falhar): empacote achados CRÍTICOS + PONTO-CEGO do veredicto como patch-brief. Dispatche executor-sprint novamente com:
  ```
  Retry patch-brief para sprint <ID> (iteração 2/3).
  Achados a corrigir: <lista priorizada com Edit-prontos ou sprint-IDs>.
  Escopo restrito: não expanda touches além do spec original.
  ```
  Achados MINÚCIA **não** entram no patch-brief — viram sprints futuras (anti-débito).

- **Iteração 2** (se validador ainda REPROVA): mesma lógica, segundo retry.

- **Iteração 3** (última tentativa): mesma lógica, terceiro retry.

- **Após 3 iterações** sem APROVADO: PARE. Apresente ao usuário:
  - Diff acumulado
  - Achados persistentes em cada iteração
  - Sugestão de ação (ajustar spec, promover achado para sprint dedicada, abandonar)

## Ao sucesso (APROVADO ou APROVADO_COM_RESSALVAS)

Execute auto-commit + auto-push + auto-PR:

1. Extraia mensagem de commit do spec (título + 1-3 bullets de summary).
2. Invoque o slash command `/commit-push-pr` do plugin `commit-commands`:
   - `git add` apenas arquivos tocados pela sprint.
   - `git commit -m "<título do spec>"` com corpo do spec.
   - **PROIBIDO** na mensagem de commit: emoji, menção a qualquer nome de IA, `Co-Authored-By`, endereços de atribuição automática. O hook `guardian.py` bloqueia se detectar; se bloquear, reescreva a mensagem sem essas atribuições.
   - Se upstream não configurado: `git push -u origin <branch>`. Senão: `git push origin <branch>`.
   - `gh pr create --title "<título>" --body "<body>"`.
3. PR body:
   - Seção `## Summary` (do spec)
   - Seção `## Test plan` (do spec + comandos runtime-real do BRIEF)
   - Seção `## Ressalvas` (se APROVADO_COM_RESSALVAS)
   - Link para `VALIDATOR_BRIEF.md` se foi atualizado
4. Retorne URL do PR ao usuário.

## Regras do ciclo

- **Zero checkpoints** entre planejar → executar → validar. Usuário só intervém em REPROVADO após 3 iterações ou em ambiguidade explícita.
- **Protocolo anti-débito absoluto**: achados colaterais do executor viram sprints novas (auto-dispatch de planejador-sprint). Executor NÃO fixa inline.
- **Todos os subagentes usam `VALIDATOR_BRIEF.md`** do projeto atual como memória compartilhada. Se BRIEF ausente, executor dispatcha validador em MODO BOOTSTRAP antes de começar.
- **Auto-correção máx 3 iterações** por ciclo.
- **Ambiguidade é blocker sempre**. Se spec é ambíguo, pause.
- **Não use `--force`, `--no-verify`, `reset --hard`** em nenhuma etapa.

Para ciclo com checkpoints manuais entre fases, use `/sprint-ciclo-manual`.
