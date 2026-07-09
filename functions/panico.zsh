#!/bin/zsh
# pânico.zsh — comando de terminal para a tela de kernel panic cosmética (fullscreen).
# É puramente visual: NÃO trava o teclado nem o sistema.
#   kernel_panic          -> abre a tela em kiosk fullscreen (com dados reais + QR)
#   kernel_panic --stop    -> encerra a tela
# Encerrar também com: Esc  ou  Alt+F4.

kernel_panic() {
  local script="$HOME/.config/zsh/panico-teatral.sh"
  if [ ! -f "$script" ]; then
    printf '\033[31m[kernel_panic]\033[0m não encontrei %s\n' "$script" >&2
    return 1
  fi
  [ -x "$script" ] || chmod +x "$script" 2>/dev/null
  "$script" "$@"
}

# atalho curto
alias panico='kernel_panic'
