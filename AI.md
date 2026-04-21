# AI.md - Protocolo Universal para Agentes de IA
# Regras para qualquer projeto | PT-BR | v4.0

## REGRA DE OURO

Antes de modificar QUALQUER arquivo, leia o código existente e entenda o contexto completo.

---

## 1. COMUNICAÇÃO

- PT-BR direto e técnico
- **ACENTUAÇÃO CORRETA É OBRIGATÓRIA** — em TODAS as respostas, código, commits, docs, comentários e variáveis em português. Isso inclui: á, é, í, ó, ú, â, ê, ô, ã, õ, à, ç. NUNCA escreva "funcao", "validacao", "descricao", "comunicacao", "configuracao" — o correto é "função", "validação", "descrição", "comunicação", "configuração". Esta regra NÃO tem exceção. Se a palavra em português exige acento, USE O ACENTO.
- **ZERO emojis** em código, commits, docs, respostas
- Sem formalidades vazias
- Explicações técnicas e concisas

---

## 2. ANONIMATO ABSOLUTO

**PROIBIDO em qualquer arquivo ou commit:**
- Nomes de IAs: "Claude", "GPT", "Gemini", "Copilot", "Anthropic", "OpenAI"
- Commits devem ser totalmente limpos e anônimos

**Exceções permitidas:**
- Strings técnicas: `api_key`, `provider`, `model`, `config`, `client`
- Documentação de API de terceiros
- Variáveis de ambiente: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`

---

## 3. CÓDIGO LIMPO

- Type hints quando a linguagem suportar
- Arquivo completo, nunca fragmentos
- Nunca use `# TODO` ou `# FIXME` inline (crie issue no GitHub)
- Logging rotacionado obrigatório (nunca `print()` / `console.log()`)
- Zero comentários desnecessários dentro do código
- Paths relativos via Path/equivalente (nunca hardcoded absolutos)
- Error handling explícito (nunca silent failures)

---

## 4. GIT

### Formato de Commit (sempre PT-BR)

```
tipo: descrição imperativa

# Tipos: feat, fix, refactor, docs, test, perf, chore
```

### Proibições

- Zero emojis em mensagens de commit
- Zero menções a IA
- Nunca `--force` sem autorização explícita

---

## 5. PROTEÇÕES

- **NUNCA** remover código funcional sem autorização explícita
- Se usuário pedir refatoração, perguntar: "Quer adicionar novo ou melhorar o existente?"
- Perguntar antes de alterar arquivos críticos ou de alto impacto

---

## 6. LIMITES

- **800 linhas** por arquivo (exceções: config, testes, registries)
- Se ultrapassar: extrair para módulos separados, manter imports limpos

---

## 7. GITIGNORE OBRIGATORIO

```gitignore
# Caches
__pycache__/
*.py[cod]
node_modules/
venv/
.venv/

# Logs e dados
logs/
*.log

# Evidencias de IA
Task_Final/
IMPORTANT.md
*.claude.md
*_AI_*.md

# Secrets
.env
*.key
*.pem
.git-credentials

# IDE
.vscode/
.idea/
*.swp

# Sistema
.DS_Store
Thumbs.db
```

---

## 8. PRINCÍPIOS

- **Simplicidade** - Código simples > código "elegante". Evitar over-engineering.
- **Observabilidade** - Tudo tem log. Se não pode medir, não pode melhorar.
- **Graceful Degradation** - Falha parcial != crash total. Sempre fallback mínimo.
- **Local First** - Tudo funciona offline por padrão. APIs pagas são opcionais.

---

## 9. META-REGRAS ANTI-REGRESSÃO

