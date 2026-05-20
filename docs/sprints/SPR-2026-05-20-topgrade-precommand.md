# SPR-2026-05-20-topgrade-precommand

## Contexto

A sprint anterior `SPR-2026-05-20-topgrade-fix` (PR #2 ainda aberto) adicionou o 13o check (`oh-my-zsh drift`) e a extensão do case `git\ *` no loop `fixes_user[@]` em `functions/aurora-self-heal.zsh`. O fix funciona em shells interativos porque `aurora-self-heal-cached` (linha 136 do mesmo arquivo) so e chamado em `.zshrc:58` (precmd).

O topgrade, porem, executa o hook do oh-my-zsh chamando `zsh /home/andrefarias/.oh-my-zsh/tools/upgrade.sh` como **subprocess não-interativo**. Esse subprocess NÃO carrega `.zshrc`, logo o self-heal nunca roda no contexto do topgrade e o erro `dubious ownership` em `~/.oh-my-zsh` voltou a aparecer as 18:57 de hoje (2026-05-20), exatamente como no pre-fix.

A solucao definitiva e amarrar o self-heal ao `[pre_commands]` do proprio topgrade, de modo que cada `topgrade` (interativo ou agendado) execute o drift sweep antes de qualquer upgrader. Como o `~/.config/topgrade.toml` atual e um arquivo regular não-versionado (11636 bytes, modificado em nov/2025), versiona-lo via `aurora/topgrade.toml` + symlink garante que o pre-command nasce com o repo e sobrevive a reinstalacoes.

## Escopo (touches autorizados)

**Arquivos a criar (no repo):**
- `aurora/topgrade.toml` — copia byte-a-byte do `~/.config/topgrade.toml` atual + 1 linha adicionada no bloco `[pre_commands]`.

**Arquivos a modificar (no repo):**
- `install.sh` — adicionar `_step_topgrade_symlink()` (modelado em `_step_fastfetch_symlink` linha 702-729) + chamada na sequencia do `main()` (apos `_step_fastfetch_symlink`, antes de `_step_chsh`).

**Operação local (NÃO-versionada, executada uma vez fora do git):**
```bash
mv ~/.config/topgrade.toml ~/.config/topgrade.toml.bak-pre-symlink-$(date +%s)
ln -sfn ~/.config/zsh/aurora/topgrade.toml ~/.config/topgrade.toml
```

**Arquivos NÃO a tocar (invariantes):**
- `functions/aurora-self-heal.zsh` — ja entregue no PR #2; não mexer.
- `functions/spellbook-sync.zsh`, `env.zsh`, `.zshrc`, `.githooks/*`, `hooks/*`, `scripts/universal-sanitizer.py`, `scripts/validar-acentuacao.py` — invariantes do BRIEF.
- `~/.local/state/*`, `vault/*.gpg*`, `.zsh_secrets*`.

## Acceptance criteria

1. `~/.config/topgrade.toml` e symlink apontando para `~/.config/zsh/aurora/topgrade.toml` (resolvido via `readlink -f`).
2. `aurora/topgrade.toml` no repo difere do backup `~/.config/topgrade.toml.bak-pre-symlink-*` APENAS na adicao de 1 linha ativa no bloco `[pre_commands]` (linha 102).
3. `topgrade --help` parseia config sem erro de TOML.
4. Comando `zsh -c 'source $HOME/.config/zsh/functions/_helpers.zsh 2>/dev/null; source $HOME/.config/zsh/functions/aurora-self-heal.zsh; aurora-self-heal'` retorna exit 0 em subprocess não-interativo (validado durante investigacao — ja funciona, `${#issues[@]}` não precisa de `emulate -L zsh`).
5. Simulacao de drift (`chmod 644 ~/.oh-my-zsh/tools/upgrade.sh` provocando dirty tree) e curada pelo pre-command quando invocado standalone.
6. `topgrade --only oh_my_zsh` roda sem erro `dubious ownership` end-to-end.
7. `bash -n install.sh` exit 0.
8. `python3 scripts/validar-acentuacao.py --paths install.sh aurora/topgrade.toml` exit 0.
9. `git status --porcelain` apos commit final contem apenas os 2 arquivos esperados (`install.sh`, `aurora/topgrade.toml`).

## Invariantes a preservar

- **BRIEF [CORE] Restricoes criticas**: sem co-autoria, sem emoji, sem mencao a ferramenta de IA em commit msg; identidade `AndreBFarias <andre.dsbf@gmail.com>`.
- **BRIEF [CORE] Invariantes #5/#6**: pre-commit/pre-push hooks ativos — NÃO usar `--no-verify`. Acentuacao PT-BR estrita.
- **BRIEF [CORE] Invariante #3**: autosync pode commitar antes do passo manual. Rodar `git log --stat -1` antes de qualquer `git commit` para detectar.
- **BRIEF [CORE] Invariante #8**: zero funções removidas. `_step_topgrade_symlink` e função NOVA, segue o padrao de `_step_fastfetch_symlink`.
- **Preservar TODOS os 11636 bytes** originais do topgrade.toml. So ADICIONAR no `[pre_commands]`.
- **Pre-commit hook ja roda `validar-acentuacao.py`** automaticamente (linha 37 de `.githooks/pre-commit`) — proof-of-work item 8 e o "executar antes do commit" para evitar rejeicao do hook.

## Plano de implementacao

### Passo 1 — Criar `aurora/topgrade.toml` no repo

Copiar byte-a-byte de `~/.config/topgrade.toml` (antes da operação local):

```bash
cp -a ~/.config/topgrade.toml /home/andrefarias/.config/zsh/aurora/topgrade.toml
```

### Passo 2 — Editar `aurora/topgrade.toml`, bloco `[pre_commands]`

**Localizacao exata**: linha 102 do arquivo (a linha logo abaixo de `[pre_commands]`), entre a abertura da secao e o comentario `# "Emacs Snapshot" = ...`.

**Diff esperado** (`aurora/topgrade.toml`, contexto linhas 100-104):

```diff
 # Commands to run before anything
 [pre_commands]
+"Aurora self-heal (drift sweep)" = "zsh -c 'source $HOME/.config/zsh/functions/_helpers.zsh 2>/dev/null; source $HOME/.config/zsh/functions/aurora-self-heal.zsh; aurora-self-heal'"
 # "Emacs Snapshot" = "rm -rf ~/.emacs.d/elpa.bak && cp -rl ~/.emacs.d/elpa ~/.emacs.d/elpa.bak"

```

Nenhuma outra alteracao no arquivo. Resultado: 11636 + len(linha nova + LF) bytes.

Justificativa da string do comando:
- `zsh -c` — subprocess explicito; topgrade não garante shell padrao do user.
- `source _helpers.zsh 2>/dev/null` — necessario para `__header/__ok/__warn` se aurora-self-heal evoluir; `2>/dev/null` evita ruido se _helpers não existir num host minimal.
- `source aurora-self-heal.zsh` — carrega a função no escopo do subshell.
- `aurora-self-heal` — invocacao direta (NÃO `aurora-self-heal-cached`, porque o cache de 1h pode bloquear cura em re-runs sucessivos de `topgrade`).

### Passo 3 — Adicionar `_step_topgrade_symlink` em `install.sh`

**Local de insercao**: apos `_step_fastfetch_symlink()` (termina linha 729), antes de `# --- Etapa 6: ~/.zshenv com ZDOTDIR ---` (linha 731).

**Bloco a inserir** (modelado em `_step_fastfetch_symlink`, linhas 702-729):

```bash
# --- Etapa topgrade: symlink ~/.config/topgrade.toml -> ~/.config/zsh/aurora/topgrade.toml ---
_step_topgrade_symlink() {
    _step "Topgrade (config versionada com pre-command Aurora)"

    local source="$ZDOTDIR_TARGET/aurora/topgrade.toml"
    local target="$HOME/.config/topgrade.toml"

    if [[ ! -f "$source" ]]; then
        _warn "$source não existe — pule esta etapa"
        return 0
    fi

    if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
        _ok "Symlink ~/.config/topgrade.toml ja aponta para o repo"
        return 0
    fi

    if [[ -f "$target" && ! -L "$target" ]]; then
        local backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"
        _info "~/.config/topgrade.toml existe (não e symlink) — backup em $backup"
        _run mv "$target" "$backup"
    elif [[ -L "$target" ]]; then
        _run rm "$target"
    fi

    _run ln -sfn "$source" "$target"
    _ok "Symlink criado: $target -> $source"
}

```

### Passo 4 — Chamar `_step_topgrade_symlink` no `main()`

**Local de insercao**: dentro do `main()` (linhas 1180+), apos `_step_fastfetch_symlink`, antes de `_step_chsh`.

**Diff esperado** (`install.sh`, contexto linhas 1193-1198):

```diff
     _step_zshenv
     _step_fastfetch_symlink
+    _step_topgrade_symlink
     _step_chsh
     _step_validate
     _step_manifest
```

### Passo 5 — Operação local (uma vez, fora do git)

```bash
# Sair do diretório do repo não e necessario. Operacao no ~/.config/.
mv ~/.config/topgrade.toml ~/.config/topgrade.toml.bak-pre-symlink-$(date +%s)
ln -sfn ~/.config/zsh/aurora/topgrade.toml ~/.config/topgrade.toml
```

Verificar imediatamente:
```bash
[ -L ~/.config/topgrade.toml ] && readlink -f ~/.config/topgrade.toml
ls -la ~/.config/topgrade.toml.bak-pre-symlink-*
```

### Passo 6 — Commit

Branch sugerida: `fix/topgrade-pre-command-self-heal`

Mensagem (PT-BR, imperativo, minusculas, sem emoji/coautoria/mencao IA):

```
fix: versiona topgrade.toml e roda aurora-self-heal antes de cada topgrade

Move ~/.config/topgrade.toml para aurora/topgrade.toml (versionado), adiciona
pre_command que chama aurora-self-heal em subprocess zsh não-interativo, e
acrescenta _step_topgrade_symlink ao install.sh para que reinstalacoes recriem
o symlink. Resolve drift do oh-my-zsh que reaparece em shells não-interativos
do topgrade, sem depender do hook precmd do .zshrc.
```

## Aritmetica

Não ha meta numerica de tamanho (sem linha-cap). Aritmetica de preservacao:

- `aurora/topgrade.toml` esperado: `wc -c ~/.config/topgrade.toml.bak-pre-symlink-*` (= 11636) + `len("\"Aurora self-heal (drift sweep)\" = \"zsh -c 'source $HOME/.config/zsh/functions/_helpers.zsh 2>/dev/null; source $HOME/.config/zsh/functions/aurora-self-heal.zsh; aurora-self-heal'\"\n")` (= 187 bytes including final LF). Total esperado: **11823 bytes**.
- Validacao: `wc -c aurora/topgrade.toml` deve retornar `11823` ± diferenca de LF residual. Se divergir, investigar antes de commitar.
- `install.sh`: 1209 linhas atuais + ~28 linhas da função nova + 1 linha da chamada no main = **~1238 linhas**.

## Testes

Não ha framework de teste automatizado para este escopo (zsh shell config). Validacao via proof-of-work runtime real.

## Proof-of-work obrigatorio

Executar literalmente, na ordem, apos passos 1-5 acima:

```bash
# 1. Symlink criado e apontando certo
[ -L ~/.config/topgrade.toml ] && [ "$(readlink -f ~/.config/topgrade.toml)" = "$HOME/.config/zsh/aurora/topgrade.toml" ] && echo "OK symlink" || { echo "FAIL symlink"; exit 1; }

# 2. Topgrade enxerga config sem quebrar parse
topgrade --help &>/dev/null && echo "OK topgrade parse" || { echo "FAIL parse"; exit 1; }

# 3. pre_command roda standalone em subprocess não-interativo
zsh -c 'source $HOME/.config/zsh/functions/_helpers.zsh 2>/dev/null; source $HOME/.config/zsh/functions/aurora-self-heal.zsh; aurora-self-heal' 2>&1 | tee /tmp/aurora-precheck.log
echo "exit=$?"

# 4. Simular drift, rodar pre_command literal, validar cura
chmod 644 ~/.oh-my-zsh/tools/upgrade.sh
PRE=$(git -C ~/.oh-my-zsh status --porcelain | wc -l)
[ "$PRE" -gt 0 ] || { echo "FAIL drift não simulado"; exit 1; }
zsh -c 'source $HOME/.config/zsh/functions/_helpers.zsh 2>/dev/null; source $HOME/.config/zsh/functions/aurora-self-heal.zsh; aurora-self-heal'
POST=$(git -C ~/.oh-my-zsh status --porcelain | wc -l)
[ "$POST" -eq 0 ] && echo "OK pre_command cura drift" || { echo "FAIL drift persistiu (POST=$POST)"; exit 1; }

# 5. Topgrade --only oh_my_zsh roda sem erro end-to-end
topgrade --only oh_my_zsh 2>&1 | tail -10
# esperado no exit: oh-my-zsh ok

# 6. install.sh syntax
bash -n install.sh && echo "OK install syntax"

# 7. Acentuacao PT-BR
python3 scripts/validar-acentuacao.py --paths install.sh aurora/topgrade.toml

# 8. Escopo cirurgico
git status --porcelain | grep -vE '^\?\?|install\.sh|aurora/topgrade\.toml' && { echo "FAIL escopo"; exit 1; } || echo "OK escopo"

# 9. Backup do topgrade.toml original preservado
ls -la ~/.config/topgrade.toml.bak-pre-symlink-* | head -1
```

## Touches permitidos

- `aurora/topgrade.toml` (CRIAR)
- `install.sh` (MODIFICAR, 2 hunks: 1 função nova + 1 linha no main)

## Touches proibidos

- `functions/aurora-self-heal.zsh` (ja entregue no PR #2)
- `functions/spellbook-sync.zsh`, `env.zsh`, `.zshrc`
- `.githooks/*`, `hooks/*`
- `scripts/universal-sanitizer.py`, `scripts/validar-acentuacao.py`
- `vault/*`, `.zsh_secrets*`
- Qualquer arquivo em `~/.local/state/`

## Riscos e não-objetivos

- **Não-objetivo**: refatorar o sistema de cache `aurora-self-heal-cached`. O pre-command usa `aurora-self-heal` direto justamente para evitar interacao com cache.
- **Não-objetivo**: estender o array `aurora-self-heal` com novos checks. Escopo isolado.
- **Risco baixo**: topgrade pode ter quirk de TOML parser com strings contendo `$HOME`. Validado no proof-of-work item 2 (`topgrade --help` carrega o arquivo).
- **Risco residual**: se outro pre_command falhar no futuro, topgrade aborta. Hoje so existe esse pre_command, entao isolamento e total.
- **Achado colateral durante execução**: registrar como sprint nova (forma C do protocolo anti-debito), NUNCA inline.

## Referencias

- BRIEF: `/home/andrefarias/.config/zsh/VALIDATOR_BRIEF.md`
- Sprint anterior relacionada: `SPR-2026-05-20-topgrade-fix` (PR #2)
- Plano original: `/home/andrefarias/.claude/plans/17-43-58-humming-newell.md`
- Padrao de symlink replicado: `install.sh:702-729` (`_step_fastfetch_symlink`)
- Funcao alvo do pre-command: `functions/aurora-self-heal.zsh:15` (`aurora-self-heal()`)

## Notas da investigacao

1. `rg -n 'symlink|ln -s|ln -sf' install.sh` confirmou padrao em `_step_fastfetch_symlink` (linhas 702-729) — modelo escolhido por ser idempotente e tratar caso de arquivo regular preexistente via backup timestamped.
2. `ls aurora/` confirmou que `aurora/` no repo existe, e o local certo (ja contem outros assets de power-management e tem `__pycache__` indicando uso ativo).
3. Teste `zsh -c 'source ... ; aurora-self-heal'` exit 0 confirmado — zsh não-interativo não precisa de `emulate -L zsh` para `${#issues[@]}` funcionar (zsh em qualquer modo trata arrays com `$#name[@]` corretamente; problema seria so se rodasse em bash).
4. `cat -A ~/.config/topgrade.toml` confirmou LF puro, UTF-8 sem BOM, sem CRLF. `file` retorna `Unicode text, UTF-8`. Move + symlink não quebra parse.
