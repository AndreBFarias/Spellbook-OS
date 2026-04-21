---
name: validacao-visual
description: Captura e valida evidência visual quando sprint toca UI, TUI, CSS, HTML, template, widget, layout ou arquivo visível. Pipeline 3-tentativas automático (scrot/import → claude-in-chrome MCP → playwright MCP). Só declara impossível após provar que as 3 tentativas falharam com log literal. Use sempre que o diff casa padrões visuais ou quando o projeto declara tipo TUI/GUI/Web no VALIDATOR_BRIEF.md.
---

# Skill: Validação Visual

## Filosofia

Screenshots não são opcionais. Em Luna (Sprint 09) e Nyx-Code (VALIDATE-ONDA-20), sprints marcadas CONCLUÍDA sem evidência visual ocultaram bugs que só apareciam na interface real. Esta skill força a evidência.

Regra absoluta: **só declare "impossível" após provar que tentou os 3 caminhos canônicos**. Sem log literal dos erros, validador REPROVA.

## Quando invocar

Invoque automaticamente em qualquer uma das condições:

- Diff toca padrões: `*.tsx, *.jsx, *.vue, *.svelte, *.html, *.css, *.scss, src/ui/**, *textual*, *widget*, templates/**, *.ui.py`
- VALIDATOR_BRIEF.md seção `[CORE] Capacidades visuais aplicáveis` declara tipo `tui | gui | web`
- Sprint cita "UI", "TUI", "interface", "render", "layout" na descrição
- Usuário pede explicitamente "tire print", "valide visualmente", "mostre como ficou"

## Pipeline 3-tentativas

### Tentativa 1 — CLI X11 (mais rápida, pré-autorizada)

Ferramentas: `scrot`, `import`, `xdotool`, `wmctrl`, `ffmpeg`, `sha256sum`.

#### Caso TUI (Textual, Rich, Curses — ex: Luna)

```bash
# Se o projeto tem script dedicado (Luna tem):
if [ -x scripts/tui_tests/capture.sh ]; then
    bash scripts/tui_tests/capture.sh <area>
    # gera /tmp/luna_tui_<area>_<ts>.png
else
    # Genérico: encontrar a janela do app
    TS=$(date +%Y%m%dT%H%M%S)
    WID=$(xdotool search --name "<nome-do-app>" | head -1)
    if [ -n "$WID" ]; then
        xdotool windowactivate "$WID"
        sleep 0.5
        import -window "$WID" "/tmp/${PROJETO}_tui_${AREA}_${TS}.png"
    fi
fi
sha256sum "/tmp/${PROJETO}_tui_${AREA}_${TS}.png"
```

#### Caso GUI (GTK/Qt — ex: apps nativos)

```bash
TS=$(date +%Y%m%dT%H%M%S)
WID=$(wmctrl -lx | grep -i "<classe-ou-titulo>" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    import -window "$WID" "/tmp/${PROJETO}_gui_${APP}_${TS}.png"
fi
sha256sum "/tmp/${PROJETO}_gui_${APP}_${TS}.png"
```

#### Caso CLI (terminal inteiro)

```bash
TS=$(date +%Y%m%dT%H%M%S)
scrot "/tmp/${PROJETO}_cli_${TS}.png"
sha256sum "/tmp/${PROJETO}_cli_${TS}.png"
```

#### Caso screencast (bug de animação/estado transiente)

```bash
TS=$(date +%Y%m%dT%H%M%S)
ffmpeg -f x11grab -video_size 1920x1080 -framerate 25 -i :1 -t 5 \
       "/tmp/${PROJETO}_screencast_${TS}.mp4"
```

Depois: `Read /tmp/<png>` — o PNG entra no contexto multimodal e você descreve o que vê.

Se CLI X11 funciona (exit 0 + PNG criado com tamanho > 0), **SUCESSO** — vá para "Critério de sucesso" abaixo.

Se falha (ex: `DISPLAY` vazio, binário ausente, janela não encontrada), **log literal o erro** e vá para tentativa 2.

### Tentativa 2 — claude-in-chrome MCP (app web com Chrome rodando)

Para apps web que o usuário já tem aberto no Chrome.

Carregue tools via ToolSearch (deferred):

