#!/bin/bash
# Aurora - Carrega Chrome extensions unpacked via --load-extension em launch
# ----------------------------------------------------------------------------
# Por que assim em vez de editar Preferences.json:
#   - Preferences é regrabado pelo Chrome ao fechar; entries de extension
#     unpacked exigem manifest exato + checksum + path EXATO. Frágil.
#   - --load-extension é a flag oficial de "carregar extension unpacked",
#     aplicada a cada launch. Persistente enquanto o .desktop existir.
#   - Idempotente: detecta se a flag já está presente com a lista correta.
#
# Mantém compat com o slice browser.slice do Aurora 2.1.
#
# Para adicionar nova extension: acrescente o path em EXTENSION_PATHS abaixo.

set -u

DESKTOP_FILE="$HOME/.local/share/applications/google-chrome.desktop"
WRAPPER_SRC="$HOME/.config/zsh/aurora/google-chrome-wrapper.sh"
USER_BIN="$HOME/.local/bin"
SPELLBOOK_ROOT="$HOME/.config/zsh"

# Lista de extensions unpacked a carregar (paths absolutos)
EXTENSION_PATHS=(
  "$HOME/.config/zsh/aurora/userscripts/control-c-ilimitado-ext"
)

# Atalhos na raiz do spellbook ~/.config/zsh/<nome>
# (Symlinks para o source em aurora/userscripts/ — facilita "Carregar sem
# compactação" no Chrome apontando diretamente para ~/.config/zsh/<nome>)
EXTENSION_ROOT_SYMLINKS=(
  "control-c-ilimitado-ext:aurora/userscripts/control-c-ilimitado-ext"
)

log()  { printf '[chrome-ext] %s\n' "$*"; }
warn() { printf '[chrome-ext][WARN] %s\n' "$*" >&2; }

if [ ! -f "$DESKTOP_FILE" ]; then
  warn "desktop file ausente: $DESKTOP_FILE — pulando"
  exit 0
fi

# Valida que todas as extensions existem
valid_paths=()
for p in "${EXTENSION_PATHS[@]}"; do
  if [ -d "$p" ] && [ -f "$p/manifest.json" ]; then
    valid_paths+=("$p")
  else
    warn "extension path inválido ou sem manifest.json: $p"
  fi
done

if [ ${#valid_paths[@]} -eq 0 ]; then
  log "nenhuma extension válida — sem mudança"
  exit 0
fi

# Junta paths com vírgula (formato aceito por --load-extension)
joined=$(IFS=','; echo "${valid_paths[*]}")
flag="--load-extension=${joined}"

# Idempotência: se o desktop file já contém exatamente essa flag, nada a fazer
if grep -qF -- "$flag" "$DESKTOP_FILE"; then
  log "ok: --load-extension já presente com ${#valid_paths[@]} ext(s)"
  exit 0
fi

# Backup antes de mexer
cp -- "$DESKTOP_FILE" "${DESKTOP_FILE}.bak-$(date +%Y%m%d-%H%M%S)"

# Remove qualquer --load-extension antigo (sem aspas e sem vírgulas dentro do valor)
# e insere o novo após "google-chrome-stable" nas linhas Exec=
python3 - "$DESKTOP_FILE" "$flag" << 'PYEOF'
import sys, re
path, new_flag = sys.argv[1], sys.argv[2]
with open(path) as f:
    src = f.read()

# remove flags antigas: --load-extension=<algo até espaço ou fim de linha>
src = re.sub(r' --load-extension=\S+', '', src)

# adiciona após google-chrome-stable (todas as ocorrências de Exec=)
def add_flag(m):
    return m.group(1) + ' ' + new_flag + m.group(2)

src = re.sub(
    r'(/usr/bin/google-chrome-stable)(\s|$)',
    add_flag,
    src,
)

with open(path, 'w') as f:
    f.write(src)
print('OK desktop file updated')
PYEOF

log "atualizado com ${#valid_paths[@]} extension(s)"
for p in "${valid_paths[@]}"; do
  log "  + $p"
done

# Refresca cache de desktop entries para o launcher pegar a mudança
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q "$HOME/.local/share/applications" 2>/dev/null || true
fi

# Symlinks na raiz do spellbook (atalho para "Carregar sem compactação")
for entry in "${EXTENSION_ROOT_SYMLINKS[@]}"; do
  name="${entry%%:*}"
  target="${entry#*:}"
  link="$SPELLBOOK_ROOT/$name"
  full_target="$SPELLBOOK_ROOT/$target"
  if [ ! -d "$full_target" ]; then
    warn "target ausente: $full_target"
    continue
  fi
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    continue
  fi
  ln -sfn "$target" "$link"
  log "symlink raiz $link -> $target"
done

# Wrapper bash: garante que `google-chrome` invocado via PATH (terminal,
# xdg-open, etc.) sempre injete --load-extension. Cobre o caso em que o launcher
# pulou o .desktop (restauração de sessão, chamada por outro app).
if [ -f "$WRAPPER_SRC" ]; then
  mkdir -p "$USER_BIN"
  for name in google-chrome google-chrome-stable; do
    target="$USER_BIN/$name"
    expected="$WRAPPER_SRC"
    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$expected")" ]; then
      continue  # já apontando certo
    fi
    ln -sfn "$expected" "$target"
    log "symlink $target -> $expected"
  done
else
  warn "wrapper source ausente: $WRAPPER_SRC"
fi
