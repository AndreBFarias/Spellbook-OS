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
- `clientId` do designOauth diferente do gravado -> consent re-garantido imediatamente (relogin do design zera o cache).

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

## Plano de implementação

> Para workers agênticos: executar tarefa por tarefa, cada uma com verificação própria. Checkboxes rastreiam progresso.

**Meta:** preflight de sessão no cca que resolve login, design consent e plugins antes de abrir.
**Arquitetura:** 4 funções novas em `cca/aliases_cca.zsh` (2 helpers de estado, o preflight, o doctor) + 3 chamadas de 1 linha + 1 linha no `.gitignore`.
**Stack:** zsh, jq, timeout (coreutils), claude CLI 2.1.200.

**Fatos de schema confirmados (não re-investigar):**
- `claude plugin list --json --available` retorna `{installed: [...], available: [...]}`; join: `installed[].id == available[].pluginId`; versão em `.version` dos dois lados; sentinela `"unknown"` existe nos dois lados.
- `claude auth status --json` retorna `.loggedIn` booleano; ~0.3s; local.
- `designOauth.clientId` em `~/.claude/.credentials.json` identifica o login do design.
- `_helpers.zsh` fornece `D_*`, `__header <titulo> <cor>`, `__ok/__warn/__err`. Carregado em shells interativos — uso apenas em runtime, nunca no top-level do arquivo.
- `.zshrc:25` sourceia `cca/aliases_cca.zsh` — funções disponíveis em `zsh -ic`.

### Tarefa 1: funções novas em `cca/aliases_cca.zsh`

Inserir o bloco abaixo APÓS a função `__cca_unlock_secrets` (linha 44, antes do comentário de `claude-safe`):

