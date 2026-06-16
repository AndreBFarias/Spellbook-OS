---
description: Ciclo automático de sprint (planejar → executar → validar) via Workflow determinístico, com painel adversarial de validação e até 3 iterações de auto-correção. Auto-commit + auto-push + auto-PR ao APROVADO.
argument-hint: <ideia-da-sprint>
---

Execute o ciclo completo de uma sprint de forma **automática e determinística**, orquestrado pela ferramenta `Workflow` (loop de retry em código, não na memória do modelo) com **validação adversarial multi-lente**.

## Mecanismo primário — Workflow

Invoque a ferramenta `Workflow` com o script versionado:

```
Workflow({ name: 'sprint-ciclo', args: "$ARGUMENTS" })
```

(Este comando instruindo o uso conta como opt-in explícito do Workflow.)

O workflow (`~/.claude/workflows/sprint-ciclo.js`, canônico em `docs/claude/workflows/`) executa:

1. **Planejar** — `planejador-sprint` redige a spec (lê BRIEF + GSD.md + GUIDE; grep confirma identificadores).
2. **Executar** — `executor-sprint` implementa (protocolo v2: PRÉ-0..7, proof-of-work runtime-real).
3. **Validar (adversarial)** — painel paralelo de `validador-sprint`, uma instância por **lente**, todas READ-ONLY:
   - `correcao-runtime` (lições 1, 4, 7, 11)
   - `acentuacao` (lição 3)
   - `visual` (lições 2, 12 — só se o diff toca UI)
   - `anti-debito-integracao` (lições 5, 6, 9, 13)
4. **Retry determinístico** — se algum achado `CRÍTICO`/`PONTO-CEGO`, empacota como patch-brief e re-executa, até `maxRetries` (default 3). `MINÚCIA`/`IMPORTANTE` **não** entram no patch-brief — viram sprints futuras (anti-débito).

O workflow **não commita**: ele retorna o veredicto para você (main loop) agir. Isso mantém o gate de ação sensível e reusa o `/commit-push-pr` + `guardian.py`.

## Tratamento do retorno do workflow

O workflow retorna um objeto com `status`. Aja conforme:

- **`PAUSA_AMBIGUIDADE`** — a ideia é ambígua. PARE e apresente `perguntas` ao usuário (use AskUserQuestion). Ambiguidade é blocker.
- **`PAUSA_BLOQUEADOR`** — o executor reportou hipótese divergente (grep), aritmética que não fecha, ou touches fora do escopo. PARE e apresente `motivo` + `exec` ao usuário.
- **`REPROVADO_APOS_RETRIES`** — esgotou os retries sem aprovar. PARE e apresente `criticosPersistentes` + `diff` + `sugestao` (ajustar spec, promover a sprint dedicada, ou abandonar).
- **`APROVADO`** / **`APROVADO_COM_RESSALVAS`** — siga para o commit (abaixo).
- **`ERRO`** — reporte `motivo` ao usuário.

## Ao sucesso (APROVADO ou APROVADO_COM_RESSALVAS)

Execute auto-commit + auto-push + auto-PR invocando o slash command `/commit-push-pr`:

1. Mensagem de commit = `titulo` do retorno (+ 1-3 bullets do `resumo`).
2. `git add` **apenas** os `arquivosTocados` do retorno (commit curado por path; **nunca** `git add -A`).
3. **PROIBIDO** na mensagem: emoji, menção a qualquer nome de IA, `Co-Authored-By`, endereços de atribuição automática. O hook `guardian.py` bloqueia; se bloquear, reescreva sem essas atribuições.
4. Se upstream não configurado: `git push -u origin <branch>`. Senão: `git push origin <branch>`.
5. PR body:
   - `## Summary` (do `resumo`)
   - `## Test plan` (do `proofOfWork` + comandos runtime-real do BRIEF)
   - `## Ressalvas` (das `ressalvas`, se `APROVADO_COM_RESSALVAS`)
   - Link para `VALIDATOR_BRIEF.md` se foi atualizado
6. Retorne a URL do PR ao usuário.

## Regras do ciclo (invariantes — valem para Workflow e fallback)

- **Zero checkpoints** entre planejar → executar → validar. O usuário só intervém em `PAUSA_*` ou `REPROVADO_APOS_RETRIES`.
- **Protocolo anti-débito absoluto**: achados colaterais viram sprints novas; executor NÃO fixa inline. `MINÚCIA`/`IMPORTANTE` nunca entram no patch-brief de retry.
- **BRIEF + GSD.md** são memória compartilhada de todos os subagentes. Subagentes não herdam o boot da sessão — cada um lê BRIEF e GSD.md diretamente. Se BRIEF ausente, o executor dispatcha validador em MODO BOOTSTRAP antes de começar.
- **Auto-correção máx `maxRetries`** (default 3) por ciclo.
- **Ambiguidade é blocker sempre.**
- **Nunca** `--force`, `--no-verify`, `reset --hard` em nenhuma etapa.

## Fallback manual (se a ferramenta Workflow estiver indisponível)

Se não for possível invocar `Workflow`, execute o ciclo manualmente, dispatchando os subagentes em sequência e aplicando as mesmas Regras do ciclo acima:

1. Dispatch `planejador-sprint` (model: opus) com `$ARGUMENTS`; capture o spec path. Ambiguidade → pause.
2. Dispatch `executor-sprint` (model: opus) com o spec path. Bloqueador → pause.
3. Dispatch `validador-sprint` (model: opus) com spec + diff + proof-of-work; capture veredicto.
4. Se `REPROVADO`: empacote achados `CRÍTICO`/`PONTO-CEGO` como patch-brief e re-dispatch o executor (iteração 2/3, depois 3/3). Após 3 sem aprovar, pare e apresente o diff acumulado.
5. Ao `APROVADO`/`APROVADO_COM_RESSALVAS`: siga a seção "Ao sucesso" acima.

Para ciclo com checkpoints manuais entre fases, use `/sprint-ciclo-manual`.
