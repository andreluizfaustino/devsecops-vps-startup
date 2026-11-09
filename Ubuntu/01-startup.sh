#!/bin/bash
# ════════════════════════════════════════════════════════
# Setup + Hardening de VPS Ubuntu (24.04 / 26.04 LTS)
# Version: 2.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
#
# Resultado final:
#   • SSH apenas via Tailscale, apenas chave, root bloqueado
#   • UFW: tudo bloqueado, exceto 80/443 (Cloudflare ou público) e Tailscale
#   • Docker com firewall próprio (DOCKER-USER) — containers não furam o UFW
#   • Atualizações de segurança automáticas (sem reboot automático)
#
# Uso: sudo bash 01-startup.sh
# ════════════════════════════════════════════════════════

set -Eeuo pipefail

# ════════════════════════════════════════════════════════
# VARIÁVEIS GLOBAIS
# ════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
CHECKPOINT_FILE="${SCRIPT_DIR}/.startup-checkpoint"
CONFIG_FILE="${SCRIPT_DIR}/.startup-config"
LOG_FILE="${LOG_DIR}/startup-$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="${LOG_DIR}/startup-errors.log"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

# Configuração (preenchida interativamente; a senha NUNCA é gravada em disco)
SSH_USER=""
SSH_USER_PASS=""
SSH_PORT="22"          # fixo: o SSH escuta só no Tailscale, trocar a porta não agrega segurança
SWAP_SIZE=""
PUB_KEY=""
TS_AUTHKEY=""          # opcional, não é gravado em disco
CF_ONLY="S"            # 80/443 apenas para IPs da Cloudflare
INSTALL_DOCKER="S"     # Docker + firewall dos containers (DOCKER-USER)
TAILSCALE_IPV4=""
TAILSCALE_IPV6=""

# Arquivos gerados no servidor
SSHD_DROPIN="/etc/ssh/sshd_config.d/00-hardening.conf"
SYSCTL_FILE="/etc/sysctl.d/90-hardening.conf"
CF_LIST="/etc/cloudflare-ips.txt"
CF_SCRIPT="/usr/local/bin/cloudflare-update-firewall.sh"
DU_SCRIPT="/usr/local/bin/docker-user-firewall.sh"

# apt sem perguntas e esperando o lock do dpkg (VPS recém-criada costuma estar atualizando)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_GET=(apt-get -y -qq -o DPkg::Lock::Timeout=600
         -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

# Ordem das fases: id|título|função
PHASES=(
    "user|Usuário SSH e senha|phase_user"
    "timezone|Timezone e NTP|phase_timezone"
    "system_update|Atualizar sistema|phase_system_update"
    "unattended_upgrades|Atualizações automáticas de segurança|phase_unattended_upgrades"
    "sysctl|Kernel e rede (sysctl + limites)|phase_sysctl"
    "kernel_modules|Bloqueio de módulos do kernel|phase_kernel_modules"
    "swap|SWAP|phase_swap"
    "ssh_key|Chave SSH|phase_ssh_key"
    "tailscale|Tailscale VPN|phase_tailscale"
    "ssh_config|SSH apenas via Tailscale|phase_ssh_config"
    "firewall|Firewall UFW + Cloudflare|phase_firewall"
    "docker|Docker + firewall dos containers (DOCKER-USER)|phase_docker"
    "logging|Logs do sistema (journald)|phase_logging"
)
TOTAL_PHASES=${#PHASES[@]}
START_TIME=$(date +%s)

# ════════════════════════════════════════════════════════
# LOG, ERROS E TEMPO
# ════════════════════════════════════════════════════════

log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    case "$level" in
        INFO)    echo -e "${COLOR_CYAN}ℹ ${COLOR_RESET}$message" ;;
        SUCCESS) echo -e "${COLOR_GREEN}✅${COLOR_RESET} $message" ;;
        WARNING) echo -e "${COLOR_YELLOW}⚠️ ${COLOR_RESET}$message" ;;
        ERROR)   echo -e "${COLOR_RED}❌${COLOR_RESET} $message"
                 echo "[$timestamp] [ERROR] $message" >> "$ERROR_LOG" ;;
        PHASE)   echo -e "\n${COLOR_BOLD}${COLOR_BLUE}═══ $message${COLOR_RESET}\n" ;;
        *)       echo "$message" ;;
    esac
}

on_error() {
    local rc=$? line=$1 cmd=$2
    trap - ERR
    log ERROR "Falha (código $rc) na linha $line: $cmd"
    log ERROR "Veja o log: $LOG_FILE"
    log ERROR "Corrija o problema e rode o script de novo — ele continua da fase em que parou."
    exit "$rc"
}
trap 'on_error $LINENO "$BASH_COMMAND"' ERR

format_time() {
    local s=$1
    if [ "$s" -lt 60 ]; then echo "${s}s"; else echo "$((s / 60))m $((s % 60))s"; fi
}

# ════════════════════════════════════════════════════════
# CHECKPOINT E EXECUÇÃO DAS FASES
# ════════════════════════════════════════════════════════

is_phase_completed() { [ -f "$CHECKPOINT_FILE" ] && grep -qx "$1" "$CHECKPOINT_FILE"; }
mark_phase_completed() { echo "$1" >> "$CHECKPOINT_FILE"; }
get_completed_phases() { if [ -f "$CHECKPOINT_FILE" ]; then wc -l < "$CHECKPOINT_FILE" | tr -d ' '; else echo 0; fi; }

show_progress() {
    local current total=$TOTAL_PHASES
    current=$(get_completed_phases)
    local filled=$((current * 40 / total))
    printf "${COLOR_BOLD}Progresso:${COLOR_RESET} ["
    printf "%${filled}s" "" | tr ' ' '█'
    printf "%$((40 - filled))s" "" | tr ' ' '░'
    printf "] %d%% (%d/%d fases)\n" $((current * 100 / total)) "$current" "$total"
}

