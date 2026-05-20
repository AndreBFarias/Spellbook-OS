#!/bin/zsh
# Aurora - sysupgrade: upgrade sistema completo + reaplicação das configs aurora
# ----------------------------------------------------------------------------
# Sequência: apt update -> upgrade -> topgrade -> autoremove -> autoclean ->
# aurora-reapply-all (re-injeta dpkg-divert, policy chrome, symlinks user-bin,
# desktop entries, daemon gradia).
#
# Cobre o cenário em que apt upgrade google-chrome-stable potencialmente
# afetaria nosso wrapper (na prática dpkg-divert sobrevive, mas garantimos).

# Reaplica todos os scripts idempotentes do aurora em ordem segura.
# Delega para aurora-reapply-all.sh (standalone, também invocado pelo APT post-invoke).
aurora-reapply-all() {
  local script="$HOME/.config/zsh/aurora/aurora-reapply-all.sh"
  if [ -x "$script" ]; then
    bash "$script"
  else
    printf '\033[31m[aurora-reapply]\033[0m script não encontrado: %s\n' "$script" >&2
    return 1
  fi
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
