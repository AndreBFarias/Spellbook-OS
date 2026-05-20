# SPR-2026-05-20-topgrade-fix

Fix de 2 regressões observadas em `topgrade` (2026-05-20): pnpm sem PATH e prevenção de drift de permissões em `~/.oh-my-zsh/`.

Fonte de verdade: `/home/andrefarias/.claude/plans/17-43-58-humming-newell.md` (plano aprovado pelo usuário).

## Contexto

1. **pnpm sem PATH** — `/home/andrefarias/.local/share/pnpm/bin` existe mas nenhum rc shell exporta `PNPM_HOME` nem adiciona ao PATH. Gap real na config, não-regressão.
2. **Drift histórico em `~/.oh-my-zsh/`** — 20 arquivos com modo 755→644 (mtime 2025-08-11, ~9 meses atrás). Causa raiz não-identificável. `git restore` já foi feito manualmente antes desta sprint. Falta prevenção: detectar e auto-restaurar drift futuro.

## Escopo (touches autorizados)

- Arquivos a modificar: **APENAS estes 2**
  - `/home/andrefarias/.config/zsh/env.zsh` — +3 linhas após linha 23
  - `/home/andrefarias/.config/zsh/functions/aurora-self-heal.zsh` — +9 linhas antes da linha 102 + 1 linha no case do loop de fixes_user
- Arquivos a criar: nenhum
- Arquivos NÃO a tocar (proibido):
  - `functions/spellbook-sync.zsh` (autosync)
  - `.githooks/*` e `hooks/*`
  - `scripts/universal-sanitizer.py`
  - Qualquer outro `.zsh`, `.sh`, `.py` fora dos 2 listados

## Acceptance criteria

1. `zsh -n env.zsh` exit 0
2. `zsh -n functions/aurora-self-heal.zsh` exit 0
3. `zsh -ic 'echo $PNPM_HOME'` printa `/home/andrefarias/.local/share/pnpm`
4. `zsh -ic 'echo $PATH' | tr ":" "\n" | grep -c "pnpm/bin"` retorna exatamente `1` (idempotente, mesmo carregando 2x)
5. `zsh -ic 'pnpm root -g'` não emite `ERROR.*not in PATH`
6. `aurora-self-heal` detecta `~/.oh-my-zsh` em drift (porcelain > 0) e reporta no array `issues`
7. `aurora-self-heal` aplica fix automaticamente quando drift detectado (loop processa o `git ...` no `fixes_user[@]`)
8. `git status --porcelain` após edits contém apenas `env.zsh` e `functions/aurora-self-heal.zsh` (escopo cirúrgico)
9. `python3 scripts/validar-acentuacao.py --paths env.zsh functions/aurora-self-heal.zsh` exit 0

## Invariantes a preservar (do BRIEF)

- **Invariante #1 — PATH idempotente**: usar `__add_to_path_once`, NUNCA `export PATH="...:$PATH"`. Helper já existe em `functions/_helpers.zsh:55-62` e em forma local em `env.zsh:10-15`.
- **Invariante #7 — Aurora self-heal 12 checks**: o novo check vira o 13º. Preservar padrão `issues+=("...")` + `fixes_user+=("...")` ou `fixes_root+=("...")`.
- **Invariante #8 — Zero funções removidas**: nenhuma função existente alterada na assinatura.
- **Invariante #9 — Acentuação PT-BR estrita**: comentários em português com acentuação correta. `validar-acentuacao.py` é juiz.
- **Sem emoji em commit ou código**: pre-push regex `_EMOJI` bloqueia.
- **Sem co-autoria/menção-IA em commit**: pre-push regex `_COAUTHOR` e `_AI` bloqueiam.
- **Autosync ativo**: não rodar `git push` manual após Edit; autosync absorve. Conferir `git log --stat -1` em vez de só `git status`.

## Investigação realizada (fatos confirmados)

| Ponto | Resultado |
|---|---|
| `env.zsh:23` literal | `__add_to_path_once "$HOME/.spicetify"` (linha 23, antes da linha 24 vazia e da 25 `export ZSH=...`) |
| `aurora-self-heal()` range | linhas 15-133 de `functions/aurora-self-heal.zsh` |
| Último check existente | APT post-invoke (linhas 97-100) |
| Ponto de inserção do novo check | **antes da linha 102** (`if [ ${#issues[@]} -eq 0 ]; then`) |
| Loop de aplicação de `fixes_user[@]` | linhas 111-116 — case match: `*systemctl*` → eval; senão `[ -x "$fix" ]` → executa como arquivo |
| **GAP descoberto** | Comando `git -C ... restore ...` NÃO casa `*systemctl*` e NÃO é arquivo executável → loop atual NUNCA aplicaria o fix. Precisa estender o case. |
| `__add_to_path_once` assinatura | `__add_to_path_once <dir>` — 1 argumento posicional, sem kwargs |
| Helper local em env.zsh | Linhas 10-15 — versão minimalista para boot antes de `_helpers.zsh` carregar. Funcional para o pnpm PATH. |

