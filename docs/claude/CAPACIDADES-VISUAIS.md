# docs/claude/CAPACIDADES-VISUAIS.md — Visão / Screenshot / Validação Visual

Catálogo completo das capacidades visuais disponíveis no ambiente Linux Pop!_OS X11 + Claude Code 2.1.114. Documentado aqui para que o Claude nunca mais diga "não consigo" sem tentar os 3 caminhos canônicos.

## Pipeline oficial: 3 tentativas antes de declarar impossível

A skill `validacao-visual` e o protocolo `[VALIDAÇÃO VISUAL]` no AI.md §13 definem:

```
Tentativa 1 — CLI X11 (mais rápido; nativo)
Tentativa 2 — claude-in-chrome MCP (app web com Chrome rodando)
Tentativa 3 — playwright MCP (app web dev local; headless)
```

Só após 3 tentativas falhadas com log literal dos erros, `fallback("impossível")` é aceitável.

## Tentativa 1 — CLI X11 (pré-autorizadas em `settings.json`)

| Tool | Binário | Uso típico |
|---|---|---|
| `scrot` | `/usr/bin/scrot` 1.7 | Screenshot full ou por região |
| `import` | `/usr/bin/import` (ImageMagick 6.9.11) | Screenshot + convert (PDF/jpg) |
| `xdotool` | `/usr/bin/xdotool` 3.20160805 | Activate window, key/mouse injection |
| `wmctrl` | `/usr/bin/wmctrl` | Listar e manipular janelas |
| `ffmpeg` | `/usr/bin/ffmpeg` | Screencast, GIF, vídeo |
| `xclip` | `/usr/bin/xclip` | Clipboard (paste image/text) |
| `sha256sum` | coreutils | Hash do PNG para proof-of-work |

### Comandos canônicos

#### TUI (Luna, Textual, Rich, Curses)

```bash
# Se o projeto tem script de captura (Luna):
bash scripts/tui_tests/capture.sh <area>
# -> gera /tmp/luna_tui_<area>_<ts>.png

# Genérico:
WID=$(xdotool search --name "Luna" | head -1)
xdotool windowactivate "$WID"; sleep 0.5
import -window "$WID" /tmp/<projeto>_tui_<area>_<ts>.png
sha256sum /tmp/<projeto>_tui_<area>_<ts>.png
```

#### GUI (GTK/Qt)

```bash
WID=$(wmctrl -lx | grep <app_class> | awk '{print $1}')
import -window "$WID" /tmp/<projeto>_gui_<app>_<ts>.png
```

#### CLI output (terminal inteiro)

```bash
scrot /tmp/<projeto>_cli_<ts>.png
```

#### Screencast curto (para demonstrar bug de animação)

```bash
ffmpeg -f x11grab -video_size 1920x1080 -framerate 25 -i :1 -t 5 /tmp/<projeto>_<ts>.mp4
```

Depois: `Read /tmp/<png>` — Claude lê multimodalmente (PNG direto entra no contexto como imagem).

## Tentativa 2 — `claude-in-chrome` MCP (app web com Chrome rodando)

Extensão instalada: `fcoeoabgfenejglbffodgkkbkcdhcgfn` (Claude in Chrome) v1.0.68
Native host: `~/.claude/chrome/chrome-native-host` -> `~/.local/share/claude/versions/2.1.114 --chrome-native-host`
Atalho toggle side-panel: `Ctrl+E` no Chrome.

### Carregar tools via ToolSearch (deferred)

```
ToolSearch select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__javascript_tool
```

### Tools úteis

- `tabs_context_mcp` — lista abas abertas
- `tabs_create_mcp` — abre nova aba
- `navigate` — navega URL
- `read_page` / `get_page_text` — lê DOM textualmente
- `computer` — ação de mouse/teclado (incluindo screenshot)
- `javascript_tool` — executa JS na página
- `find` / `form_input` — localizar e preencher
- `read_console_messages` / `read_network_requests` — dev tools
- `gif_creator` — GIF animado de interações

### Verificar pairing

```bash
test -x ~/.claude/chrome/chrome-native-host && echo "native-host OK" || echo "NÃO OK"
test -d ~/.config/google-chrome/Default/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn/1.0.68_0 && echo "ext OK" || echo "NÃO OK"
```

Se falha: abrir Chrome, ativar a extensão Claude (Ctrl+E), parear via pairing.html.

## Tentativa 3 — `playwright` MCP (app web dev local)

