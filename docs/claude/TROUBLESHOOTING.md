# docs/claude/TROUBLESHOOTING.md — Problemas conhecidos e workarounds

Catálogo de problemas recorrentes no setup Claude Code + soluções testadas.

## MCPs

### "InputValidationError: tool not loaded"

**Sintoma**: Chamar `mcp__claude-in-chrome__*` ou `mcp__plugin_playwright_playwright__*` retorna erro de validação.

**Causa**: Tool deferred — precisa ToolSearch antes.

**Fix**:
```
ToolSearch query="select:mcp__claude-in-chrome__<nome_exato>" max_results=5
```

Cheatsheet no bloco `[CAPACIDADES VISUAIS]` do hook session-start-briefing.py.

### claude-in-chrome não responde

**Sintoma**: Tool carrega mas fica pendurada.

**Causa**: Extensão Chrome não pareada / native-host não rodando.

**Fix**:
1. Verificar pairing:
   ```bash
   test -x ~/.claude/chrome/chrome-native-host && echo OK
   ls ~/.config/google-chrome/Default/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn/
   pgrep -af chrome-native-host
   ```
2. Abrir Chrome, `Ctrl+E` -> Sign in -> parear.
3. Reabrir sessão Claude.

### playwright cold start 20+ segundos

**Sintoma**: Primeira chamada a `mcp__plugin_playwright_playwright__*` demora.

**Causa**: `npx @playwright/mcp@latest` baixa o pacote na primeira vez.

**Fix**: Aguardar (não re-tentar). Ou pré-aquecer manualmente:
```bash
npx -y @playwright/mcp@latest --version
```

### playwright "browser not found"

**Sintoma**: `browser_navigate` falha com erro de binário.

**Causa**: Chromium bundled não instalado.

**Fix**:
```bash
npx playwright install chromium
```

## Hooks

### session-start-briefing.py não dispara

**Sintoma**: Ao abrir sessão, primeira mensagem não tem bloco `[SANTUÁRIO READY]`.

**Causa**: Hook não registrado em settings.json ou erro de sintaxe.

**Fix**:
1. `cat ~/.claude/settings.json | jq '.hooks.SessionStart'` — deve listar o script
2. `readlink ~/.claude/hooks/session-start-briefing.py` — symlink OK?
3. `python3 ~/.claude/hooks/session-start-briefing.py < /dev/null` — roda standalone?
4. `claude --debug` e ver output dos hooks.

### guardian.py bloqueia commit legítimo

**Sintoma**: `Emoji detectado` ou `Atribuição a IA detectada` em conteúdo que não deveria.

**Causa**: Regex do guardian pegou falso-positivo.

**Fix**:
1. Verificar path — é isento? (ver lista em `guardian.py`)
2. Se é bug do regex: adicionar path ao `IGNORE_IF_PATH_CONTAINS`.
3. Se é conteúdo real: corrigir o conteúdo.

### Hooks do superpowers + learning + custom conflitam

**Sintoma**: additionalContext duplicado ou Claude fica confuso no boot.

**Causa**: 3 hooks SessionStart em paralelo.

**Fix**: Não devem conflitar por design (cada um tem stdout isolado). Se conflito aparece:
- Marcar blocos do custom com `[SANTUÁRIO READY]` etc, para diferenciar visualmente.
- Evitar info duplicada (ex: custom não precisa listar skills do superpowers).

## Permissões

### Prompt de permissão repete toda sessão

**Sintoma**: Claude pede "Allow Bash(scrot:*)?" mesmo que você já aprovou antes.

**Causa**: `skipDangerousModePermissionPrompt: true` está em `settings.json`, mas regra não está em `permissions.allow`.

**Fix**: Adicionar regra em `~/.claude/settings.json` `permissions.allow`:
```json
"Bash(scrot:*)"
```

### "Permission denied" em script Python do zsh

**Sintoma**: `python3 ~/.config/zsh/scripts/X.py` pede aprovação.

**Causa**: Regra `Bash(python3 /home/andrefarias/.config/zsh/scripts/*)` falta.

**Fix**: Adicionar em `settings.json`.

## cca wrapper

### cca "comando não encontrado"

**Sintoma**: No shell, `cca` retorna "command not found".

**Causa**: Função não carregada (arquivo `aliases_cca.zsh` não foi source-d).

**Fix**:
```bash
source ~/.config/zsh/cca/aliases_cca.zsh
# ou abrir novo terminal (zshrc carrega automaticamente)
```

### cca não exporta CLAUDE_PROJECT_ROOT