## Plano de implementação

### Passo 1 — `env.zsh`: inserir bloco pnpm após linha 23

**Antes** (linhas 20-25):
```zsh
__add_to_path_once "/snap/bin"
__add_to_path_once "$HOME/.local/bin"
__add_to_path_once "$HOME/.cargo/bin"
__add_to_path_once "$HOME/.spicetify"

export ZSH="${ZDOTDIR:-$HOME/.config/zsh}/.oh-my-zsh"
```

**Depois** (linhas 20-28):
```zsh
__add_to_path_once "/snap/bin"
__add_to_path_once "$HOME/.local/bin"
__add_to_path_once "$HOME/.cargo/bin"
__add_to_path_once "$HOME/.spicetify"

# pnpm (instalado via nvm/corepack; binários globais em PNPM_HOME/bin).
export PNPM_HOME="$HOME/.local/share/pnpm"
__add_to_path_once "$PNPM_HOME/bin"

export ZSH="${ZDOTDIR:-$HOME/.config/zsh}/.oh-my-zsh"
```

**Diff exato** (3 linhas inseridas após `env.zsh:23`, antes da linha 24 em branco):
```
+
+# pnpm (instalado via nvm/corepack; binários globais em PNPM_HOME/bin).
+export PNPM_HOME="$HOME/.local/share/pnpm"
+__add_to_path_once "$PNPM_HOME/bin"
```

(A linha em branco existente em `env.zsh:24` é mantida; o novo bloco fica entre o `.spicetify` e essa linha em branco.)

### Passo 2 — `functions/aurora-self-heal.zsh`: inserir check antes da linha 102

**Antes** (linhas 96-104):
```zsh
  # APT post-invoke hook (defesa contra removal acidental)
  if [ ! -f /etc/apt/apt.conf.d/99-aurora-postinvoke ]; then
    issues+=("APT post-invoke hook ausente (auto-reapply não vai disparar em próximo upgrade)")
    fixes_root+=("$aurora/aurora-reapply-all.sh")
  fi

  if [ ${#issues[@]} -eq 0 ]; then
    return 0
  fi
```

**Depois** (linhas 96-113):
```zsh
  # APT post-invoke hook (defesa contra removal acidental)
  if [ ! -f /etc/apt/apt.conf.d/99-aurora-postinvoke ]; then
    issues+=("APT post-invoke hook ausente (auto-reapply não vai disparar em próximo upgrade)")
    fixes_root+=("$aurora/aurora-reapply-all.sh")
  fi

  # ~/.oh-my-zsh drift (executabilidade removida em massa por causa desconhecida — incidente 2025-08-11)
  if [ -d "$HOME/.oh-my-zsh/.git" ]; then
    local omz_dirty
    omz_dirty=$(git -C "$HOME/.oh-my-zsh" status --porcelain 2>/dev/null | wc -l)
    if [ "$omz_dirty" -gt 0 ]; then
      issues+=("oh-my-zsh com $omz_dirty arquivos em drift (provável regressão de permissões)")
      fixes_user+=("git -C $HOME/.oh-my-zsh restore --staged --worktree -- .")
    fi
  fi

  if [ ${#issues[@]} -eq 0 ]; then
    return 0
  fi
```

### Passo 3 — `functions/aurora-self-heal.zsh`: estender case do loop de `fixes_user` para aceitar `git ...`

**Justificativa**: o template do usuário coloca um comando shell-string (`git -C ... restore ...`) em `fixes_user[@]`. O loop atual (linhas 111-116) só processa `*systemctl*` (via `eval`) ou paths executáveis (via `[ -x "$fix" ]`). Sem extensão do case, o fix é detectado mas nunca aplicado, contradizendo o ACC-7. Extensão é cirúrgica: 1 linha, padrão `eval` mesmo do branch `systemctl`.

**Antes** (linhas 111-116):
```zsh
  for fix in "${fixes_user[@]}"; do
    case "$fix" in
      *systemctl*) eval "$fix" 2>/dev/null && applied=$((applied+1)) ;;
      *) [ -x "$fix" ] && "$fix" >/dev/null 2>&1 && applied=$((applied+1)) ;;
    esac
  done
```

