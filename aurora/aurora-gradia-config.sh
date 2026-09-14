#!/usr/bin/env bash
# aurora-gradia-config.sh — garante o que o fluxo de screenshot do Aurora precisa
# do Gradia (ver aurora-print-clipboard.sh e aurora-gradia-clipboard.sh):
#   - pasta ~/Imagens/Gradia_prints (destino das capturas/edições);
#   - overwrite-screenshot=true   → ao FECHAR, o Gradia salva a edição por cima
#     do arquivo de origem (que vive em Gradia_prints), dando o "auto-save";
#   - trash-screenshots-on-close=false → não joga o resultado na lixeira ao fechar;
#   - exit-method='none' (v3.38) → o Gradia NÃO copia ao fechar. O "copiar e
#     morrer" do 'copy' perdia a cópia (clipboard Wayland morre com o dono; o
#     wl-clip-persist não clonava a tempo — Broken pipe no journal) e deixava o
#     clipboard preso na imagem anterior. A edição continua salva no arquivo;
#     copiar com a janela ABERTA (botão do app) segue funcionando.
#
# Idempotente e leve: se o keyfile já está como queremos, NÃO invoca o flatpak
# (que é pesado). Roda como a usuária, chamado pelo self-heal no bloco user.
set -uo pipefail
APP=be.alexandervanhee.gradia
KEYFILE="$HOME/.var/app/$APP/config/glib-2.0/settings/keyfile"

mkdir -p "$HOME/Imagens/Gradia_prints" 2>/dev/null || true

command -v flatpak >/dev/null 2>&1 || exit 0
flatpak info "$APP" >/dev/null 2>&1 || exit 0   # Gradia não instalado → nada a fazer

# Fast-path: keyfile já correto → sai sem custo.
if [ -f "$KEYFILE" ] \
   && grep -q '^overwrite-screenshot=true' "$KEYFILE" \
   && grep -q "^exit-method='none'" "$KEYFILE" \
   && ! grep -q '^trash-screenshots-on-close=true' "$KEYFILE"; then
  exit 0
fi

gset() {
  local key="$1" want="$2" cur
  cur="$(flatpak run --command=gsettings "$APP" get "$APP" "$key" 2>/dev/null)" || return 0
  [ "$cur" = "$want" ] || flatpak run --command=gsettings "$APP" set "$APP" "$key" "$want" 2>/dev/null || true
}
gset overwrite-screenshot true
gset trash-screenshots-on-close false
gset exit-method "'none'"
