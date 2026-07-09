#!/usr/bin/env bash
# panico-teatral.sh — tela de kernel panic (cosmética) em fullscreen, tema Pop!_OS.
# Uso:
#   ./panico-teatral.sh          -> gera a tela com dados reais e abre em kiosk
#   ./panico-teatral.sh --stop   -> encerra a tela
# É puramente visual: NÃO trava o teclado nem o sistema. Alt+F4 ou --stop encerra.

WORK="${TMPDIR:-/tmp}/panico-teatral"
HTML="$WORK/panic.html"
PROFILE="$WORK/panico-profile"          # marcador usado pelo --stop (não aparece no argv deste script)
export DISPLAY="${DISPLAY:-:1}"

# ---- encerrar --------------------------------------------------------------
if [ "${1:-}" = "--stop" ]; then
  if pkill -f "panico-profile" 2>/dev/null; then echo "kiosk encerrado."; else echo "nada rodando."; fi
  exit 0
fi

mkdir -p "$WORK"

# ---- dados reais (capturados AGORA) ----------------------------------------
NOW="$(date '+%a %d %b %Y · %H:%M:%S %Z')"
HOSTN="$(hostname)"
KREL="$(uname -r)"
DISTRO="$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}" )"
WHO="$(id -un 2>/dev/null || whoami)"

FF="$(fastfetch --pipe --logo none 2>/dev/null)"
field(){ printf '%s\n' "$FF" | sed -n "s/^$1: //p" | head -1; }
CPU_F="$(field 'CPU')";      : "${CPU_F:=CPU desconhecida}"
MODEL_F="$(field 'Modelo')"; : "${MODEL_F:=$HOSTN}"
GPU_F="$(field 'GPU 1')";    : "${GPU_F:=GPU}"
UP_F="$(field 'Tempo Ativo')"; : "${UP_F:=?}"
MEM_F="$(field 'Memória')";  : "${MEM_F:=?}"

# ---- QR real e escaneável -> system76.com (SVG, sem PIL) -------------------
# grava em arquivo (evita heredoc no stdin + shim do pyenv, que zerava o SVG)
python3 -c "import qrcode, qrcode.image.svg as s; qrcode.make('https://system76.com', image_factory=s.SvgPathImage, border=1).save('$WORK/qr.svg')" 2>/dev/null
# tira a declaração XML e as dimensões em mm para o CSS controlar o tamanho
QR="$(sed 's/<?xml[^>]*?>//; s/ width="[0-9]*mm"//; s/ height="[0-9]*mm"//' "$WORK/qr.svg" 2>/dev/null)"
[ -z "$QR" ] && QR='<div style="font:12px monospace">system76.com</div>'

# ---- logo Pop!_OS em ASCII -------------------------------------------------
IFS= read -r -d '' LOGO <<'ART'
             /////////////
         /////////////////////
      ///////*767////////////////
    //////7676767676*//////////////
   /////76767//7676767//////////////
  /////767676///*76767///////////////
 ///////767676///76767.///7676*///////
/////////767676//76767///767676////////
//////////76767676767////76767/////////
///////////76767676//////7676//////////
////////////,7676,///////767///////////
/////////////*7676///////76////////////
///////////////7676////////////////////
 ///////////////7676///767////////////
  //////////////////////'////////////
   //////.7676767676767676767,//////
    /////767676767676767676767/////
      ///////////////////////////
         /////////////////////
             /////////////
ART