run_all_phases() {
    local n=0 entry id title fn start
    for entry in "${PHASES[@]}"; do
        n=$((n + 1))
        IFS='|' read -r id title fn <<< "$entry"
        if is_phase_completed "$id"; then
            log INFO "Fase $n/$TOTAL_PHASES ($title) já concluída. Pulando..."
            continue
        fi
        log PHASE "Fase $n/$TOTAL_PHASES: $title"
        start=$(date +%s)
        "$fn"
        mark_phase_completed "$id"
        log SUCCESS "Fase $n concluída em $(format_time $(( $(date +%s) - start )))"
        show_progress
    done
}

# ════════════════════════════════════════════════════════
# VERIFICAÇÕES INICIAIS
# ════════════════════════════════════════════════════════

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "❌ Este script deve ser executado como root: sudo bash 01-startup.sh"
        exit 1
    fi
}

check_ubuntu() {
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ]; then
        log ERROR "Este script é apenas para Ubuntu (detectado: ${PRETTY_NAME:-desconhecido})"
        exit 1
    fi
    case "${VERSION_ID:-}" in
        24.04|26.04) log INFO "Sistema: $PRETTY_NAME" ;;
        *)
            log WARNING "Testado em Ubuntu 24.04 e 26.04 LTS. Detectado: $PRETTY_NAME"
            read -r -p "Continuar mesmo assim? (s/N): " confirm
            [[ "$confirm" =~ ^[Ss]$ ]] || exit 1
            ;;
    esac
}

public_iface() {
    ip -4 route show default 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}'
}

# ════════════════════════════════════════════════════════
# DETECÇÃO DE HARDWARE E SUGESTÃO DE SWAP
# ════════════════════════════════════════════════════════

detect_hardware() {
    HW_CPUS=$(nproc 2>/dev/null || echo 1)
    HW_RAM_MB=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
    HW_RAM_GB=$(( (HW_RAM_MB + 512) / 1024 ))        # arredonda (15.6 GB → 16)
    [ "$HW_RAM_GB" -lt 1 ] && HW_RAM_GB=1
    HW_SWAP_MB=$(awk '/^SwapTotal:/ {print int($2/1024)}' /proc/meminfo)
    HW_DISK_TOTAL_GB=$(df -BG --output=size / | tail -1 | tr -dc '0-9')
    HW_DISK_FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
}

# Regra (servidor, sem hibernação):
#   RAM ≤ 2 GB  → 2× RAM   (máquina pequena precisa de folga contra OOM)
#   RAM ≤ 32 GB → 4 GB     (swap é só rede de segurança, não memória extra)
#   RAM > 32 GB → 8 GB
# Limite: nunca mais que 10% do disco livre.
choose_swap_size() {
    detect_hardware

    local rec
    if   [ "$HW_RAM_GB" -le 2 ];  then rec=$((HW_RAM_GB * 2))
    elif [ "$HW_RAM_GB" -le 32 ]; then rec=4
    else                               rec=8
    fi

    local cap=$((HW_DISK_FREE_GB / 10))
    [ "$cap" -lt 1 ] && cap=1
    [ "$rec" -gt "$cap" ] && rec=$cap

    local min=$((rec / 2)); [ "$min" -lt 1 ] && min=1
    local big=$((rec * 2)); [ "$big" -gt "$cap" ] && big=$cap

    echo "Hardware detectado:"
    echo "  • CPU:   ${HW_CPUS} vCPU"
    echo "  • RAM:   ${HW_RAM_GB} GB (${HW_RAM_MB} MB)"
    echo "  • Disco: ${HW_DISK_TOTAL_GB} GB total, ${HW_DISK_FREE_GB} GB livres"
    if [ "$HW_SWAP_MB" -gt 0 ]; then
        echo "  • Swap atual: ${HW_SWAP_MB} MB (será substituído)"
    else
        echo "  • Swap atual: nenhum"
    fi
    echo ""
    echo "Opções de SWAP para este servidor:"
    echo "  1) Mínimo      — ${min} GB  (só proteção contra falta de memória)"
    echo "  2) Recomendado — ${rec} GB  ✅"
    echo "  3) Folgado     — ${big} GB  (muitos containers ou builds pesados)"
    echo "  4) Outro valor (1 a ${cap} GB)"
    echo ""

    local swap_choice
    while true; do
        read -r -p "Opção [1-4] (padrão: 2): " swap_choice
        swap_choice=${swap_choice:-2}
        case $swap_choice in
            1) SWAP_SIZE=$min; break ;;
            2) SWAP_SIZE=$rec; break ;;
            3) SWAP_SIZE=$big; break ;;
            4)
                read -r -p "Tamanho do SWAP em GB (1-${cap}): " SWAP_SIZE
                if [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] && [ "$SWAP_SIZE" -ge 1 ] && [ "$SWAP_SIZE" -le "$cap" ]; then
                    break
                fi
                log ERROR "Valor inválido. Use um número entre 1 e ${cap}"
                ;;
            *) log ERROR "Opção inválida. Escolha 1, 2, 3 ou 4" ;;
        esac
    done
}

# ════════════════════════════════════════════════════════
# CONFIGURAÇÃO INTERATIVA
# ════════════════════════════════════════════════════════

