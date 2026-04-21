#!/bin/zsh
#==============================================================================
#  ALIASES
#==============================================================================

# -- Navegacao ----------------------------------------------------------------

# Propósito: Sobe 1 nivel de diretório
# Uso: ..
alias ..="cd .."
# Propósito: Sobe 2 niveis de diretório
# Uso: ...
alias ...="cd ../.."
# Propósito: Sobe 3 niveis de diretório
# Uso: ....
alias ....="cd ../../.."
# Propósito: Sobe 4 niveis de diretório
# Uso: .....
alias .....="cd ../../../.."
# Propósito: Sobe 2 niveis (alternativo)
# Uso: ..2
alias ..2="cd ../.."
# Propósito: Sobe 3 niveis (alternativo)
# Uso: ..3
alias ..3="cd ../../.."
# Propósito: Sobe 4 niveis (alternativo)
# Uso: ..4
alias ..4="cd ../../../.."
# Propósito: Ir para pasta de projetos
# Uso: dev
alias dev='cd ${DEV_DIR:-$HOME/Desenvolvimento}'
# Propósito: Ir para config do zsh
# Uso: cfg
alias cfg='cd ${ZDOTDIR:-$HOME/.config/zsh}'

# -- Arquivos -----------------------------------------------------------------

# Propósito: Apagar com confirmacao
# Uso: apagar <arquivo>
alias apagar='rm -i'
# Propósito: Copiar recursivo com verbose
# Uso: copiar <origem> <destino>
alias copiar='cp -rv'
# Propósito: Mover com verbose
# Uso: mover <origem> <destino>
alias mover='mv -v'
# Propósito: Criar diretórios aninhados
# Uso: criar_pastas <caminho>
alias criar_pastas='mkdir -p'
# Propósito: Listar tudo em formato longo
# Uso: liste_tudo
alias liste_tudo='ls -alF'
# Propósito: Listar tudo exceto . e ..
# Uso: liste_tudo_menos
alias liste_tudo_menos='ls -A'
# Propósito: Listar em colunas com indicadores
# Uso: liste_colunas
alias liste_colunas='ls -CF'
# Propósito: Uso de disco do primeiro nivel ordenado
# Uso: duso
alias duso="du -hd 1 | sort -rh"
# Propósito: Tamanho total de um arquivo ou pasta
# Uso: tamanho <caminho>
alias tamanho='du -sh'
# Propósito: Buscar arquivo por nome no diretório atual
# Uso: encontre <padrao>
alias encontre="find . -name"
# Propósito: Buscar texto dentro de arquivos recursivamente
# Uso: procure_por_texto <texto> <pasta>
alias procure_por_texto="grep -rIl"

# -- APT / Sistema ------------------------------------------------------------

# Propósito: Instalar pacote via apt
# Uso: instalar <pacote>
alias instalar="sudo apt install"
# Propósito: Remover pacote (mantendo configs)
# Uso: remover <pacote>
alias remover="sudo apt remove"
# Propósito: Remover pacote e configs
# Uso: expurgar <pacote>
alias expurgar='sudo apt purge'
# Propósito: Atualizar sistema completo, limpar cache e reconstruir icones
# Uso: limpar_cache
limpar_cache() {
    sudo apt update && sudo apt full-upgrade -y
    flatpak update -y
    flatpak repair --user 2>/dev/null
    sudo apt autoremove -y && sudo apt clean
    _fix_flatpak_icons
    _reconstruir_caches_icones
}
# Propósito: Corrigir dependencias quebradas
# Uso: corrigir_deps
alias corrigir_deps='sudo apt -f install'
# Propósito: Reconfigurar pacotes com falha
# Uso: reparar_pacotes
alias reparar_pacotes='sudo dpkg --configure -a'
# Propósito: Atualizar tudo (apt + topgrade + flatpak + limpeza + caches de icones)
# Uso: atualizar_tudo
atualizar_tudo() {
    sudo dpkg --configure -a
    sudo apt update && sudo apt upgrade -y && sudo apt full-upgrade -y
    topgrade -y
    flatpak update -y
    flatpak repair --user 2>/dev/null
    sudo apt autoremove -y && sudo apt autoclean
    _fix_flatpak_icons
    _reconstruir_caches_icones
}
# Propósito: Atualizar apenas flatpaks
# Uso: flatpak_atualizar
alias flatpak_atualizar='flatpak update -y'
# Propósito: Últimos 20 pacotes instalados via apt
# Uso: instalados_recente
alias instalados_recente="grep ' install ' /var/log/apt/history.log | tail -n 20"
# Propósito: Top 20 maiores pacotes instalados
# Uso: maiores_pacotes
alias maiores_pacotes="dpkg-query -Wf '\${Installed-Size}\t\${Package}\n' | sort -rn | head -n 20"
# Propósito: Reconstruir caches de icones e desktop database
# Uso: atualizar_icones
alias atualizar_icones='_reconstruir_caches_icones'

