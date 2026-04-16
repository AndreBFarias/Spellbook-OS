#!/bin/zsh
#==============================================================================
#  ALIASES
#==============================================================================

# -- Navegacao ----------------------------------------------------------------

# Proposito: Sobe 1 nivel de diretorio
# Uso: ..
alias ..="cd .."
# Proposito: Sobe 2 niveis de diretorio
# Uso: ...
alias ...="cd ../.."
# Proposito: Sobe 3 niveis de diretorio
# Uso: ....
alias ....="cd ../../.."
# Proposito: Sobe 4 niveis de diretorio
# Uso: .....
alias .....="cd ../../../.."
# Proposito: Sobe 2 niveis (alternativo)
# Uso: ..2
alias ..2="cd ../.."
# Proposito: Sobe 3 niveis (alternativo)
# Uso: ..3
alias ..3="cd ../../.."
# Proposito: Sobe 4 niveis (alternativo)
# Uso: ..4
alias ..4="cd ../../../.."
# Proposito: Ir para pasta de projetos
# Uso: dev
alias dev='cd ${DEV_DIR:-$HOME/Desenvolvimento}'
# Proposito: Ir para config do zsh
# Uso: cfg
alias cfg='cd ${ZDOTDIR:-$HOME/.config/zsh}'

# -- Arquivos -----------------------------------------------------------------

# Proposito: Apagar com confirmacao
# Uso: apagar <arquivo>
alias apagar='rm -i'
# Proposito: Copiar recursivo com verbose
# Uso: copiar <origem> <destino>
alias copiar='cp -rv'
# Proposito: Mover com verbose
# Uso: mover <origem> <destino>
alias mover='mv -v'
# Proposito: Criar diretorios aninhados
# Uso: criar_pastas <caminho>
alias criar_pastas='mkdir -p'
# Proposito: Listar tudo em formato longo
# Uso: liste_tudo
alias liste_tudo='ls -alF'
# Proposito: Listar tudo exceto . e ..
# Uso: liste_tudo_menos
alias liste_tudo_menos='ls -A'
# Proposito: Listar em colunas com indicadores
# Uso: liste_colunas
alias liste_colunas='ls -CF'
# Proposito: Uso de disco do primeiro nivel ordenado
# Uso: duso
alias duso="du -hd 1 | sort -rh"
# Proposito: Tamanho total de um arquivo ou pasta
# Uso: tamanho <caminho>
alias tamanho='du -sh'
# Proposito: Buscar arquivo por nome no diretorio atual
# Uso: encontre <padrao>
alias encontre="find . -name"
# Proposito: Buscar texto dentro de arquivos recursivamente
# Uso: procure_por_texto <texto> <pasta>
alias procure_por_texto="grep -rIl"

# -- APT / Sistema ------------------------------------------------------------

# Proposito: Instalar pacote via apt
# Uso: instalar <pacote>
alias instalar="sudo apt install"
# Proposito: Remover pacote (mantendo configs)
# Uso: remover <pacote>
alias remover="sudo apt remove"
# Proposito: Remover pacote e configs
# Uso: expurgar <pacote>
alias expurgar='sudo apt purge'
# Proposito: Atualizar sistema completo, limpar cache e reconstruir icones
# Uso: limpar_cache
limpar_cache() {
    sudo apt update && sudo apt full-upgrade -y
    flatpak update -y
    flatpak repair --user 2>/dev/null
    sudo apt autoremove -y && sudo apt clean
    _reconstruir_caches_icones
}
# Proposito: Corrigir dependencias quebradas
# Uso: corrigir_deps
alias corrigir_deps='sudo apt -f install'
# Proposito: Reconfigurar pacotes com falha
# Uso: reparar_pacotes
alias reparar_pacotes='sudo dpkg --configure -a'
# Proposito: Atualizar tudo (apt + flatpak + limpeza + caches de icones)
# Uso: atualizar_tudo
atualizar_tudo() {
    sudo apt update && sudo apt full-upgrade -y
    flatpak update -y
    flatpak repair --user 2>/dev/null
    sudo apt autoremove -y && sudo apt clean
    echo "Reconstruindo caches de icones..."
    _reconstruir_caches_icones
}
# Proposito: Atualizar apenas flatpaks
# Uso: flatpak_atualizar
alias flatpak_atualizar='flatpak update -y'
# Proposito: Ultimos 20 pacotes instalados via apt
# Uso: instalados_recente
alias instalados_recente="grep ' install ' /var/log/apt/history.log | tail -n 20"
# Proposito: Top 20 maiores pacotes instalados
# Uso: maiores_pacotes
alias maiores_pacotes="dpkg-query -Wf '\${Installed-Size}\t\${Package}\n' | sort -rn | head -n 20"
# Proposito: Reconstruir caches de icones e desktop database
# Uso: atualizar_icones
alias atualizar_icones='_reconstruir_caches_icones'

