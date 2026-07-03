# SPR-2026-07-03-cca-preflight

Preflight inteligente no `cca`: detectar e resolver login, design login, design consent e frescor de plugins ANTES de abrir a sessão, eliminando o ritual manual de `/reload-plugins`, `/design consent`, `/design-login` e `/login` no meio do fluxo.

Design aprovado pelo usuário em 3 seções nesta sessão (2026-07-03). Abordagem A: preflight síncrono no zsh, checks rápidos toda sessão + ações de rede 1x/dia.

## Contexto

O `cca` roda sempre com `--dangerously-skip-permissions` (bypass). Nesse modo, o prompt de consent do Claude Design é suprimido e não pode ser auto-aprovado — string literal do binário CC 2.1.200: *"run /design consent to grant it (it can't be approved automatically in this permission mode)"*. Resultado: o usuário precisava rodar manualmente uma sequência de comandos a cada sessão, interrompendo o progresso.

Sintomas confirmados pelo usuário (todos os 4): design pede consent, plugins/skills stale, login principal expira às vezes, ritual preventivo sem saber o que é necessário.

## Investigação realizada (fatos confirmados em 2026-07-03)

| Ponto | Resultado |
|---|---|
| Consent do design | Server-side: `GET/POST/DELETE /v1/design/consent` (bit `agent_design_projects`). Persiste na conta. Inacessível de fora (404 na api.anthropic.com direta, Cloudflare no claude.ai). |
| Built-ins em print mode | `claude -p --bare "/design consent"` FUNCIONA headless: concedeu consent, exit 0, ~1s. Idempotente. |
| Login principal | `claude auth status --json` retorna `.loggedIn` em ~0.3s (leitura local, funciona offline). `claude auth login` existe para fluxo interativo. |
| Design login | Bloco `designOauth` em `~/.claude/.credentials.json` (accessToken/refreshToken/expiresAt/clientId). Refresh automático; só some se nunca logou ou revogou. Sem CLI de status. |
| `/reload-plugins` no startup | Redundante: sessão nova carrega plugins do zero (doc oficial). Útil só mid-session. Sem equivalente headless. |
| Frescor de plugins | `claude plugin marketplace update` (headless, atualiza índices). `claude plugin list --json --available` lista instalada vs disponível. `claude plugin update <id>` atualiza; no-op limpo "already at the latest version" (~1.6s por plugin — atualizar SÓ os desatualizados). |
| Versões "unknown" | Alguns plugins reportam `version: "unknown"` no `plugin list --json` — comparação deve pular esses (sem crash, sem update cego). |
| DesignSync em bypass | Testado nesta sessão: `list_projects` funcionou sem prompt — consent já gravado na conta do usuário. |

## Decisões do usuário

1. UX: resolver ANTES de abrir a sessão (login interativo no terminal; nada de comandos dentro da sessão).
2. Plugins: auto-update com aviso de 1 linha por plugin atualizado, cadência 1x/dia.
3. Saída: 1 linha compacta sempre visível no caso feliz.
4. Abordagem A aprovada (preflight síncrono, cadência diária para rede, falha-soft).

## Escopo (touches autorizados)

- Arquivos a modificar: **APENAS estes 2**
  - `cca/aliases_cca.zsh` — função `__cca_preflight` + helpers de estado + comando `cca-preflight` + 3 chamadas de 1 linha (`__cca_run`, `cca-resume`, `claude-safe`)
  - `.gitignore` — 1 linha: `.cca_preflight_state`
- Arquivos criados em runtime (não commitados): `cca/.cca_preflight_state`
- Arquivos NÃO a tocar (proibido):
  - `cca/cca_guard.sh`, `cca/cca_quota_manager.sh` (quota intocada)
  - `functions/spellbook-sync.zsh`, `.githooks/*`, `hooks/*`
  - `claude-force` (é o escape hatch — permanece sem checks)
  - Qualquer outro `.zsh`, `.sh`, `.py` fora dos 2 listados

## Design

### Encaixe

```
cca / cca-here / cca-ghostty / cca-tmux -> __cca_run --+
cca-resume --------------------------------------------+--> __cca_preflight (novo, ANTES do guard)
claude-safe -------------------------------------------+
claude-force -> sem preflight (escape hatch)
```

