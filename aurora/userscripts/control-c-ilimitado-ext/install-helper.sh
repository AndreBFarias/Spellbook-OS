#!/bin/bash
# Helper de instalação da Chrome extension Ctrl+C Ilimitado.
# Abre chrome://extensions e copia o caminho da pasta pro clipboard.

set -u

EXT_PATH="$HOME/userscripts/control-c-ilimitado-ext"

if [ ! -d "$EXT_PATH" ]; then
  echo "Pasta não encontrada: $EXT_PATH" >&2
  echo "Rode antes: control_c_ilimitado sync" >&2
  exit 1
fi

if command -v xclip >/dev/null 2>&1; then
  printf '%s' "$EXT_PATH" | xclip -selection clipboard
  CB_MSG="(caminho ja no clipboard, Ctrl+V no dialogo do Chrome)"
else
  CB_MSG="(xclip ausente -- copie manualmente: $EXT_PATH)"
fi

cat <<EOF
=== Ctrl+C Ilimitado -- instalacao da Chrome extension ===

Pasta: $EXT_PATH
       $CB_MSG

Vou abrir chrome://extensions/ no Chrome.

No Chrome (one-time, ~3 cliques):
  1. Ative "Modo do desenvolvedor" (canto superior direito)
  2. Clique "Carregar sem compactacao" (canto superior esquerdo)
  3. Cole o caminho (Ctrl+V) ou navegue ate a pasta acima
  4. Apos instalar, fixe o icone "C+" via menu de extensoes (quebra-cabeca)

EOF

# Tenta abrir chrome://extensions/. Varios chrome bins possiveis.
opened=0
for bin in google-chrome google-chrome-stable chromium chromium-browser brave-browser; do
  if command -v "$bin" >/dev/null 2>&1; then
    "$bin" --new-window chrome://extensions/ >/dev/null 2>&1 &
    echo "abrindo via $bin..."
    opened=1
    break
  fi
done

if [ $opened -eq 0 ]; then
  # fallback xdg-open (pode não funcionar com chrome:// URLs)
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "chrome://extensions/" >/dev/null 2>&1 &
    echo "abrindo via xdg-open..."
  else
    echo "ERRO: nenhum navegador Chrome/Chromium/Brave detectado." >&2
    echo "Abra manualmente: chrome://extensions/" >&2
    exit 1
  fi
fi

# Notify-send se disponivel pra reforcar o lembrete
if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 12000 -u normal "Claude Export" "Modo do desenvolvedor -> Carregar sem compactacao -> cole o caminho (Ctrl+V)"
fi

exit 0
