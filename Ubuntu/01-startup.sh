#!/bin/bash
# ════════════════════════════════════════════════════════
# Script de Hardening de Servidor Ubuntu - Default VPS
# Version: 1.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
# ════════════════════════════════════════════════════════

set -uo pipefail
IFS=$'\n\t'

# ════════════════════════════════════════════════════════
# VARIÁVEIS GLOBAIS
# ════════════════════════════════════════════════════════

# Diretório base do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Diretórios de log e checkpoint
LOG_DIR="${SCRIPT_DIR}/logs"
CHECKPOINT_FILE="${SCRIPT_DIR}/.startup-checkpoint"
LOG_FILE="${LOG_DIR}/startup-$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="${LOG_DIR}/startup-errors.log"

# Garantir que diretório de logs existe
mkdir -p "$LOG_DIR"

# Variáveis de configuração (serão preenchidas interativamente)
SSH_USER=""
SSH_USER_PASS=""
SSH_PORT=""
SWAP_SIZE=""
PUB_KEY=""
TAILSCALE_IPV4=""
TAILSCALE_IPV6=""
INSTALL_MOD_BLOCK=""

# Cores para output
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

# Total de fases (15 fases)
TOTAL_PHASES=15

# Tempo inicial do script
START_TIME=$(date +%s)

# ════════════════════════════════════════════════════════
# FUNÇÕES DE TEMPO
# ════════════════════════════════════════════════════════

format_time() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    
    if [ $minutes -eq 0 ]; then
        echo "${remaining_seconds}s"
    else
        echo "${minutes}m ${remaining_seconds}s"
    fi
}

get_elapsed_time() {
    local current=$(date +%s)
    local elapsed=$((current - START_TIME))
    format_time $elapsed
}

# ════════════════════════════════════════════════════════
# FUNÇÕES DE LOGGING
# ════════════════════════════════════════════════════════

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log para arquivo (sempre)
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Log para terminal (com cores)
    case "$level" in
        INFO)
            echo -e "${COLOR_CYAN}ℹ ${COLOR_RESET}$message"
            ;;
        SUCCESS)
            echo -e "${COLOR_GREEN}✅${COLOR_RESET} $message"
            ;;
        WARNING)
            echo -e "${COLOR_YELLOW}⚠️ ${COLOR_RESET}$message"
            ;;
        ERROR)
            echo -e "${COLOR_RED}❌${COLOR_RESET} $message"
            echo "[$timestamp] [ERROR] $message" >> "$ERROR_LOG"
            ;;
        PHASE)
            echo -e "\n${COLOR_BOLD}${COLOR_BLUE}═══ $message${COLOR_RESET}\n"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# ════════════════════════════════════════════════════════
# FUNÇÕES DE CHECKPOINT
# ════════════════════════════════════════════════════════

is_phase_completed() {
    local phase="$1"
    if [ -f "$CHECKPOINT_FILE" ]; then
        grep -q "^${phase}$" "$CHECKPOINT_FILE" 2>/dev/null
        return $?
    fi
    return 1
}

mark_phase_completed() {
    local phase="$1"
    echo "$phase" >> "$CHECKPOINT_FILE"
    log SUCCESS "Fase '$phase' concluída e salva no checkpoint"
}

get_completed_phases() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        wc -l < "$CHECKPOINT_FILE" | tr -d ' '
    else
        echo "0"
    fi
}

reset_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        rm -f "$CHECKPOINT_FILE"
        log INFO "Checkpoint resetado"
    fi
}

# ════════════════════════════════════════════════════════
# FUNÇÃO DE PROGRESS BAR
# ════════════════════════════════════════════════════════

show_progress() {
    local current=$(get_completed_phases)
    local total=$TOTAL_PHASES
    local percentage=$((current * 100 / total))
    local filled=$((current * 50 / total))
    local empty=$((50 - filled))
    
    printf "\r${COLOR_BOLD}Progresso:${COLOR_RESET} ["
    printf "${COLOR_GREEN}%${filled}s${COLOR_RESET}" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] ${COLOR_CYAN}%d%%${COLOR_RESET} (%d/%d fases)" "$percentage" "$current" "$total"
}

# ════════════════════════════════════════════════════════
# VERIFICAÇÕES INICIAIS
# ════════════════════════════════════════════════════════

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log ERROR "Este script deve ser executado como ROOT"
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        log WARNING "Este script foi projetado para Ubuntu. Pode não funcionar corretamente em outros sistemas."
        read -p "Deseja continuar mesmo assim? (s/N): " confirm
        if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
            exit 1
        fi
    fi
}

# ════════════════════════════════════════════════════════
# CONFIGURAÇÃO INTERATIVA (apenas se não houver checkpoint)
# ════════════════════════════════════════════════════════