```
ToolSearch select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__navigate
```

Uso:

```
1. mcp__claude-in-chrome__tabs_context_mcp  → lista abas
2. mcp__claude-in-chrome__computer action=screenshot  → PNG da aba atual
   (ou) mcp__claude-in-chrome__navigate + computer
3. Salve PNG em /tmp/<projeto>_web_<ts>.png e sha256sum
```

Se extensão não pareada ou tool falha (ex: "native-host not responding"), log literal o erro e vá para tentativa 3.

### Tentativa 3 — playwright MCP (app web dev local, headless)

Para apps dev local (ex: `npm run dev`, `python -m flask run`) ou quando Chrome não está aberto.

Carregue via ToolSearch:

```
ToolSearch select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_take_screenshot,mcp__plugin_playwright_playwright__browser_snapshot
```

Uso:

```
1. mcp__plugin_playwright_playwright__browser_navigate url=http://localhost:<port>
2. mcp__plugin_playwright_playwright__browser_take_screenshot path=/tmp/<projeto>_web_<ts>.png
3. sha256sum /tmp/<projeto>_web_<ts>.png
```

Se falha (ex: `npx` sem cache, porta não responde, timeout), log literal o erro.

## Critério de sucesso

Proof-of-work visual obriga 3 itens:

1. **Path PNG absoluto** (`/tmp/<projeto>_<area>_<timestamp>.png`).
2. **sha256sum** do arquivo gerado.
3. **Descrição multimodal** (via Read do PNG), 3-5 linhas cobrindo:
   - Elementos renderizados (menu, botão, lista, mensagem, cursor, input)
   - Acentuação em strings visíveis (correta / incorreta — especialmente PT-BR)
   - Contraste / cor / layout quando aplicável
   - Comparação com estado anterior (antes/depois) se sprint altera UI existente

4. **Validação contra critério** (se existe `scripts/tui_tests/criteria/<area>.txt` no projeto):
   - Ler critério item por item.
   - Checar cada item contra o PNG observado.
   - Reportar passes/falhas literalmente.

## Fallback "impossível"

Só é aceitável declarar impossível **após as 3 tentativas falharem** com log literal. Relatório obrigatório:

```
Validação visual impossível após 3 tentativas:

Tentativa 1 (CLI X11):
  Comando: <literal>
  Erro: <literal>
  Ambiente: DISPLAY=<valor>, $XDG_SESSION_TYPE=<valor>

Tentativa 2 (claude-in-chrome MCP):
  Tool: mcp__claude-in-chrome__<nome>
  Erro: <literal>
  Pairing: <status do Chrome extension>

Tentativa 3 (playwright MCP):
  Tool: mcp__plugin_playwright_playwright__<nome>
  Erro: <literal>
  npx cache: <aquecido / frio>

Recomendação ao usuário:
  <ação específica: parear extensão, instalar chromium, liberar DISPLAY, etc.>
```

Sem este bloco, validador-sprint REPROVA a sprint.

## Regras

- **PT-BR direto.** Zero emojis nos nomes/paths/descrições.
- **Nunca commitar os PNGs.** Eles são efêmeros em `/tmp/`.
- **Incluir path + hash no proof-of-work** para rastreabilidade.
- **Respeitar permissões** — CLI tools estão pré-autorizadas em `settings.json`; MCPs carregam via ToolSearch.
- **Se sessão SSH / sem DISPLAY**: pule tentativa 1 explicitamente, vá direto para 2 ou 3.
- **Nunca inventar** descrição. Se não consegue ler o PNG, reporte como impossível.

## Integração com sprint-workflow

1. Executor-sprint, após implementar, invoca esta skill automaticamente se diff toca UI.
2. Esta skill tenta tentativa 1 → sucesso termina pipeline.
3. Se falha, tenta tentativa 2 → sucesso termina.
4. Se falha, tenta tentativa 3 → sucesso termina.
5. Se as 3 falham, emite relatório "impossível" documentado.
6. Validador-sprint inclui PNG+hash+descrição no veredicto.
7. Se `fallback("impossível")` tem logs literais, sprint pode continuar. Senão, REPROVA.

---

*"Screenshot é a diferença entre 'eu acho que ficou bom' e 'ficou bom'."*
