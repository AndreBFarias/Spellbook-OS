# Checklist de validação — Spellbook-OS Claude Code v2

To-do list sequencial para validar que a instalação v2 está funcionando. Cada passo tem comando + resultado esperado + ação se falhar.

Tempo estimado: **10–15 minutos**.

Abra um terminal novo e siga de cima pra baixo.

---

## Fase A — Infra (sem abrir o Claude)

### A1. Sync do Spellbook-OS

```bash
cd ~/.config/zsh
spellbook_sync_status 2>&1 | head
```

**Esperado**: branch `main`, sem conflitos, `git log --oneline -5` mostra commits recentes.

**Se falhar**: resolver conflito manualmente (`git status` + edit + `git add` + `git commit`).

### A2. Shell functions carregadas

```bash
typeset -f cca > /dev/null && echo "[OK] cca"
typeset -f santuario > /dev/null && echo "[OK] santuario"
typeset -f sprint > /dev/null && echo "[OK] sprint"
typeset -f __sprint_doctor_quick > /dev/null && echo "[OK] __sprint_doctor_quick"
```

**Esperado**: 4 linhas `[OK]`.

**Se falhar**: `source ~/.zshrc` ou abrir terminal novo.

### A3. Aliases novos

```bash
alias | grep -E '^(sciclo|sciclom|sbr|splan|sexec|sval)=' | sort
```

**Esperado**: 6 aliases listados, incluindo `sciclom` (ciclo manual) e `sbr` (bootstrap rich).

**Se falhar**: conferir `~/.config/zsh/cca/aliases_sprint.zsh`; `source ~/.zshrc`.

### A4. Symlinks de docs versionadas

```bash
for f in \
  ~/.claude/agents/validador-sprint.md \
  ~/.claude/commands/sprint-ciclo.md \
  ~/.claude/hooks/session-start-briefing.py \
  ~/.claude/skills/validacao-visual/SKILL.md \
  ~/.claude/PLUGINS.md \
  ~/.claude/SPECIAL_PROJECTS.json; do
    [ -L "$f" ] || [ -L "$(dirname "$f")" ] && \
        echo "[OK] $f -> $(readlink -f "$f" | sed 's|.*docs/claude|docs/claude|')" || \
        echo "[FALTA] $f"
done
```

**Esperado**: 6 linhas `[OK]` apontando para `docs/claude/...`.

**Se falhar**: rodar `bash ~/.config/zsh/install.sh --relink`.

### A5. Hooks registrados em settings.json

```bash
python3 -c "
import json
d = json.load(open('$HOME/.claude/settings.json'))
for h in ['SessionStart', 'UserPromptSubmit', 'PreToolUse']:
    entries = d.get('hooks', {}).get(h, [])
    print(f'[{\"OK\" if entries else \"FALTA\"}] {h}: {len(entries)} hook(s)')
print(f'[INFO] permissions: {len(d[\"permissions\"][\"allow\"])} regras')
"
```

**Esperado**: 3 linhas `[OK]` + 24 regras de permissões.

**Se falhar**: conferir se o arquivo foi corrompido; restaurar backup em `~/.claude/settings.json.bak-20260420-v2`.

### A6. Sprint doctor completo

```bash
sdoc
```

**Esperado**: Várias linhas `[OK]`, mensagem final `Setup Claude v2 saudável (tudo integrado)` ou avisos específicos.

**Se falhar**: anotar exatamente quais `[FALTA]` aparecem e verificar componente correspondente.

---

## Fase B — Boot capacitado (com o Claude aberto)

### B1. Variáveis de ambiente exportadas pelo `cca`

```bash
cd ~/Desenvolvimento/Luna          # ou outro repo git
santuario Luna
```

**Esperado**: `santuario` roda sem erros; `[VALIDADOR]` linha mostra BRIEF ativo (Luna já tem BRIEF de 206L gerado pelo bootstrap).

### B2. Smoke do hook SessionStart (offline, sem abrir Claude)

```bash
CLAUDE_PROJECT_ROOT=/home/andrefarias/Desenvolvimento/Luna \
CLAUDE_PROJECT_NAME=Luna \
CLAUDE_BRIEF_PATH=/home/andrefarias/Desenvolvimento/Luna/VALIDATOR_BRIEF.md \
CLAUDE_BRIEF_STATUS=exists \
CLAUDE_PROJECT_KIND=luna \
python3 ~/.claude/hooks/session-start-briefing.py < /dev/null | python3 -m json.tool | head -30
```