```zsh
# ---------------------------------------------------------------------------
# Preflight de sessão (SPR-2026-07-03-cca-preflight)
# Resolve ANTES de abrir a sessão: login principal, design login, design
# consent (headless via print mode — em bypass o prompt de consent nunca
# aparece) e frescor de plugins (marketplace + update dos desatualizados).
# Checks locais toda sessão (~0.3s); rede em cadência de 1 dia, retry
# automático em falha (timestamp só grava em sucesso).
# Escape: CCA_NO_PREFLIGHT=1. Doctor: cca-preflight (ignora cadência).
# ---------------------------------------------------------------------------

# Propósito: lê uma chave do estado do preflight (formato chave=valor).
__cca_pf_get() {
    local f="${ZDOTDIR:-$HOME/.config/zsh}/cca/.cca_preflight_state"
    [ -f "$f" ] || return 1
    grep -m1 "^${1}=" "$f" 2>/dev/null | cut -d= -f2-
}

# Propósito: grava/substitui uma chave no estado (leitura via grep, nunca source).
__cca_pf_set() {
    local f="${ZDOTDIR:-$HOME/.config/zsh}/cca/.cca_preflight_state"
    local resto=""
    [ -f "$f" ] && resto=$(grep -v "^${1}=" "$f" 2>/dev/null)
    { [ -n "$resto" ] && printf '%s\n' "$resto"; printf '%s=%s\n' "$1" "$2"; } > "$f"
}

# Propósito: preflight de sessão. Interno (__cca_run/cca-resume/claude-safe)
# ou manual via cca-preflight. Com --force ignora cadência.
__cca_preflight() {
    [ -n "${CCA_NO_PREFLIGHT:-}" ] && return 0
    command -v jq >/dev/null 2>&1 || return 0  # sem jq, falha-soft: sessão abre sem preflight

    local force=""
    [ "$1" = "--force" ] && force=1
    local ttl=86400 now creds="$HOME/.claude/.credentials.json"
    now=$(date +%s)
    local seg_login seg_design seg_consent seg_plugins

    # 1. Login principal (local, ~0.3s)
    if timeout 10 command claude auth status --json 2>/dev/null | jq -e '.loggedIn' >/dev/null 2>&1; then
        seg_login="login ${D_GREEN}OK${D_RESET}"
    elif [ -t 0 ]; then
        echo -e "${D_PURPLE}[cca]${D_RESET} deslogado — abrindo login antes da sessão..."
        command claude auth login
        if timeout 10 command claude auth status --json 2>/dev/null | jq -e '.loggedIn' >/dev/null 2>&1; then
            seg_login="login ${D_GREEN}OK${D_RESET}"
        else
            __err "login falhou ou foi abortado — sessão não aberta"
            return 1
        fi
    else
        __warn "deslogado e sem TTY — a sessão vai pedir /login"
        seg_login="login ${D_YELLOW}FALTA${D_RESET}"
    fi

    # 2. Design login (local, instantâneo)
    local client_id
    client_id=$(jq -r '.designOauth.clientId // empty' "$creds" 2>/dev/null)
    if [ -n "$client_id" ]; then
        seg_design="design ${D_GREEN}OK${D_RESET}"
    else
        __warn "design deslogado — rode /design-login dentro da sessão"
        seg_design="design ${D_YELLOW}FALTA${D_RESET}"
    fi

    # 3. Consent do design (1x/dia, ou na hora se o clientId mudou = relogin)
    if [ -n "$client_id" ]; then
        local last_ok saved_id
        last_ok=$(__cca_pf_get last_consent_ok); : "${last_ok:=0}"
        saved_id=$(__cca_pf_get consent_client_id)
        if [ -z "$force" ] && [ "$saved_id" = "$client_id" ] && [ $(( now - last_ok )) -lt $ttl ]; then
            seg_consent="consent ${D_GREEN}OK${D_RESET} ${D_COMMENT}(cache)${D_RESET}"
        elif timeout 30 command claude -p --bare "/design consent" >/dev/null 2>&1; then
            __cca_pf_set last_consent_ok "$now"
            __cca_pf_set consent_client_id "$client_id"
            seg_consent="consent ${D_GREEN}OK${D_RESET}"
        else
            __warn "design consent falhou (rede?) — nova tentativa na próxima sessão"
            seg_consent="consent ${D_YELLOW}FALHOU${D_RESET}"
        fi
    else
        seg_consent="consent ${D_COMMENT}pulado${D_RESET}"
    fi

    # 4. Plugins (1x/dia: marketplace update + update só dos desatualizados)
    local last_sync
    last_sync=$(__cca_pf_get last_plugin_sync); : "${last_sync:=0}"
    if [ -z "$force" ] && [ $(( now - last_sync )) -lt $ttl ]; then
        seg_plugins="plugins ${D_GREEN}OK${D_RESET} ${D_COMMENT}(cache)${D_RESET}"
    elif timeout 60 command claude plugin marketplace update >/dev/null 2>&1; then
        local desatualizados pid old new falha=""
        desatualizados=$(command claude plugin list --json --available 2>/dev/null | jq -r '
            (.available | map({key: .pluginId, value: .version}) | from_entries) as $av
            | .installed[]
            | select(.version != null and .version != "unknown")
            | select(($av[.id] // "unknown") != "unknown" and $av[.id] != .version)
            | "\(.id) \(.version) \($av[.id])"' 2>/dev/null)
        while IFS=' ' read -r pid old new; do
            [ -z "$pid" ] && continue
            if timeout 60 command claude plugin update "$pid" >/dev/null 2>&1; then
                echo -e "${D_PURPLE}[cca]${D_RESET} plugin ${pid%%@*} ${old} -> ${D_GREEN}${new}${D_RESET}"
            else
                falha=1
                __warn "update de ${pid%%@*} falhou"
            fi
        done <<< "$desatualizados"
        if [ -z "$falha" ]; then
            __cca_pf_set last_plugin_sync "$now"
            seg_plugins="plugins ${D_GREEN}OK${D_RESET}"
        else
            seg_plugins="plugins ${D_YELLOW}PARCIAL${D_RESET}"
        fi
    else
        __warn "marketplace update falhou (rede?) — nova tentativa na próxima sessão"
        seg_plugins="plugins ${D_YELLOW}FALHOU${D_RESET}"
    fi

    echo -e "${D_PURPLE}[cca]${D_RESET} preflight: $seg_login · $seg_design · $seg_consent · $seg_plugins"
    return 0
}

# Propósito: doctor do cca — preflight completo ignorando cadência.
# Uso: cca-preflight
cca-preflight() {
    __header "CCA PREFLIGHT" "$D_PURPLE"
    __cca_preflight --force
}
```

