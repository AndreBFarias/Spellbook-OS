#!/bin/zsh
# Aurora - self-heal: detecta drift das configs persistentes e reaplica
# ----------------------------------------------------------------------------
# Roda automaticamente ao abrir terminal (via .zshrc) com cache de 1h para não
# repetir em cada shell. Detecta:
#   - Policy file Chrome /etc/opt/chrome/policies/managed/aurora-no-ai-no-antigravity.json
#   - dpkg-divert /usr/bin/google-chrome-stable.distrib
#   - Symlinks ~/.local/bin/google-chrome[-stable]
#   - Desktop entry com --load-extension
#   - Daemon gradia-autosave.service ativo
#
# Quando detecta drift, re-aplica o que dá user-space sem prompt; alerta sobre
# itens que precisam sudo (e dá comando exato pro user rodar).

aurora-self-heal() {
  local issues=()
  local fixes_user=()
  local fixes_root=()
  local aurora="$HOME/.config/zsh/aurora"

  # Chrome policy (root-owned)
  if [ ! -f /etc/opt/chrome/policies/managed/aurora-no-ai-no-antigravity.json ]; then
    issues+=("policy IA/Antigravity ausente em /etc/opt/chrome/policies/managed/")
    fixes_root+=("$aurora/aurora-chrome-divert-apply.sh")
  fi

  # dpkg-divert (root-owned)
  if [ ! -L /usr/bin/google-chrome-stable.distrib ] && [ ! -e /usr/bin/google-chrome-stable.distrib ]; then
    issues+=("dpkg-divert do google-chrome-stable perdido")
    fixes_root+=("$aurora/aurora-chrome-divert-apply.sh")
  fi

  # Symlinks user-bin
  if [ ! -L "$HOME/.local/bin/google-chrome" ] || [ ! -L "$HOME/.local/bin/google-chrome-stable" ]; then
    issues+=("symlinks ~/.local/bin/google-chrome[-stable] ausentes")
    fixes_user+=("$aurora/aurora-chrome-extensions-apply.sh")
  fi

  # Desktop entry com flag
  if [ -f "$HOME/.local/share/applications/google-chrome.desktop" ]; then
    if ! grep -q "load-extension" "$HOME/.local/share/applications/google-chrome.desktop"; then
      issues+=(".desktop google-chrome sem --load-extension")
      fixes_user+=("$aurora/aurora-chrome-extensions-apply.sh")
    fi
  fi

  # Daemon gradia
  if ! systemctl --user is-active --quiet gradia-autosave.service 2>/dev/null; then
    issues+=("daemon gradia-autosave inativo")
    fixes_user+=("systemctl --user start gradia-autosave.service")
  fi

  # Daemon imagens-router (FireShot/PrintFriendly -> ~/Imagens/<pasta>)
  if ! systemctl --user is-active --quiet imagens-router.service 2>/dev/null; then
    issues+=("daemon imagens-router inativo")
    fixes_user+=("$aurora/aurora-user-services-apply.sh")
  fi

  # Ctrl+C Ilimitado carregada no Chrome (precisa load manual em Chrome 128+)
  local pref_file="$HOME/.config/google-chrome/Default/Preferences"
  if [ -f "$pref_file" ] && ! grep -q "control-c-ilimitado-ext" "$pref_file" 2>/dev/null; then
    issues+=("Ctrl+C Ilimitado não carregada no Chrome (Chrome 128+ ignora --load-extension)")
    fixes_user+=("INFO: rode 'control_c_ilimitado' para abrir chrome://extensions e importar manualmente")
  fi

  # /etc/sysctl.d/99-aurora.conf (kernel tuning persistido)
  if [ ! -f /etc/sysctl.d/99-aurora.conf ] || ! cmp -s "$aurora/99-aurora.conf" /etc/sysctl.d/99-aurora.conf 2>/dev/null; then
    issues+=("/etc/sysctl.d/99-aurora.conf ausente ou divergente")
    fixes_root+=("$aurora/aurora-reapply-all.sh")
  fi

  # /etc/default/earlyoom (pode ser sobrescrito por apt update do pacote earlyoom)
  if [ -f "$aurora/earlyoom.default" ]; then
    if [ ! -f /etc/default/earlyoom ] || ! cmp -s "$aurora/earlyoom.default" /etc/default/earlyoom 2>/dev/null; then
      issues+=("/etc/default/earlyoom ausente ou divergente (apt pode ter sobrescrito)")
      fixes_root+=("$aurora/aurora-reapply-all.sh")
    fi
  fi

  # /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf — Aurora remove esse para preservar powersave=2
  if [ -f /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf ] && \
     [ ! -f /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf.bak-aurora-ultra ]; then
    # Apt reinstalou o pacote network-manager e voltou o arquivo
    issues+=("NetworkManager wifi-powersave-on reativado (apt sobrescreveu)")
    fixes_root+=("$aurora/aurora-reapply-all.sh")
  fi

  # units systemd root (aurora-root.service, aurora-watchdog.{service,timer})
  for unit in aurora-root.service aurora-watchdog.service aurora-watchdog.timer; do
    if ! systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      issues+=("unit systemd '$unit' não habilitada (apt pode ter removido)")
      fixes_root+=("$aurora/aurora-reapply-all.sh")
    fi
  done

  # APT post-invoke hook (defesa contra removal acidental)
  if [ ! -f /etc/apt/apt.conf.d/99-aurora-postinvoke ]; then
    issues+=("APT post-invoke hook ausente (auto-reapply não vai disparar em próximo upgrade)")
    fixes_root+=("$aurora/aurora-reapply-all.sh")
  fi

  # ~/.oh-my-zsh drift (executabilidade removida em massa por causa desconhecida — incidente 2025-08-11)
  if [ -d "$HOME/.oh-my-zsh/.git" ]; then
    local omz_dirty
    omz_dirty=$(git -C "$HOME/.oh-my-zsh" status --porcelain 2>/dev/null | wc -l)
    if [ "$omz_dirty" -gt 0 ]; then
      issues+=("oh-my-zsh com $omz_dirty arquivos em drift (provável regressão de permissões)")
      fixes_user+=("git -C $HOME/.oh-my-zsh restore --staged --worktree -- .")
    fi
  fi

  if [ ${#issues[@]} -eq 0 ]; then
    return 0
  fi

  printf '\033[33m[aurora-self-heal]\033[0m drift detectado em %d ítem(ns):\n' ${#issues[@]}
  for i in "${issues[@]}"; do printf '  - %s\n' "$i"; done

  # Aplica fixes user-space sem prompt
  local applied=0
  for fix in "${fixes_user[@]}"; do
    case "$fix" in
      *systemctl*) eval "$fix" 2>/dev/null && applied=$((applied+1)) ;;
      git\ *) eval "$fix" 2>/dev/null && applied=$((applied+1)) ;;
      *) [ -x "$fix" ] && "$fix" >/dev/null 2>&1 && applied=$((applied+1)) ;;
    esac
  done

  # Fixes root-space: só roda se sudo NOPASSWD; senão informa user
  if [ ${#fixes_root[@]} -gt 0 ]; then
    if sudo -n true 2>/dev/null; then
      for fix in "${fixes_root[@]}"; do
        [ -x "$fix" ] && bash "$fix" >/dev/null 2>&1 && applied=$((applied+1))
      done
    else
      printf '\033[33m[aurora-self-heal]\033[0m fixes que precisam sudo (rode manualmente):\n'
      for fix in "${fixes_root[@]}"; do
        printf '  sudo bash %s\n' "$fix"
      done
    fi
  fi

  [ $applied -gt 0 ] && printf '\033[32m[aurora-self-heal]\033[0m %d fix(es) aplicado(s)\n' $applied
}

# Wrapper com cache (não roda toda hora se já checou recentemente)
aurora-self-heal-cached() {
  local cache="$HOME/.cache/aurora-self-heal.timestamp"
  local now last elapsed
  now=$(date +%s)
  last=0
  [ -f "$cache" ] && last=$(cat "$cache" 2>/dev/null) && [[ "$last" =~ ^[0-9]+$ ]] || last=0
  elapsed=$((now - last))
  # Cache de 1h. Override com AURORA_SELF_HEAL_FORCE=1
  if [ -z "${AURORA_SELF_HEAL_FORCE:-}" ] && [ $elapsed -lt 3600 ]; then
    return 0
  fi
  aurora-self-heal
  mkdir -p "$(dirname "$cache")" 2>/dev/null
  echo "$now" > "$cache" 2>/dev/null
}