# -- Rede / Processos ---------------------------------------------------------

# Propósito: Mostrar IP publico
# Uso: meu_ip
alias meu_ip="curl -s ifconfig.me"
# Propósito: Listar portas abertas e processos
# Uso: portas
alias portas="sudo netstat -tulanp"
# Propósito: Buscar processo por nome
# Uso: processo_especifico <nome>
alias processo_especifico='ps aux | grep -v grep | grep'
# Propósito: Acompanhar logs do sistema em tempo real
# Uso: logs
alias logs='journalctl -f'
# Propósito: Abrir monitor de sistema grafico
# Uso: tarefas
alias tarefas='gnome-system-monitor'
# Propósito: Monitor de sistema no terminal (htop)
# Uso: tarefas_terminal
alias tarefas_terminal='htop'
# Propósito: Flush do cache DNS e estatisticas
# Uso: dsn
alias dsn='resolvectl statistics && sudo resolvectl flush-caches && resolvectl statistics'

# -- Git: Status / Log --------------------------------------------------------

# Propósito: Status resumido do git
# Uso: gs
alias gs='git status -s'
# Propósito: Log visual compacto com grafo
# Uso: gl
alias gl='git log --oneline --graph --decorate'
# Propósito: Listar branches locais
# Uso: gb
alias gb='git branch'
# Propósito: Listar branches locais com último commit
# Uso: gbl
alias gbl='git branch -v'
# Propósito: Listar todas as branches (locais + remotas)
# Uso: gbla
alias gbla='git branch -av'
# Propósito: Listar repositorios remotos
# Uso: grv
alias grv='git remote -v'
# Propósito: Diff resumido entre branches
# Uso: gdiff <branch>
alias gdiff='git diff --stat'
# Propósito: Commits que existem em outra branch mas não na atual
# Uso: gmissing <branch>
alias gmissing='git log --oneline HEAD..'
# Propósito: Reflog formatado (histórico de operações git)
# Uso: grf
alias grf='git reflog --format="%C(yellow)%h%Creset %C(blue)%gd%Creset %C(green)%ar%Creset %gs"'

# -- Git: Fluxo Principal -----------------------------------------------------

# Propósito: Commit com mensagem inline
# Uso: gc <mensagem>
alias gc='git commit -m'
# Propósito: Add tudo + commit com mensagem
# Uso: gac <mensagem>
alias gac='git add . && git commit -m'
# Propósito: Push para o remoto
# Uso: gp
alias gp='git push'
# Propósito: Pull com rebase (commits locais no topo)
# Uso: gup
alias gup='git pull --rebase'
# Propósito: Force push seguro (verifica se remoto não mudou)
# Uso: gpf
alias gpf='git push --force-with-lease'
# Propósito: Commit abrindo editor
# Uso: gcm
alias gcm='git commit'
# Propósito: Commit ignorando pre-commit hooks (com aviso de segurança)
# Uso: gcnv
gcnv() {
    echo "  [!] --no-verify pula pre-commit e commit-msg (hooks de anonimato)"
    echo "      pre-push ainda vai validar no momento do push."
    echo ""
    git commit --no-verify "$@"
}