# -- Rede / Processos ---------------------------------------------------------

# Proposito: Mostrar IP publico
# Uso: meu_ip
alias meu_ip="curl -s ifconfig.me"
# Proposito: Listar portas abertas e processos
# Uso: portas
alias portas="sudo netstat -tulanp"
# Proposito: Buscar processo por nome
# Uso: processo_especifico <nome>
alias processo_especifico='ps aux | grep -v grep | grep'
# Proposito: Acompanhar logs do sistema em tempo real
# Uso: logs
alias logs='journalctl -f'
# Proposito: Abrir monitor de sistema grafico
# Uso: tarefas
alias tarefas='gnome-system-monitor'
# Proposito: Monitor de sistema no terminal (htop)
# Uso: tarefas_terminal
alias tarefas_terminal='htop'
# Proposito: Flush do cache DNS e estatisticas
# Uso: dsn
alias dsn='resolvectl statistics && sudo resolvectl flush-caches && resolvectl statistics'

# -- Git: Status / Log --------------------------------------------------------

# Proposito: Status resumido do git
# Uso: gs
alias gs='git status -s'
# Proposito: Log visual compacto com grafo
# Uso: gl
alias gl='git log --oneline --graph --decorate'
# Proposito: Listar branches locais
# Uso: gb
alias gb='git branch'
# Proposito: Listar branches locais com ultimo commit
# Uso: gbl
alias gbl='git branch -v'
# Proposito: Listar todas as branches (locais + remotas)
# Uso: gbla
alias gbla='git branch -av'
# Proposito: Listar repositorios remotos
# Uso: grv
alias grv='git remote -v'
# Proposito: Diff resumido entre branches
# Uso: gdiff <branch>
alias gdiff='git diff --stat'
# Proposito: Commits que existem em outra branch mas nao na atual
# Uso: gmissing <branch>
alias gmissing='git log --oneline HEAD..'
# Proposito: Reflog formatado (historico de operacoes git)
# Uso: grf
alias grf='git reflog --format="%C(yellow)%h%Creset %C(blue)%gd%Creset %C(green)%ar%Creset %gs"'

# -- Git: Fluxo Principal -----------------------------------------------------

# Proposito: Commit com mensagem inline
# Uso: gc <mensagem>
alias gc='git commit -m'
# Proposito: Add tudo + commit com mensagem
# Uso: gac <mensagem>
alias gac='git add . && git commit -m'
# Proposito: Push para o remoto
# Uso: gp
alias gp='git push'
# Proposito: Pull com rebase (commits locais no topo)
# Uso: gup
alias gup='git pull --rebase'
# Proposito: Force push seguro (verifica se remoto nao mudou)
# Uso: gpf
alias gpf='git push --force-with-lease'
# Proposito: Commit abrindo editor
# Uso: gcm
alias gcm='git commit'
# Proposito: Commit ignorando pre-commit hooks (com aviso de seguranca)
# Uso: gcnv
gcnv() {
    echo "  [!] --no-verify pula pre-commit e commit-msg (hooks de anonimato)"
    echo "      pre-push ainda vai validar no momento do push."
    echo ""
    git commit --no-verify "$@"
}