1. **Sincronização N-para-N** - Se um valor existe em N lugares, atualizar TODOS ou nenhum.
2. **Filtros sem falso-positivo** - Todo regex/filtro DEVE ser testado contra inputs que NÃO devem casar.
3. **Soberania de subsistema** - Subsistema A NUNCA descarrega/mata recurso de subsistema B.
4. **Observabilidade adaptativa** - Sistema adaptativo sem métrica de saúde = bomba-relógio.
5. **Scope atômico** - Bug encontrado ao testar feature Y NÃO é fixado inline. Registrar como nova issue.
6. **Evidência empírica > hipótese do revisor** - Antes de aplicar qualquer fix sugerido (pelo revisor Opus ou outro agente), confirmar via `rg` dos identificadores citados. Se 0 matches, reportar divergência com dados em vez de inventar código morto. Base: Luna AUD-03 FEN-01d.
7. **Zero follow-up acumulado** - Cada achado de code review tem `Edit` exato pronto, `sed` pronto, OU sprint-nova com ID. NUNCA "abrir issue depois", "criar TODO", "seria bom revisar", "pré-existente fora escopo". Base: Luna feedback_zero_follow_up_acumulado + feedback_fix_inline_never_skip.
8. **Validação runtime-real obrigatória** - Pytest/unit test não basta. Sprint que toca runtime exige smoke boot real (`./run.sh --smoke` ou equivalente), TUI completa (se projeto é TUI), gauntlet por fase. Comandos canônicos vivem na seção `Contratos de runtime` do `VALIDATOR_BRIEF.md` de cada projeto. Base: Luna feedback_always_test_tui + Nyx BOOT-FIX-01.

---

## 10. WORKFLOW

```
1. Ler arquivos relacionados
2. Entender fluxo completo
3. Procurar testes existentes
4. Implementar mantendo compatibilidade
5. Testar incrementalmente
6. Documentar mudanças
```

---

## 11. CHECKLIST PRE-COMMIT

- [ ] Testes passando
- [ ] Zero emojis no código
- [ ] Zero menções a IA
- [ ] Zero hardcoded values introduzidos
- [ ] Commit message descritivo (PT-BR)
- [ ] Sincronização N-para-N verificada
- [ ] Documentação atualizada se necessário

---

## 12. ASSINATURA

Todo script finalizado recebe uma citacao de filosofo/estoico/libertario como comentario final.

---

## 13. VALIDAÇÃO VISUAL (obrigatória em UI/TUI/Web)

Screenshot não é opcional em sprint que toca interface. Regra absoluta: só declare "impossível" após provar que tentou os 3 caminhos canônicos, com log literal dos erros.

Pipeline 3-tentativas (sempre nesta ordem):

1. **CLI X11** (pre-autorizado em `settings.json`): `scrot`, `import` (ImageMagick), `xdotool`, `wmctrl`, `ffmpeg`, `xclip`, `sha256sum`.
2. **claude-in-chrome MCP** (app web com Chrome rodando): carregar via `ToolSearch select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__computer`.
3. **playwright MCP** (app web dev local, headless): carregar via `ToolSearch select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_take_screenshot`.

Skill canônica: `validacao-visual` (auto-invocada pelo validador-sprint quando diff toca UI).

Proof-of-work visual obriga três itens:
- PNG path absoluto em `/tmp/<projeto>_<área>_<ts>.png`
- `sha256sum` do arquivo
- Descrição multimodal (via Read do PNG, 3-5 linhas cobrindo elementos, acentuação visível, contraste/layout)

Fallback "impossível" só aceito com log literal das 3 tentativas (comando + erro + ambiente).

---

## 14. CAPACIDADES VISUAIS DISPONÍVEIS

Catálogo completo das ferramentas visuais no ambiente Pop!_OS X11:

**CLI (pré-autorizado via `permissions.allow` em `~/.claude/settings.json`):**
```
scrot, import, xdotool, wmctrl, xclip, xsel, ffmpeg, sha256sum
```

**MCP claude-in-chrome** (extensão v1.0.68 pareada, native-host em `~/.claude/chrome/`):
```
ToolSearch select:mcp__claude-in-chrome__tabs_context_mcp,
                 mcp__claude-in-chrome__read_page,
                 mcp__claude-in-chrome__computer,
                 mcp__claude-in-chrome__navigate,
                 mcp__claude-in-chrome__javascript_tool
```