O preflight roda antes de `cca_guard.sh before` e antes da medição `pre_size` (assim os bytes de transcript do `-p` interno não inflam a estimativa de tokens).

### Passos, na ordem

1. **Login principal** (toda sessão, ~0.3s, local):
   - `claude auth status --json` com `loggedIn: true` -> segue em silêncio.
   - `loggedIn: false` E stdin é TTY -> mensagem + `command claude auth login` interativo; re-checa; falhou/abortou -> `__err` e **aborta** (return 1).
   - `loggedIn: false` SEM TTY -> `__warn` e segue (não pode interagir; sessão vai falhar com mensagem própria do CC).
2. **Design login** (toda sessão, ~0ms, local):
   - `designOauth` presente no `~/.claude/.credentials.json` (via `jq -e '.designOauth.accessToken'`) -> segue.
   - Ausente -> `__warn "design deslogado — rode /design-login dentro da sessão"` e segue. Passo 3 é pulado.
3. **Consent do design** (1x/dia OU quando `designOauth.clientId` mudou, ~1s):
   - `timeout 30 claude -p --bare "/design consent"` exit 0 -> grava `last_consent_ok=<epoch>` e `consent_client_id=<clientId>` no estado.
   - Falha -> `__warn` com motivo, NÃO grava timestamp (re-tenta na próxima sessão), segue.
4. **Plugins** (1x/dia, rede, o mais lento):
   - `timeout 60 claude plugin marketplace update` -> falhou: `__warn`, não grava timestamp, segue.
   - `claude plugin list --json --available` -> para cada plugin com versão instalada != disponível (ambas conhecidas, pular "unknown"): `timeout 60 claude plugin update <id>` + linha `[cca] plugin <nome> <velha> -> <nova>`.
   - Sucesso total -> grava `last_plugin_sync=<epoch>`.

### Estado e cadência

- Arquivo `cca/.cca_preflight_state`, formato `chave=valor` (uma por linha): `last_consent_ok`, `consent_client_id`, `last_plugin_sync`.
- Leitura via grep/cut (sem source — sem execução de conteúdo).
- Cadência: 86400s. Passo de rede que falha não grava timestamp -> retry automático na próxima sessão.
- `clientId` do designOauth diferente do gravado -> consent re-garantido imediatamente (relogin do design inválida cache).

### Saída (paleta Dracula, helpers ASCII da casa)

Caso feliz (tudo cache):
```
[cca] preflight: login OK · design OK · consent OK (cache) · plugins OK (cache)
```
Com ação executada, o `(cache)` some do item executado e linhas extras aparecem só para updates de plugin ou warns. Item em falha aparece na própria linha em amarelo (ex: `design FALTA`), com o `__warn` detalhado na linha seguinte. Cores: label `[cca]` em `D_PURPLE`, OK em `D_GREEN`, `(cache)` em `D_COMMENT`, warns via `__warn`.

### Escape hatches

- `CCA_NO_PREFLIGHT=1 cca` — pula o preflight inteiro (padrão do `CCA_CONTEXT7`).
- `claude-force` — segue sem nenhum check (inalterado).
- `cca-preflight` — comando manual: roda tudo ignorando cadência, relatório verboso (`__header` + `__ok`/`__warn`/`__err` por check). É o "doctor" do cca.

## Acceptance criteria

1. `zsh -n cca/aliases_cca.zsh` exit 0.
2. `zsh -ic 'true'` exit 0 (boot limpo).
3. Com tudo OK e cache quente: `cca` mostra exatamente 1 linha de preflight e o startup adiciona <1s (medível: passos 3-4 pulados por cadência).
4. `CCA_NO_PREFLIGHT=1` não emite nenhuma linha de preflight e não lê/escreve estado.
5. `cca-preflight` (manual) executa os 4 passos ignorando cadência e imprime relatório verboso.
6. Estado gravado em `cca/.cca_preflight_state` com as 3 chaves; arquivo ausente = primeira execução completa (sem crash).
7. Simulação de falha de rede (ex: `timeout 1` forçado ou offline): sessão abre mesmo assim, warn visível, timestamp não gravado.
8. `.gitignore` contém `.cca_preflight_state`; `git status --porcelain` não lista o arquivo de estado após rodar.
9. `python3 scripts/validar-acentuacao.py --paths cca/aliases_cca.zsh` exit 0.
10. Zero funções removidas ou com assinatura alterada em `aliases_cca.zsh` (diff só adiciona + 3 linhas de chamada).
11. Plugin com `version: "unknown"` não gera update cego nem crash no comparador.

