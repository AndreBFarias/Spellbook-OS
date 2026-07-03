#!/bin/zsh
# .zshenv do ZDOTDIR — roda em TODO zsh (interativo ou não; cron, systemd, zsh -c).
# Mantenha MÍNIMO. Criado em 2026-07-02: garante ~/.local/bin no PATH também em
# shells não-interativos (scripts como docx_doctor/relatorio_pdf ficam sempre acháveis).
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