interactive_config() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        log INFO "Checkpoint encontrado. Recuperando configuração anterior..."
        # Carregar variáveis do checkpoint (se necessário)
        return
    fi
    
    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  CONFIGURAÇÃO INICIAL DO SISTEMA${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""

    # ETAPA 1: Escolher usuário SSH
    log PHASE "ETAPA 1/5: Configurar usuário SSH"
    echo "Escolha qual usuário terá acesso SSH:"
    echo "  1) root (manterá acesso root com chave SSH)"
    echo "  2) ubuntu (criar/usar usuário ubuntu - recomendado)"
    echo "  3) outro (especificar nome de usuário customizado)"
    echo ""
    while true; do
        read -p "Opção [1-3]: " user_choice
        case $user_choice in
            1)
                SSH_USER="root"
                log SUCCESS "Usuário SSH será: root"
                log WARNING "⚠️  Root login será permitido apenas com chave SSH"
                break
                ;;
            2)
                SSH_USER="ubuntu"
                log SUCCESS "Usuário SSH será: ubuntu"
                break
                ;;
            3)
                read -p "Nome do usuário: " SSH_USER
                if [[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ ${#SSH_USER} -le 32 ]; then
                    log SUCCESS "Usuário SSH será: $SSH_USER"
                    break
                else
                    log ERROR "Nome de usuário inválido. Use apenas letras minúsculas, números, _ e -"
                fi
                ;;
            *)
                log ERROR "Opção inválida. Escolha 1, 2 ou 3"
                ;;
        esac
    done
    echo ""

    # ETAPA 2: Senha do usuário (apenas se não for root)
    if [ "$SSH_USER" != "root" ]; then
        log PHASE "ETAPA 2/5: Definir senha para usuário $SSH_USER"
        while true; do
            read -s -p "Digite a nova senha do usuário $SSH_USER: " SSH_USER_PASS
            echo
            read -s -p "Repita a senha: " SSH_USER_PASS2
            echo
            
            if [ "$SSH_USER_PASS" = "$SSH_USER_PASS2" ]; then
                if [ -z "$SSH_USER_PASS" ]; then
                    log ERROR "Senha não pode ser vazia"
                    continue
                fi
                break
            else
                log ERROR "As senhas não conferem. Tente novamente."
            fi
        done
        log SUCCESS "Senha definida"
        echo ""
    else
        log INFO "Usuário root - senha não será alterada"
        echo ""
    fi

    # ETAPA 3: Porta SSH
    log PHASE "ETAPA 3/5: Configurar porta SSH"
    while true; do
        read -p "Digite a porta SSH desejada (22 ou 1024-65535) [padrão: 2222]: " SSH_PORT
        SSH_PORT=${SSH_PORT:-2222}
        
        if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && ([ "$SSH_PORT" -eq 22 ] || ([ "$SSH_PORT" -ge 1024 ] && [ "$SSH_PORT" -le 65535 ])); then
            break
        else
            log ERROR "Porta inválida. Deve ser 22 ou um número entre 1024 e 65535"
        fi
    done
    log SUCCESS "Porta SSH será: $SSH_PORT"
    echo ""

    # ETAPA 4: SWAP
    log PHASE "ETAPA 4/5: Configurar SWAP"
    while true; do
        read -p "Digite o tamanho do SWAP em GB [padrão: 2]: " SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-2}
        
        if [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] && [ "$SWAP_SIZE" -gt 0 ]; then
            break
        else
            log ERROR "Tamanho inválido. Deve ser um número maior que 0"
        fi
    done
    log SUCCESS "SWAP será: ${SWAP_SIZE}GB"
    echo ""

    # ETAPA 5: Chave SSH pública
    log PHASE "ETAPA 5/5: Configurar autenticação SSH"
    while true; do
        read -p "Cole sua chave pública SSH: " PUB_KEY
        
        if [ -n "$PUB_KEY" ]; then
            # Validação básica de chave SSH
            if [[ "$PUB_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
                break
            else
                log ERROR "Formato de chave SSH inválido. Deve começar com 'ssh-rsa', 'ssh-ed25519' ou 'ssh-ecdsa'"
            fi
        else
            log ERROR "Chave SSH não pode ser vazia"
        fi
    done
    log SUCCESS "Chave SSH configurada"
    echo ""

    # ETAPA 6: Componentes Opcionais de Segurança
    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  COMPONENTES OPCIONAIS DE SEGURANÇA${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    echo "Selecione os componentes OPCIONAIS que deseja instalar:"
    echo ""
    
    # Unattended Upgrades
    echo -e "${COLOR_BOLD}[1] Unattended Upgrades${COLOR_RESET} (atualizações automáticas)"
    echo "    • Instala patches de segurança automaticamente"
    echo "    • Reboot manual se necessário"
    echo "    • Tempo: ~2 min"
    read -p "    Instalar? [S/n]: " INSTALL_UPGRADES
    INSTALL_UPGRADES=${INSTALL_UPGRADES:-S}
    echo ""
    
    # Auditd
    echo -e "${COLOR_BOLD}[2] Auditd${COLOR_RESET} (monitoramento avançado)"
    echo "    • Registra acessos a arquivos críticos"
    echo "    • 5 regras otimizadas (overhead ~1%)"
    echo "    • Tempo: ~2 min"
    read -p "    Instalar? [S/n]: " INSTALL_AUDITD
    INSTALL_AUDITD=${INSTALL_AUDITD:-S}
    echo ""
    
    # Logging
    echo -e "${COLOR_BOLD}[4] Logging Avançado${COLOR_RESET} (logrotate + journald)"
    echo "    • Configura rotação de logs"
    echo "    • Limita journald a 500MB"
    echo "    • Tempo: ~5 segundos"
    read -p "    Instalar? [S/n]: " INSTALL_LOGGING
    INSTALL_LOGGING=${INSTALL_LOGGING:-S}
    echo ""

    # Kernel module blocking
    echo -e "${COLOR_BOLD}[7] Bloqueio de Módulos de Kernel${COLOR_RESET} (reduz superfície de ataque)"
    echo "    • Desabilita protocolos não utilizados: dccp, sctp, rds, tipc"
    echo "    • Bloqueia filesystems raramente usados em servidores"
    echo "    • Baixo risco, melhora postura de segurança (CIS Benchmark)"
    echo "    • Tempo: ~5 segundos"
    read -p "    Instalar? [S/n]: " INSTALL_MOD_BLOCK
    INSTALL_MOD_BLOCK=${INSTALL_MOD_BLOCK:-S}
    echo ""

    echo -e "${COLOR_GREEN}────────────────────────────────────────────────────────${COLOR_RESET}"
    echo "Resumo de componentes opcionais:"
    [[ "$INSTALL_UPGRADES" =~ ^[Ss]$ ]] && echo "  ✅ Unattended Upgrades" || echo "  ⏭️  Unattended Upgrades (pulado)"
    [[ "$INSTALL_AUDITD" =~ ^[Ss]$ ]] && echo "  ✅ Auditd" || echo "  ⏭️  Auditd (pulado)"
    [[ "$INSTALL_LOGGING" =~ ^[Ss]$ ]] && echo "  ✅ Logging Avançado" || echo "  ⏭️  Logging Avançado (pulado)"
    [[ "$INSTALL_MOD_BLOCK" =~ ^[Ss]$ ]] && echo "  ✅ Bloqueio de Módulos de Kernel" || echo "  ⏭️  Bloqueio de Módulos (pulado)"
    echo -e "${COLOR_GREEN}────────────────────────────────────────────────────────${COLOR_RESET}"
    echo ""
    
    log SUCCESS "Configuração interativa concluída!"
    
    # Salvar configuração em arquivo temporário para recuperação
    cat > "${SCRIPT_DIR}/.startup-config" << EOF
SSH_USER="${SSH_USER}"
SSH_USER_PASS="${SSH_USER_PASS}"
SSH_PORT="${SSH_PORT}"
SWAP_SIZE="${SWAP_SIZE}"
PUB_KEY="${PUB_KEY}"
TAILSCALE_IPV4="${TAILSCALE_IPV4}"
TAILSCALE_IPV6="${TAILSCALE_IPV6}"
INSTALL_UPGRADES="${INSTALL_UPGRADES}"
INSTALL_AUDITD="${INSTALL_AUDITD}"
INSTALL_LOGGING="${INSTALL_LOGGING}"
INSTALL_MOD_BLOCK="${INSTALL_MOD_BLOCK}"
EOF
    chmod 600 "${SCRIPT_DIR}/.startup-config"
}

# Carregar configuração se houver checkpoint
load_config() {
    if [ -f "${SCRIPT_DIR}/.startup-config" ]; then
        source "${SCRIPT_DIR}/.startup-config"
        log INFO "Configuração carregada do checkpoint"
    fi
}

# ════════════════════════════════════════════════════════
# FASES DE INSTALAÇÃO
# ════════════════════════════════════════════════════════

phase_ubuntu_password() {
    local PHASE="ubuntu_password"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    local phase_start=$(date +%s)
    log PHASE "Fase 1/14: Configurar usuário SSH ($SSH_USER)"
    
    # Se não for root, criar/configurar usuário
    if [ "$SSH_USER" != "root" ]; then
        # Verificar se usuário já existe
        if id "$SSH_USER" &>/dev/null; then
            log INFO "Usuário $SSH_USER já existe - apenas atualizando senha"
        else
            log INFO "Criando usuário $SSH_USER..."
            useradd -m -s /bin/bash -G sudo "$SSH_USER" 2>&1 | tee -a "$LOG_FILE"
            log SUCCESS "Usuário $SSH_USER criado"
        fi
        
        # Definir senha
        echo "$SSH_USER:$SSH_USER_PASS" | chpasswd
        log SUCCESS "Senha do usuário $SSH_USER definida"
    else
        log INFO "Usuário root selecionado - pulando criação de usuário"
    fi
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_timezone() {
    local PHASE="timezone"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    local phase_start=$(date +%s)
    log PHASE "Fase 2/14: Configurar timezone"
    
    timedatectl set-timezone 'America/Sao_Paulo' 2>&1 | tee -a "$LOG_FILE"
    timedatectl set-ntp true 2>&1 | tee -a "$LOG_FILE"
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_system_update() {
    local PHASE="system_update"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 3/14: Atualizar sistema"
    local phase_start=$(date +%s)
    
    # Limpar repositórios problemáticos antes de atualizar
    log INFO "Verificando repositórios problemáticos..."
    
    # Remover repositórios Monarx problemáticos se existirem
    if [ -f /etc/apt/sources.list.d/monarx.list ]; then
        log WARNING "Removendo repositório Monarx problemático..."
        rm -f /etc/apt/sources.list.d/monarx.list
    fi
    
    # Desabilitar repositórios que causam erro 404
    for file in /etc/apt/sources.list.d/*.list; do
        if [ -f "$file" ] && grep -q "repository.monarx.com" "$file" 2>/dev/null; then
            log WARNING "Desabilitando repositório problemático: $file"
            mv "$file" "$file.disabled"
        fi
    done
    
    # Tentar atualizar, se falhar por repositórios ruins, continuar mesmo assim
    log INFO "Atualizando lista de pacotes..."
    if ! apt update -y -qq >> "$LOG_FILE" 2>&1; then
        log WARNING "apt update teve erros, mas continuando..."
    fi
    
    log INFO "Atualizando pacotes do sistema (pode demorar)..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >> "$LOG_FILE" 2>&1
    
    log INFO "Removendo pacotes desnecessários..."
    apt autoremove -y -qq >> "$LOG_FILE" 2>&1
    
    log INFO "Limpando cache de pacotes..."
    apt autoclean -y -qq >> "$LOG_FILE" 2>&1
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_unattended_upgrades() {
    local PHASE="unattended_upgrades"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 4/14: Configurar atualizações automáticas de segurança"
    local phase_start=$(date +%s)
    
    log INFO "Instalando unattended-upgrades..."
    DEBIAN_FRONTEND=noninteractive apt install -y -qq unattended-upgrades apt-listchanges >> "$LOG_FILE" 2>&1
    
    # Configurar para instalar apenas updates de segurança
    log INFO "Configurando atualizações automáticas..."
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UNATTENDED_EOF'
// Configuração de Atualizações Automáticas de Segurança
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    // "${distro_id}:${distro_codename}-updates";  // Descomente se quiser updates também
};

// Lista de pacotes que NÃO devem ser atualizados automaticamente
Unattended-Upgrade::Package-Blacklist {
    // "vim";
    // "libc6";
};

// Remover automaticamente dependências não usadas
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Reiniciar automaticamente se necessário (DESABILITADO para segurança)
Unattended-Upgrade::Automatic-Reboot "false";

// Se reboot for necessário, criar arquivo avisando
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";

// Logging
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
UNATTENDED_EOF
    
    # Ativar atualizações automáticas
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTO_UPGRADES_EOF'
// Habilitar atualizações automáticas
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
AUTO_UPGRADES_EOF
    
    # Configurar sem interação
    echo 'Dpkg::Options {"--force-confdef"; "--force-confold";}' > /etc/apt/apt.conf.d/99local
    
    # Verificar configuração
    if systemctl is-enabled unattended-upgrades.service > /dev/null 2>&1 || \
       systemctl list-timers 2>/dev/null | grep -q apt-daily-upgrade; then
        log SUCCESS "Atualizações automáticas configuradas"
        log SUCCESS "Apenas patches de segurança serão instalados automaticamente"
        log SUCCESS "Reboot manual necessário se kernel for atualizado"
    else
        log WARNING "Unattended-upgrades instalado mas serviço não habilitado automaticamente"
        log INFO "Será ativado no próximo boot"
    fi
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_kernel_security() {
    local PHASE="kernel_security"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 5/14: Hardening do kernel"
    local phase_start=$(date +%s)
    
    echo "kernel.randomize_va_space = 2" > /etc/sysctl.d/60-aslr.conf
    echo "kernel.yama.ptrace_scope = 1" > /etc/sysctl.d/60-yama.conf
    echo "* hard core 0" >> /etc/security/limits.conf
    echo "fs.suid_dumpable = 0" > /etc/sysctl.d/60-coredump.conf
    
    sysctl --system 2>&1 | tee -a "$LOG_FILE"
    
    log SUCCESS "Segurança do kernel configurada (ASLR, ptrace, core dumps)"
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_network_hardening() {
    local PHASE="network_hardening"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 6/14: Hardening de rede + Performance tuning"
    local phase_start=$(date +%s)
    
    log INFO "Configurando parâmetros de rede (segurança + performance)..."
    
    cat > /etc/sysctl.d/60-net.conf << 'NET_CONF'
# ════════════════════════════════════════════════════════
# Network Security Hardening
# ════════════════════════════════════════════════════════
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ratelimit = 100
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_synack_retries = 2

# ════════════════════════════════════════════════════════
# TCP Performance Tuning (APIs de alto tráfego)
# ════════════════════════════════════════════════════════

# Connection queue (essencial para múltiplas conexões simultâneas)
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# TCP buffers (melhor throughput em conexões rápidas)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Reuso de sockets (previne esgotamento de portas)
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 400000

# TCP Fast Open (reduz latência)
net.ipv4.tcp_fastopen = 3

# Keepalive otimizado
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# ════════════════════════════════════════════════════════
# File Descriptor Limits (suporta 1M+ conexões)
# ════════════════════════════════════════════════════════
fs.file-max = 2097152
fs.nr_open = 2097152
NET_CONF
    
    sysctl -p /etc/sysctl.d/60-net.conf 2>&1 | tee -a "$LOG_FILE"
    
    # Configurar BBR se disponível
    log INFO "Verificando suporte a BBR congestion control..."
    if modprobe tcp_bbr 2>/dev/null; then
        echo "net.core.default_qdisc = fq" >> /etc/sysctl.d/60-net.conf
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.d/60-net.conf
        sysctl -p /etc/sysctl.d/60-net.conf 2>&1 | tee -a "$LOG_FILE"
        log SUCCESS "BBR congestion control ativado (throughput 2-25x melhor)"
    else
        log WARNING "BBR não disponível (kernel < 4.9) - usando CUBIC"
    fi
    
    # Garantir que nf_conntrack carrega no boot ANTES do sysctl
    log INFO "Configurando nf_conntrack para carregar no boot..."
    echo "nf_conntrack" > /etc/modules-load.d/nf_conntrack.conf
    modprobe nf_conntrack 2>/dev/null || true

    # Configurar conntrack (Camada 3 — proteção contra DDoS por esgotamento de tabela)
    log INFO "Configurando conntrack (nf_conntrack)..."
    if [ -d /proc/sys/net/netfilter ]; then
        cat > /etc/sysctl.d/60-conntrack.conf << 'CONNTRACK_CONF'
# ════════════════════════════════════════════════════════
# Conntrack — Proteção contra DDoS por flood de conexões
# ════════════════════════════════════════════════════════
# Tabela pode suportar 1M conexões simultâneas
net.netfilter.nf_conntrack_max = 1048576
# Conexões estabelecidas: expiram em 24h
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
# SYN_RECV: reduzido para 15s (mitiga SYN flood)
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 15
# TIME_WAIT: reduzido para liberar slots mais rápido
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 15
# CLOSE_WAIT: reduzido para 30s
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 30
CONNTRACK_CONF
        sysctl -p /etc/sysctl.d/60-conntrack.conf 2>&1 | tee -a "$LOG_FILE"
        log SUCCESS "Conntrack configurado:"
        log SUCCESS "  • Tabela: 1M conexões simultâneas"
        log SUCCESS "  • Timeouts reduzidos: syn_recv=15s, time_wait=15s, close_wait=30s"
    else
        log WARNING "nf_conntrack não disponível agora — será ativado após reboot"
    fi

    # Configurar file descriptor limits (user level)

    # /etc/security/limits.conf
    if ! grep -q "^* soft nofile 1048576" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITS_EOF'

# File descriptor limits (hardening script)
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS_EOF
        log SUCCESS "Limits.conf configurado (1M file descriptors)"
    else
        log INFO "Limits.conf já configurado"
    fi
    
    # /etc/systemd/system.conf
    if [ -f /etc/systemd/system.conf ]; then
        if ! grep -q "^DefaultLimitNOFILE=1048576" /etc/systemd/system.conf 2>/dev/null; then
            sed -i 's/^#*DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/system.conf
            log SUCCESS "Systemd system.conf configurado (1M file descriptors)"
        else
            log INFO "Systemd system.conf já configurado"
        fi
    fi
    
    # /etc/systemd/user.conf
    if [ -f /etc/systemd/user.conf ]; then
        if ! grep -q "^DefaultLimitNOFILE=1048576" /etc/systemd/user.conf 2>/dev/null; then
            sed -i 's/^#*DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/user.conf
            log SUCCESS "Systemd user.conf configurado (1M file descriptors)"
        else
            log INFO "Systemd user.conf já configurado"
        fi
    fi
    
    # Recarregar systemd
    systemctl daemon-reexec 2>&1 | tee -a "$LOG_FILE"
    
    log SUCCESS "Hardening de rede configurado:"
    log SUCCESS "  • Segurança: SYN cookies, ICMP, redirects bloqueados"
    log SUCCESS "  • Performance: somaxconn=4096, buffers=16MB, tw_reuse"
    log SUCCESS "  • File descriptors: 1M (suporta APIs de alto tráfego)"
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_swap() {
    local PHASE="swap"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 7/14: Configurar SWAP"
    local phase_start=$(date +%s)
    
    SWAPFILE="/swap/swapfile"
    
    # Verificar se já existe SWAP ativo
    if swapon --show | grep -q "/"; then
        log WARNING "SWAP já ativo detectado:"
        swapon --show | tee -a "$LOG_FILE"
        
        # Desativar todos os swaps ativos
        log INFO "Desativando swaps existentes..."
        swapoff -a
        
        # Remover entradas antigas do fstab
        log INFO "Limpando entradas antigas de swap do fstab..."
        sed -i.bak '/swap/d' /etc/fstab
    fi
    
    # Remover arquivo de swap antigo se existir
    if [ -f "$SWAPFILE" ]; then
        log INFO "Removendo arquivo de swap antigo..."
        rm -f "$SWAPFILE"
    fi
    
    # Criar novo swap
    log INFO "Criando novo SWAP de ${SWAP_SIZE}GB..."
    mkdir -p /swap
    dd if=/dev/zero of=$SWAPFILE bs=1M count=$((SWAP_SIZE * 1024)) >> "$LOG_FILE" 2>&1
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE >> "$LOG_FILE" 2>&1
    swapon $SWAPFILE
    
    # Adicionar ao fstab
    echo "$SWAPFILE swap swap defaults 0 0" >> /etc/fstab
    
    # Verificar
    if swapon --show | grep -q "$SWAPFILE"; then
        log SUCCESS "SWAP de ${SWAP_SIZE}GB criado e ativado"
        log SUCCESS "Localização: $SWAPFILE"
    else
        log ERROR "Falha ao ativar SWAP!"
        exit 1
    fi
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_ssh_key() {
    local PHASE="ssh_key"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 8/14: Configurar chave SSH"
    local phase_start=$(date +%s)
    
    # Configurar chave SSH para o usuário correto
    if [ "$SSH_USER" = "root" ]; then
        SSH_HOME="/root"
    else
        SSH_HOME="/home/$SSH_USER"
    fi
    
    mkdir -p "$SSH_HOME/.ssh"
    chmod 700 "$SSH_HOME/.ssh"
    echo "$PUB_KEY" > "$SSH_HOME/.ssh/authorized_keys"
    chmod 600 "$SSH_HOME/.ssh/authorized_keys"
    
    if [ "$SSH_USER" != "root" ]; then
        chown -R "$SSH_USER:$SSH_USER" "$SSH_HOME/.ssh"
    fi
    
    log SUCCESS "Chave SSH configurada para usuário $SSH_USER"
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_tailscale() {
    local PHASE="tailscale"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 9/14: Instalar e configurar Tailscale VPN"
    local phase_start=$(date +%s)
    
    log INFO "Baixando e instalando Tailscale..."
    if curl -fsSL https://tailscale.com/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Tailscale instalado com sucesso"
    else
        log ERROR "Falha ao instalar Tailscale"
        exit 1
    fi
    
    log INFO "Iniciando Tailscale..."
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}  ⚠️  AÇÃO NECESSÁRIA: Autenticação Tailscale${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    echo "O Tailscale irá gerar uma URL de autenticação."
    echo "Você deve abrir essa URL no seu navegador para autenticar este servidor."
    echo ""
    echo -e "${COLOR_CYAN}Iniciando Tailscale...${COLOR_RESET}"
    echo ""
    
    # Executar tailscale up e capturar output
    tailscale up 2>&1 | tee -a "$LOG_FILE"
    
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}  Aguardando autenticação...${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    echo "Após autenticar no navegador, pressione ENTER para continuar..."
    read -p ""
    
    # Verificar se está conectado e capturar IPs
    if tailscale status &>/dev/null; then
        log SUCCESS "Tailscale conectado com sucesso!"
        echo ""
        log INFO "Endereços IP do Tailscale:"
        tailscale ip 2>&1 | tee -a "$LOG_FILE"
        
        # Capturar IPs do Tailscale para uso posterior no SSH
        TAILSCALE_IPV4=$(tailscale ip -4 2>/dev/null | head -n1)
        TAILSCALE_IPV6=$(tailscale ip -6 2>/dev/null | head -n1)
        
        if [ -n "$TAILSCALE_IPV4" ]; then
            log SUCCESS "IPv4 Tailscale capturado: $TAILSCALE_IPV4"
            
            # Salvar IP do Tailscale no config para usar em outras fases
            if [ -f "${SCRIPT_DIR}/.startup-config" ]; then
                sed -i "s|TAILSCALE_IPV4=\".*\"|TAILSCALE_IPV4=\"$TAILSCALE_IPV4\"|" "${SCRIPT_DIR}/.startup-config"
            fi
        fi
        if [ -n "$TAILSCALE_IPV6" ]; then
            log SUCCESS "IPv6 Tailscale capturado: $TAILSCALE_IPV6"
            
            # Salvar IP do Tailscale no config
            if [ -f "${SCRIPT_DIR}/.startup-config" ]; then
                sed -i "s|TAILSCALE_IPV6=\".*\"|TAILSCALE_IPV6=\"$TAILSCALE_IPV6\"|" "${SCRIPT_DIR}/.startup-config"
            fi
        fi
        
        echo ""
        log INFO "Status do Tailscale:"
        tailscale status 2>&1 | tee -a "$LOG_FILE"
    else
        log WARNING "Tailscale instalado mas não conectado. Você pode conectar depois com: sudo tailscale up"
        log ERROR "SSH requer IPs do Tailscale. Execute 'tailscale up' manualmente e rode o script novamente."
        exit 1
    fi
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_ssh_config() {
    local PHASE="ssh_config"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 10/14: Configurar SSH com segurança (acesso apenas via Tailscale)"
    local phase_start=$(date +%s)
    
    # Verificar se temos IP do Tailscale
    if [ -z "$TAILSCALE_IPV4" ]; then
        log ERROR "IP do Tailscale não encontrado! Carregando do config..."
        load_config
        
        if [ -z "$TAILSCALE_IPV4" ]; then
            log ERROR "Não foi possível obter IP do Tailscale. Execute a fase do Tailscale primeiro."
            exit 1
        fi
    fi
    
    # Backup
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
    
    # CORREÇÃO CRÍTICA: Desabilitar arquivos cloud-init que sobrescrevem configurações
    log INFO "Desabilitando arquivos cloud-init que sobrescrevem SSH..."
    if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
        log WARNING "Encontrado 50-cloud-init.conf - desabilitando..."
        mv /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/sshd_config.d/50-cloud-init.conf.disabled 2>&1 | tee -a "$LOG_FILE"
    fi
    
    if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
        log WARNING "Encontrado 60-cloudimg-settings.conf - desabilitando..."
        mv /etc/ssh/sshd_config.d/60-cloudimg-settings.conf /etc/ssh/sshd_config.d/60-cloudimg-settings.conf.disabled 2>&1 | tee -a "$LOG_FILE"
    fi
    
    log INFO "Removendo configurações inseguras antigas..."
    
    # REMOVER COMPLETAMENTE (deletar) as configurações antigas
    sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config
    sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config
    sed -i '/^ChallengeResponseAuthentication/d' /etc/ssh/sshd_config
    sed -i '/^PubkeyAuthentication/d' /etc/ssh/sshd_config
    sed -i '/^Port /d' /etc/ssh/sshd_config
    sed -i '/^AllowUsers/d' /etc/ssh/sshd_config
    sed -i '/^PermitEmptyPasswords/d' /etc/ssh/sshd_config
    sed -i '/^UsePAM/d' /etc/ssh/sshd_config
    sed -i '/^ListenAddress/d' /etc/ssh/sshd_config
    
    # Remover também linhas comentadas antigas
    sed -i '/^#PermitRootLogin/d' /etc/ssh/sshd_config
    sed -i '/^#PasswordAuthentication/d' /etc/ssh/sshd_config
    sed -i '/^#ChallengeResponseAuthentication/d' /etc/ssh/sshd_config
    sed -i '/^#PubkeyAuthentication/d' /etc/ssh/sshd_config
    
    log SUCCESS "Configurações antigas removidas"
    
    # Adicionar configurações seguras (agora serão as ÚNICAS presentes)
    log INFO "Adicionando configurações seguras..."
    tee -a /etc/ssh/sshd_config > /dev/null << EOF_SSH_CONFIG

# ════════════════════════════════════════════════════════
# Security Hardening Configuration - $(date +%Y-%m-%d)
# ════════════════════════════════════════════════════════
# ATENÇÃO: Estas são as ÚNICAS configurações de autenticação ativas
# Todas as anteriores foram REMOVIDAS para evitar conflitos
# SSH acessível APENAS via Tailscale VPN
# ════════════════════════════════════════════════════════

# Listen only on Tailscale IPs (máxima segurança)
# SSH acessível APENAS via Tailscale VPN
ListenAddress 127.0.0.1
ListenAddress $TAILSCALE_IPV4
$([ -n "$TAILSCALE_IPV6" ] && echo "ListenAddress $TAILSCALE_IPV6" || echo "")

# Port and Protocol
Port $SSH_PORT
Protocol 2
AddressFamily any

# Authentication (FORÇA apenas chave pública)
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
UsePAM yes

# Root access configuration
$(if [ "$SSH_USER" = "root" ]; then echo "PermitRootLogin prohibit-password"; else echo "PermitRootLogin no"; fi)
AllowUsers $SSH_USER

# Security limits
LoginGraceTime 30
MaxAuthTries 3
MaxSessions 2
MaxStartups 10:30:60

# Timeouts
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no

# Disable unnecessary features
X11Forwarding no
PermitUserEnvironment no
AllowAgentForwarding yes
AllowTcpForwarding yes
GatewayPorts no
PermitTunnel no

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Strong crypto only
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Host keys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Banner
PrintMotd no
PrintLastLog yes
Compression yes
EOF_SSH_CONFIG
    
    # Validar configuração
    log INFO "Validando configuração SSH..."
    if sshd -t 2>&1 | tee -a "$LOG_FILE"; then
        log SUCCESS "Configuração SSH validada"
        
        # Verificar se as configurações críticas estão presentes
        log INFO "Verificando configurações críticas..."
        
        # Validar PermitRootLogin baseado no usuário escolhido
        if [ "$SSH_USER" = "root" ]; then
            if ! grep -q "^PermitRootLogin prohibit-password" /etc/ssh/sshd_config; then
                log ERROR "ERRO: PermitRootLogin prohibit-password não encontrado no arquivo!"
                echo "Linhas com PermitRootLogin:" | tee -a "$LOG_FILE"
                grep "PermitRootLogin" /etc/ssh/sshd_config | tee -a "$LOG_FILE"
                exit 1
            fi
        else
            if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
                log ERROR "ERRO: PermitRootLogin no não encontrado no arquivo!"
                echo "Linhas com PermitRootLogin:" | tee -a "$LOG_FILE"
                grep "PermitRootLogin" /etc/ssh/sshd_config | tee -a "$LOG_FILE"
                exit 1
            fi
        fi
        
        if ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
            log ERROR "ERRO: PasswordAuthentication no não encontrado no arquivo!"
            echo "Linhas com PasswordAuthentication:" | tee -a "$LOG_FILE"
            grep "PasswordAuthentication" /etc/ssh/sshd_config | tee -a "$LOG_FILE"
            exit 1
        fi
        
        if ! grep -q "^AllowUsers $SSH_USER" /etc/ssh/sshd_config; then
            log ERROR "ERRO: AllowUsers $SSH_USER não encontrado no arquivo!"
            echo "Linhas com AllowUsers:" | tee -a "$LOG_FILE"
            grep "AllowUsers" /etc/ssh/sshd_config | tee -a "$LOG_FILE"
            exit 1
        fi
        
        log WARNING "⚠️  ATENÇÃO: SSH será reiniciado na porta $SSH_PORT"
        log WARNING "⚠️  SSH acessível APENAS via Tailscale: $TAILSCALE_IPV4"
        
        # Mostrar configurações críticas aplicadas
        if [ "$SSH_USER" = "root" ]; then
            log SUCCESS "✅ PermitRootLogin prohibit-password (apenas chave SSH)"
        else
            log SUCCESS "✅ PermitRootLogin no"
        fi
        log SUCCESS "✅ PasswordAuthentication no"
        log SUCCESS "✅ AllowUsers $SSH_USER"
        log SUCCESS "✅ ListenAddress $TAILSCALE_IPV4 (apenas Tailscale)"
        
        # Reiniciar SSH (tentar ambos os nomes de serviço)
        systemctl restart sshd 2>&1 | tee -a "$LOG_FILE" || systemctl restart ssh 2>&1 | tee -a "$LOG_FILE"
        sleep 2
        
        # Verificar se SSH está rodando
        if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
            log SUCCESS "✅ SSH reiniciado e ativo"
        else
            log ERROR "❌ SSH não está rodando! Restaurando backup..."
            cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
            systemctl restart sshd || systemctl restart ssh
            exit 1
        fi
        
        log SUCCESS "SSH configurado (porta $SSH_PORT)"
        log SUCCESS "Acesso: ssh $SSH_USER@$TAILSCALE_IPV4 -p $SSH_PORT"
        if [ "$SSH_USER" = "root" ]; then
            log SUCCESS "Root login: PERMITIDO apenas com chave SSH"
        else
            log SUCCESS "Root login: BLOQUEADO"
        fi
        log SUCCESS "Password auth: DESABILITADO"
        log SUCCESS "Apenas chave pública para usuário '$SSH_USER'"
    else
        log ERROR "Erro na configuração SSH. Restaurando backup..."
        cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
        systemctl restart sshd || systemctl restart ssh
        exit 1
    fi
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_fail2ban() {
    local PHASE="fail2ban"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 11/14: Instalar Fail2Ban"
    local phase_start=$(date +%s)
    
    apt install -y -qq fail2ban >> "$LOG_FILE" 2>&1
    
    tee /etc/fail2ban/jail.local > /dev/null << FAIL2BAN_CONF
[DEFAULT]
bantime = -1
findtime = 600
maxretry = 3
destemail = root@localhost
sendername = Fail2Ban-$(hostname)
action = %(action_)s

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = -1

[sshd-ddos]
enabled = true
port = $SSH_PORT
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
FAIL2BAN_CONF
    
    systemctl enable fail2ban 2>&1 | tee -a "$LOG_FILE"
    systemctl restart fail2ban 2>&1 | tee -a "$LOG_FILE"
    
    log SUCCESS "Fail2Ban configurado (porta $SSH_PORT protegida)"
    log INFO "  • Escopo: SSH brute force via Tailscale (auth.log)"
    log INFO "  • Para proteção HTTP/bots: use CrowdSec (escopo complementar, sem conflito)"
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_firewall_ufw() {
    local PHASE="firewall_ufw"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 12/14: Configurar Firewall UFW (acesso público apenas HTTP/HTTPS)"
    local phase_start=$(date +%s)
    
    # Instalar UFW se não estiver instalado
    if ! command -v ufw &> /dev/null; then
        log INFO "Instalando UFW..."
        apt install -y -qq ufw >> "$LOG_FILE" 2>&1
    fi
    
    # Garantir que UFW suporte IPv6
    log INFO "Garantindo suporte a IPv6 no UFW..."
    if [ -f /etc/default/ufw ]; then
        sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
        log SUCCESS "✅ IPv6 habilitado no UFW"
    fi

    # Resetar regras (limpar configurações anteriores)
    log INFO "Resetando configurações do UFW..."
    ufw --force reset >> "$LOG_FILE" 2>&1
    
    # Configurar políticas padrão
    log INFO "Configurando políticas padrão..."
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1
    
    # Permitir HTTP e HTTPS publicamente (portas 80 e 443)
    log INFO "Liberando portas HTTP/HTTPS (acesso público)..."
    ufw allow 80/tcp comment 'HTTP - public' >> "$LOG_FILE" 2>&1
    ufw allow 443/tcp comment 'HTTPS - public' >> "$LOG_FILE" 2>&1
    log SUCCESS "✅ Portas 80 (HTTP) e 443 (HTTPS) liberadas"
    log INFO    "  • Para restringir aos IPs da Cloudflare, execute: bash cloudflare-update-ufw.sh"
    
    # Permitir TUDO via Tailscale (VPN privada)
    log INFO "Liberando interface Tailscale (acesso total via VPN)..."
    ufw allow in on tailscale0 comment 'Tailscale VPN - full access' >> "$LOG_FILE" 2>&1
    log SUCCESS "✅ Interface Tailscale liberada - SSH e outras portas acessíveis APENAS via VPN"
    
    # Mostrar configuração antes de habilitar
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}  ⚠️  ATENÇÃO: UFW será habilitado!${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    echo "Regras configuradas:"
    echo "  ✅ HTTP: 80/tcp (PÚBLICO)"
    echo "  ✅ HTTPS: 443/tcp (PÚBLICO)"
    echo "  ✅ SSH: porta $SSH_PORT (APENAS via Tailscale)"
    echo "  ✅ Todas outras portas: (APENAS via Tailscale)"
    echo "  ❌ Política padrão: DENY (bloqueia acesso público)"
    echo ""
    echo -e "${COLOR_RED}${COLOR_BOLD}IMPORTANTE:${COLOR_RESET}"
    echo "  • Acesso público: APENAS HTTP (80) e HTTPS (443)"
    echo "  • Para Cloudflare-Only execute: bash cloudflare-update-ufw.sh"
    echo "  • SSH, painéis, DBs, etc: APENAS via Tailscale VPN"
    echo "  • Conecte via: ssh $SSH_USER@$TAILSCALE_IPV4 -p $SSH_PORT"
    echo "  • Para acessar outras portas, conecte primeiro ao Tailscale"
    echo ""
    
    # Habilitar UFW e configurar logging
    log WARNING "Habilitando UFW..."
    ufw --force enable >> "$LOG_FILE" 2>&1
    ufw logging medium >> "$LOG_FILE" 2>&1
    log SUCCESS "✅ UFW logging configurado em modo medium (loga pacotes bloqueados por regra + política)"
    
    # Verificar status
    if ufw status | grep -q "Status: active"; then
        log SUCCESS "✅ UFW habilitado e ativo"
        echo ""
        log INFO "Status do UFW:"
        ufw status numbered 2>&1 | tee -a "$LOG_FILE"
    else
        log ERROR "❌ Falha ao habilitar UFW"
        exit 1
    fi
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

phase_auditd() {
    local PHASE="auditd"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 13/14: Instalar Auditd (otimizado para performance)"
    local phase_start=$(date +%s)
    
    apt install -y -qq auditd audispd-plugins >> "$LOG_FILE" 2>&1
    
    # Configurar regras OTIMIZADAS (apenas críticas, sem overhead)
    tee /etc/audit/rules.d/hardening.rules > /dev/null << 'AUDIT_RULES'
-D

# Buffer reduzido para melhor performance
-b 2048

# Failure mode (1 = continua funcionando mesmo com erro)
-f 1

# ===== Arquivos críticos do sistema (baixo overhead) =====
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/ssh/sshd_config -p wa -k sshd_changes

# ===== Comandos de privilégio (essencial para segurança) =====
-w /usr/bin/sudo -p x -k sudo_execution
-w /bin/su -p x -k su_execution

# Nota: Regras pesadas removidas para melhor performance:
# - Monitoramento de /home e /var/www (muito I/O)
# - Syscalls execve (loga todas execuções)
# - Mudanças de permissão (overhead em deployments)
# - wget/curl (comum em APIs)
AUDIT_RULES
    
    sed -i 's/^max_log_file = .*/max_log_file = 50/' /etc/audit/auditd.conf
    sed -i 's/^num_logs = .*/num_logs = 10/' /etc/audit/auditd.conf
    sed -i 's/^max_log_file_action = .*/max_log_file_action = rotate/' /etc/audit/auditd.conf
    
    systemctl enable auditd 2>&1 | tee -a "$LOG_FILE"
    systemctl restart auditd 2>&1 | tee -a "$LOG_FILE"
    augenrules --load 2>&1 | tee -a "$LOG_FILE"
    
    log SUCCESS "Auditd configurado (logs em /var/log/audit/)"
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

# ════════════════════════════════════════════════════════
# FASE: DOCKER
# ════════════════════════════════════════════════════════

phase_logging() {
    local PHASE="logging"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi
    
    log PHASE "Fase 15/14: Configurar logging do sistema"
    local phase_start=$(date +%s)
    
    tee /etc/logrotate.d/sudo > /dev/null << 'EOF_LOGROTATE'
/var/log/sudo.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF_LOGROTATE
    
    systemctl enable rsyslog 2>&1 | tee -a "$LOG_FILE"
    systemctl start rsyslog 2>&1 | tee -a "$LOG_FILE"
    
    sed -i 's/^#*Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
    sed -i 's/^#*SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
    systemctl restart systemd-journald 2>&1 | tee -a "$LOG_FILE"
    
    log SUCCESS "Logging configurado"
    
    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"
    
    mark_phase_completed "$PHASE"
    show_progress
}

# ════════════════════════════════════════════════════════
# FASE: BLOQUEIO DE MÓDULOS DE KERNEL
# ════════════════════════════════════════════════════════

phase_kernel_modules() {
    local PHASE="kernel_modules"
    if is_phase_completed "$PHASE"; then
        log INFO "Fase '$PHASE' já concluída. Pulando..."
        return 0
    fi

    log PHASE "Bloqueando módulos de kernel desnecessários (CIS Benchmark)"
    local phase_start=$(date +%s)

    cat > /etc/modprobe.d/blacklist-hardening.conf << 'MOD_CONF'
# ════════════════════════════════════════════════════════
# Módulos de kernel bloqueados — reduz superfície de ataque
# Gerado pelo script de hardening
# ════════════════════════════════════════════════════════

# Protocolos de rede não utilizados em servidores
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true

# Filesystems raramente usados em ambientes de servidor
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
MOD_CONF

    # Recarregar initramfs para garantir aplicação no próximo boot
    if command -v update-initramfs &> /dev/null; then
        update-initramfs -u >> "$LOG_FILE" 2>&1 || true
    fi

    log SUCCESS "Módulos de kernel bloqueados:"
    log SUCCESS "  • Protocolos de rede: dccp, sctp, rds, tipc"
    log SUCCESS "  • Filesystems desnecessários: cramfs, freevxfs, jffs2, hfs, hfsplus, udf"
    log WARNING "  ⚠️  Efeito total após reboot (será feito automaticamente ao final)"

    local phase_end=$(date +%s)
    local phase_duration=$((phase_end - phase_start))
    log SUCCESS "Fase concluída em $(format_time $phase_duration) | Tempo total: $(get_elapsed_time)"

    mark_phase_completed "$PHASE"
    show_progress
}

# ════════════════════════════════════════════════════════
# ════════════════════════════════════════════════════════
# RESUMO FINAL
# ════════════════════════════════════════════════════════

show_summary() {
    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}  ✅ CONFIGURAÇÃO CONCLUÍDA COM SUCESSO!${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    echo "📊 Resumo das configurações aplicadas:"
    echo ""
    echo "  🕒 Sistema:"
    echo "    • Timezone: America/Sao_Paulo"
    echo "    • SWAP: ${SWAP_SIZE}GB"
    [[ "$INSTALL_UPGRADES" =~ ^[Ss]$ ]] && echo "    • Atualizações de segurança: AUTOMÁTICAS"
    echo ""
    echo "  🛡️  Segurança do Kernel:"
    echo "    • ASLR habilitado"
    echo "    • ptrace restrito"
    echo "    • Core dumps desabilitados"
    echo ""
    echo "  🌐 Hardening de Rede:"
    echo "    • IP forwarding desabilitado"
    echo "    • ICMP/TCP redirects bloqueados (IPv4 + IPv6)"
    echo "    • Reverse path filter ativado (anti-spoofing)"
    echo "    • SYN cookies + tcp_rfc1337 + synack_retries=2"
    echo "    • Conntrack: 1M conexões, timeouts reduzidos"
    echo "    • BBR congestion control ativo"
    echo "    • File descriptors: 1M"
    echo ""
    echo "  🔐 SSH:"
    echo "    • Porta: $SSH_PORT"
    echo "    • Usuário: $SSH_USER (chave privada apenas)"
    echo "    • Acesso APENAS via Tailscale: $TAILSCALE_IPV4"
    if [ "$SSH_USER" = "root" ]; then
        echo "    • Root login: CHAVE SSH APENAS"
    else
        echo "    • Root login: BLOQUEADO"
    fi
    echo ""
    echo "  🔒 Tailscale VPN:"
    echo "    • IPv4: $TAILSCALE_IPV4"
    [ -n "$TAILSCALE_IPV6" ] && echo "    • IPv6: $TAILSCALE_IPV6"
    echo "    • Status: Conectado"
    echo ""
    echo "  🛡️  Firewall UFW:"
    echo "    • HTTP (80): PÚBLICO"
    echo "    • HTTPS (443): PÚBLICO"
    echo "    • Cloudflare-Only: execute bash cloudflare-update-ufw.sh"
    echo "    • SSH ($SSH_PORT): APENAS VIA TAILSCALE"
    echo "    • Outras portas: APENAS VIA TAILSCALE"
    echo "    • IPv6: HABILITADO"
    echo ""
    echo "  🔍 Sistemas de Detecção:"
    [[ "$INSTALL_AUDITD" =~ ^[Ss]$ ]] && echo "    • Auditd: ATIVO (otimizado)"
    echo "    • Fail2Ban: ATIVO (escopo: SSH)"
    [[ "$INSTALL_MOD_BLOCK" =~ ^[Ss]$ ]] && echo "    • Módulos kernel bloqueados: dccp, sctp, rds, tipc"
    echo ""
    echo "   Logs: /var/log/"
    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  ⚠️  IMPORTANTE: Anote estas informações!${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo "  🔐 Acesso SSH (APENAS via Tailscale):"
    echo "    ssh $SSH_USER@$TAILSCALE_IPV4 -p $SSH_PORT"
    echo ""
    echo "  🌐 Acesso Web:"
    echo "    • HTTP: http://SEU_IP_PUBLICO"
    echo "    • HTTPS: https://SEU_IP_PUBLICO"
    echo "    • Para Cloudflare-Only: bash cloudflare-update-ufw.sh"
    echo ""
    echo "  📝 Logs deste script:"
    echo "    • Log completo: $LOG_FILE"
    echo "    • Log de erros: $ERROR_LOG"
    echo ""
    
    # Salvar informações importantes em arquivo
    cat > /root/server-info.txt << EOF_INFO
════════════════════════════════════════════════════════
INFORMAÇÕES DO SERVIDOR - $(date)
════════════════════════════════════════════════════════

SSH (APENAS via Tailscale):
  Comando: ssh $SSH_USER@$TAILSCALE_IPV4 -p $SSH_PORT
  Usuário: $SSH_USER
  Porta: $SSH_PORT
  Autenticação: Chave privada apenas

Tailscale VPN:
  IPv4: $TAILSCALE_IPV4
  IPv6: $TAILSCALE_IPV6
  Interface: tailscale0

Firewall UFW:
  • HTTP/HTTPS (80/443): PÚBLICO
  • Outras portas: APENAS via Tailscale
  • Cloudflare-Only: execute bash cloudflare-update-ufw.sh para restringir

Sistema:
  • Timezone: America/Sao_Paulo
  • SWAP: ${SWAP_SIZE}GB
  • Atualizações automáticas: $([ "$INSTALL_UPGRADES" = "S" ] && echo "SIM" || echo "NÃO")

Segurança:
  • Fail2Ban: Ativo
  • Auditd: $([ "$INSTALL_AUDITD" = "S" ] && echo "Ativo" || echo "Desativado")

Logs do script:
  • $LOG_FILE
  • $ERROR_LOG

════════════════════════════════════════════════════════
EOF_INFO
    
    log SUCCESS "Informações salvas em: /root/server-info.txt"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
}

# ════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════

main() {
    # Verificações iniciais
    check_root
    check_ubuntu
    
    log INFO "════════════════════════════════════════════════════════"
    log INFO "  Script de Hardening de Servidor Ubuntu - Default VPS"
    log INFO "  Acesso seguro via Tailscale (exceto HTTP/HTTPS)"
    log INFO "  Log: $LOG_FILE"
    log INFO "════════════════════════════════════════════════════════"
    
    # Verificar se há checkpoint
    if [ -f "$CHECKPOINT_FILE" ]; then
        local completed=$(get_completed_phases)
        log WARNING "Checkpoint encontrado! $completed de $TOTAL_PHASES fases concluídas."
        echo ""
        echo "Opções:"
        echo "  1) Continuar de onde parou"
        echo "  2) Recomeçar do zero (apaga checkpoint)"
        echo "  3) Sair"
        read -p "Escolha [1-3]: " choice
        
        case $choice in
            1)
                log INFO "Continuando instalação..."
                load_config
                ;;
            2)
                log WARNING "Resetando checkpoint..."
                reset_checkpoint
                rm -f "${SCRIPT_DIR}/.startup-config"
                interactive_config
                ;;
            3)
                log INFO "Saindo..."
                exit 0
                ;;
            *)
                log ERROR "Opção inválida"
                exit 1
                ;;
        esac
    else
        # Primeira execução
        interactive_config
    fi
    
    echo ""
    log INFO "Iniciando configuração do sistema..."
    show_progress
    echo ""
    
    # Executar todas as fases
    phase_ubuntu_password
    phase_timezone
    phase_system_update
    
    # Fases opcionais
    if [[ "$INSTALL_UPGRADES" =~ ^[Ss]$ ]]; then
        phase_unattended_upgrades
    else
        log INFO "⏭️  Pulando Unattended Upgrades (opcional)"
        # Marcar como concluída para não quebrar a contagem de progresso
        mark_phase_completed "unattended_upgrades"
    fi
    
    phase_kernel_security
    phase_network_hardening
    phase_swap
    phase_ssh_key
    phase_tailscale  # Fase 9: Instalar Tailscale
    phase_ssh_config # Fase 10: Configurar SSH para escutar apenas no Tailscale
    phase_fail2ban
    phase_firewall_ufw # Fase 12: UFW - 80/443 (Cloudflare-only ou público) + resto via Tailscale

    if [[ "$INSTALL_MOD_BLOCK" =~ ^[Ss]$ ]]; then
        phase_kernel_modules
    else
        log INFO "⏭️  Pulando bloqueio de módulos de kernel (opcional)"
        mark_phase_completed "kernel_modules"
    fi

    if [[ "$INSTALL_AUDITD" =~ ^[Ss]$ ]]; then
        phase_auditd
    else
        log INFO "⏭️  Pulando Auditd (opcional)"
        mark_phase_completed "auditd"
    fi

    if [[ "$INSTALL_LOGGING" =~ ^[Ss]$ ]]; then
        phase_logging
    else
        log INFO "⏭️  Pulando Logging Avançado (opcional)"
        mark_phase_completed "logging"
    fi

    # Progress bar final
    echo ""
    show_progress
    echo ""
    
    # Calcular tempo total
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    
    # Mostrar tempo total
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}  ⏱️  TEMPO TOTAL DE EXECUÇÃO: $(format_time $total_duration)${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    
    # Mostrar resumo
    show_summary
    
    # Limpar checkpoint e config
    rm -f "$CHECKPOINT_FILE"
    rm -f "${SCRIPT_DIR}/.startup-config"
    
    log SUCCESS "Script concluído com sucesso!"
    log INFO "Informações do servidor salvas em: /root/server-info.txt"
    echo ""
    log WARNING "⚠️  Para acessar este servidor:"
    log WARNING "    1. Conecte ao Tailscale no seu computador"
    log WARNING "    2. Use: ssh $SSH_USER@$TAILSCALE_IPV4 -p $SSH_PORT"
    echo ""
    log INFO "Sistema será reiniciado em 10 segundos..."
    sleep 10
    reboot
}

# Executar script
main "$@"