prompt_password() {
    echo "Esta senha NÃO serve para SSH (SSH é só por chave)."
    echo "Ela é usada no 'sudo' e no console web da VPS se o Tailscale cair — guarde-a!"
    echo ""
    local pass2
    while true; do
        read -r -s -p "Digite a nova senha do usuário $SSH_USER: " SSH_USER_PASS; echo
        read -r -s -p "Repita a senha: " pass2; echo
        if [ -z "$SSH_USER_PASS" ]; then
            log ERROR "Senha não pode ser vazia"
        elif [ ${#SSH_USER_PASS} -lt 12 ]; then
            log ERROR "Use pelo menos 12 caracteres"
        elif [ "$SSH_USER_PASS" != "$pass2" ]; then
            log ERROR "As senhas não conferem. Tente novamente."
        else
            break
        fi
    done
    log SUCCESS "Senha definida"
}

interactive_config() {
    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  CONFIGURAÇÃO INICIAL${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"

    # 1) Usuário (root nunca tem acesso SSH)
    log PHASE "PERGUNTA 1/5: Usuário SSH"
    echo "Escolha qual usuário terá acesso SSH (login como root fica bloqueado):"
    echo "  1) ubuntu (recomendado)"
    echo "  2) outro (nome customizado)"
    echo ""
    local user_choice
    while true; do
        read -r -p "Opção [1-2] (padrão: 1): " user_choice
        case ${user_choice:-1} in
            1) SSH_USER="ubuntu"; break ;;
            2)
                read -r -p "Nome do usuário: " SSH_USER
                if [ "$SSH_USER" = "root" ]; then
                    log ERROR "root não é permitido. Escolha outro nome"
                elif [[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ ${#SSH_USER} -le 32 ]; then
                    break
                else
                    log ERROR "Nome inválido. Use letras minúsculas, números, _ e -"
                fi
                ;;
            *) log ERROR "Opção inválida. Escolha 1 ou 2" ;;
        esac
    done
    log SUCCESS "Usuário SSH: $SSH_USER"

    # 2) Senha
    log PHASE "PERGUNTA 2/5: Senha do usuário $SSH_USER"
    prompt_password

    # 3) Swap
    log PHASE "PERGUNTA 3/5: SWAP"
    choose_swap_size
    log SUCCESS "SWAP: ${SWAP_SIZE} GB"

    # 4) Chave pública
    log PHASE "PERGUNTA 4/5: Chave pública SSH"
    echo "No seu computador: cat ~/.ssh/<sua-chave>.pub"
    while true; do
        read -r -p "Cole sua chave pública SSH: " PUB_KEY
        if [ -n "$PUB_KEY" ] && ssh-keygen -l -f - <<< "$PUB_KEY" &>/dev/null; then
            break
        fi
        log ERROR "Chave inválida. Cole a linha inteira (ex.: ssh-ed25519 AAAA... comentario)"
    done
    log SUCCESS "Chave válida: $(ssh-keygen -l -f - <<< "$PUB_KEY" | awk '{print $2}')"

    # 5) Tailscale, Cloudflare e Docker
    log PHASE "PERGUNTA 5/5: Tailscale, Cloudflare e Docker"
    echo "Tailscale auth key (opcional). Deixe vazio para autenticar pelo navegador."
    echo "  Gerar em: https://login.tailscale.com/admin/settings/keys"
    read -r -s -p "Auth key: " TS_AUTHKEY; echo
    echo ""
    echo "Os domínios deste servidor passam pelo proxy da Cloudflare (nuvem laranja)?"
    echo "  S = portas 80/443 aceitam SÓ IPs da Cloudflare (recomendado)"
    echo "  n = portas 80/443 abertas para qualquer IP"
    read -r -p "Modo Cloudflare-only? [S/n]: " CF_ONLY
    CF_ONLY=${CF_ONLY:-S}
    [[ "$CF_ONLY" =~ ^[Ss]$ ]] && CF_ONLY="S" || CF_ONLY="N"
    echo ""
    echo "Instalar o Docker? (necessário para Portainer, Traefik e containers)"
    echo "  Junto vem o firewall dos containers: o Docker não consegue abrir portas para a internet."
    read -r -p "Instalar Docker? [S/n]: " INSTALL_DOCKER
    [[ "${INSTALL_DOCKER:-S}" =~ ^[Ss]$ ]] && INSTALL_DOCKER="S" || INSTALL_DOCKER="N"

    echo ""
    echo -e "${COLOR_GREEN}────────────────────────────────────────────────────────${COLOR_RESET}"
    echo "  Usuário SSH:      $SSH_USER (porta 22, só via Tailscale)"
    echo "  SWAP:             ${SWAP_SIZE} GB"
    echo "  Tailscale:        $([ -n "$TS_AUTHKEY" ] && echo "auth key" || echo "login pelo navegador")"
    echo "  80/443:           $([ "$CF_ONLY" = "S" ] && echo "somente Cloudflare" || echo "público")"
    echo "  Docker:           $([ "$INSTALL_DOCKER" = "S" ] && echo "sim, com firewall DOCKER-USER" || echo "não")"
    echo -e "${COLOR_GREEN}────────────────────────────────────────────────────────${COLOR_RESET}"
    read -r -p "Confirmar e iniciar? [S/n]: " go
    [[ "${go:-S}" =~ ^[Ss]$ ]] || { log INFO "Cancelado. Nada foi alterado."; exit 0; }

    save_config
}

# Grava só o que é necessário para retomar (sem senha, sem auth key), com escape seguro
save_config() {
    (
        umask 077   # só neste subshell: o arquivo nasce com permissão 600
        {
            printf 'SSH_USER=%q\n' "$SSH_USER"
            printf 'SWAP_SIZE=%q\n' "$SWAP_SIZE"
            printf 'PUB_KEY=%q\n' "$PUB_KEY"
            printf 'CF_ONLY=%q\n' "$CF_ONLY"
            printf 'INSTALL_DOCKER=%q\n' "$INSTALL_DOCKER"
            printf 'TAILSCALE_IPV4=%q\n' "$TAILSCALE_IPV4"
            printf 'TAILSCALE_IPV6=%q\n' "$TAILSCALE_IPV6"
        } > "$CONFIG_FILE"
    )
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log ERROR "Checkpoint existe mas $CONFIG_FILE não. Escolha 'Recomeçar do zero'."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    log INFO "Configuração anterior carregada (usuário: $SSH_USER)"
    # A senha não é gravada: se o usuário ainda não foi configurado, pede de novo
    if ! is_phase_completed "user"; then
        log PHASE "Senha do usuário $SSH_USER"
        prompt_password
    fi
}

# ════════════════════════════════════════════════════════
# FASES
# ════════════════════════════════════════════════════════

phase_user() {
    if id "$SSH_USER" &>/dev/null; then
        log INFO "Usuário $SSH_USER já existe — atualizando senha e grupo sudo"
        usermod -aG sudo "$SSH_USER"
    else
        useradd -m -s /bin/bash -G sudo "$SSH_USER"
        log SUCCESS "Usuário $SSH_USER criado"
    fi
    echo "$SSH_USER:$SSH_USER_PASS" | chpasswd
    SSH_USER_PASS=""
    log SUCCESS "Senha definida (sudo e console web)"
}

phase_timezone() {
    timedatectl set-timezone 'America/Sao_Paulo'
    timedatectl set-ntp true
    log SUCCESS "Timezone America/Sao_Paulo + NTP"
}

phase_system_update() {
    # Repositório da Monarx (agente da Hostinger) costuma quebrar o apt com 404
    local f
    for f in /etc/apt/sources.list.d/*; do
        [ -f "$f" ] || continue
        if grep -q "repository.monarx.com" "$f" 2>/dev/null; then
            log WARNING "Desabilitando repositório Monarx: $f"
            mv "$f" "$f.disabled"
        fi
    done

    log INFO "Atualizando pacotes (pode demorar)..."
    "${APT_GET[@]}" update >> "$LOG_FILE" 2>&1
    "${APT_GET[@]}" full-upgrade >> "$LOG_FILE" 2>&1
    "${APT_GET[@]}" install curl ca-certificates gnupg ufw iptables >> "$LOG_FILE" 2>&1
    "${APT_GET[@]}" autoremove --purge >> "$LOG_FILE" 2>&1
    "${APT_GET[@]}" autoclean >> "$LOG_FILE" 2>&1
    log SUCCESS "Sistema atualizado"
}

phase_unattended_upgrades() {
    "${APT_GET[@]}" install unattended-upgrades update-notifier-common >> "$LOG_FILE" 2>&1

    cat > /etc/apt/apt.conf.d/52unattended-upgrades-hardening << 'EOF'
// Gerado por 01-startup.sh — apenas atualizações de SEGURANÇA, sem reboot automático
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl enable --now unattended-upgrades >> "$LOG_FILE" 2>&1
    log SUCCESS "Patches de segurança automáticos (o servidor NUNCA reinicia sozinho)"
    log INFO "  • Quando precisar de reboot, o login SSH mostra: *** System restart required ***"
}

phase_sysctl() {
    cat > "$SYSCTL_FILE" << 'EOF'
# Gerado por 01-startup.sh
# Obs.: net.ipv4.ip_forward NÃO é definido aqui — Docker e Tailscale precisam dele = 1.

# ── Kernel ───────────────────────────────────────────────
kernel.dmesg_restrict = 1           # só root lê o log do kernel
kernel.kptr_restrict = 2            # esconde endereços do kernel
fs.suid_dumpable = 0                # sem core dump de programas privilegiados

# ── Rede: proteções ──────────────────────────────────────
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_synack_retries = 2

# ── Rede: desempenho (proxy reverso / APIs) ──────────────
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.ip_local_port_range = 10240 65535

# ── Arquivos, inotify e memória ──────────────────────────
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
vm.swappiness = 10
EOF

    # BBR (carregado no boot antes do sysctl)
    if modprobe tcp_bbr 2>/dev/null; then
        echo "tcp_bbr" > /etc/modules-load.d/tcp_bbr.conf
        printf '\n# ── Controle de congestionamento ──\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' >> "$SYSCTL_FILE"
        log SUCCESS "BBR ativado"
    else
        log WARNING "BBR indisponível neste kernel — mantendo padrão"
    fi

    # Conntrack (tabela grande e timeouts curtos contra flood de conexões)
    echo "nf_conntrack" > /etc/modules-load.d/nf_conntrack.conf
    modprobe nf_conntrack 2>/dev/null || true
    cat > /etc/sysctl.d/91-conntrack.conf << 'EOF'
# Gerado por 01-startup.sh
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 15
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 30
EOF

    sysctl --system >> "$LOG_FILE" 2>&1

    # Limites: core dump desligado e 1M de file descriptors
    cat > /etc/security/limits.d/90-hardening.conf << 'EOF'
# Gerado por 01-startup.sh
*    hard core   0
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    mkdir -p /etc/systemd/system.conf.d
    printf '[Manager]\nDefaultLimitNOFILE=1048576\n' > /etc/systemd/system.conf.d/90-nofile.conf
    systemctl daemon-reexec

    log SUCCESS "Sysctl aplicado: $SYSCTL_FILE"
}

phase_kernel_modules() {
    cat > /etc/modprobe.d/blacklist-hardening.conf << 'EOF'
# Gerado por 01-startup.sh — módulos sem uso em servidor (CIS Benchmark)
# Protocolos de rede
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
blacklist dccp
blacklist sctp
blacklist rds
blacklist tipc
# Sistemas de arquivos
install cramfs /bin/false
install freevxfs /bin/false
install jffs2 /bin/false
install hfs /bin/false
install hfsplus /bin/false
install udf /bin/false
blacklist cramfs
blacklist freevxfs
blacklist jffs2
blacklist hfs
blacklist hfsplus
blacklist udf
EOF
    update-initramfs -u >> "$LOG_FILE" 2>&1 || log WARNING "update-initramfs falhou (efeito vale no próximo boot mesmo assim)"
    log SUCCESS "Módulos bloqueados: dccp, sctp, rds, tipc, cramfs, freevxfs, jffs2, hfs, hfsplus, udf"
}

phase_swap() {
    local swapfile="/swap/swapfile"

    # Remove swaps existentes (arquivo da imagem da VPS, swap antigo etc.)
    if [ -n "$(swapon --show --noheadings)" ]; then
        log INFO "Desativando swap existente:"
        swapon --show | tee -a "$LOG_FILE"
        local old
        for old in $(swapon --show=NAME --noheadings); do
            swapoff "$old"
            [ -f "$old" ] && rm -f "$old"
        done
    fi
    cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    awk '$3 != "swap"' /etc/fstab > /etc/fstab.new && mv /etc/fstab.new /etc/fstab

    mkdir -p /swap
    rm -f "$swapfile"
    if ! fallocate -l "${SWAP_SIZE}G" "$swapfile" 2>/dev/null; then
        dd if=/dev/zero of="$swapfile" bs=1M count=$((SWAP_SIZE * 1024)) status=none
    fi
    chmod 600 "$swapfile"
    mkswap "$swapfile" >> "$LOG_FILE" 2>&1
    swapon "$swapfile"
    echo "$swapfile none swap sw 0 0" >> /etc/fstab

    if [[ "$(swapon --show=NAME --noheadings)" != *"$swapfile"* ]]; then
        log ERROR "SWAP não ativou"
        exit 1
    fi
    log SUCCESS "SWAP de ${SWAP_SIZE} GB ativo em $swapfile (swappiness=10)"
}

phase_ssh_key() {
    local home
    home=$(getent passwd "$SSH_USER" | cut -d: -f6)
    install -d -m 700 -o "$SSH_USER" -g "$SSH_USER" "$home/.ssh"
    echo "$PUB_KEY" > "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
    chown "$SSH_USER:$SSH_USER" "$home/.ssh/authorized_keys"
    log SUCCESS "Chave instalada em $home/.ssh/authorized_keys"
}

phase_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        log INFO "Instalando Tailscale (script oficial, repositório apt assinado)..."
        curl -fsSL https://tailscale.com/install.sh | sh >> "$LOG_FILE" 2>&1
    fi
    systemctl enable --now tailscaled >> "$LOG_FILE" 2>&1

    if [ -z "$(tailscale ip -4 2>/dev/null || true)" ]; then
        if [ -n "$TS_AUTHKEY" ]; then
            log INFO "Conectando com auth key..."
            tailscale up --auth-key="$TS_AUTHKEY" --hostname="$(hostname -s)" 2>&1 | tee -a "$LOG_FILE"
        else
            echo ""
            echo -e "${COLOR_BOLD}${COLOR_YELLOW}  ⚠️  AÇÃO NECESSÁRIA: abra o link abaixo no navegador para autenticar${COLOR_RESET}"
            echo ""
            tailscale up --hostname="$(hostname -s)" 2>&1 | tee -a "$LOG_FILE"
        fi
    fi
    TS_AUTHKEY=""

    local i
    for i in $(seq 1 30); do
        TAILSCALE_IPV4=$(tailscale ip -4 2>/dev/null | head -n1 || true)
        [ -n "$TAILSCALE_IPV4" ] && break
        sleep 1
    done
    if [ -z "$TAILSCALE_IPV4" ]; then
        log ERROR "Tailscale não conectou. Rode 'tailscale up' e depois este script de novo."
        exit 1
    fi
    TAILSCALE_IPV6=$(tailscale ip -6 2>/dev/null | head -n1 || true)
    save_config
    log SUCCESS "Tailscale conectado: $TAILSCALE_IPV4 ${TAILSCALE_IPV6}"

    # Sem isso o servidor sai da rede em ~180 dias e o SSH fica inacessível
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}  ⚠️  OBRIGATÓRIO: desativar a expiração da chave deste servidor${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo "  O SSH só vai funcionar pelo Tailscale. Se a chave expirar, você perde o acesso."
    echo ""
    echo "  1. Abra: https://login.tailscale.com/admin/machines"
    echo "  2. Na máquina '$(hostname -s)' clique em '...' → 'Disable key expiry'"
    echo ""
    local done_expiry
    while true; do
        read -r -p "  Já desativou? Digite 'ok' para continuar: " done_expiry
        [ "$done_expiry" = "ok" ] && break
    done
    log SUCCESS "Expiração da chave Tailscale desativada (confirmado pelo usuário)"
}

phase_ssh_config() {
    if [ -z "$TAILSCALE_IPV4" ]; then
        log ERROR "IP do Tailscale desconhecido. Rode a fase do Tailscale primeiro."
        exit 1
    fi

    local backup_dir
    backup_dir="/root/ssh-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.d "$backup_dir/"
    log INFO "Backup da configuração SSH: $backup_dir"

    ssh-keygen -A >> "$LOG_FILE" 2>&1

    # Outros arquivos em sshd_config.d (cloud-init, imagem da VPS) podem reabilitar senha
    local f
    for f in /etc/ssh/sshd_config.d/*.conf; do
        [ -e "$f" ] || continue
        [ "$f" = "$SSHD_DROPIN" ] && continue
        log WARNING "Desabilitando $(basename "$f")"
        mv "$f" "$f.disabled"
    done
    # Port/ListenAddress no arquivo principal se somariam aos nossos
    sed -i -E 's/^[[:space:]]*(Port|ListenAddress)[[:space:]]/# desabilitado por 01-startup.sh: &/' /etc/ssh/sshd_config

    # Kex pós-quântico quando o OpenSSH suporta (10.x: mlkem; 9.x: sntrup)
    local supported kex="" k
    supported=$(ssh -Q kex)
    for k in mlkem768x25519-sha256 sntrup761x25519-sha512 sntrup761x25519-sha512@openssh.com \
             curve25519-sha256 curve25519-sha256@libssh.org; do
        grep -qx "$k" <<< "$supported" && kex="${kex:+$kex,}$k"
    done

    cat > "$SSHD_DROPIN" << EOF
# Gerado por 01-startup.sh em $(date '+%Y-%m-%d %H:%M')
# SSH acessível APENAS via Tailscale, apenas com chave.
# Este arquivo é lido antes de qualquer outro (prefixo 00): os valores daqui prevalecem.

Port $SSH_PORT
ListenAddress 127.0.0.1
ListenAddress $TAILSCALE_IPV4
$([ -n "$TAILSCALE_IPV6" ] && echo "ListenAddress $TAILSCALE_IPV6")

# Autenticação
PermitRootLogin no
AllowUsers $SSH_USER
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
UsePAM yes

# Limites
LoginGraceTime 30
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:60
ClientAliveInterval 300
ClientAliveCountMax 2

# Recursos
X11Forwarding no
PermitUserEnvironment no
AllowAgentForwarding yes
AllowTcpForwarding yes
GatewayPorts no
PermitTunnel no

# Criptografia
HostKey /etc/ssh/ssh_host_ed25519_key
KexAlgorithms $kex
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

LogLevel VERBOSE
EOF
    chmod 644 "$SSHD_DROPIN"

    rollback_ssh() {
        log ERROR "Restaurando configuração SSH anterior..."
        rm -f "$SSHD_DROPIN"
        rm -rf /etc/ssh/sshd_config.d
        cp -a "$backup_dir/sshd_config.d" /etc/ssh/
        cp -a "$backup_dir/sshd_config" /etc/ssh/sshd_config
        restart_ssh || true
    }

    restart_ssh() {
        systemctl daemon-reload
        if systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
            systemctl restart ssh.socket          # Ubuntu 24.04+: socket activation
        fi
        systemctl restart ssh.service 2>/dev/null || true
        sleep 2
    }

    if ! sshd -t >> "$LOG_FILE" 2>&1; then
        sshd -t || true
        rollback_ssh
        exit 1
    fi

    # Confere a configuração EFETIVA (não só o texto do arquivo)
    local eff
    eff=$(sshd -T 2>/dev/null)
    local expect
    for expect in "passwordauthentication no" "permitrootlogin no" "kbdinteractiveauthentication no" \
                  "pubkeyauthentication yes" "allowusers $SSH_USER" "listenaddress $TAILSCALE_IPV4:$SSH_PORT"; do
        if ! grep -qix "$expect" <<< "$eff"; then
            log ERROR "Configuração efetiva não contém: '$expect'"
            rollback_ssh
            exit 1
        fi
    done
    if grep -qiE "^listenaddress (0\.0\.0\.0|\[::\]):" <<< "$eff"; then
        log ERROR "SSH ainda escutaria em todos os IPs"
        rollback_ssh
        exit 1
    fi

    restart_ssh
    local listening
    listening=$(ss -tlnH | awk '{print $4}')
    if ! grep -qx "$TAILSCALE_IPV4:$SSH_PORT" <<< "$listening"; then
        log ERROR "SSH não está escutando em $TAILSCALE_IPV4:$SSH_PORT"
        rollback_ssh
        exit 1
    fi

    # Teste real antes de seguir: se não funcionar, desfaz e você continua com o acesso atual
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}  🔐 TESTE O NOVO ACESSO (não feche esta sessão!)${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_YELLOW}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo "  Em OUTRO terminal, com o Tailscale ligado no seu computador:"
    echo ""
    echo "    ssh -i <sua-chave-privada> $SSH_USER@$TAILSCALE_IPV4"
    echo "    sudo -v        # confirme que a senha do sudo funciona"
    echo ""
    local ok
    read -r -p "  O login e o sudo funcionaram? [s/N]: " ok
    if [[ ! "$ok" =~ ^[Ss]$ ]]; then
        rollback_ssh
        log ERROR "Configuração SSH desfeita. Verifique Tailscale/chave e rode o script de novo."
        exit 1
    fi

    log SUCCESS "SSH: só chave, só Tailscale ($TAILSCALE_IPV4:$SSH_PORT), root bloqueado"
    log SUCCESS "Kex: $kex"
}

phase_firewall() {
    sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw

    ufw --force reset >> "$LOG_FILE" 2>&1
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1
    ufw allow in on tailscale0 comment 'Tailscale - acesso total' >> "$LOG_FILE" 2>&1

    # Script de atualização dos IPs da Cloudflare (UFW + DOCKER-USER)
    cat > "$CF_SCRIPT" << 'EOF'
#!/bin/bash
# Gerado por 01-startup.sh — sincroniza as faixas de IP da Cloudflare com o firewall.
# Libera 80/443 apenas para a Cloudflare no UFW e reaplica o DOCKER-USER.
# Uso: cloudflare-update-firewall.sh [--force]
set -euo pipefail
export LC_ALL=C
LIST=/etc/cloudflare-ips.txt
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
log() { echo "[cloudflare-update-firewall] $*"; }

if ! { curl -fsS --max-time 30 --retry 3 https://www.cloudflare.com/ips-v4 && echo &&
        curl -fsS --max-time 30 --retry 3 https://www.cloudflare.com/ips-v6 && echo
      } > "$TMP.raw"; then
    log "ERRO: não foi possível baixar a lista da Cloudflare. Nada foi alterado."
    rm -f "$TMP.raw"
    exit 1
fi
tr -d '\r' < "$TMP.raw" \
  | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$|^[0-9a-fA-F:]+/[0-9]{1,3}$' \
  | sort -u > "$TMP" || true
rm -f "$TMP.raw"

v4=$(grep -c '\.' "$TMP" || true)
v6=$(grep -c ':' "$TMP" || true)
if [ "$v4" -lt 5 ] || [ "$v6" -lt 3 ]; then
    log "ERRO: lista suspeita (IPv4=$v4, IPv6=$v6). Nada foi alterado."
    exit 1
fi

touch "$LIST"
if cmp -s "$TMP" "$LIST" && [ "${1:-}" != "--force" ]; then
    log "Sem mudanças ($v4 IPv4 + $v6 IPv6)."
    exit 0
fi

# Remove regras públicas de 80/443 (modo aberto), se existirem
for p in 80 443; do ufw delete allow "$p/tcp" >/dev/null 2>&1 || true; done

# Remove faixas que saíram da lista da Cloudflare
comm -23 "$LIST" "$TMP" | while read -r ip; do
    [ -n "$ip" ] || continue
    for p in 80 443; do ufw delete allow proto tcp from "$ip" to any port "$p" >/dev/null 2>&1 || true; done
    log "Removido: $ip"
done

# Adiciona as faixas atuais (o UFW ignora regras já existentes)
while read -r ip; do
    for p in 80 443; do ufw allow proto tcp from "$ip" to any port "$p" comment 'Cloudflare' >/dev/null; done
done < "$TMP"

install -m 644 "$TMP" "$LIST"
if systemctl is-enabled --quiet docker-user-firewall.service 2>/dev/null; then
    systemctl restart docker-user-firewall.service
fi
log "Atualizado: $v4 faixas IPv4 + $v6 faixas IPv6."
EOF
    chmod 755 "$CF_SCRIPT"

    cat > /etc/systemd/system/cloudflare-update-firewall.service << EOF
[Unit]
Description=Atualiza IPs da Cloudflare no UFW e DOCKER-USER
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CF_SCRIPT
EOF
    cat > /etc/systemd/system/cloudflare-update-firewall.timer << 'EOF'
[Unit]
Description=Atualiza IPs da Cloudflare semanalmente

[Timer]
OnCalendar=weekly
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload

    if [ "$CF_ONLY" = "S" ]; then
        if "$CF_SCRIPT" --force 2>&1 | tee -a "$LOG_FILE"; then
            systemctl enable --now cloudflare-update-firewall.timer >> "$LOG_FILE" 2>&1
            log SUCCESS "80/443 liberados SÓ para a Cloudflare (atualização semanal automática)"
        else
            log WARNING "Não foi possível baixar os IPs da Cloudflare — abrindo 80/443 para todos"
            log WARNING "Depois rode: sudo $CF_SCRIPT --force && sudo systemctl enable --now cloudflare-update-firewall.timer"
            ufw allow 80/tcp comment 'HTTP - publico' >> "$LOG_FILE" 2>&1
            ufw allow 443/tcp comment 'HTTPS - publico' >> "$LOG_FILE" 2>&1
        fi
    else
        ufw allow 80/tcp comment 'HTTP - publico' >> "$LOG_FILE" 2>&1
        ufw allow 443/tcp comment 'HTTPS - publico' >> "$LOG_FILE" 2>&1
        log SUCCESS "80/443 públicos (para Cloudflare-only depois: sudo $CF_SCRIPT --force)"
    fi

    ufw logging low >> "$LOG_FILE" 2>&1
    ufw --force enable >> "$LOG_FILE" 2>&1
    local ufw_status
    ufw_status=$(ufw status verbose)
    echo "$ufw_status" | tee -a "$LOG_FILE"
    if ! grep -q "Status: active" <<< "$ufw_status"; then
        log ERROR "UFW não ativou"
        exit 1
    fi
    log SUCCESS "UFW ativo: tudo bloqueado exceto 80/443 e Tailscale"
}

phase_docker() {
    if [ "$INSTALL_DOCKER" != "S" ]; then
        log INFO "Docker não selecionado — pulando"
        log INFO "  • Para instalar depois, rode o script de novo em uma VPS nova ou instale manualmente"
        return 0
    fi

    if ! command -v docker &>/dev/null; then
        log INFO "Adicionando repositório oficial do Docker..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        # shellcheck disable=SC1091
        cat > /etc/apt/sources.list.d/docker.sources << EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
        "${APT_GET[@]}" update >> "$LOG_FILE" 2>&1
        log INFO "Instalando Docker Engine..."
        "${APT_GET[@]}" install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
    fi

    # Padrões seguros:
    #  ip=127.0.0.1         → porta publicada sem IP explícito escuta só no localhost
    #  no-new-privileges    → processo no container não ganha privilégio via setuid
    #  live-restore         → containers continuam rodando quando o Docker atualiza
    #  log rotation         → 3 × 10 MB por container
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "ip": "127.0.0.1",
  "no-new-privileges": true,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    systemctl enable docker >> "$LOG_FILE" 2>&1
    systemctl restart docker
    docker info &>/dev/null
    log SUCCESS "Docker $(docker version --format '{{.Server.Version}}') rodando"

    # Por que DOCKER-USER: portas publicadas pelo Docker passam pela chain FORWARD,
    # que o UFW não filtra. Sem isso, "-p 9443:9443" ficaria aberto para a internet.
    cat > "$DU_SCRIPT" << 'EOF'
#!/bin/bash
# Gerado por 01-startup.sh — firewall dos containers (chain DOCKER-USER).
# Internet → containers: só 80/443 (e só da Cloudflare, se /etc/cloudflare-ips.txt existir).
# Tailscale → containers: tudo. Tráfego entre containers: inalterado.
set -uo pipefail
LIST=/etc/cloudflare-ips.txt

iface() { ip "$1" route show default 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}'; }
IF4=$(iface -4); IF4=${IF4:-eth0}
IF6=$(iface -6); IF6=${IF6:-$IF4}

apply() {
    local ipt=$1 ifc=$2 family=$3 src p
    if ! $ipt -n -L DOCKER-USER >/dev/null 2>&1; then
        echo "DOCKER-USER não existe em $ipt (Docker parado ou sem IPv6) — pulando"
        return 0
    fi
    $ipt -F DOCKER-USER
    $ipt -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    $ipt -A DOCKER-USER -i tailscale0 -j ACCEPT
    # --ctorigdstport = porta PUBLICADA no host (antes do DNAT), não a porta interna do container
    if [ -s "$LIST" ]; then
        while read -r src; do
            for p in 80 443; do
                $ipt -A DOCKER-USER -i "$ifc" -s "$src" -p tcp -m conntrack --ctorigdstport "$p" --ctdir ORIGINAL -j ACCEPT
            done
        done < <(grep -E "$family" "$LIST")
    else
        for p in 80 443; do
            $ipt -A DOCKER-USER -i "$ifc" -p tcp -m conntrack --ctorigdstport "$p" --ctdir ORIGINAL -j ACCEPT
        done
    fi
    $ipt -A DOCKER-USER -i "$ifc" -j DROP
    $ipt -A DOCKER-USER -j RETURN
    echo "$ipt: DOCKER-USER aplicado em $ifc"
}

apply iptables  "$IF4" '\.'
apply ip6tables "$IF6" ':'
EOF
    chmod 755 "$DU_SCRIPT"

    cat > /etc/systemd/system/docker-user-firewall.service << EOF
[Unit]
Description=Firewall dos containers (chain DOCKER-USER)
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
Type=oneshot
ExecStart=$DU_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target docker.service
EOF
    systemctl daemon-reload
    systemctl enable docker-user-firewall.service >> "$LOG_FILE" 2>&1
    systemctl restart docker-user-firewall.service
    local du_rules
    du_rules=$(iptables -S DOCKER-USER)
    echo "$du_rules" >> "$LOG_FILE"
    if ! grep -q -- "-j DROP" <<< "$du_rules"; then
        log ERROR "Regras DOCKER-USER não foram aplicadas (veja: journalctl -u docker-user-firewall)"
        exit 1
    fi
    log SUCCESS "DOCKER-USER ativo: internet → containers só em 80/443$([ -s "$CF_LIST" ] && echo " (Cloudflare)")"
    log INFO "  • Admin (Portainer, Grafana...): publique no IP do Tailscale, ex.: \"$TAILSCALE_IPV4:9443:9443\""
    log INFO "  • Traefik: publique explicitamente \"0.0.0.0:80:80\" e \"0.0.0.0:443:443\""
    log INFO "  • Docker exige sudo (não adicionamos $SSH_USER ao grupo docker: isso equivale a root)"
}

phase_logging() {
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/90-hardening.conf << 'EOF'
# Gerado por 01-startup.sh — logs persistentes com limite de disco
[Journal]
Storage=persistent
SystemMaxUse=500M
MaxRetentionSec=3month
EOF
    systemctl restart systemd-journald
    log SUCCESS "Journald persistente (máx. 500 MB / 3 meses). Logs do Docker: 3 × 10 MB por container"
}

# ════════════════════════════════════════════════════════
# RESUMO FINAL
# ════════════════════════════════════════════════════════

show_summary() {
    local total=$(( $(date +%s) - START_TIME ))
    local summary
    summary=$(cat << EOF
════════════════════════════════════════════════════════
  SERVIDOR CONFIGURADO — $(date '+%Y-%m-%d %H:%M')
════════════════════════════════════════════════════════

ACESSO SSH (somente via Tailscale, somente chave)
  ssh $SSH_USER@$TAILSCALE_IPV4
  Root: bloqueado | Senha do $SSH_USER: só para sudo e console web

TAILSCALE
  IPv4: $TAILSCALE_IPV4
  IPv6: ${TAILSCALE_IPV6:-—}
  Lembre: expiração da chave desativada no painel

FIREWALL
  UFW: tudo bloqueado, exceto Tailscale e 80/443
  80/443: $([ "$CF_ONLY" = "S" ] && echo "somente IPs da Cloudflare (atualização semanal)" || echo "público")
  Containers: $([ "$INSTALL_DOCKER" = "S" ] && echo "DOCKER-USER (internet só alcança 80/443)" || echo "Docker não instalado")

SISTEMA
  Ubuntu: $(. /etc/os-release && echo "$PRETTY_NAME")
  SWAP: ${SWAP_SIZE} GB (swappiness 10)
  Atualizações de segurança: automáticas, SEM reboot automático
  Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "não instalado")

ARQUIVOS
  SSH:       $SSHD_DROPIN
  Sysctl:    $SYSCTL_FILE
  Firewall:  $CF_SCRIPT
             $DU_SCRIPT
  Log:       $LOG_FILE

Validar: sudo bash $SCRIPT_DIR/_audit.sh
Tempo total: $(format_time $total)
════════════════════════════════════════════════════════
EOF
)
    echo ""
    echo "$summary"
    echo "$summary" > /root/server-info.txt
    chmod 600 /root/server-info.txt
    log SUCCESS "Resumo salvo em /root/server-info.txt"
}

# ════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════

main() {
    check_root
    check_ubuntu

    if [ -z "$(public_iface)" ]; then
        log ERROR "Não foi possível detectar a interface de rede pública (rota default)"
        exit 1
    fi

    log INFO "Log desta execução: $LOG_FILE"

    if [ -f "$CHECKPOINT_FILE" ]; then
        log WARNING "Execução anterior encontrada: $(get_completed_phases) de $TOTAL_PHASES fases concluídas."
        echo "  1) Continuar de onde parou"
        echo "  2) Recomeçar do zero"
        echo "  3) Sair"
        local choice
        read -r -p "Escolha [1-3]: " choice
        case $choice in
            1) load_config ;;
            2) rm -f "$CHECKPOINT_FILE" "$CONFIG_FILE"; interactive_config ;;
            *) exit 0 ;;
        esac
    else
        interactive_config
    fi

    echo ""
    show_progress
    run_all_phases
    show_summary

    rm -f "$CHECKPOINT_FILE" "$CONFIG_FILE"

    echo ""
    log WARNING "Reinicie para aplicar kernel/módulos. Depois, conecte por: ssh $SSH_USER@$TAILSCALE_IPV4"
    local rb
    read -r -p "Reiniciar agora? [S/n]: " rb
    if [[ "${rb:-S}" =~ ^[Ss]$ ]]; then
        log INFO "Reiniciando..."
        systemctl reboot
    else
        log INFO "Reinicie quando quiser: sudo reboot"
    fi
}

main "$@"