- [ ] Passo 1.1: inserir o bloco acima em `cca/aliases_cca.zsh` após `__cca_unlock_secrets`.
- [ ] Passo 1.2: `zsh -n cca/aliases_cca.zsh` — esperado: exit 0, sem output.
- [ ] Passo 1.3: `python3 scripts/validar-acentuacao.py --paths cca/aliases_cca.zsh` — esperado: exit 0.

### Tarefa 2: encaixe nos pontos de entrada + `.gitignore`

- [ ] Passo 2.1: em `claude-safe()`, adicionar após a linha `__cca_unlock_secrets  # falha-soft: ...`:
```zsh
    __cca_preflight || return 1
```
- [ ] Passo 2.2: em `__cca_run()`, adicionar como PRIMEIRA linha do corpo (antes de `bash ... cca_guard.sh before`):
```zsh
    __cca_preflight || return 1
```
- [ ] Passo 2.3: em `cca-resume()`, adicionar após o bloco `if ! command -v claude ...fi` (antes do guard):
```zsh
    __cca_preflight || return 1
```
- [ ] Passo 2.4: em `.gitignore`, adicionar após a linha `.cca_quota` (linha 39):
```
.cca_preflight_state
```
- [ ] Passo 2.5: `zsh -n cca/aliases_cca.zsh` — esperado: exit 0.

### Tarefa 3: verificação runtime (proof-of-work do BRIEF)

- [ ] Passo 3.1: `zsh -ic 'true'` — esperado: exit 0 (boot limpo).
- [ ] Passo 3.2: `rm -f cca/.cca_preflight_state && zsh -ic 'cca-preflight'` — esperado: header + linha compacta com `login OK`, `design OK`, `consent OK` (sem cache), `plugins OK`; estado criado com 3 chaves.
- [ ] Passo 3.3: `zsh -ic '__cca_preflight'` — esperado: `consent OK (cache)` e `plugins OK (cache)` (cadência ativa), <1s.
- [ ] Passo 3.4: `CCA_NO_PREFLIGHT=1 zsh -ic '__cca_preflight; echo exit=$?'` — esperado: nenhuma linha de preflight, `exit=0`.
- [ ] Passo 3.5: simular falha de rede no passo de plugins: `rm -f cca/.cca_preflight_state && zsh -ic 'PATH=/usr/bin:/bin; __cca_preflight'` não serve (claude fora do PATH mata tudo); em vez disso, validar o branch de falha com timeout curto: editar NADA — usar `zsh -ic 'timeout() { return 124; }; __cca_preflight'` sobrescrevendo `timeout` por função que falha — esperado: warns de consent e marketplace, linha com `FALHOU`, e `cca/.cca_preflight_state` SEM `last_consent_ok`/`last_plugin_sync` novos. Exit 0 (sessão abriria).
- [ ] Passo 3.6: `git status --porcelain | grep .cca_preflight_state` — esperado: vazio (gitignore ativo).
- [ ] Passo 3.7: conferir escopo: `git status --porcelain` só com `aliases_cca.zsh`, `.gitignore`, `docs/sprints/`.

### Tarefa 4: commit

- [ ] Passo 4.1: `git log --oneline -5` — se autosync já absorveu as edições (`auto: sync nitro-5 ...` recente com os arquivos), NÃO commitar de novo; documentar via `git log --stat -1`.
- [ ] Passo 4.2: caso contrário, commit manual com a mensagem da seção "Mensagem de commit sugerida" (PT-BR, sem emoji/menção-IA). Sem `git push` manual (autosync pusha).

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