# -- Git: Branches -------------------------------------------------------------

# Proposito: Mudar de branch
# Uso: gco <branch>
alias gco='git checkout'
# Proposito: Criar nova branch e mudar para ela
# Uso: gcb <novo_branch>
alias gcb='git checkout -b'
# Proposito: Deletar branch local (seguro, so se merjada)
# Uso: gdb <branch>
alias gdb='git branch -d'
# Proposito: Deletar branch local forcado
# Uso: gdbf <branch>
alias gdbf='git branch -D'

# -- Git: Stash ----------------------------------------------------------------

# Proposito: Guardar alteracoes nao commitadas
# Uso: gss
alias gss='git stash push -u'
# Proposito: Recuperar ultimo stash
# Uso: gsp
alias gsp='git stash pop'
# Proposito: Listar stashes
# Uso: gsl
alias gsl='git stash list'
# Proposito: Limpar todos os stashes
# Uso: gsc
alias gsc='git stash clear'

# -- Git: Reset / Limpeza -----------------------------------------------------

# Proposito: Reset hard (destroi alteracoes locais)
# Uso: grh
alias grh='git reset --hard'
# Proposito: Unstage arquivo (mantem alteracoes)
# Uso: grs <arquivo>
alias grs='git reset HEAD --'
# Proposito: Unstage tudo (mantem alteracoes)
# Uso: grsa
alias grsa='git reset'
# Proposito: Descartar alteracoes de um arquivo
# Uso: gcheckout <arquivo>
alias gcheckout='git checkout --'
# Proposito: Remover arquivos nao rastreados e ignorados
# Uso: gclean
alias gclean='git clean -fdx'

# -- Git: Merge / Rebase ------------------------------------------------------
# Proposito: dá um pull trazendo e sobrescrevendo o que temos localmente
# Uso: sincronizar_mec
alias sincronizar_mec='cd ~/Desenvolvimento/MEC/pipelines-main && git pull --rebase origin develop'

# Proposito: Merge de outra branch na atual
# Uso: gm <branch>
alias gm='git merge'
# Proposito: Abortar merge em andamento
# Uso: gma
alias gma='git merge --abort'
# Proposito: Rebase interativo para limpar commits
# Uso: grbi <branch>
alias grbi='git rebase -i'
# Proposito: Abortar rebase em andamento
# Uso: grba
alias grba='git rebase --abort'
# Proposito: Aceitar versao "deles" em conflito
# Uso: gcth <arquivo>
alias gcth='git checkout --theirs'
# Proposito: Aceitar versao "nossa" em conflito
# Uso: gcoo <arquivo>
alias gcoo='git checkout --ours'

# -- Compactacao ---------------------------------------------------------------

# Proposito: Criar arquivo .tar
# Uso: crie_tar <arquivo.tar> <pasta>
alias crie_tar='tar -cvf'
# Proposito: Criar arquivo .tar.gz compactado
# Uso: crie_tar.gz <arquivo.tar.gz> <pasta>
alias crie_tar.gz='tar -czvf'
# Proposito: Criar arquivo .zip recursivo
# Uso: crie_zip <arquivo.zip> <pasta>
alias crie_zip='zip -r'

# -- Shell / QoL ---------------------------------------------------------------