**Esperado**: JSON com `additionalContext` contendo `[SANTUÁRIO READY] Projeto: Luna`, `[PROJETO ESPECIAL]`, `[CAPACIDADES VISUAIS]`, `[SPRINT CICLO]`, `[AÇÃO AUTOMÁTICA] BRIEF ativo`.

### B3. Smoke do hook post-plan-clear

```bash
echo '{"prompt":"aprovo, pode executar"}' | python3 ~/.claude/hooks/post-plan-clear.py | python3 -m json.tool
```

**Esperado**: JSON com `additionalContext` contendo `DICA (automatica - pos plan approval detectado)`.

### B4. Boot real em Luna

```bash
cca
```

Primeiro prompt dentro da sessão Claude:

```
Qual projeto? Qual é o status do BRIEF? Quais capacidades visuais você tem disponíveis? Qual é o tipo de projeto detectado?
```

**Esperado**: resposta citando:
- Projeto Luna, tipo `tui`, BRIEF ativo com N linhas
- Capacidades CLI (`scrot`, `import`, `xdotool`, etc.)
- MCPs `claude-in-chrome` + `playwright` + `context7`
- Skill `validacao-visual`
- Ciclo automático `/sprint-ciclo` com 3-retry

**Se falhar**: rodar novamente o comando da B2 pra confirmar que o hook está emitindo output; se sim, o Claude não está lendo o `additionalContext` — verificar `claude --debug hooks` no launch.

---

## Fase C — BRIEFs dos 3 projetos conhecidos

### C1. Inspecionar BRIEFs gerados

```bash
for p in Luna Nyx-Code protocolo-ouroboros; do
    f=~/Desenvolvimento/$p/VALIDATOR_BRIEF.md
    if [ -f "$f" ]; then
        echo "=== $p ==="
        echo "Linhas: $(wc -l < "$f")"
        echo "Seções [CORE]:"
        grep '^## \[CORE\]' "$f" | head
        echo "Rodapé:"
        tail -1 "$f"
        echo ""
    fi
done
```

**Esperado**: 3 BRIEFs (Luna 206L, Nyx-Code 151L, ouroboros 125L). Seções `[CORE]`: Identidade, Como rodar, Arquitetura, Checks universais, Contratos de runtime, Arquivos periféricos, Heurísticas de aritmética, Capacidades visuais.

### C2. Bootstrap rico manual (alternativo)

Só rode se quiser regenerar algum BRIEF:

```bash
cd ~/Desenvolvimento/Luna
python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto luna --saida /tmp/test_brief.md --dry-run | head -30
```

**Esperado**: saída idêntica ao BRIEF já gerado.

---

## Fase D — Capacidades visuais

### D1. CLI X11 pré-autorizado

```bash
which scrot import xdotool wmctrl ffmpeg xclip sha256sum
```

**Esperado**: 7 paths.

### D2. Permissões sem prompt

Dentro do Claude (`cca`), pedir:

```
Tire um screenshot deste terminal com scrot, grave em /tmp/validacao_cli_$(date +%s).png, e me mostre o hash sha256.
```

**Esperado**: Claude executa `scrot /tmp/validacao_cli_*.png` + `sha256sum` sem pedir permissão; retorna hash.

**Se falhar com prompt de permissão**: regra `Bash(scrot:*)` ausente em `permissions.allow`. Rodar `cat ~/.claude/settings.json | jq '.permissions.allow'`.

### D3. Pairing Chrome (opcional, só se quiser validar MCP chrome)

```bash
test -x ~/.claude/chrome/chrome-native-host && echo "[OK] native-host" || echo "[FALTA]"
ls ~/.config/google-chrome/Default/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn/ 2>/dev/null | head
```

**Esperado**: `[OK] native-host` + pasta de versão da extensão.

### D4. Playwright cache (opcional)

```bash
find ~/.npm/_npx -type d -name "@playwright" 2>/dev/null | head
```

**Esperado**: pelo menos 1 resultado indicando cache aquecido. Vazio = cold start na primeira invocação.

