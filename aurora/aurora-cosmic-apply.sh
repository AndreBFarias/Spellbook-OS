#!/usr/bin/env bash
# aurora-cosmic-apply.sh — leva-03 da Migração-OS: o que a migração
# 22.04/GNOME → 24.04/COSMIC (2026-09-11) deixou quebrado no dia a dia.
#
# Cinco queixas do dono em 2026-09-14, e o que cada uma era de verdade:
#
#   1. "Ctrl+V não cola imagem no terminal"   → NÃO era o agente Code. O binário
#      2.1.270 já chama `wl-paste --type image/png` sozinho. O que faltava era o
#      PACOTE wl-clipboard: a máquina só tinha xclip/xsel, que são X11 e não
#      enxergam o clipboard de um cosmic-term nativo Wayland. Instalar resolve.
#
#   2. "o Print tem que usar a ferramenta nativa"  → já usava. Conferido por 12
#      capturas em ~/Imagens/Screenshots/ no mesmo dia. O binding vem do default
#      do sistema (linha 114 de /usr/share/cosmic/.../v1/defaults). Declarar no
#      custom não muda hoje; garante que um reset de defaults não leve junto.
#
#   3. "o atalho do Gradia não presta"  → o Ctrl+Shift+S do dono PENDURAVA. O
#      main() do Gradia chama read_from_stdin() antes do app.run(), e sob o Spawn
#      do cosmic-comp o filho herda um pipe que nunca fecha: read() bloqueia para
#      sempre e a janela nunca abre. Medido às 18:06 (4 PIDs presos em bwrap).
#      Curado pelo aurora-gradia-clipboard.sh, que fecha o stdin (`</dev/null`).
#
#   4. "Alt+F2 não funciona como na Andromeda"  → o alvo não existia aqui. O
#      aurora-reiniciar-painel.sh (v3.66) foi portado da meowsystem em 14/09.
#
#   5. "a webcam não funciona"  → o hardware está perfeito (ffmpeg capturou
#      1280x720 na primeira tentativa). Quem bloqueava era
#      ~/.local/share/flatpak/overrides/global com `devices=!all;dri;`. O `!all`
#      REVOGA o `devices=all` que Discord, Edge, OBS e Telegram trazem no próprio
#      manifesto — todos apareciam com `devices=dri;` apenas. Ver NOTA abaixo.
#
# NOTA DE SEGURANÇA — por que `devices=dri` e não `devices=all`:
#   A auditoria aud-01 (Migração-OS/auditorias/02-hardware-drivers.md) achou um
#   `devices=all` POSITIVO no global, que dava /dev inteiro aos 25 apps, e mandou
#   removê-lo. Certíssimo. Mas o que acabou no arquivo foi `!all`, que é outra
#   coisa: negar para todos, inclusive para quem o manifesto autoriza. Este script
#   deixa a linha em `devices=dri;` — o meio-termo correto: o global não CONCEDE
#   device nenhum além de dri, e cada app fica com o que seu próprio manifesto
#   pede. É o comportamento padrão do Flatpak, não um afrouxamento.
#
# IDEMPOTÊNCIA E SOBREVIVÊNCIA A DIST-UPGRADE (requisito do dono, 2026-09-14):
#   - Fonte canônica = ~/.config/zsh/aurora/ (repo Spellbook-OS, com git e
#     spellbook-autosync). /usr/local/bin é DESTINO, nunca origem: um dist-upgrade
#     que limpe /usr/local não perde nada, e rodar este script reconstrói.
#   - Toda cópia passa por cmp antes (não reescreve o que já está igual).
#   - Os atalhos são mesclados pelo aurora-cosmic-shortcuts.py, que compara
#     SEMÂNTICA (frozenset de modificadores + tecla), não texto: a reserialização
#     que o COSMIC faz do arquivo não vira churn, e atalho criado pelo dono na GUI
#     é preservado.
#   - Rodar N vezes seguidas produz o mesmo estado. Testado.
#
# Uso:  aurora-cosmic-apply.sh [--check]
#       --check  relata o que faria, não escreve nada.
set -uo pipefail

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

AURORA_REPO="${AURORA_REPO:-$HOME/.config/zsh/aurora}"
log()  { printf '[cosmic-apply] %s\n' "$*"; }
warn() { printf '[cosmic-apply][WARN] %s\n' "$*" >&2; }
MUDOU=0

# ---------------------------------------------------------------------------
# 1. Dependências de clipboard Wayland
# ---------------------------------------------------------------------------
faltando=()
for p in wl-clipboard wtype; do
  dpkg -s "$p" >/dev/null 2>&1 || faltando+=("$p")