## Invariantes a preservar (do BRIEF)

- **#1 PATH idempotente**: não aplicável (sem PATH).
- **#3 Autosync ativo**: sem `git push` manual; antes de commit manual, `git log --oneline -5`.
- **#8 Zero funções removidas**: só adições + chamadas de 1 linha em 3 funções existentes.
- **#9 Acentuação PT-BR estrita**: comentários novos validados por `validar-acentuacao.py`.
- **#10 Paleta Dracula**: usar `D_*` e `__ok/__warn/__err` de `_helpers.zsh`; marcadores ASCII (sem glyphs fora do canônico — pre-commit remove).
- **Sem emoji/menção-IA em commits**: pre-push bloqueia.

## Proof-of-work esperado (runtime-real)

```bash
cd ~/.config/zsh
zsh -n cca/aliases_cca.zsh
zsh -ic 'true'
python3 scripts/validar-acentuacao.py --paths cca/aliases_cca.zsh
# preflight manual verboso (executa de verdade: auth 0.3s + consent 1s + plugins)
zsh -ic 'cca-preflight'
# cadência: segunda chamada deve mostrar (cache) nos passos 3-4
rm -f cca/.cca_preflight_state && zsh -ic 'cca-preflight' && zsh -ic '__cca_preflight'
# escape hatch
CCA_NO_PREFLIGHT=1 zsh -ic '__cca_preflight; echo exit=$?'
# escopo cirúrgico
git status --porcelain | grep -vE '^\?\?|aliases_cca\.zsh|\.gitignore|docs/sprints/' || echo "OK escopo"
```

## Riscos e não-objetivos

- **Não-objetivo**: automatizar `/design-login` (OAuth com browser+callback; manual por natureza, raro).
- **Não-objetivo**: `/reload-plugins` mid-session (impossível de fora; preflight elimina a necessidade no startup).
- **Não-objetivo**: tocar quota guard, slice systemd, NODE_OPTIONS.
- **Risco aceito**: `claude -p --bare` cria transcript mínimo em `~/.claude/projects/` (1x/dia, bytes desprezíveis; roda antes do `pre_size`, não infla estimativa).
- **Risco aceito**: `/design consent` re-concede sem checar (GET externo inacessível). Idempotente por design do endpoint.
- **Risco aceito**: comportamento de `-p --bare "/design consent"` é interno não-documentado do CC — pode quebrar em versão futura. Mitigação: falha-soft com warn; pior caso volta ao estado atual (rodar manual).
- **Dependência**: `jq` (já usado no repo — invariante `functions/restaurar.zsh:402`).

## Mensagem de commit sugerida

```
feat(cca): preflight de sessão — login, design consent e plugins resolvidos antes de abrir

Adiciona __cca_preflight aos pontos de entrada (cca/resume/safe): checa login
principal (auth status, 0.3s), presença do design login, garante design consent
headless (print mode, 1x/dia ou quando clientId muda) e atualiza marketplace +
plugins desatualizados (1x/dia, com aviso por plugin). Falha-soft com timeout:
offline nunca trava o startup. Escape: CCA_NO_PREFLIGHT=1; doctor: cca-preflight.
Elimina o ritual manual de /login, /design consent, /design-login e /reload-plugins.
```

## Referências

- BRIEF: `VALIDATOR_BRIEF.md` (invariantes #3, #8, #9, #10)
- Infra alvo: `cca/aliases_cca.zsh` (`__cca_run:163`, `cca-resume:362`, `claude-safe:48`, padrão `CCA_CONTEXT7:180`)
- Helpers de saída: `functions/_helpers.zsh:47-49`
- Estado análogo: `cca/.cca_quota` (gitignored linha 39 do `.gitignore`)
- Strings do binário CC 2.1.200 que fundamentam o design: usage `/design consent | /design revoke`; endpoints `/v1/design/consent`; erro "can't be approved automatically in this permission mode"
