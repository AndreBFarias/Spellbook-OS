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
- Copiar seleção como markdown ou texto puro
- Salvar seleção como `.md` ou `.pdf` (texto puro, formatado, ou screenshot fiel)

**Especifico em claude.ai:**
- Botao "Exportar conversa completa" no popup
- Tenta API interna primeiro; se falhar, faz auto-scroll + DOM scrape

## Limitacoes conhecidas

- Sites que renderizam texto em `<canvas>` (alguns paywalled): so via screenshot PDF
- Sites que detectam DevTools e descarregam conteudo: não tem o que fazer
- A extension não desbloqueia DRM (HBO Max, Netflix, etc) -- nem tenta
