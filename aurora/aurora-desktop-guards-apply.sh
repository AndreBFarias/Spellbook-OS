#!/bin/bash
# Aurora - desktop-guards: mantém os .desktop de ~/.local/share/applications
# saudáveis (idempotente). Conserta os modos de quebra observados em 2026-06-22:
#   1. Permissão 600 → launcher do Pop não abre o app. Fix: chmod 644.
#   2. PhotoGIMP Exec=--command=gimp-3.0 (inexistente no GIMP 3.2+, bwrap falha)
#      → normaliza para 'gimp'.
#   3. .desktop órfão NoDisplay=true apontando p/ Flatpak DESINSTALADO → esconde
#      o app no launcher mesmo após reinstalar (precedência XDG). Move p/ .bak.
# Também garante tracker-extract-3 mascarado (loop de crash SIGSYS seccomp×libcuda).
# Roda em user-space, sem sudo. Sempre exit 0 (não bloqueia o self-heal).
set -u

APPS="$HOME/.local/share/applications"
changed=0
log(){ printf '[aurora-desktop-guards] %s\n' "$1"; }

[ -d "$APPS" ] || exit 0

# 1. Permissões: qualquer .desktop sem leitura para todos → 644
while IFS= read -r f; do
  chmod 644 "$f" 2>/dev/null && { log "perm 644: ${f##*/}"; changed=1; }
done < <(find "$APPS" -maxdepth 1 -type f -name '*.desktop' ! -perm -044 2>/dev/null)

# 2. PhotoGIMP: Exec=--command=gimp-3.0 → gimp (genérico, sobrevive a upgrades)
gimp_desktop="$APPS/org.gimp.GIMP.desktop"
if [ -f "$gimp_desktop" ] && grep -q -- '--command=gimp-3\.0' "$gimp_desktop" 2>/dev/null; then
  sed -i 's/--command=gimp-3\.0/--command=gimp/' "$gimp_desktop" \
    && { log "Exec gimp-3.0→gimp em org.gimp.GIMP.desktop"; changed=1; }
fi

# 3. Órfãos NoDisplay=true apontando p/ Flatpak não-instalado → move p/ .bak
bak="$APPS/.aurora-orphan-bak"
while IFS= read -r f; do
  grep -qi '^NoDisplay=true' "$f" 2>/dev/null || continue
  grep -q 'flatpak run' "$f" 2>/dev/null || continue
  # app-id = token reverse-DNS (>=2 pontos) na linha Exec
  appid=$(grep -m1 '^Exec=' "$f" | tr ' ' '\n' \
    | grep -E '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_-]+){2,}$' | head -1)
  [ -n "$appid" ] || continue
  if ! flatpak info "$appid" >/dev/null 2>&1; then
    mkdir -p "$bak"
    mv "$f" "$bak/" 2>/dev/null \
      && { log "órfão p/ .bak: ${f##*/} (Flatpak $appid não instalado)"; changed=1; }
  fi
done < <(find "$APPS" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null)

# 4. tracker-extract-3 mascarado (mata o loop SIGSYS de vez)
if [ "$(systemctl --user is-enabled tracker-extract-3.service 2>/dev/null)" != "masked" ]; then
  systemctl --user mask tracker-extract-3.service >/dev/null 2>&1 \
    && { log "tracker-extract-3 mascarado"; changed=1; }
fi

[ "$changed" = "1" ] && update-desktop-database "$APPS" 2>/dev/null
exit 0
