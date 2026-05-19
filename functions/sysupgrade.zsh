#!/bin/zsh
# Aurora - sysupgrade: upgrade sistema completo + reaplicação das configs aurora
# ----------------------------------------------------------------------------
# Sequência: apt update -> upgrade -> topgrade -> autoremove -> autoclean ->
# aurora-reapply-all (re-injeta dpkg-divert, policy chrome, symlinks user-bin,
# desktop entries, daemon gradia).
#
# Cobre o cenário em que apt upgrade google-chrome-stable potencialmente
# afetaria nosso wrapper (na prática dpkg-divert sobrevive, mas garantimos).

# Reaplica todos os scripts idempotentes do aurora em ordem segura
aurora-reapply-all() {
  local aurora="$HOME/.config/zsh/aurora"
  local scripts=(
    aurora-userscripts-apply.sh
    aurora-chrome-extensions-apply.sh
    aurora-chrome-divert-apply.sh
    aurora-user-apply.sh
  )

  for s in "${scripts[@]}"; do
    if [ -x "$aurora/$s" ]; then
      printf '\033[36m[aurora-reapply]\033[0m %s\n' "$s"
      "$aurora/$s" 2>&1 | sed 's/^/  /' || true
    fi
  done
}

sysupgrade() {
  set -o pipefail
  printf '\033[36m[sysupgrade]\033[0m apt update + upgrade...\n'
  sudo apt update && sudo apt upgrade -y || { printf '[sysupgrade] apt falhou\n' >&2; return 1; }

  if command -v topgrade >/dev/null 2>&1; then
    printf '\033[36m[sysupgrade]\033[0m topgrade...\n'
    topgrade -y || printf '[sysupgrade][warn] topgrade retornou erro (não bloqueia)\n' >&2
  fi

  printf '\033[36m[sysupgrade]\033[0m apt autoremove + autoclean...\n'
  sudo apt autoremove -y
  sudo apt autoclean

  printf '\033[36m[sysupgrade]\033[0m reaplicando configs Aurora...\n'
  aurora-reapply-all
}
