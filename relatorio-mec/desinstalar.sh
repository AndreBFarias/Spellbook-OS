#!/usr/bin/env bash
# desinstalar_relatorio_mec.sh — remove tudo que instalar_relatorio_mec.sh criou
set -uo pipefail
systemctl --user disable --now onlyoffice-pdf-lavar.path 2>/dev/null
rm -f "$HOME/.config/systemd/user/onlyoffice-pdf-lavar."{path,service}
systemctl --user daemon-reload 2>/dev/null
rm -f "$HOME/.local/bin/"{relatorio_fontfix,docx_doctor,pdf_lavar,pdf_lavar_watch,relatorio_pdf}
rm -f "$HOME/.config/fontconfig/conf.d/60-relatorio-mec.conf"
rm -rf "$HOME/.local/share/fonts/LiberationNarrow"
fc-cache -f >/dev/null 2>&1
echo "relatorio-mec removido (fontes OpenSansCondensed e função zsh preservadas — remova à mão se quiser)"
