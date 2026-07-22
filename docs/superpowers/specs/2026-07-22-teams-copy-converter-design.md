# Ctrl+C Ilimitado — conversor de cópia Teams-aware

Data: 2026-07-22
Extensão: `aurora/userscripts/control-c-ilimitado-ext/`

## Problema

A extensão copia via `window.getSelection().toString()` — a mesma serialização da
cópia nativa do navegador. No Teams (novo, `teams.cloud.microsoft`, Fluent UI) isso
resulta em:

- Lixo de acessibilidade no texto: "Início da citação", "tem menu de contexto",
  "X Coração reações".
- Menções (@Fulano) fragmentadas em pedaços com blocos vazios.
- Avatares e emojis de reação entrando como `<img>` quebrados.
- Citações/respostas só com o preview truncado ("…") — limite do próprio Teams.
- Nenhuma diferenciação semântica (citação, código, imagem) no `.md` nem no texto puro.

Diagnóstico confirmou: **sem shadow DOM** (`shadowRoots=0`), texto no DOM normal,
`toString_len ≈ cloneContents_innerText_len` (o corpo não é perdido em massa). As
classes são Fluent UI estáveis no prefixo: `fui-ChatMessage`, `fui-ChatMessage__body`,
`fui-ChatMessage__author`, `fui-ChatControlMessage`, `fui-StyledText`. Sufixos
`___hash` são voláteis — não depender deles.

## Objetivo

Extrair a seleção do Teams para três saídas limpas, consistentes e sem ambiguidade
(legíveis por humano, por Obsidian e por uma IA):

1. **Formatado (Word/Docs)** — HTML rico no clipboard, imagens embutidas.
2. **Markdown** (`.md`, copiar ou baixar) — semântico, estilo Obsidian.
3. **Texto puro** — sem símbolos markdown, mas diferenciando citação/código/imagem.

Imagens de conteúdo em três modos: **embutir** (data-URI, padrão), **baixar** (arquivo),
**link** (só a URL).

## Arquitetura (Abordagem C: modelo estruturado + renderizadores)

Fluxo: `seleção → cloneContents → extrator → MODELO → renderizador(md|html|txt) → saída`.

Módulos novos (funções puras, testáveis isoladamente):

| Arquivo | Responsabilidade |
|---|---|
| `lib/teams-extract.js` | DOM (fragmento) → modelo. Parte Teams-aware/frágil, isolada. |
| `lib/render-md.js` | modelo → markdown Obsidian/LLM-clean |
| `lib/render-html.js` | modelo → HTML rico limpo (clipboard `text/html`) |
| `lib/render-txt.js` | modelo → texto puro organizado |
| `lib/images.js` | classifica imagem (avatar/emoji/conteúdo); `src → data-URI`; download |

Todos anexam a `self.CCI` e são listados no `content_scripts` antes de `content.js`
(mesmo mundo isolado, escopo compartilhado, sem bundler — segue o estilo atual).

## Modelo de dados (o contrato)

```
model   = { messages: [Message] }
Message = { kind:'system', text }
        | { kind:'message', author, timestamp, blocks:[Block] }
Block   = { type:'p',     inlines:[Inline] }
        | { type:'quote', author, timestamp, truncated:bool, blocks:[Block] }
        | { type:'code',  lang, text }
        | { type:'image', src, alt, dataUri, imgKind:'content' }
        | { type:'list',  ordered:bool, items:[[Inline]] }
Inline  = { t:'text'|'bold'|'italic'|'code'|'mention', v }
        | { t:'link', v, href }
```

Reações descartadas por padrão. Menção fragmentada recolhida em um `mention` único.

## Renderizadores

**Markdown** (`render-md`):
- Mensagem → `### {autor} — {hora}`.
- Citação → `> **Citação — {autor}, {hora}**` + linhas `> `; se truncada, sufixo
  `[…truncado pelo Teams]`.
- Código → cerca ```` ``` ````; inline code → `` ` ``; negrito `**`; itálico `*`;
  link `[texto](href)`; menção `@Nome`.
- Imagem → conforme modo: `![alt](data-uri)` | `![alt](arquivo.png)` | `![alt](url)`.
- Sistema → linha `*{texto}*`.

**HTML rico** (`render-html`): `<h3>` autor+hora, `<blockquote>` citação, `<pre><code>`
código, `<img src=data-uri>`, `<b>/<i>/<a>` inline. Construído como **string** (nunca
injetado no DOM do Teams → sem Trusted Types). Vai pro clipboard como `text/html`.

**Texto puro** (`render-txt`): autor em linha própria; citação com prefixo `> `; código
indentado; imagem como `[imagem: alt]`; menção `@Nome`. Sem símbolos markdown.

## Imagens

`classify(img)` → `avatar` (classe `Avatar`/dentro do autor) | `emoji` (alt é emoji /
dentro de barra de reação → vira unicode ou descarta) | `content` (mantém). `toDataUri(src)`
= `fetch(src,{credentials:'include'})` → blob → base64 (roda no content script, com os
cookies do Teams; cobre `blob:` e `https:`). Falha de fetch → cai pra link, conta no status,
não aborta o resto. Guard de tamanho (imagem gigante → link).

Modo escolhido por **seletor no popup** (`Embutir · Baixar · Link`, padrão Embutir),
aplicado à ação clicada.

## Ações / clipboard

Popup:
- **Copiar formatado (Word/Docs)** → `ClipboardItem({'text/html', 'text/plain'})` escrito
  **pelo popup** (que está focado — resolve o `NotAllowedError` já visto).
- **Copiar .md** / **Copiar texto puro** → `text/plain`.
- **Baixar .md** → arquivo.
- Seletor de modo de imagem.

`content.js` faz extração + busca de imagens (async, contexto da página) + render, e
devolve `{html, md, txt}` ao popup. Popup escreve no clipboard / dispara downloads.
Botões de PDF ficam como estão (bloqueados no Teams por Trusted Types — fora de escopo).

## Erros e limites

- Citação truncada = limite do Teams (só preview no DOM) → marcada `[…truncado pelo Teams]`.
- Imagem que falha fetch → link + aviso.
- Nada selecionado → mensagem clara.

## Teste / afinação

Sem login no Teams do dono, a afinação do extrator é via **harness de console**: as funções
puras `extract`+`renderMd`+`renderTxt` concatenadas num snippet, rodado numa seleção real,
saída colada de volta. 1-2 rodadas previstas. 1-2 fragmentos reais (sanitizados) viram
fixtures pra não regredir. Verificação final: colar "formatado" no Docs (imagens aparecem),
`.md` no Obsidian (limpo), conferir legibilidade pra IA.