# ---- dump do panic (com dados reais) + revelação linha-a-linha -------------
LINES=(
"[   57.884211] EXT4-fs (nvme0n1p2): re-mounted. Opts: errors=remount-ro"
"[   58.012774] audit: type=1400 audit(1783531200.114:42): apparmor=\"STATUS\" operation=\"profile_load\""
"[   58.128390] usb 1-4: USB disconnect, device number 7"
"[   58.241905] systemd[1]: Starting Journal Service..."
"[   58.301447] systemd[1]: Caught &lt;SEGV&gt;, dumped core as pid 1084."
"[   58.312902] systemd[1]: Freezing execution."
"[   58.319774] Kernel panic - not syncing: Attempted to kill init! exitcode=0x0000000b"
"[   58.319774]"
"[   58.331066] CPU: 5 PID: 1 Comm: systemd Tainted: G        W   OE     ${KREL} #202607"
"[   58.341558] Hardware name: Acer ${MODEL_F}, BIOS 1.17 08/21/2025"
"[   58.343100] microcode: ${CPU_F}"
"[   58.344920] nouveau 0000:01:00.0: ${GPU_F}"
"[   58.346551] mem: ${MEM_F}"
"[   58.350021] Call Trace:"
"[   58.353884]  &lt;TASK&gt;"
"[   58.357012]  dump_stack_lvl+0x48/0x70"
"[   58.361559]  dump_stack+0x10/0x20"
"[   58.365770]  panic+0x35c/0x370"
"[   58.369640]  do_exit+0xb41/0xc60"
"[   58.373682]  do_group_exit+0x35/0x90"
"[   58.378047]  get_signal+0x9a3/0x9c0"
"[   58.382240]  arch_do_signal_or_restart+0x3e/0x270"
"[   58.387643]  exit_to_user_mode_loop+0xd6/0x130"
"[   58.392787]  irqentry_exit_to_user_mode+0x9/0x20"
"[   58.398103]  asm_exc_page_fault+0x27/0x30"
"[   58.408046] RIP: 0033:0x7f3c1a4e8a2f"
"[   58.412324] Code: Unable to access opcode bytes at 0x7f3c1a4e8a05."
"[   58.419055] RSP: 002b:00007ffd4b9c2ad0 EFLAGS: 00010246"
"[   58.424976] RAX: 0000000000000000 RBX: 00005618f2c1a0e0 RCX: 00007f3c1a4e8a2f"
"[   58.432920]  &lt;/TASK&gt;"
"[   58.435701] Kernel Offset: 0x2ae00000 from 0xffffffff81000000"
"[   58.447553] ---[ end Kernel panic - not syncing: Attempted to kill init! exitcode=0x0000000b ]---"
)

LOGHTML=""
i=0
for ln in "${LINES[@]}"; do
  cs=$((16 + i*3))
  d="$((cs/100)).$(printf '%02d' $((cs%100)))"
  cls="ln"
  case "$ln" in
    *"Kernel panic - not syncing"*) cls="ln hot" ;;
    *"end Kernel panic"*)           cls="ln end" ;;
  esac
  LOGHTML+="<div class=\"$cls\" style=\"animation-delay:${d}s\">$ln</div>"
  i=$((i+1))
done
# cursor fica no rodapé (sempre visível — a área do log faz overflow:hidden)

