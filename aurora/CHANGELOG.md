# Aurora — Changelog de features e mapa de reaplicação

Cada feature listada tem um **aplicador idempotente** que pode reaplicar a configuração após `apt full-upgrade`, reinstalação de pacote, ou drift acidental.

## Mecanismo de reaplicação automática

1. **APT DPkg::Post-Invoke** (`/etc/apt/apt.conf.d/99-aurora-postinvoke`):
   Após cada operação apt (install/upgrade/remove), roda `aurora-bootstrap.sh --post-update --quiet` como usuário `andrefarias`. Cobre TUDO listado abaixo.

2. **`aurora-reapply-all.sh`** (manual ou via `sysupgrade`):
   Wrapper standalone que invoca o bootstrap + sub-aplicadores user-space. Loga em `~/.local/state/aurora-reapply.log`.

3. **`aurora-self-heal-cached`** (boot do shell, cache 1h):
   Detecta drift em 13 checkpoints. Se houver, oferece o aplicador correspondente.

4. **`sysupgrade`** (zsh function):
   Sequência completa: `apt update -> upgrade -> topgrade -> autoremove -> autoclean -> aurora-reapply-all`.

## Matriz feature -> aplicador

Coluna "Self-heal check" indica se `aurora-self-heal` consegue detectar drift dessa feature: `OK` = detecta, `(pendente)` = a implementar.

| Data | Versão | Feature | Side-effect | Aplicador | Self-heal check |
|---|---|---|---|---|---|
| 2026-03 | 1.0 | Persistent journald | `/etc/systemd/journald.conf.d/00-aurora-persistent.conf` | bootstrap (sysctl + journald) | (pendente) |
| 2026-03 | 1.0 | earlyoom config | `/etc/default/earlyoom` | bootstrap copia_se_diff | OK |
| 2026-03 | 1.0 | sysctl tuning | `/etc/sysctl.d/99-aurora.conf` | bootstrap copia_se_diff | OK |
| 2026-03 | 1.0 | aurora-root.service + watchdog | `/etc/systemd/system/aurora-{root,watchdog}.*` | bootstrap copia_se_diff | OK |
| 2026-03 | 1.0 | APT post-invoke (auto-reapply) | `/etc/apt/apt.conf.d/99-aurora-postinvoke` | bootstrap copia_se_diff | OK |
| 2026-04 | 1.5 | mem-snapshot + logrotate | `/var/log/mem-snapshot.log` + units | bootstrap (units) | (pendente) |
| 2026-04 | 1.5 | product-oom-watchdog | systemd unit | bootstrap (units) | (pendente) |
| 2026-04 | 2.0 | Ollama keepalive + VRAM watchdog | `slices ollama.slice + units` | bootstrap (units) | (pendente) |
| 2026-06-01 | 2.3 | amdgpu DMCUB display watchdog (recupera display AMD travado sem reboot: gpu_recover + restart do compositor; endurecido: detecta Wayland, valida debugfs/recover, rajada de reset >=3/10min, assinaturas extras de hang) | `units amdgpu-dmcub-watchdog.{service,timer}` + `aurora/amdgpu-dmcub-watchdog` | bootstrap (units) | OK |
| 2026-06-01 | 2.3 | botão de pânico de GPU (Ctrl+Alt+0 via xbindkeys: 1x recupera, 2x reinicia a sessão) | `/usr/local/sbin/aurora-gpu-revive` + `/etc/sudoers.d/aurora-gpu-revive` + `~/.xbindkeysrc` + autostart | bootstrap (revive+sudoers) + aurora-gpu-shortcut-apply.sh | OK |
| 2026-06-01 | 2.3 | editor padrão estilo Notepad (gnome-text-editor restaura sessão e guarda rascunho sem título; gedit mantido) | `xdg-mime default text/plain` + `gsettings restore-session` | aurora-editor-apply.sh | OK |
| 2026-04 | 2.0 | Chrome dpkg-divert (anti-IA) | `/usr/bin/google-chrome-stable.distrib` + symlinks | aurora-chrome-divert-apply.sh | OK |
| 2026-04 | 2.0 | Chrome policy IA/Antigravity | `/etc/opt/chrome/policies/managed/aurora-no-ai-no-antigravity.json` | aurora-chrome-divert-apply.sh | OK |
| 2026-04 | 2.0 | Chrome --load-extension | `~/.local/share/applications/google-chrome.desktop` | aurora-chrome-extensions-apply.sh | OK |
| 2026-04 | 2.0 | Ctrl+C Ilimitado userscript | `~/.local/bin/control-c-ilimitado-ext` | aurora-userscripts-apply.sh | OK (info) |
| 2026-04 | 2.1 | gradia-autosave daemon | `~/.config/systemd/user/gradia-autosave.service` | aurora-user-services-apply.sh | OK |
| 2026-05-16 | 2.3-ULTRA | Anti-suspend persistente | `/etc/systemd/logind.conf.d/99-no-suspend.conf` | bootstrap | (pendente) |
| 2026-05-16 | 2.3-ULTRA | NVIDIA persistence-mode | systemd unit | bootstrap | (pendente) |
| 2026-05-16 | 2.3-ULTRA | Wi-Fi powersave OFF | `/etc/NetworkManager/conf.d/99-aurora-ultra-wifi.conf` + remoção do `default-wifi-powersave-on.conf` | bootstrap (com .bak guard) | OK |
| 2026-05-16 | 2.3-ULTRA | kernel cmdline params (pcie_aspm, nvme PS0) | `kernelstub --add-options` | bootstrap (--first-install) | (pendente; check via `/proc/cmdline`) |
| 2026-05-19 | 2.4 | imagens-router daemon | `~/.config/systemd/user/imagens-router.service` | aurora-user-services-apply.sh | OK |
| 2026-05-20 | 2.5 | aurora-reapply-all.sh consolidado | `~/.config/zsh/aurora/aurora-reapply-all.sh` | (próprio) | -- |
| 2026-05-20 | 2.5 | self-heal ampliado (13 checks) | -- | -- | -- |

## Para validar o sistema todo

```bash
aurora-self-heal           # 17 checks, mostra drift e propoe fix
bash aurora-reapply-all.sh # reaplica tudo idempotente; loga em ~/.local/state/aurora-reapply.log
sysupgrade                 # apt + topgrade + reapply em sequencia
```

## Cenário de falha após `apt full-upgrade`

Se uma feature se perder:
1. `apt full-upgrade` roda; ao terminar, `99-aurora-postinvoke` dispara `aurora-bootstrap.sh --post-update --quiet`.
2. Bootstrap reaplica `/etc/sysctl.d/`, `/etc/systemd/system/`, `/etc/default/earlyoom`, NetworkManager, etc.
3. Próxima abertura de terminal, `aurora-self-heal-cached` faz double-check (1h de cache para não pesar boot).
4. Se ainda houver drift, mostra mensagem com o aplicador específico.
