# Ctrl+C Ilimitado — instalação

## Modo facil: um comando

```bash
control_c_ilimitado
```

Isso roda o deploy idempotente + abre `chrome://extensions/` com a pasta no clipboard.

## Por que precisa de setup manual no Chrome

O Chrome **bloqueia** instalação programatica de extensions fora da Chrome Web
Store por design de seguranca. Vale pra qualquer extension unpacked.

A parte automatizada do `control_c_ilimitado`:
- Garante que os arquivos estao em `~/userscripts/control-c-ilimitado-ext/`
- Copia o caminho da pasta pro clipboard
- Abre o Chrome ja na pagina de extensions
- Mostra notificacao visual com instrucoes

A parte manual (one-time, ~3 cliques):
1. No Chrome em `chrome://extensions/`, ative **"Modo do desenvolvedor"**
2. Clique **"Carregar sem compactacao"**
3. Cole o caminho (Ctrl+V) -> **Selecionar**
4. Fixe o icone "C+" via menu de extensoes (quebra-cabeca -> alfinete)

Apos isso, a extension fica registrada e roda em **todos os sites**.

## Atualizacoes

```bash
control_c_ilimitado sync       # re-deploya
control_c_ilimitado status     # verifica integridade
control_c_ilimitado update     # baixa html2pdf mais recente
```

Apos qualquer mudanca nos arquivos source, o Chrome precisa recarregar a extension:
- `chrome://extensions/` -> botao **"Recarregar"** sob a extension
- (Auto-reload sem clique manual e impossivel em extensions unpacked.)

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