# -- Git: Branches -------------------------------------------------------------

# Propósito: Mudar de branch
# Uso: gco <branch>
alias gco='git checkout'
# Propósito: Criar nova branch e mudar para ela
# Uso: gcb <novo_branch>
alias gcb='git checkout -b'
# Propósito: Deletar branch local (seguro, só se mergeada)
# Uso: gdb <branch>
alias gdb='git branch -d'
# Propósito: Deletar branch local forcado
# Uso: gdbf <branch>
alias gdbf='git branch -D'

# -- Git: Stash ----------------------------------------------------------------

# Propósito: Guardar alterações não commitadas
# Uso: gss
alias gss='git stash push -u'
# Propósito: Recuperar último stash
# Uso: gsp
alias gsp='git stash pop'
# Propósito: Listar stashes
# Uso: gsl
alias gsl='git stash list'
# Propósito: Limpar todos os stashes
# Uso: gsc
alias gsc='git stash clear'

# -- Git: Reset / Limpeza -----------------------------------------------------

# Propósito: Reset hard (destrói alterações locais)
# Uso: grh
alias grh='git reset --hard'
# Propósito: Unstage arquivo (mantém alterações)
# Uso: grs <arquivo>
alias grs='git reset HEAD --'
# Propósito: Unstage tudo (mantém alterações)
# Uso: grsa
alias grsa='git reset'
# Propósito: Descartar alterações de um arquivo
# Uso: gcheckout <arquivo>
alias gcheckout='git checkout --'
# Propósito: Remover arquivos não rastreados e ignorados
# Uso: gclean
alias gclean='git clean -fdx'

# -- Git: Merge / Rebase ------------------------------------------------------
# Propósito: dá um pull trazendo e sobrescrevendo o que temos localmente
# Uso: sincronizar_mec
alias sincronizar_mec='cd ~/Desenvolvimento/MEC/pipelines-main && git pull --rebase origin develop'

# Propósito: Merge de outra branch na atual
# Uso: gm <branch>
alias gm='git merge'
# Propósito: Abortar merge em andamento
# Uso: gma
alias gma='git merge --abort'
# Propósito: Rebase interativo para limpar commits
# Uso: grbi <branch>
alias grbi='git rebase -i'
# Propósito: Abortar rebase em andamento
# Uso: grba
alias grba='git rebase --abort'
# Propósito: Aceitar versão "deles" em conflito
# Uso: gcth <arquivo>
alias gcth='git checkout --theirs'
# Propósito: Aceitar versão "nossa" em conflito
# Uso: gcoo <arquivo>
alias gcoo='git checkout --ours'

# -- Compactacao ---------------------------------------------------------------

# Propósito: Criar arquivo .tar
# Uso: crie_tar <arquivo.tar> <pasta>
alias crie_tar='tar -cvf'
# Propósito: Criar arquivo .tar.gz compactado
# Uso: crie_tar.gz <arquivo.tar.gz> <pasta>
alias crie_tar.gz='tar -czvf'
# Propósito: Criar arquivo .zip recursivo
# Uso: crie_zip <arquivo.zip> <pasta>
alias crie_zip='zip -r'

# -- Shell / QoL ---------------------------------------------------------------

