#!/bin/bash
# ════════════════════════════════════════════════════════
# Script de Auditoria de Servidor Ubuntu - Default VPS
# Version: 1.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
#
# Uso: sudo bash audit.sh
# Rodar APÓS o startup.sh + reboot para validar todas as configurações.
# ════════════════════════════════════════════════════════

set -uo pipefail

# ════════════════════════════════════════════════════════
# CORES E VARIÁVEIS
# ════════════════════════════════════════════════════════

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
AUDIT_LOG="${LOG_DIR}/audit-$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

PASS=0
FAIL=0
WARN=0
TOTAL=0

# ════════════════════════════════════════════════════════
# FUNÇÕES DE OUTPUT
# ════════════════════════════════════════════════════════

log_result() {
    local status="$1"   # PASS | FAIL | WARN
    local check="$2"
    local detail="${3:-}"

    TOTAL=$((TOTAL + 1))

    case "$status" in
        PASS)
            PASS=$((PASS + 1))
            printf "  ${COLOR_GREEN}✅ PASS${COLOR_RESET}  %-45s %s\n" "$check" "$detail"
            echo "[PASS] $check $detail" >> "$AUDIT_LOG"
            ;;
        FAIL)
            FAIL=$((FAIL + 1))
            printf "  ${COLOR_RED}❌ FAIL${COLOR_RESET}  %-45s %s\n" "$check" "$detail"
            echo "[FAIL] $check $detail" >> "$AUDIT_LOG"
            ;;
        WARN)
            WARN=$((WARN + 1))
            printf "  ${COLOR_YELLOW}⚠️  WARN${COLOR_RESET}  %-45s %s\n" "$check" "$detail"
            echo "[WARN] $check $detail" >> "$AUDIT_LOG"
            ;;
    esac
}

section() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_BLUE}── $1 ${COLOR_RESET}"
    echo "" >> "$AUDIT_LOG"
    echo "## $1" >> "$AUDIT_LOG"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Execute como root: sudo bash audit.sh${COLOR_RESET}"
        exit 1
    fi
}

# ════════════════════════════════════════════════════════
# VERIFICAÇÕES
# ════════════════════════════════════════════════════════

check_system() {
    section "Sistema Base"

    # Timezone
    local tz
    tz=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null)
    if [ "$tz" = "America/Sao_Paulo" ]; then
        log_result PASS "Timezone" "($tz)"
    else
        log_result FAIL "Timezone" "(esperado: America/Sao_Paulo, atual: $tz)"
    fi

    # NTP
    if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q "yes"; then
        log_result PASS "NTP sincronizado"
    else
        log_result WARN "NTP sincronizado" "(pode demorar alguns minutos após reboot)"
    fi

    # SWAP ativo
    local swap_total
    swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    if [ "${swap_total:-0}" -gt 0 ]; then
        log_result PASS "SWAP ativo" "(${swap_total}MB)"
    else
        log_result FAIL "SWAP ativo" "(nenhum swap detectado)"
    fi

    # Unattended upgrades
    if dpkg -l unattended-upgrades &>/dev/null && \
       [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
        log_result PASS "Unattended Upgrades instalado"
    else
        log_result WARN "Unattended Upgrades" "(não instalado — opcional)"
    fi
}

