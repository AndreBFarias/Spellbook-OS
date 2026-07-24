# Ctrl+C Ilimitado — instalação

## Modo facil: um comando

```bash
control_c_ilimitado
```

Isso roda o deploy idempotente + abre `chrome://extensions/` com a pasta no clipboard.

## Por que precisa de setup manual no Chrome

O Chrome **bloqueia** instalação programática de extensions fora da Chrome Web
Store por design de segurança. Vale pra qualquer extension unpacked. **Chrome
128+ (mar/2024) removeu o suporte à flag `--load-extension` de linha de
comando** — antes funcionava via `.desktop` ou wrapper, hoje retorna warning
"`--load-extension is not allowed in Google Chrome, ignoring`" e ignora.
O único caminho oficial é UI.

A parte automatizada do `control_c_ilimitado`:
- Valida que os arquivos estão no source `~/.config/zsh/aurora/userscripts/control-c-ilimitado-ext/`
- Copia o caminho da pasta pro clipboard (xclip)
- Abre o Chrome em `chrome://extensions/`
- Mostra notificação visual com instruções

A parte manual (one-time, ~3 cliques):
1. No Chrome em `chrome://extensions/`, ative **"Modo do desenvolvedor"**
2. Clique **"Carregar sem compactacao"**
3. Cole o caminho (Ctrl+V) -> **Selecionar**
4. Fixe o icone "C+" via menu de extensoes (quebra-cabeca -> alfinete)

Apos isso, a extension fica registrada e roda em **todos os sites**.

## Atualizações

```bash
control_c_ilimitado status     # verifica integridade do source
control_c_ilimitado update     # baixa html2pdf mais recente
```

Após qualquer mudança nos arquivos source, o Chrome precisa recarregar a extension:
- `chrome://extensions/` → botão **"Recarregar"** sob a extension
- (Auto-reload sem clique manual é impossível em extensions unpacked.)

## O que ela faz

**Universal (todo site):**
- Tier 1 automatico: anula bloqueios CSS/JS de copy/paste/seleção
- Botao "Desbloquear total" no popup: Tier 2 (mais invasivo, override de listeners futuros)
- Copiar seleção como markdown, texto puro, ou formatado (Word/Docs, com imagens embutidas)
- Salvar seleção como `.md`
- Imagens: embutir (data-URI), baixar como arquivo separado, ou só link — escolha no popup

**Especifico no Teams (`teams.microsoft.com`):**
- Extração estruturada (autor, hora, citação, código, lista, anexo) em vez de texto cru
- Guia **"Arquivos"** no final da saída: todo anexo da seleção, agrupado por tipo (Excel/PDF/Word/...), com link real de download quando disponível
- O link real do anexo é lido do próprio React da página (não do DOM visível) — por isso passa por uma ponte via `background.js` rodando no *main world* da aba; não é possível ler isso de dentro do content script (isolated world não enxerga os `__reactProps$` do React, é uma barreira de segurança do Chrome)

**Especifico em claude.ai:**
- Botao "Exportar conversa completa" no popup
- Tenta API interna primeiro; se falhar, faz auto-scroll + DOM scrape

## Limitacoes conhecidas

- **PDF desabilitado temporariamente** (removido da interface, código comentado em `content.js`/`popup.html`/`background.js`): bloqueado no Teams por Trusted Types (`ERR_BLOCKED_BY_CLIENT`). Reativar exige resolver isso primeiro.
- Sites que detectam DevTools e descarregam conteudo: não tem o que fazer
- A extension não desbloqueia DRM (HBO Max, Netflix, etc) -- nem tenta
- Anexos do Teams ainda carregando (placeholder do Fluent UI, sem dado nenhum) na hora da seleção não entram na guia "Arquivos" — espere a página terminar de carregar antes de selecionar