**Depois**:
```zsh
  for fix in "${fixes_user[@]}"; do
    case "$fix" in
      *systemctl*) eval "$fix" 2>/dev/null && applied=$((applied+1)) ;;
      git\ *) eval "$fix" 2>/dev/null && applied=$((applied+1)) ;;
      *) [ -x "$fix" ] && "$fix" >/dev/null 2>&1 && applied=$((applied+1)) ;;
    esac
  done
```

Apenas 1 linha adicionada: `      git\ *) eval "$fix" 2>/dev/null && applied=$((applied+1)) ;;` entre o branch `*systemctl*` e o branch default.

**Após o passo 2 a linha do loop terá deslocado +9 (de `:111` para `:120`).** Aplicar o passo 3 após o passo 2 e localizar via `rg '\*systemctl\*\) eval' functions/aurora-self-heal.zsh` para confirmar a linha exata antes de editar.

## Aritmética

Sem meta numérica de redução de linhas. Adições:
- `env.zsh`: +4 linhas (1 em branco + 3 de código). Total esperado: 164 → 168.
- `functions/aurora-self-heal.zsh`: +9 linhas (passo 2) + 1 linha (passo 3) = +10. Total esperado: 151 → 161.

## Testes (Proof-of-work obrigatório)

Executar literalmente, na ordem, a partir de `/home/andrefarias/.config/zsh`:

```bash
# 1. Syntax check
zsh -n env.zsh
zsh -n functions/aurora-self-heal.zsh

# 2. pnpm PATH em shell fresh
DUPS=$(zsh -ic 'echo $PATH' | tr ":" "\n" | grep -c "pnpm/bin")
[[ "$DUPS" -eq 1 ]] && echo "OK pnpm no PATH e idempotente" || { echo "FAIL: PATH errado (count=$DUPS)"; exit 1; }
zsh -ic 'echo $PNPM_HOME' | grep -q '/home/andrefarias/.local/share/pnpm' && echo "OK PNPM_HOME" || { echo "FAIL PNPM_HOME"; exit 1; }

# 3. pnpm root -g funciona sem erro de PATH
zsh -ic 'pnpm root -g' 2>&1 | grep -qE 'ERROR.*not in PATH' && { echo "FAIL: erro persiste"; exit 1; } || echo "OK pnpm operacional"

# 4. Self-heal detecta e cura drift simulado
chmod 644 ~/.oh-my-zsh/tools/upgrade.sh
PRE=$(git -C ~/.oh-my-zsh status --porcelain | wc -l)
[[ "$PRE" -gt 0 ]] || { echo "FAIL: drift não simulou"; exit 1; }
zsh -ic 'source ~/.config/zsh/functions/aurora-self-heal.zsh && aurora-self-heal' 2>&1 | grep -q 'oh-my-zsh' && echo "OK self-heal detectou" || { echo "FAIL: self-heal não detectou"; exit 1; }
git -C ~/.oh-my-zsh restore --staged --worktree -- .
POST=$(git -C ~/.oh-my-zsh status --porcelain | wc -l)
[[ "$POST" -eq 0 ]] && echo "OK fix repara" || { echo "FAIL: fix não curou"; exit 1; }

# 5. Idempotência rodando 2x
zsh -ic 'source ~/.config/zsh/env.zsh; source ~/.config/zsh/env.zsh; echo $PATH' | tr ":" "\n" | grep -c "pnpm/bin"
# esperado: 1

# 6. Escopo cirúrgico
git status --porcelain | grep -vE '^\?\?|env\.zsh|aurora-self-heal\.zsh' && { echo "FAIL: touches fora do escopo"; exit 1; } || echo "OK escopo"

# 7. Acentuação PT-BR
python3 scripts/validar-acentuacao.py --paths env.zsh functions/aurora-self-heal.zsh
```

**Nota sobre o passo 4**: a chamada `aurora-self-heal` no shell de teste deve aplicar o fix automaticamente (graças ao passo 3 do plano que estendeu o case do loop). O `git -C ... restore ...` explícito no script de teste é redundância de segurança caso o loop ainda falhe — se o self-heal funcionar como esperado, o `POST` já vem `0` antes mesmo desse `git restore` redundante. Validador pode confirmar olhando a saída completa do `aurora-self-heal` (procurar linha `[aurora-self-heal] N fix(es) aplicado(s)`).

## Smoke geral pós-sprint (do BRIEF §Comandos runtime-real)