check_kernel() {
    section "Kernel e Rede (sysctl)"

    # Parâmetros obrigatórios
    local params=(
        "kernel.randomize_va_space:2"
        "net.ipv4.tcp_syncookies:1"
        "net.ipv4.tcp_rfc1337:1"
        "net.ipv4.tcp_timestamps:0"
        "net.ipv4.tcp_synack_retries:2"
        "net.ipv4.conf.all.rp_filter:1"
        "net.ipv4.conf.default.rp_filter:1"
        "net.ipv4.conf.all.accept_redirects:0"
        "net.ipv4.conf.default.accept_redirects:0"
        "net.ipv4.conf.all.send_redirects:0"
        "net.ipv4.conf.default.send_redirects:0"
        "net.ipv4.icmp_echo_ignore_broadcasts:1"
        "net.ipv4.icmp_ignore_bogus_error_responses:1"
        "net.ipv4.icmp_ratelimit:100"
        "net.core.somaxconn:4096"
        "net.ipv4.tcp_max_syn_backlog:8192"
        "fs.file-max:2097152"
    )

    for param in "${params[@]}"; do
        local key="${param%%:*}"
        local expected="${param##*:}"
        local actual
        actual=$(sysctl -n "$key" 2>/dev/null)
        if [ "$actual" = "$expected" ]; then
            log_result PASS "sysctl $key" "(= $actual)"
        else
            log_result FAIL "sysctl $key" "(esperado: $expected, atual: ${actual:-não definido})"
        fi
    done

    # BBR
    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$cc" = "bbr" ]; then
        log_result PASS "BBR congestion control" "(ativo)"
    else
        log_result WARN "BBR congestion control" "(atual: ${cc:-desconhecido})"
    fi

    # Conntrack
    if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
        local ct_max
        ct_max=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)
        if [ "${ct_max:-0}" -ge 1048576 ]; then
            log_result PASS "Conntrack max" "(${ct_max} conexões)"
        else
            log_result FAIL "Conntrack max" "(esperado: 1048576, atual: ${ct_max:-0})"
        fi
    else
        log_result WARN "Conntrack" "(módulo não carregado — carregará com primeiro pacote NAT)"
    fi

    # File descriptors
    local fd_limit
    fd_limit=$(grep -m1 "^* soft nofile" /etc/security/limits.conf 2>/dev/null | awk '{print $4}')
    if [ "${fd_limit:-0}" -ge 1048576 ]; then
        log_result PASS "File descriptors (limits.conf)" "(${fd_limit})"
    else
        log_result FAIL "File descriptors (limits.conf)" "(esperado: 1048576, atual: ${fd_limit:-não configurado})"
    fi
}

check_kernel_modules() {
    section "Módulos de Kernel Bloqueados"

    if [ ! -f /etc/modprobe.d/blacklist-hardening.conf ]; then
        log_result WARN "blacklist-hardening.conf" "(não encontrado — opcional)"
        return
    fi

    local modules=("dccp" "sctp" "rds" "tipc" "cramfs" "jffs2" "hfs" "hfsplus" "udf")
    for mod in "${modules[@]}"; do
        if grep -q "install $mod /bin/true" /etc/modprobe.d/blacklist-hardening.conf 2>/dev/null; then
            # Verifica se não está carregado
            if ! lsmod 2>/dev/null | grep -q "^${mod} "; then
                log_result PASS "Módulo bloqueado: $mod"
            else
                log_result WARN "Módulo bloqueado: $mod" "(configurado mas ainda carregado — reboot necessário)"
            fi
        else
            log_result FAIL "Módulo bloqueado: $mod" "(não encontrado no blacklist)"
        fi
    done
}