**Sintoma**: Hook session-start-briefing.py reclama que variáveis estão vazias.

**Causa**: Ou você rodou `claude` direto (sem `cca`), ou a função `cca` está desatualizada.

**Fix**:
1. Sempre usar `cca` em vez de `claude` direto.
2. Verificar em `aliases_cca.zsh` que há bloco `export CLAUDE_PROJECT_ROOT=...` antes de `command claude`.

## Spellbook-OS autosync

### Conflito de merge ao abrir terminal

**Sintoma**: `__spellbook_resolve_conflict` abre editor na abertura.

**Causa**: Editou docs em outra máquina sem sincronizar.

**Fix**: Resolver conflito manualmente e `git commit`.

### Commit `auto: sync` com conteúdo incompleto

**Sintoma**: Você fechou terminal no meio de uma edição e o commit pegou draft.

**Fix**: Critério:
- Se quer commit consciente: rodar `spellbook_sync_status` + `git commit -m "..."` ANTES de `exit`.
- Se já commitou auto: `git commit --amend -m "msg descritiva"` (antes de push) ou deixar como está.

## Memórias

### MEMORY.md trunca no contexto

**Sintoma**: Partes do MEMORY.md não aparecem na primeira mensagem do Claude.

**Causa**: Harness trunca MEMORY.md após linha 200.

**Fix**: Manter MEMORY.md compacto. Mover conteúdo detalhado para arquivos individuais e deixar MEMORY.md como ÍNDICE apenas.

### Claude escreve memórias em inglês

**Sintoma**: Arquivos `.md` com frontmatter em inglês ou corpo em inglês.

**Causa**: Default do harness é inglês.

**Fix**: Regra PT-BR já está em `CLAUDE.md` §1. Ao salvar memória, Claude deve preencher name+description+corpo em PT-BR. Se não fez, corrigir e lembrar.

## Plan mode

### "Clear context and auto-accept edits" não aparece

**Sintoma**: Ao aprovar plan mode, menu não mostra a opção de limpar contexto.

**Causa**: Bug conhecido (issues #45034, #38071, #39665 do Claude Code).

**Fix**:
- Usar subagents via `/sprint-ciclo` (resolve estruturalmente).
- OU: aprovar plan e depois digitar `/clear` manualmente.
- OU: versão `next` (2.1.116) pode ter fix.

### Plan file muito grande

**Sintoma**: Plan file ultrapassa 800 linhas e fica difícil navegar.

**Fix**: Quebrar em sub-planes por fase. Manter plan principal como índice + linkar sub-planes.

## Sprint-ciclo

### Ciclo trava em 3 iterações de REPROVADO

**Sintoma**: Após iteração 3, ciclo pausa com mesma falha persistente.

**Causa**: Validador detecta problema que executor não consegue corrigir com patch-brief.

**Fix**:
- Usuário revisa estado acumulado (diff + veredicto).
- Decide: promover a problema para nova sprint dedicada, OU ajustar spec original, OU abandonar.
- Registrar em SPRINT_ORDER_MASTER.md.

### Achado colateral explode em N sprints novas

**Sintoma**: Executor dispatcha muitas sprints-derivadas, usuário perde foco.

**Fix**: Adicionar limite no executor: máx 3 achados colaterais por sprint (já embutido). Resto vai para seção "Para revisão manual" do veredicto.

## Versão Claude Code

### `claude update` falha

**Sintoma**: `claude update` retorna erro de download.

**Fix**:
```bash
claude install latest  # mesmo que update, mas explícito
# ou
claude install 2.1.114  # versão específica
```

### Regressão após update

**Sintoma**: Comportamento muda após `claude update`.

**Fix**: Rollback manual:
```bash
ls ~/.local/share/claude/versions/  # ver versões disponíveis
# se tem 2.1.113 disponível:
claude install 2.1.113
```

## Debugging geral

### Sessão lenta

- `claude --debug api` — ver chamadas API
- `claude --debug hooks` — ver execução de hooks
- `claude --debug` sozinho — full debug

### Logs

- `~/.claude/history.jsonl` — transcripts completos
- `~/.claude/debug/` — debug logs
- `~/.claude/telemetry/` — métricas

### Voltar para estado anterior

```bash
# Restaurar settings de backup:
cp ~/.claude/settings.json.bak-20260420 ~/.claude/settings.json

# Reverter agents para versão anterior:
cd ~/.config/zsh && git log -- docs/claude/agents/ | head
git checkout <hash> -- docs/claude/agents/
```
