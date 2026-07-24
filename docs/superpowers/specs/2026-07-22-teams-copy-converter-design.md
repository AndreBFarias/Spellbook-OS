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

## Adendo 2026-07-23 — guia "Arquivos" + correção estrutural do link de anexo

Sessão seguinte adicionou a seção **"Arquivos"** no final de `renderMd`/`renderTxt`/`renderHtml`
(`lib/teams-extract.js`: `collectAttachments` + `groupAttachmentsByExt`, agrupamento por
extensão, só aparece se houver ao menos um anexo) e corrigiu a extração do link real do anexo,
que nunca tinha funcionado de fato. Duas causas raiz distintas, achadas em sequência:

**1. `cloneContents()` não copia expando properties do React.** O card de anexo do Teams
(`[data-tid="file-attachment-grid"]`) não expõe `href` em nenhum atributo do DOM — o link
(`shareUrl`) mora nos props que o React anexa ao nó via `__reactProps$<sufixo>`. A seleção do
usuário é processada via `range.cloneContents()` pra virar um fragmento estático seguro de
percorrer, mas `Node.cloneNode()` (usado internamente) só copia estrutura DOM/HTML — não copia
propriedades JS arbitrárias que a página anexou ao objeto do elemento. Resultado: **todo** card
de anexo caía no fallback antigo (nome via `innerText`, concatenado sem separador quando o card
agrupa vários arquivos, `href: null`), sempre, não só às vezes. Confirmado via harness de console
que rodava direto no DOM vivo (funcionava) vs. o pipeline real (sempre falhava) — a diferença era
exatamente clonado vs. vivo.

**2. Isolated world do content script não enxerga os mesmos expando properties, nem nos nós
vivos.** Correção óbvia seria "ler os props ANTES de clonar" — mas mesmo lendo os nós vivos
diretamente de dentro de `content.js`, `Object.keys(el)` não encontra `__reactProps$...`. Motivo:
content scripts rodam em **isolated world** (mesmo DOM da página, heap de JS separado); é uma
barreira de segurança do Chrome, não um detalhe de timing — propriedades DOM nativas (tag,
atributos, filhos) são compartilhadas entre isolated/main world, mas expando properties que a
própria página anexa a um objeto (como o React faz) ficam isoladas por mundo. Um harness de
console rodando via `javascript_tool`/DevTools executa no **main world** (mesmo mundo do React da
página) — por isso "funcionava" nesses testes e nunca no content script real. Achado só depois de
instrumentar `buildOutputs()` com `console.log` temporário e comparar a saída real com o
resultado esperado (a saída do content script tinha `gridAttachments: [[],[]]` — a função rodava,
mas sempre vazia).

**Fix final:** a leitura dos props roda no **main world de verdade**, via
`chrome.scripting.executeScript({world:'MAIN', func: readGridAttachmentsInMainWorld})` disparado
por `background.js` (mesmo padrão já usado pro bridge do PDF, `main-bridge.js`, só que com a API
nativa do MV3 em vez de injeção de `<script>`). Como `executeScript` serializa a função e a
reexecuta isolada (sem closures do arquivo que a define), a lógica de `attachmentsFromGrid` ficou
duplicada intencionalmente em `background.js` — precisa ser mantida em sincronia manualmente se
mudar. `content.js` marca os cards da seleção com um atributo DOM real (`data-cci-grid-tmp`, que
SIM atravessa isolated/main world, ao contrário de props JS), manda mensagem, recebe de volta só
dados serializáveis (`{name, href}`), desmarca. `lib/teams-extract.js` ficou só com a fila
(`gridQueue.shift()` em `walkBlock`) — não lê props do React em lugar nenhum mais.

Efeito colateral descoberto no caminho: cards de anexo recém-carregados (grid grande, 7-8
arquivos) podem ter filhos ainda em estado de placeholder do Fluent UI (`isPlaceholder: true`,
sem `props.file`) — esses ficam de fora da guia "Arquivos" silenciosamente (fallback já cobre:
sem dado, sem entrada). Não tratado — documentado como limitação em `INSTALL.md`.

PDF (`ensureBridge`/`generatePdf`/3 ações `selection-pdf-*`) foi **desabilitado** nessa mesma
sessão (comentado, não removido) — bloqueado no Teams por Trusted Types, e o gancho anti-IA do
repo passou a ter uma exceção dedicada em `.githooks/pre-commit` (`aurora/userscripts/control-c-ilimitado-ext/*`
fica fora da substituição automática `agente→agente`, porque `agente.ai`/`font-agente-message`
são constantes externas reais, não menção a ferramenta de IA).