check_ssh() {
    section "SSH Hardening"

    local sshd_config="/etc/ssh/sshd_config"

    # Serviço ativo
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log_result PASS "SSH serviço ativo"
    else
        log_result FAIL "SSH serviço ativo" "(serviço parado!)"
    fi

    # PasswordAuthentication no
    if grep -q "^PasswordAuthentication no" "$sshd_config" 2>/dev/null; then
        log_result PASS "PasswordAuthentication no"
    else
        log_result FAIL "PasswordAuthentication no" "(não encontrado em sshd_config)"
    fi

    # PubkeyAuthentication yes
    if grep -q "^PubkeyAuthentication yes" "$sshd_config" 2>/dev/null; then
        log_result PASS "PubkeyAuthentication yes"
    else
        log_result FAIL "PubkeyAuthentication yes" "(não encontrado em sshd_config)"
    fi

    # PermitRootLogin
    if grep -q "^PermitRootLogin no\|^PermitRootLogin prohibit-password" "$sshd_config" 2>/dev/null; then
        local rl
        rl=$(grep "^PermitRootLogin" "$sshd_config" | awk '{print $2}')
        log_result PASS "PermitRootLogin" "($rl)"
    else
        log_result FAIL "PermitRootLogin" "(não configurado de forma segura)"
    fi

    # SSH NÃO escuta no 0.0.0.0 (IP público)
    local listen_addrs
    listen_addrs=$(grep "^ListenAddress" "$sshd_config" 2>/dev/null | awk '{print $2}')
    if echo "$listen_addrs" | grep -q "^0\.0\.0\.0$\|^::$"; then
        log_result FAIL "SSH não exposto publicamente" "(ListenAddress 0.0.0.0 ou :: encontrado)"
    elif [ -n "$listen_addrs" ]; then
        log_result PASS "SSH escuta apenas em IPs específicos" "($(echo "$listen_addrs" | tr '\n' ' '))"
    else
        log_result WARN "SSH ListenAddress" "(não configurado explicitamente)"
    fi

    # Porta SSH diferente de 22
    local ssh_port
    ssh_port=$(grep "^Port " "$sshd_config" 2>/dev/null | awk '{print $2}')
    if [ -n "$ssh_port" ] && [ "$ssh_port" != "22" ]; then
        log_result PASS "SSH porta customizada" "(porta $ssh_port)"
    elif [ "$ssh_port" = "22" ]; then
        log_result WARN "SSH porta customizada" "(usando porta padrão 22)"
    else
        log_result WARN "SSH porta" "(não definida explicitamente)"
    fi

    # Criptografia forte
    if grep -q "chacha20-poly1305\|aes256-gcm" "$sshd_config" 2>/dev/null; then
        log_result PASS "Criptografia forte configurada"
    else
        log_result WARN "Criptografia forte" "(Ciphers não configurados explicitamente)"
    fi

    # Cloud-init desabilitado
    if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
        log_result FAIL "Cloud-init SSH override" "(50-cloud-init.conf ainda ativo — pode sobrescrever config)"
    else
        log_result PASS "Cloud-init SSH override desabilitado"
    fi
}

check_tailscale() {
    section "Tailscale VPN"

    if ! command -v tailscale &>/dev/null; then
        log_result FAIL "Tailscale instalado" "(comando não encontrado)"
        return
    fi
    log_result PASS "Tailscale instalado"

    if systemctl is-active --quiet tailscaled 2>/dev/null; then
        log_result PASS "Tailscaled serviço ativo"
    else
        log_result FAIL "Tailscaled serviço ativo" "(serviço parado)"
    fi

    local ts_status
    ts_status=$(tailscale status 2>/dev/null | head -1)
    if tailscale status &>/dev/null && ! echo "$ts_status" | grep -qi "stopped\|logout\|needs login"; then
        local ts_ipv4
        ts_ipv4=$(tailscale ip -4 2>/dev/null | head -1)
        log_result PASS "Tailscale conectado" "(IPv4: ${ts_ipv4:-desconhecido})"
    else
        log_result FAIL "Tailscale conectado" "(execute: sudo tailscale up)"
    fi
}