# Propósito: Recarregar configuração do zsh
# Uso: update_zshrc
alias update_zshrc="exec zsh"
# Propósito: Recarregar configuração do zsh (alias em pt-br)
# Uso: atualizar_terminal
alias atualizar_terminal="exec zsh"
# Propósito: Aplicar hooks git em todos os repos
# Uso: aplicar_hooks
alias aplicar_hooks='aplicar_hooks_globais'
# Propósito: Auditar todos os repos por violações de anonimato
# Uso: auditar_repos [diretorio_base]
alias auditar='auditar_repos'
# Propósito: Limpeza interativa do Controle de Bordo
# Uso: limpar
alias limpar='limpeza_interativa'
# Propósito: Limpar cache do npm/npx
# Uso: cache_cli
alias cache_cli='npm cache clean --force'
# Propósito: Limpar tela do terminal
# Uso: cls
alias cls='clear'
# Propósito: Atalho para python3
# Uso: py <script>
alias py='python3'
# Propósito: Pip via módulo python
# Uso: pip <args>
alias pip='python3 -m pip'
# Propósito: Criar virtualenv
# Uso: venv <nome>
alias venv='python3 -m venv'
# Propósito: Ativar venv do projeto atual
# Uso: activate
alias activate='source venv/bin/activate 2>/dev/null || source .venv/bin/activate 2>/dev/null || echo "Nenhum venv encontrado."'
# Propósito: Clima atual da sua cidade
# Uso: tempo
alias tempo='curl -s "wttr.in/?format=%l:+%c+%t+%h+%w"'
# Propósito: Timestamp no formato padrão
# Uso: timestamp
alias timestamp='date +"%Y-%m-%d_%Hh%M"'
# Propósito: Listar PATH de forma legível
# Uso: path
alias path='echo $PATH | tr ":" "\n" | sort'

# -- MEC / dbt ----------------------------------------------------------------

# Propósito: Entrar no projeto pipelines-main (branch padrão)
# Uso: mec
alias mec='santuario MEC pipelines-main'
# Propósito: Entrar no projeto pipelines-main na branch develop
# Uso: mec_dev
alias mec_dev='santuario MEC pipelines-main develop'

# Propósito: dbt run com profiles-dir local (obrigatório no MEC)
# Uso: dbt_run [args]
alias dbt_run='dbt run --profiles-dir dev'
# Propósito: dbt test com profiles-dir local
# Uso: dbt_test [args]
alias dbt_test='dbt test --profiles-dir dev'
# Propósito: dbt compile com profiles-dir local
# Uso: dbt_compile [args]
alias dbt_compile='dbt compile --profiles-dir dev'
# Propósito: dbt ls com profiles-dir local
# Uso: dbt_ls [args]
alias dbt_ls='dbt ls --profiles-dir dev'

# Propósito: Verificar identidade git e status antes de qualquer ação no MEC
# Uso: mec_check
alias mec_check='git_info && git status'

# -- Fontes e Encoding -------------------------------------------------------

# Propósito: Instalar todas as fontes de compatibilidade
# Uso: fontes
alias fontes='fontes_instalar'
# Propósito: Verificar cobertura de fontes instaladas
# Uso: fcheck
alias fcheck='fontes_verificar'
# Propósito: Detectar encoding, BOM e line endings de arquivo ou diretório
# Uso: enc <arquivo|diretório>
alias enc='enc_detectar'

# -- Sistema / Restauracao ----------------------------------------------------

# Propósito: Capturar estado completo do sistema em manifesto JSON
# Uso: capturar
alias capturar='sistema_capturar'
# Propósito: Restaurar sistema a partir de manifesto
# Uso: restaurar <manifesto.json>
alias restaurar='sistema_restaurar'

# -- Spellbook Vault -----------------------------------------------------------

# Propósito: Exportar credentials criptografados para o vault do repo
# Uso: spellbook_export [senha]
spellbook_export() {
    local spellbook_dir="${SPELLBOOK_DIR:-$HOME/Desenvolvimento/Spellbook-OS}"
    bash "$spellbook_dir/scripts/spellbook-secrets.sh" export "$@"
}

# Propósito: Importar credentials do vault criptografado
# Uso: spellbook_import [senha]
spellbook_import() {
    local spellbook_dir="${SPELLBOOK_DIR:-$HOME/Desenvolvimento/Spellbook-OS}"
    bash "$spellbook_dir/scripts/spellbook-secrets.sh" import "$@"
}