# Proposito: Recarregar configuracao do zsh
# Uso: update_zshrc
alias update_zshrc="exec zsh"
# Proposito: Recarregar configuracao do zsh (alias em pt-br)
# Uso: atualizar_terminal
alias atualizar_terminal="exec zsh"
# Proposito: Aplicar hooks git em todos os repos
# Uso: aplicar_hooks
alias aplicar_hooks='aplicar_hooks_globais'
# Proposito: Auditar todos os repos por violacoes de anonimato
# Uso: auditar_repos [diretorio_base]
alias auditar='auditar_repos'
# Proposito: Limpeza interativa do Controle de Bordo
# Uso: limpar
alias limpar='limpeza_interativa'
# Proposito: Limpar cache do npm/npx
# Uso: cache_cli
alias cache_cli='npm cache clean --force'
# Proposito: Limpar tela do terminal
# Uso: cls
alias cls='clear'
# Proposito: Atalho para python3
# Uso: py <script>
alias py='python3'
# Proposito: Pip via modulo python
# Uso: pip <args>
alias pip='python3 -m pip'
# Proposito: Criar virtualenv
# Uso: venv <nome>
alias venv='python3 -m venv'
# Proposito: Ativar venv do projeto atual
# Uso: activate
alias activate='source venv/bin/activate 2>/dev/null || source .venv/bin/activate 2>/dev/null || echo "Nenhum venv encontrado."'
# Proposito: Clima atual da sua cidade
# Uso: tempo
alias tempo='curl -s "wttr.in/?format=%l:+%c+%t+%h+%w"'
# Proposito: Timestamp no formato padrao
# Uso: timestamp
alias timestamp='date +"%Y-%m-%d_%Hh%M"'
# Proposito: Listar PATH de forma legivel
# Uso: path
alias path='echo $PATH | tr ":" "\n" | sort'

# -- MEC / dbt ----------------------------------------------------------------

# Proposito: Entrar no projeto pipelines-main (branch padrao)
# Uso: mec
alias mec='santuario MEC pipelines-main'
# Proposito: Entrar no projeto pipelines-main na branch develop
# Uso: mec_dev
alias mec_dev='santuario MEC pipelines-main develop'

# Proposito: dbt run com profiles-dir local (obrigatorio no MEC)
# Uso: dbt_run [args]
alias dbt_run='dbt run --profiles-dir dev'
# Proposito: dbt test com profiles-dir local
# Uso: dbt_test [args]
alias dbt_test='dbt test --profiles-dir dev'
# Proposito: dbt compile com profiles-dir local
# Uso: dbt_compile [args]
alias dbt_compile='dbt compile --profiles-dir dev'
# Proposito: dbt ls com profiles-dir local
# Uso: dbt_ls [args]
alias dbt_ls='dbt ls --profiles-dir dev'

# Proposito: Verificar identidade git e status antes de qualquer acao no MEC
# Uso: mec_check
alias mec_check='git_info && git status'

# -- Fontes e Encoding -------------------------------------------------------

# Proposito: Instalar todas as fontes de compatibilidade
# Uso: fontes
alias fontes='fontes_instalar'
# Proposito: Verificar cobertura de fontes instaladas
# Uso: fcheck
alias fcheck='fontes_verificar'
# Proposito: Detectar encoding, BOM e line endings de arquivo ou diretorio
# Uso: enc <arquivo|diretorio>
alias enc='enc_detectar'

# -- Sistema / Restauracao ----------------------------------------------------

# Proposito: Capturar estado completo do sistema em manifesto JSON
# Uso: capturar
alias capturar='sistema_capturar'
# Proposito: Restaurar sistema a partir de manifesto
# Uso: restaurar <manifesto.json>
alias restaurar='sistema_restaurar'

# -- Spellbook Vault -----------------------------------------------------------

# Proposito: Exportar credentials criptografados para o vault do repo
# Uso: spellbook_export [senha]
spellbook_export() {
    local spellbook_dir="${SPELLBOOK_DIR:-$HOME/Desenvolvimento/Spellbook-OS}"
    bash "$spellbook_dir/scripts/spellbook-secrets.sh" export "$@"
}

# Proposito: Importar credentials do vault criptografado
# Uso: spellbook_import [senha]
spellbook_import() {
    local spellbook_dir="${SPELLBOOK_DIR:-$HOME/Desenvolvimento/Spellbook-OS}"
    bash "$spellbook_dir/scripts/spellbook-secrets.sh" import "$@"
}