check_firewall() {
    section "Firewall UFW"

    if ! command -v ufw &>/dev/null; then
        log_result FAIL "UFW instalado" "(não encontrado)"
        return
    fi

    # Status ativo
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        log_result PASS "UFW ativo"
    else
        log_result FAIL "UFW ativo" "(execute: ufw enable)"
    fi

    # Política padrão DENY
    if ufw status verbose 2>/dev/null | grep -q "Default: deny (incoming)"; then
        log_result PASS "Política padrão DENY incoming"
    else
        log_result FAIL "Política padrão DENY incoming" "(verifique: ufw default deny incoming)"
    fi

    # IPv6
    if grep -q "^IPV6=yes" /etc/default/ufw 2>/dev/null; then
        log_result PASS "IPv6 habilitado no UFW"
    else
        log_result FAIL "IPv6 habilitado no UFW" "(verifique /etc/default/ufw)"
    fi

    # Logging medium
    if ufw status verbose 2>/dev/null | grep -qi "Logging: on (medium)\|logging medium"; then
        log_result PASS "UFW logging medium"
    else
        log_result WARN "UFW logging" "(pode não estar em modo medium — execute: ufw logging medium)"
    fi

    # Tailscale liberado
    if ufw status 2>/dev/null | grep -q "tailscale0"; then
        log_result PASS "Interface Tailscale liberada no UFW"
    else
        log_result FAIL "Interface Tailscale liberada no UFW" "(SSH ficará inacessível)"
    fi

    # Cloudflare IP Updater
    if systemctl is-enabled --quiet cf-update-ufw.timer 2>/dev/null; then
        local next_run
        next_run=$(systemctl status cf-update-ufw.timer 2>/dev/null | grep "Trigger:" | awk '{print $2, $3}')
        log_result PASS "Cloudflare IP Updater timer ativo" "(próximo: ${next_run:-desconhecido})"

        # Contar regras Cloudflare
        local cf_rules
        cf_rules=$(ufw status 2>/dev/null | grep -c "Cloudflare" || echo 0)
        if [ "${cf_rules:-0}" -gt 0 ]; then
            log_result PASS "Regras Cloudflare no UFW" "(${cf_rules} regras ativas)"
        else
            log_result WARN "Regras Cloudflare no UFW" "(nenhuma regra — execute: systemctl start cf-update-ufw.service)"
        fi
    else
        log_result WARN "Cloudflare IP Updater" "(não configurado — opcional se CF-Only desativado)"
    fi
}

check_fail2ban() {
    section "Fail2Ban"

    if ! command -v fail2ban-client &>/dev/null; then
        log_result FAIL "Fail2Ban instalado" "(não encontrado)"
        return
    fi
    log_result PASS "Fail2Ban instalado"

    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        log_result PASS "Fail2Ban serviço ativo"
    else
        log_result FAIL "Fail2Ban serviço ativo" "(serviço parado)"
    fi

    # Jail sshd ativo
    if fail2ban-client status sshd &>/dev/null; then
        local banned
        banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
        log_result PASS "Jail sshd ativo" "(${banned:-0} IPs banidos)"
    else
        log_result FAIL "Jail sshd ativo" "(jail não encontrado)"
    fi
}

check_crowdsec() {
    section "CrowdSec"

    if ! command -v cscli &>/dev/null; then
        log_result WARN "CrowdSec instalado" "(não encontrado — opcional)"
        return
    fi
    log_result PASS "CrowdSec instalado"

    if systemctl is-active --quiet crowdsec 2>/dev/null; then
        log_result PASS "CrowdSec serviço ativo"
    else
        log_result FAIL "CrowdSec serviço ativo" "(serviço parado)"
    fi

    # Bouncer iptables
    if systemctl is-active --quiet crowdsec-firewall-bouncer 2>/dev/null; then
        local blocked
        blocked=$(cscli decisions list 2>/dev/null | grep -c "ban" || echo 0)
        log_result PASS "Bouncer iptables ativo" "(${blocked} IPs bloqueados)"
    else
        log_result FAIL "Bouncer iptables ativo" "(serviço parado — IPs não estão sendo bloqueados)"
    fi

    # Collections
    for col in "crowdsecurity/linux" "crowdsecurity/traefik" "crowdsecurity/nginx"; do
        if cscli collections list 2>/dev/null | grep -q "$col"; then
            log_result PASS "Collection: $col"
        else
            log_result WARN "Collection: $col" "(não instalada)"
        fi
    done
}