Plugin oficial `playwright@claude-plugins-official`. MCP server via `npx @playwright/mcp@latest` (cold start 20s na primeira vez; ~1s subsequentes).

### Carregar via ToolSearch

```
ToolSearch select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_take_screenshot,mcp__plugin_playwright_playwright__browser_snapshot,mcp__plugin_playwright_playwright__browser_console_messages
```

### Tools úteis

- `browser_navigate` — navega URL
- `browser_take_screenshot` — PNG da página
- `browser_snapshot` — accessibility tree
- `browser_click` / `browser_type` / `browser_fill_form` — interação
- `browser_evaluate` — JS
- `browser_console_messages` / `browser_network_requests` — debug
- `browser_file_upload` — upload

### Verificar cache

```bash
test -d ~/.npm/_npx/*/node_modules/@playwright/mcp && echo "cache OK" || echo "frio (cold start na 1a chamada)"
```

## Skill `validacao-visual`

Path: `docs/claude/skills/validacao-visual/SKILL.md`

**Frontmatter**:
```
name: validacao-visual
description: Captura e valida evidência visual quando sprint toca UI/TUI/CSS/HTML.
             Pipeline 3-tentativas (scrot/import -> claude-in-chrome -> playwright).
             Trigger automático via validador-sprint quando diff casa padrões de UI.
```

**Trigger automático**:
- Diff toca `*.tsx,*.jsx,*.vue,*.svelte,*.html,*.css,*.scss`
- Diff toca `src/ui/**,*textual*,*widget*,templates/**`
- Projeto declara tipo TUI/GUI/Web no BRIEF na seção `[CORE] Capacidades visuais aplicáveis`

**Critério de sucesso** (proof-of-work visual):
- PNG path absoluto (`/tmp/<projeto>_<area>_<ts>.png`)
- sha256 hash do arquivo
- Descrição multimodal (via Read do PNG, 3-5 linhas):
  - Elementos renderizados (menu, botão, lista, mensagem)
  - Acentuação em strings visíveis (correta / incorreta)
  - Contraste / cor / layout quando aplicável
- Validação contra critério (se existe `scripts/tui_tests/criteria/<area>.txt`)

**Fallback "impossível"** (só aceitável após 3 tentativas):
```
Tentativa 1 (scrot): <comando> -> <erro literal>
Tentativa 2 (claude-in-chrome): <tool> -> <erro literal>
Tentativa 3 (playwright): <tool> -> <erro literal>
Ambiente: DISPLAY=<...>, headless=<...>, MCP servers=<...>
Recomendação: <ação manual do usuário>
```

Sem esse bloco, validador REPROVA.

## Armazenamento

`/tmp/<projeto>_<area>_<timestamp>.png` — efêmero.
- Não polui repo
- Não precisa gitignore
- `sprint doctor` (nos modos estendidos) pode listar os mais recentes
- Se usuário quer persistir, move manualmente

## Troubleshooting

### "scrot: can't open display"

```bash
echo $DISPLAY  # deve ser ":1" no Pop!_OS X11
# Se vazio, Claude está em sessão não-X11
```

### "xdotool: No such file or directory"

Binário falta. Instalar: `sudo apt install xdotool`.

### claude-in-chrome responde "InputValidationError"

Tool não foi carregada via ToolSearch. Fazer:
```
ToolSearch select:mcp__claude-in-chrome__<nome_exato>
```

### playwright timeout no cold start

Primeira invocação baixa `@playwright/mcp` via npx — pode levar 20s. Avisar usuário e aguardar.

### Extensão Chrome não pareada

`Ctrl+E` no Chrome -> Sign in -> pareamento. Native host deve estar rodando.

### Sessão SSH / sem DISPLAY

CLI X11 não funciona. Usar playwright headless como caminho primário. Claude deve detectar via `test -z "$DISPLAY"` e pular tentativa 1.

## Integração com sprint-workflow

1. Executor-sprint, após implementar, invoca skill `validacao-visual` automaticamente se diff toca UI.
2. Skill tenta tentativa 1 (CLI X11) -> se sucesso, termina.
3. Se falha, tenta tentativa 2 (claude-in-chrome) -> se sucesso, termina.
4. Se falha, tenta tentativa 3 (playwright) -> se sucesso, termina.
5. Se todas falham, emite relatório "impossível" com logs literais.
6. Validador-sprint inclui PNG+hash+descrição no veredicto.
7. Se `fallback("impossível")` aceitável (logs provam), sprint pode continuar. Senão, REPROVA.