# ---- monta o HTML ----------------------------------------------------------
cat > "$HTML" <<EOF
<!doctype html><html><head><meta charset="utf-8"><title>kernel panic</title>
<style>
  :root{--bg:#564a86;--fg:#ece7fb;--dim:#b6aadf;--hot:#ffb27a;--end:#ff9d9d;}
  *{box-sizing:border-box}
  html,body{margin:0;height:100%;overflow:hidden;cursor:none;background:var(--bg);color:var(--fg);
    font-family:"Ubuntu Mono","DejaVu Sans Mono","Liberation Mono","Consolas",monospace;}
  body{background:radial-gradient(130% 120% at 50% 35%, #6154a0 0%, #564a86 55%, #3e356a 100%);
    display:flex;flex-direction:column;padding:2.4vh 3vw;gap:1.2vh;}
  .top{display:flex;align-items:flex-start;gap:2.2vw;flex:none;}
  .logo{margin:0;font-size:.9vh;line-height:1;color:#cdbff2;text-shadow:0 0 6px rgba(180,150,255,.5);opacity:.95;white-space:pre;}
  .meta{padding-top:.6vh;}
  .brand{font-size:2.5vh;letter-spacing:.28em;color:#fff;text-shadow:0 0 10px rgba(255,190,130,.35);}
  .meta .l{font-size:1.9vh;color:var(--dim);margin-top:.5vh;}
  .meta .l b{color:var(--fg);font-weight:400;}
  .log{flex:1;min-height:0;font-size:1.68vh;line-height:1.24;overflow:hidden;}
  .ln{opacity:0;white-space:pre-wrap;word-break:break-word;animation:rv .16s ease-out forwards;}
  .ln.hot{color:var(--hot);text-shadow:0 0 8px rgba(255,150,90,.5);}
  .ln.end{color:var(--end);}
  .cur{display:inline-block;width:.72em;height:1.25em;background:var(--fg);vertical-align:-3px;
    box-shadow:0 0 9px rgba(230,220,255,.6);animation:bl 1.05s steps(1) infinite;}
  .bottom{display:flex;justify-content:space-between;align-items:flex-end;gap:3vw;flex:none;}
  .crash .big{font-size:3.6vh;font-weight:700;letter-spacing:.16em;color:var(--hot);
    text-shadow:0 0 14px rgba(255,160,90,.55);}
  .crash .r{font-size:2.2vh;margin-top:.6vh;color:var(--fg);}
  .crash .d{font-size:1.7vh;margin-top:.4vh;color:var(--dim);}
  .qrbox{display:flex;flex-direction:column;align-items:center;gap:.7vh;}
  .qr{width:13vh;height:13vh;background:#fff;border-radius:6px;padding:.8vh;box-shadow:0 0 18px rgba(0,0,0,.35);}
  .qr svg{display:block;width:100%;height:100%;}
  .qr svg path{fill:#3a2f66;}
  .qrcap{font-size:1.45vh;color:var(--dim);text-align:center;letter-spacing:.04em;}
  .qrcap b{color:#ffd9b0;font-weight:400;}
  /* CRT: scanlines + flicker + vinheta */
  .vig{position:fixed;inset:0;pointer-events:none;z-index:4;
    background:radial-gradient(120% 120% at 50% 42%, transparent 52%, rgba(18,10,38,.6) 100%);}
  .scan{position:fixed;inset:0;pointer-events:none;z-index:5;mix-blend-mode:overlay;
    background:repeating-linear-gradient(0deg, rgba(0,0,0,.22) 0 1px, rgba(255,255,255,.03) 1px 2px, transparent 2px 4px);
    animation:flick 5.5s steps(48) infinite;}
  @keyframes flick{0%,100%{opacity:.55}12%{opacity:.72}47%{opacity:.6}63%{opacity:.8}81%{opacity:.62}}
  @keyframes rv{from{opacity:0;transform:translateY(3px)}to{opacity:1;transform:none}}
  @keyframes bl{50%{opacity:0}}
</style></head><body>
  <div class="top">
    <pre class="logo">${LOGO}</pre>
    <div class="meta">
      <div class="brand">SYSTEM76 · POP!_OS</div>
      <div class="l"><b>${DISTRO}</b></div>
      <div class="l">user <b>${WHO}</b> · host <b>${HOSTN}</b></div>
      <div class="l">${NOW}</div>
      <div class="l">uptime <b>${UP_F}</b></div>
    </div>
  </div>
  <div class="log">${LOGHTML}</div>
  <div class="bottom">
    <div class="crash">
      <div class="big">KERNEL PANIC !</div>
      <div class="r">Please reboot your computer.</div>
      <div class="d">sysrq triggered crash · init killed · exitcode 0x0000000b</div>
      <div class="d">system halted <span class="cur"></span></div>
    </div>
    <div class="qrbox">
      <div class="qr">${QR}</div>
      <div class="qrcap">scan with camera<br><b>system76.com</b></div>
    </div>
  </div>
  <div class="vig"></div><div class="scan"></div>
</body></html>
EOF

# ---- abre em kiosk fullscreen (perfil isolado -> não mexe no seu Chrome) ----
pkill -f "panico-profile" 2>/dev/null
sleep 1
BROWSER="$(command -v google-chrome || command -v google-chrome-stable || command -v chromium || command -v chromium-browser)"
if [ -z "$BROWSER" ]; then echo "nenhum Chrome/Chromium encontrado" >&2; exit 1; fi

nohup "$BROWSER" --kiosk --start-fullscreen --new-window \
  --user-data-dir="$PROFILE" \
  --no-first-run --no-default-browser-check --disable-session-crashed-bubble \
  --disable-infobars --hide-crash-restore-bubble \
  "file://$HTML" >/dev/null 2>&1 &
disown

# fecha no Esc: listener global via python-Xlib (grab_key na raiz -> independe de foco/WM)
if python3 -c "import Xlib" >/dev/null 2>&1; then
  cat > "$WORK/esc_listener.py" <<'PY'
import subprocess, time, sys
from Xlib import X, display, XK
d = display.Display()
root = d.screen().root
kc = d.keysym_to_keycode(XK.XK_Escape)
mods = [0, X.LockMask, X.Mod2Mask, X.LockMask | X.Mod2Mask]
for m in mods:
    try:
        root.grab_key(kc, m, False, X.GrabModeAsync, X.GrabModeAsync)
    except Exception:
        pass
d.sync()

def alive():
    return subprocess.call(['pgrep', '-f', 'panico-profile'],
                           stdout=subprocess.DEVNULL) == 0

try:
    while alive():
        while d.pending_events():
            ev = d.next_event()
            if ev.type == X.KeyPress:
                subprocess.call(['pkill', '-f', 'panico-profile'])
                sys.exit(0)
        time.sleep(0.15)
finally:
    for m in mods:
        try:
            root.ungrab_key(kc, m)
        except Exception:
            pass
    d.sync()
PY
  nohup python3 "$WORK/esc_listener.py" >/dev/null 2>&1 &
  disown
fi

echo "tela de panic no ar (fullscreen)."
echo "para encerrar:  Esc   (também Alt+F4  ou  $0 --stop)"