check_auditd() {
    section "Auditd"

    if ! command -v auditctl &>/dev/null; then
        log_result WARN "Auditd instalado" "(não encontrado — opcional)"
        return
    fi
    log_result PASS "Auditd instalado"

    if systemctl is-active --quiet auditd 2>/dev/null; then
        log_result PASS "Auditd serviço ativo"
    else
        log_result FAIL "Auditd serviço ativo" "(serviço parado)"
    fi

    # Regras ativas
    local rule_count
    rule_count=$(auditctl -l 2>/dev/null | grep -v "^No rules" | grep -c "." || echo 0)
    if [ "${rule_count:-0}" -gt 0 ]; then
        log_result PASS "Regras de auditoria ativas" "(${rule_count} regras)"
    else
        log_result WARN "Regras de auditoria" "(nenhuma regra carregada)"
    fi
}

check_docker() {
    section "Docker"

    if ! command -v docker &>/dev/null; then
        log_result WARN "Docker instalado" "(não encontrado — opcional)"
        return
    fi
    log_result PASS "Docker instalado"

    if systemctl is-active --quiet docker 2>/dev/null; then
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "desconhecido")
        log_result PASS "Docker serviço ativo" "(v${docker_version})"
    else
        log_result FAIL "Docker serviço ativo" "(serviço parado)"
    fi

    # Porta Docker NÃO exposta publicamente (2375/2376)
    if ss -tlnp 2>/dev/null | grep -q ":2375\|:2376"; then
        log_result FAIL "Docker API não exposta" "(porta 2375/2376 aberta — risco crítico!)"
    else
        log_result PASS "Docker API não exposta publicamente"
    fi
}

check_netdata() {
    section "Netdata (Monitoramento)"

    if ! command -v docker &>/dev/null; then
        log_result WARN "Netdata" "(Docker não instalado — pulando)"
        return
    fi

    if docker ps 2>/dev/null | grep -q "netdata"; then
        local uptime
        uptime=$(docker inspect netdata --format '{{.State.StartedAt}}' 2>/dev/null | cut -c1-19 || echo "desconhecido")
        log_result PASS "Container Netdata rodando" "(iniciado: ${uptime})"
    elif docker ps -a 2>/dev/null | grep -q "netdata"; then
        log_result FAIL "Container Netdata" "(existe mas está parado — execute: cd /opt/netdata && docker compose up -d)"
    else
        log_result WARN "Container Netdata" "(não encontrado — opcional)"
        return
    fi

    # Porta 19999 NÃO deve estar pública (UFW deve bloquear)
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
    if [ -n "$ts_ip" ]; then
        log_result PASS "Netdata acessível via Tailscale" "(http://${ts_ip}:19999)"
    fi

    # Verificar se docker-compose.yml existe
    if [ -f /opt/netdata/docker-compose.yml ]; then
        log_result PASS "Netdata compose file" "(/opt/netdata/docker-compose.yml)"
    else
        log_result WARN "Netdata compose file" "(não encontrado em /opt/netdata/)"
    fi
}

check_logging() {
    section "Logging do Sistema"

    # Journald limite
    local journald_max
    journald_max=$(grep "^SystemMaxUse=" /etc/systemd/journald.conf 2>/dev/null | cut -d= -f2)
    if [ -n "$journald_max" ]; then
        log_result PASS "Journald limite configurado" "($journald_max)"
    else
        log_result WARN "Journald limite" "(SystemMaxUse não configurado — pode encher disco)"
    fi

    # Rsyslog ativo
    if systemctl is-active --quiet rsyslog 2>/dev/null; then
        log_result PASS "Rsyslog ativo"
    else
        log_result WARN "Rsyslog" "(não ativo)"
    fi
}

