#!/bin/zsh
# Aliases curtos para o sistema de sprint Claude Code
# Atalhos para `sprint <subcomando>` (definido em functions/sprint.zsh)
# Conflitos: se algum alias colidir com comando existente, remova o que não usar

# Atalhos do ciclo
alias splan='sprint plan'
alias sexec='sprint exec'
alias sval='sprint val'
alias sciclo='sprint ciclo'
alias sciclom='sprint ciclo-manual'

# Atalhos de memória
alias sbrief='sprint brief'
alias sbedit='sprint brief-edit'
alias sboot='sprint bootstrap'
alias sbr='sprint bootstrap --rich'

# Diagnostico
alias sdoc='sprint doctor'