**MCP playwright** (via plugin `playwright@claude-plugins-official`):
```
ToolSearch select:mcp__plugin_playwright_playwright__browser_navigate,
                 mcp__plugin_playwright_playwright__browser_take_screenshot,
                 mcp__plugin_playwright_playwright__browser_snapshot,
                 mcp__plugin_playwright_playwright__browser_console_messages
```

**MCP context7** (docs de libraries):
```
ToolSearch select:mcp__plugin_context7_context7__query-docs,
                 mcp__plugin_context7_context7__resolve-library-id
```

Protocolo: tente sempre 3 caminhos antes de declarar impossível. Referência canônica: skill `validacao-visual`.

---

## 15. CICLO DE SPRINT UNIVERSAL

Fluxo canonico em qualquer projeto:

```
/planejar-sprint "<ideia>"  → planejador-sprint (subagent opus, contexto isolado) redige spec
/executar-sprint <spec>     → executor-sprint (subagent opus, contexto isolado) aplica
/validar-sprint             → validador-sprint (subagent opus, contexto isolado) veredicto
```

`VALIDATOR_BRIEF.md` na raiz de cada repo-alvo e memória compartilhada — não é volátil.

**Ciclo automático** (`/sprint-ciclo <ideia>`):
- Planejador → Executor → Validador em cadeia sem checkpoints.
- Se REPROVADO: auto-dispatch de executor-sprint com patch-brief até 3 iterações (configurável via `CLAUDE_SPRINT_CICLO_MAX_RETRIES`).
- Se APROVADO/APROVADO_COM_RESSALVAS: auto-commit + auto-push + auto-PR via `/commit-push-pr`.

**Ciclo manual** (`/sprint-ciclo-manual <ideia>`): checkpoints de aprovação entre fases. Opt-in.

**Protocolo anti-débito**:
- Achado colateral → auto-dispatch planejador-sprint (executor NÃO fixa inline).
- Achado no-escopo → Edit-pronto OU bash-pronto OU sprint-nova-ID. Zero "issue depois".

**Subagents têm contexto isolado** — não herdam a conversa principal. Economiza tokens e evita alucinação em projetos grandes.

---

## 16. SESSÃO INICIA CAPACITADA

Ao abrir sessão Claude Code em projeto git (via wrapper `cca`), o hook `SessionStart` custom (`~/.claude/hooks/session-start-briefing.py`) injeta `additionalContext` contendo:

- Nome e raiz do projeto ativo (`$CLAUDE_PROJECT_ROOT`, `$CLAUDE_PROJECT_NAME`)
- Status do `VALIDATOR_BRIEF.md` (exists/missing)
- Tipo do projeto (luna/nyx-code/protocolo-ouroboros/generic)
- Bloco **[CAPACIDADES VISUAIS]** com queries `ToolSearch` exatas
- Bloco **[SPRINT CICLO]** com orçamento de retries
- Bloco **[AÇÃO AUTOMÁTICA]** quando BRIEF ausente:
  - Projeto conhecido + memórias → auto-disparar `bootstrap-rico-brief.py`
  - Projeto genérico → auto-dispatch de validador-sprint em MODO BOOTSTRAP

Variáveis exportadas pelo `cca` (consumidas pelo hook e pelos subagents):
- `CLAUDE_PROJECT_ROOT`, `CLAUDE_PROJECT_NAME`, `CLAUDE_BRIEF_PATH`
- `CLAUDE_BRIEF_STATUS` (exists|missing), `CLAUDE_PROJECT_KIND`
- `CLAUDE_SANTUARIO_READY`, `CLAUDE_VISUAL_TOOLS_EXPECTED`
- `CLAUDE_SPRINT_CICLO_MAX_RETRIES`

Hook `UserPromptSubmit` (`post-plan-clear.py`) sugere `/clear` quando detecta aprovação de plan — não força, apenas lembra de usar subagents (que têm contexto isolado por design) ou `/clear` manual.

Documentação completa: `~/.config/zsh/docs/claude/` (espelhada via symlink em `~/.claude/`).

---

*"Código que não pode ser entendido não pode ser mantido."*
*"Local First. Zero Emojis. Zero Bullshit."*
*"Memória em disco, não em contexto. Ciclo em uma janela. Rigor de duas abas."*