---

## Fase E — Ciclo de sprint (teste leve)

**ATENÇÃO**: este é o teste de fogo. Use um projeto-sandbox se não quiser commits em Luna/Nyx/ouroboros.

### E1. Criar repo-sandbox

```bash
mkdir -p /tmp/sandbox-sprint && cd /tmp/sandbox-sprint
git init -q
echo "# Sandbox" > README.md
git add README.md && git commit -qm "init"
```

### E2. Abrir Claude no sandbox e pedir sprint trivial

```bash
cca "/sprint-ciclo adicionar linha 'teste v2' no README.md"
```

**Esperado**:
1. Claude dispatcha `planejador-sprint` → gera spec em `~/.claude/plans/sprint-<ID>.md`.
2. Dispatcha `executor-sprint` → implementa (adiciona linha ao README).
3. Dispatcha `validador-sprint` → veredicto.
4. Se APROVADO, tenta auto-commit.

**Observação**: o sandbox não tem upstream remoto, então `git push` e `gh pr create` vão falhar — isso é esperado. O ciclo ainda deve completar até o commit local.

### E3. Conferir artefatos gerados

```bash
cd /tmp/sandbox-sprint
git log --oneline
ls VALIDATOR_BRIEF.md
cat README.md
```

**Esperado**: 2 commits (init + sprint), BRIEF criado via MODO BOOTSTRAP, README com linha "teste v2".

### E4. Limpar sandbox

```bash
rm -rf /tmp/sandbox-sprint
```

---

## Fase F — Validação de acentuação PT-BR

### F1. Scripts sem palavras sem acento em strings de interface

```bash
cd ~/.config/zsh
grep -r -l -E "\b(funcao|validacao|configuracao|descricao|execucao|atencao|operacao)\b" \
    --include='*.zsh' --include='*.md' --include='*.sh' --include='*.py' \
    2>/dev/null | grep -v docs/claude/PADROES-VALIDADOR.md | head
```

**Esperado**: vazio (ou apenas `PADROES-VALIDADOR.md` que cita palavras SEM acento propositalmente como exemplo de erro).

### F2. AI.md com acentuação correta

```bash
grep -E "^## " ~/.config/zsh/AI.md | head -20
```

**Esperado**: seções com acentuação (COMUNICAÇÃO, CÓDIGO LIMPO, PROTEÇÕES, PRINCÍPIOS, META-REGRAS ANTI-REGRESSÃO, VALIDAÇÃO VISUAL, etc.).

---

## Fase G — Rollback (se precisar voltar)

### G1. Backup dos settings

```bash
ls ~/.claude/settings.json.bak-* 2>/dev/null
```

**Esperado**: pelo menos `settings.json.bak-20260420` (v1) e `settings.json.bak-20260420-v2` (antes da v2 atual).

### G2. Como reverter tudo

```bash
# Restaurar settings:
cp ~/.claude/settings.json.bak-20260420 ~/.claude/settings.json

# Remover symlinks novos (se quiser):
rm ~/.claude/hooks/session-start-briefing.py ~/.claude/hooks/post-plan-clear.py
rm ~/.claude/commands/sprint-ciclo-manual.md
rm -rf ~/.claude/skills/validacao-visual

# Docs versionadas em docs/claude/ podem ficar (são só docs).
```

Não execute esses comandos a menos que queira rollback.

---

## Resumo de resultados esperados

Se tudo OK, você deve ter:

- [ ] A1–A6: infra shell + symlinks + hooks + sprint doctor funcionando
- [ ] B1–B4: boot capacitado injetando contexto correto no Claude
- [ ] C1–C2: 3 BRIEFs (Luna 206L, Nyx 151L, ouroboros 125L) com seções CORE preenchidas
- [ ] D1–D4: CLI X11 pré-autorizado + pairing Chrome + playwright cache
- [ ] E1–E4: ciclo automático completa em sandbox
- [ ] F1–F2: sem palavras sem acento fora dos exemplos didáticos

## Relate problemas encontrados

Se algum passo falhar, anote qual (ex: "A3 — alias `sbr` não aparece") e me passe. Ajusto imediatamente.

---

*Tempo total: ~12 minutos se tudo correr bem; ~25 minutos se precisar investigar falhas.*
