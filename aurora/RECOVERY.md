# Aurora 2.0 — Recuperação Total

## Cenário: reinstalei Pop!_OS / formatei / mudei de máquina

```bash
# 1. Clonar dotfiles (spellbook autosync ja sincroniza ~/.config/zsh)
git clone <seu-repo-spellbook> ~/.config/zsh

# 2. Bootstrap completo
bash ~/.config/zsh/aurora/aurora-bootstrap.sh --first-install

# 3. Reboot (kernelstub args precisam de reboot pra entrar em vigor)
sudo reboot

# 4. Verificar
systemctl is-active aurora-root.service earlyoom.service aurora-watchdog.timer
systemctl --user is-active aurora-user.service
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor   # -> performance
sysctl vm.swappiness                                          # -> 180
sudo kernelstub --print-config | grep mitigations             # -> mitigations=off
```

## Cenário: apt upgrade rodou — quero validar que nada foi perdido

```bash
# Hook /etc/apt/apt.conf.d/99-aurora-postinvoke ja roda automaticamente.
# Para forcar manualmente:
bash ~/.config/zsh/aurora/aurora-bootstrap.sh --post-update
```

## Cenário: governor caiu pra schedutil (suspend/resume regrediu)

Watchdog reaplica em <=15min. Pra forçar imediato:
```bash
sudo systemctl start aurora-watchdog.service
```

## Cenário: Claude/cca travou, sessão Mutter morreu

```bash
# Sessão tmux sobrevive. Liste:
tmux ls
# Reanexe:
tmux a -t claude-<projeto>-<sha>
```

## Pré-requisitos

- `kernelstub` (já vem no Pop!_OS)
- `system76-power` (já vem no Pop!_OS System76)
- `earlyoom` (`sudo apt install earlyoom`)
- `tmux`
- `nvidia-settings` + `nvidia-smi` (drivers proprietários)
- NOPASSWD em `/etc/sudoers.d/andrefarias` (já configurado)

## Troubleshooting

- **`aurora-root.service` falha**: `journalctl -u aurora-root.service --no-pager`
- **Kernel cmdline não atualizou**: `sudo kernelstub --print-config` — verifique flag por flag
- **earlyoom matando o que não devia**: `journalctl -u earlyoom -n 100` — ajuste regex em `~/.config/zsh/aurora/earlyoom.default` e re-rode bootstrap
- **`claude.slice` não aplica**: `systemctl --user status claude.slice` deve mostrar `MemoryHigh=10G`
- **Freeze após acordar de suspend**: bug do driver NVIDIA Optimus. Mitigação: `sudo systemctl restart nvidia-persistenced`. Para preservar VRAM em transições futuras, garanta que `nvidia-suspend.service`, `nvidia-resume.service` e `nvidia-hibernate.service` estão `enabled` (Aurora 2.1 habilita automaticamente no `aurora-bootstrap.sh`).
- **Freeze quando ollama satura VRAM**: o watchdog `ollama-vram-watchdog.timer` checa a cada 30s e reinicia `ollama.service` se ele for o top consumer e VRAM ≥ 90%. Logs em `journalctl -t aurora-vram-watchdog -n 50`. Se o problema persistir, ajuste limites em `aurora/units/ollama.slice` (default `MemoryHigh=6G MemoryMax=9G`).
- **Aviso de saúde no Desktop (`AURORA-AVISO.md`)**: gerado pelo `aurora-health.timer` (a cada 30min). Verifica SMART, disk space (>=90%), CPU >85°C, GPU >80°C. Só aparece com falha; somem sozinhos quando resolver. Logs em `journalctl -t aurora-health -n 50`.
- **Forensics pós-OOM/freeze (Aurora 2.2)**: `journalctl -b -1 -k | grep -iE "oom|killed process"` mostra kernel OOM killer do boot anterior (journald agora é persistente). Pressão de memória nos minutos antes do crash em `/var/log/mem-snapshot.log` (CSV, sample 30s): coluna `psi_some_avg10 > 5.0` = thrashing; coluna `top15` formato `pid:comm:rss_mib;...` revela picos súbitos de RSS. Util: `sudo awk -F, 'NR>1 && $6+0 > 5' /var/log/mem-snapshot.log`.
- **Slices de browser/Electron**: Chrome roda dentro de `browser.slice` (`MemoryHigh=8G MemoryMax=10G`); apps Electron (Slack, Discord, VS Code) em `electron.slice` (`MemoryHigh=4G MemoryMax=6G`). Aplicado via override XDG em `~/.local/share/applications/<app>.desktop` que envolve `Exec=` em `systemd-run --user --slice=<slice> --scope`. **Apps já abertos continuam fora do slice** até serem fechados e reabertos pelo menu/dock. Pra verificar: `systemd-cgls --no-pager | grep -A3 browser.slice`.

## Habilitando kdump (debug pós-mortem de kernel panic)

Não vem aplicado pelo Aurora — reserva ~256 MiB de RAM no boot e mexe no kernel cmdline (risco de regressão por benefício esporádico). Quem quiser:

```bash
sudo apt install linux-crashdump
# Responder "yes" ao prompt sobre reservar crashkernel memory
sudo reboot
# Confirmar:
cat /proc/cmdline | tr ' ' '\n' | grep crashkernel
ls /var/crash
```

Após panic, `/var/crash/<timestamp>/` terá `dmesg.txt` e `dump.<n>` (memory image). Dumps grandes (~RAM size); apagar manualmente após análise.