```bash
zsh -ic 'true'                                          # login shell sem erro
source ~/.config/zsh/.zsh_secrets && echo "${GIT_TOKEN_PESSOAL:0:7}"  # esperado: ghp_NaT
git log --oneline -3                                     # mensagens limpas
```

## Checklist touches

**Permitidos**:
- [x] `/home/andrefarias/.config/zsh/env.zsh`
- [x] `/home/andrefarias/.config/zsh/functions/aurora-self-heal.zsh`

**Proibidos** (qualquer um destes presente em `git diff` reprova a sprint):
- [ ] `functions/spellbook-sync.zsh`
- [ ] `.githooks/*`
- [ ] `hooks/*`
- [ ] `scripts/universal-sanitizer.py`
- [ ] `scripts/validar-acentuacao.py`
- [ ] `aurora/aurora-bootstrap.sh`, `aurora-root-apply`, `aurora-reapply-all.sh`, demais aurora/*
- [ ] `.zshrc`, `aliases.zsh`, `functions.zsh`
- [ ] Qualquer outro `*.zsh`, `*.sh`, `*.py`, `*.md` fora dos 2 autorizados

## Mensagem de commit sugerida

Branch sugerida: `fix/topgrade-pnpm-omz-self-heal`

Commit msg (PT-BR, minúsculas, imperativo, sem emoji/menção-IA/co-autoria — conforme BRIEF §Convenções):

```
fix(env+self-heal): pnpm PATH + auto-restauração de drift no ~/.oh-my-zsh

Adiciona PNPM_HOME e $PNPM_HOME/bin ao PATH (idempotente via __add_to_path_once),
resolvendo o erro "configured global bin directory is not in PATH" do pnpm setup
no topgrade. Adiciona 13º check em aurora-self-heal que detecta drift em
~/.oh-my-zsh/ (regressão histórica de 2025-08-11 que removeu executabilidade
em 20 arquivos) e auto-restaura via git restore. Estende o case do loop de
fixes_user para processar comandos git além de systemctl.
```

**Atenção autosync**: antes de `git commit` manual, rodar `git log --oneline -5` — autosync (`auto: sync nitro-5 ...`) pode já ter capturado as edições. Se sim, criar commit semântico em cima é redundante; conferir `git log --stat -1` para ver o que entrou. Se autosync absorveu, **não** rebasar/amend — deixar como está e documentar no proof-of-work.

## Riscos e não-objetivos

- **Não-objetivo**: caçar causa raiz do drift histórico do oh-my-zsh (2025-08-11, ~9 meses atrás, pré-todas-nossas-sprints). Decisão do usuário: prevenir, não investigar fantasma.
- **Não-objetivo**: configurar pnpm além do PATH (versão, plugins, registry). Apenas exportar `PNPM_HOME` e adicionar ao PATH.
- **Risco aceito**: o passo 3 (estender case do loop) muda comportamento de `aurora-self-heal` para qualquer fix que comece com `git ` — hoje só existe o do oh-my-zsh, mas futuras sprints que adicionem outros `git ...` em `fixes_user[@]` terão execução automática. Documentado no diff via comentário implícito (case `git\ *`).
- **Risco aceito**: o helper local `__add_to_path_once` em `env.zsh:10-15` é o que processa o `$PNPM_HOME/bin` (porque a linha 24 vem antes do source do oh-my-zsh, e `_helpers.zsh` só carrega depois em `functions.zsh`). Versão local é funcionalmente equivalente à pública — confirmado por leitura side-by-side de ambas. Sem risco prático.
- **Achado colateral encontrado** (lição 5 do BRIEF): o loop `fixes_user[@]` só processava `systemctl` ou paths executáveis. Para qualquer comando shell-string que não seja systemctl, o fix era detectado mas silenciosamente ignorado. O passo 3 corrige isso para `git`. Sprints futuras podem precisar generalizar — mas no escopo atual fica restrito a `git\ *` para minimizar superfície de mudança.

## Referências

- BRIEF: `/home/andrefarias/.config/zsh/VALIDATOR_BRIEF.md`
- Plano aprovado: `/home/andrefarias/.claude/plans/17-43-58-humming-newell.md`
- Helper PATH idempotente: `/home/andrefarias/.config/zsh/functions/_helpers.zsh:55-62` (versão pública) e `env.zsh:10-15` (versão de boot)
- Arquivo alvo 1: `/home/andrefarias/.config/zsh/env.zsh:23` (ponto de inserção)
- Arquivo alvo 2: `/home/andrefarias/.config/zsh/functions/aurora-self-heal.zsh:101` (ponto de inserção do bloco) e `:111-116` (loop de aplicação)