check_security_exposure() {
    section "Exposição de Portas (verificação extra)"

    # Portas escutando em 0.0.0.0 que não deveriam estar
    local exposed_ports
    exposed_ports=$(ss -tlnp 2>/dev/null | grep "0.0.0.0:\|:::"\
        | grep -v "127.0.0.1\|tailscale\|:80 \|:443 " \
        | awk '{print $4}' | sort -u)

    if [ -n "$exposed_ports" ]; then
        while IFS= read -r port; do
            local port_num="${port##*:}"
            # Ignorar portas esperadas
            case "$port_num" in
                80|443) continue ;;
            esac
            log_result WARN "Porta exposta publicamente" "($port — verifique se é intencional)"
        done <<< "$exposed_ports"
    else
        log_result PASS "Nenhuma porta inesperada exposta publicamente"
    fi

    # Verificar se SSH está escutando em IP público
    local public_ip
    public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
    if [ -n "$public_ip" ]; then
        local ssh_port
        ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
        if ss -tlnp 2>/dev/null | grep ":${ssh_port}" | grep -q "$public_ip\|0\.0\.0\.0"; then
            log_result FAIL "SSH exposto no IP público" "(IP: $public_ip porta: $ssh_port)"
        else
            log_result PASS "SSH não exposto no IP público" "(IP público: $public_ip)"
        fi
    else
        log_result WARN "Verificação IP público" "(não foi possível obter IP público)"
    fi
}

# ════════════════════════════════════════════════════════
# RELATÓRIO FINAL
# ════════════════════════════════════════════════════════

show_report() {
    local end_time
    end_time=$(date '+%Y-%m-%d %H:%M:%S')

    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  RELATÓRIO DE AUDITORIA — $end_time${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""

    local score=$((PASS * 100 / TOTAL))

    printf "  ${COLOR_GREEN}✅ PASS${COLOR_RESET}  %d/%d verificações\n" "$PASS" "$TOTAL"
    printf "  ${COLOR_RED}❌ FAIL${COLOR_RESET}  %d verificações críticas\n" "$FAIL"
    printf "  ${COLOR_YELLOW}⚠️  WARN${COLOR_RESET}  %d avisos (opcionais/menores)\n" "$WARN"
    echo ""

    # Score visual
    printf "  Score: ${COLOR_BOLD}"
    if [ "$score" -ge 90 ]; then
        printf "${COLOR_GREEN}%d%% — Excelente${COLOR_RESET}\n" "$score"
    elif [ "$score" -ge 75 ]; then
        printf "${COLOR_YELLOW}%d%% — Bom (revise os FAILs)${COLOR_RESET}\n" "$score"
    else
        printf "${COLOR_RED}%d%% — Atenção (corrija os FAILs antes de ir para produção)${COLOR_RESET}\n" "$score"
    fi

    echo ""

    if [ "$FAIL" -gt 0 ]; then
        echo -e "  ${COLOR_RED}${COLOR_BOLD}Itens críticos que precisam correção:${COLOR_RESET}"
        grep "^\[FAIL\]" "$AUDIT_LOG" | sed 's/\[FAIL\]/  ❌/' | head -20
        echo ""
    fi

    echo -e "  📄 Log completo salvo em: ${COLOR_CYAN}$AUDIT_LOG${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"

    # Salvar resumo no log
    {
        echo ""
        echo "════════════════════════════════════════════════════════"
        echo "RESUMO: PASS=$PASS FAIL=$FAIL WARN=$WARN TOTAL=$TOTAL SCORE=${score}%"
        echo "════════════════════════════════════════════════════════"
    } >> "$AUDIT_LOG"
}

# ════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════

main() {
    check_root

    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  🔍 Auditoria de Segurança — VPS Ubuntu${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  $(date '+%Y-%m-%d %H:%M:%S') | $(hostname)${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"

    {
        echo "════════════════════════════════════════════════════════"
        echo "AUDITORIA: $(date '+%Y-%m-%d %H:%M:%S') | $(hostname)"
        echo "════════════════════════════════════════════════════════"
    } > "$AUDIT_LOG"

    check_system
    check_kernel
    check_kernel_modules
    check_ssh
    check_tailscale
    check_firewall
    check_fail2ban
    check_crowdsec
    check_auditd
    check_docker
    check_netdata
    check_logging
    check_security_exposure

    show_report

    # Exit code reflete resultado
    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"
