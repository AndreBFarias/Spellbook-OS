#!/bin/bash
#
# DEPRECATED em 2026-04-29 — substituído por Aurora 2.0
# Ver: ~/.config/zsh/aurora/ (units systemd + watchdog + bootstrap idempotente)
# Recovery: ~/.config/zsh/aurora/RECOVERY.md
# Este script é mantido APENAS para referência histórica; nada o invoca mais.
#

# Propósito: Ajusta a GPU e garante que serviços essenciais estejam rodando.
#            Lógica: Só pede senha (sudo) se encontrar algo desligado.
#

# Definição de Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Iniciando o RITUAL DA AURORA...${NC}"

# --- FUNÇÃO INTELIGENTE (O Cérebro do Script) ---
# Verifica se o serviço roda. Se sim, avisa. Se não, tenta ligar (pedindo senha).
garantir_servico() {
    local servico=$1
    local nome=$2

    # Verifica status (silent) - Qualquer usuário pode ler isso
    if systemctl is-active --quiet "$servico"; then
        echo -e "${GREEN}-> $nome: Já está ativo e operante.${NC}"
    else
        echo -e "${YELLOW}-> $nome: ESTÁ DORMINDO! Solicitando permissão para acordá-lo...${NC}"

        # Aqui ele vai pedir a senha APENAS se entrar neste 'else'
        if sudo systemctl enable --now "$servico"; then
            echo -e "${GREEN}-> $nome: Acordado com sucesso.${NC}"
        else
            echo -e "${RED}-> $nome: Falha ao ligar (Senha recusada ou erro).${NC}"
        fi
    fi
}

# --- 1. CONFIGURAÇÃO DE ENERGIA E GRÁFICOS ---
echo -e "\n[1/4] Despertando o coração da Nvidia (Modo Performance)..."
# Pequena pausa para garantir que o ambiente gráfico carregou
sleep 3

if command -v nvidia-settings &> /dev/null; then
    # Configuração de usuário (não pede senha)
    nvidia-settings -a '[gpu:0]/GpuPowerMizerMode=1'

    # Configuração de sistema (usa nossa regra Polkit - não pede senha)
    system76-power profile performance

    echo -e "${GREEN}-> GPU e Energia configurados para poder máximo.${NC}"
else
    echo -e "${YELLOW}-> Nvidia não detectada. Pulando.${NC}"
fi

# --- 2. GUARDIÃO DA MEMÓRIA ---
echo -e "\n[2/4] Verificando o Guardião da Memória..."
if command -v earlyoom &> /dev/null; then
    garantir_servico "earlyoom" "EarlyOOM"
else
    echo -e "${RED}ERRO: 'earlyoom' não instalado.${NC}"
fi

# --- 3. CONECTIVIDADE E REDE ---
echo -e "\n[3/4] Verificando Portais de Conexão..."

# SSH
if command -v sshd &> /dev/null; then
    garantir_servico "ssh" "Mordomo SSH"
else
    echo -e "${RED}ERRO: SSH Server não instalado.${NC}"
fi

# Avahi (mDNS)
if command -v avahi-daemon &> /dev/null; then
    garantir_servico "avahi-daemon" "Farol da Rede (mDNS)"
else
    echo -e "${RED}ERRO: Avahi Daemon não instalado.${NC}"
fi

# --- 4. CONCLUSÃO ---
echo -e "\n${GREEN}[4/4] Ritual concluido. O sistema está pronto.${NC}"
sleep 3