done
if [ ${#faltando[@]} -gt 0 ]; then
  if [ $CHECK -eq 1 ]; then
    log "[check] instalaria: ${faltando[*]}"
  elif sudo -n apt-get install -y "${faltando[@]}" >/dev/null 2>&1; then
    log "pacotes instalados: ${faltando[*]}"; MUDOU=1
  else
    warn "sem sudo -n para instalar ${faltando[*]} — rode 'sudo -v' antes"
  fi
else
  log "ok: wl-clipboard e wtype presentes"
fi

# ---------------------------------------------------------------------------
# 2. Scripts do repo -> /usr/local/bin (cmp antes; repo é a fonte da verdade)
# ---------------------------------------------------------------------------
for f in claude-paste-image.sh aurora-gradia-clipboard.sh \
         aurora-gradia-config.sh aurora-reiniciar-painel.sh \
         aurora-reiniciar-casca.sh; do
  src="$AURORA_REPO/$f"; dst="/usr/local/bin/$f"
  [ -f "$src" ] || { warn "fonte ausente: $src"; continue; }
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then continue; fi
  if [ $CHECK -eq 1 ]; then log "[check] instalaria $dst"; continue; fi
  if sudo -n install -o root -g root -m 0755 "$src" "$dst" 2>/dev/null; then
    log "instalado: $dst"; MUDOU=1
  else
    warn "falha ao instalar $dst (sudo -n sem cache)"
  fi
done

# ---------------------------------------------------------------------------
# 3. Atalhos do COSMIC (merge semântico — ver aurora-cosmic-shortcuts.py)
# ---------------------------------------------------------------------------
if [ -x "$AURORA_REPO/aurora-cosmic-shortcuts.py" ]; then
  if [ $CHECK -eq 1 ]; then
    "$AURORA_REPO/aurora-cosmic-shortcuts.py" --check 2>&1 | grep -E '^  (>>|OK|!!|--)' | head -20
  else
    "$AURORA_REPO/aurora-cosmic-shortcuts.py" 2>&1 | sed 's/^/[cosmic-apply] /'
  fi
else
  warn "aurora-cosmic-shortcuts.py ausente — atalhos não aplicados"
fi

# ---------------------------------------------------------------------------
# 4. Webcam: tirar a negação `!all` do override global do Flatpak
# ---------------------------------------------------------------------------
FP="$HOME/.local/share/flatpak/overrides/global"
if [ -f "$FP" ] && grep -q '^devices=.*!all' "$FP"; then
  if [ $CHECK -eq 1 ]; then
    log "[check] removeria '!all' de devices= em $FP"
  else
    # remove só o token !all, preserva o resto da linha
    sed -i 's/^\(devices=.*\)!all;/\1/' "$FP"
    sed -i 's/^devices=$/devices=dri;/' "$FP"
    log "webcam: '!all' removido de $FP -> $(grep '^devices=' "$FP")"
    MUDOU=1
  fi
else
  log "ok: override do Flatpak sem negação de devices"
fi

# ---------------------------------------------------------------------------
# 5. Webcam: a gambiarra do uvcvideo que não era necessária
#    Só remove se o conteúdo for EXATAMENTE o quirk conhecido. Se alguém
#    escreveu outra coisa ali depois, é decisão nova e não se mexe.
# ---------------------------------------------------------------------------
UVC=/etc/modprobe.d/uvcvideo.conf
if [ -f "$UVC" ]; then
  if [ "$(tr -d '[:space:]' < "$UVC")" = "optionsuvcvideoquirks=0x80" ]; then
    if [ $CHECK -eq 1 ]; then
      log "[check] removeria $UVC (quirk 0x80 comprovadamente desnecessário)"
    elif sudo -n mv "$UVC" "$UVC.removido-leva-03" 2>/dev/null; then
      log "webcam: $UVC removido (o 'Forcing UVC 1.0a' vem da tabela do kernel, não daqui)"
      MUDOU=1
    else
      warn "sem sudo -n para remover $UVC"
    fi
  else
    warn "$UVC tem conteúdo diferente do quirk conhecido — não mexi"
  fi
else
  log "ok: sem gambiarra de uvcvideo"
fi

# ---------------------------------------------------------------------------
# 6. Gradia: exit-method='none' + overwrite-screenshot (auto-save da edição)
# ---------------------------------------------------------------------------
if [ -x /usr/local/bin/aurora-gradia-config.sh ] && [ $CHECK -eq 0 ]; then
  /usr/local/bin/aurora-gradia-config.sh 2>&1 | sed 's/^/[cosmic-apply] /' || true
fi

[ $CHECK -eq 1 ] && { log "--check: nada foi escrito"; exit 0; }
[ $MUDOU -eq 0 ] && log "nada a fazer — já consistente"
exit 0
