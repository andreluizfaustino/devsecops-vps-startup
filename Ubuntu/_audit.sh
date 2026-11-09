#!/bin/bash
# ════════════════════════════════════════════════════════
# Auditoria de Segurança — VPS Ubuntu
# Version: 2.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
#
# Uso: sudo bash _audit.sh
# Rode após o 01-startup.sh + reboot, e de tempos em tempos.
# Somente leitura: não altera nada no servidor.
# ════════════════════════════════════════════════════════

set -uo pipefail

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
DOCKER_PRESENT=0

# ════════════════════════════════════════════════════════
# OUTPUT
# ════════════════════════════════════════════════════════

log_result() {
    local status="$1" check="$2" detail="${3:-}"
    TOTAL=$((TOTAL + 1))
    case "$status" in
        PASS) PASS=$((PASS + 1)); printf "  ${COLOR_GREEN}✅ PASS${COLOR_RESET}  %-46s %s\n" "$check" "$detail" ;;
        FAIL) FAIL=$((FAIL + 1)); printf "  ${COLOR_RED}❌ FAIL${COLOR_RESET}  %-46s %s\n" "$check" "$detail" ;;
        WARN) WARN=$((WARN + 1)); printf "  ${COLOR_YELLOW}⚠️  WARN${COLOR_RESET}  %-46s %s\n" "$check" "$detail" ;;
    esac
    echo "[$status] $check $detail" >> "$AUDIT_LOG"
}

section() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_BLUE}── $1 ${COLOR_RESET}"
    printf '\n## %s\n' "$1" >> "$AUDIT_LOG"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${COLOR_RED}❌ Execute como root: sudo bash _audit.sh${COLOR_RESET}"
        exit 1
    fi
}

# Lê um campo do /etc/docker/daemon.json (vazio se não existir)
daemon_json() {
    python3 -c "import json,sys; d=json.load(open('/etc/docker/daemon.json')); v=d.get(sys.argv[1], ''); print(str(v).lower() if isinstance(v, bool) else v)" "$1" 2>/dev/null
}

# ════════════════════════════════════════════════════════
# VERIFICAÇÕES
# ════════════════════════════════════════════════════════

check_system() {
    section "Sistema"

    # shellcheck disable=SC1091
    . /etc/os-release
    case "${VERSION_ID:-}" in
        24.04|26.04) log_result PASS "Ubuntu suportado" "($PRETTY_NAME)" ;;
        *)           log_result WARN "Ubuntu suportado" "($PRETTY_NAME — testado em 24.04/26.04)" ;;
    esac

    local tz
    tz=$(timedatectl show --property=Timezone --value 2>/dev/null)
    if [ "$tz" = "America/Sao_Paulo" ]; then
        log_result PASS "Timezone" "($tz)"
    else
        log_result WARN "Timezone" "(atual: ${tz:-?}, esperado: America/Sao_Paulo)"
    fi

    if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q yes; then
        log_result PASS "NTP sincronizado"
    else
        log_result WARN "NTP sincronizado" "(pode levar alguns minutos após o boot)"
    fi

    local swap_mb swappiness
    swap_mb=$(free -m | awk '/^Swap:/ {print $2}')
    swappiness=$(sysctl -n vm.swappiness 2>/dev/null)
    if [ "${swap_mb:-0}" -gt 0 ]; then
        log_result PASS "SWAP ativo" "(${swap_mb} MB, swappiness=${swappiness})"
    else
        log_result FAIL "SWAP ativo" "(nenhum swap)"
    fi

    if dpkg -s unattended-upgrades &>/dev/null && \
       grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
        log_result PASS "Atualizações automáticas de segurança"
    else
        log_result FAIL "Atualizações automáticas de segurança" "(unattended-upgrades inativo)"
    fi

    if apt-config dump 2>/dev/null | grep -q 'Unattended-Upgrade::Automatic-Reboot "true"'; then
        log_result WARN "Reboot automático" "(ativo — o padrão do projeto é nunca reiniciar sozinho)"
    else
        log_result PASS "Reboot automático desativado"
    fi

    if [ -f /var/run/reboot-required ]; then
        local pkgs
        pkgs=$(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)
        log_result WARN "Reboot pendente" "(atualizações esperando reinício: ${pkgs:-kernel})"
    else
        log_result PASS "Nenhum reboot pendente"
    fi
}

check_sysctl() {
    section "Kernel e Rede (sysctl)"

    local params=(
        "kernel.dmesg_restrict:1"
        "kernel.kptr_restrict:2"
        "fs.suid_dumpable:0"
        "net.ipv4.tcp_syncookies:1"
        "net.ipv4.tcp_rfc1337:1"
        "net.ipv4.tcp_synack_retries:2"
        "net.ipv4.conf.all.rp_filter:1"
        "net.ipv4.conf.all.accept_redirects:0"
        "net.ipv4.conf.all.secure_redirects:0"
        "net.ipv4.conf.all.send_redirects:0"
        "net.ipv4.conf.all.accept_source_route:0"
        "net.ipv6.conf.all.accept_redirects:0"
        "net.ipv6.conf.all.accept_source_route:0"
        "net.ipv4.icmp_echo_ignore_broadcasts:1"
        "net.ipv4.icmp_ignore_bogus_error_responses:1"
        "net.core.somaxconn:4096"
        "net.ipv4.tcp_max_syn_backlog:8192"
        "net.ipv4.tcp_tw_reuse:1"
        "fs.file-max:2097152"
        "fs.inotify.max_user_watches:524288"
        "vm.swappiness:10"
        "net.ipv4.ip_nonlocal_bind:1"
    )
    local param key expected actual
    for param in "${params[@]}"; do
        key="${param%%:*}"
        expected="${param##*:}"
        actual=$(sysctl -n "$key" 2>/dev/null)
        if [ "$actual" = "$expected" ]; then
            log_result PASS "$key" "(= $actual)"
        else
            log_result FAIL "$key" "(esperado: $expected, atual: ${actual:-não definido})"
        fi
    done

    # tcp_timestamps desligado anula o tcp_tw_reuse (config antiga do projeto)
    if [ "$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null)" = "0" ]; then
        log_result WARN "net.ipv4.tcp_timestamps" "(= 0 — anula tcp_tw_reuse; remova de /etc/sysctl.d)"
    else
        log_result PASS "net.ipv4.tcp_timestamps" "(ligado)"
    fi

    # ip_forward precisa ser 1 com Docker/Tailscale; alguém fixando 0 quebra a rede dos containers
    if grep -rqsE '^\s*net\.ipv4\.ip_forward\s*=\s*0' /etc/sysctl.conf /etc/sysctl.d/; then
        log_result FAIL "ip_forward fixado em 0" "(quebra Docker/Tailscale ao rodar sysctl --system)"
    else
        log_result PASS "ip_forward não fixado em 0"
    fi

    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$cc" = "bbr" ]; then
        log_result PASS "BBR congestion control"
    else
        log_result WARN "BBR congestion control" "(atual: ${cc:-?})"
    fi

    local ct_max
    ct_max=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)
    if [ "${ct_max:-0}" -ge 1048576 ]; then
        log_result PASS "Conntrack max" "(${ct_max})"
    else
        log_result WARN "Conntrack max" "(atual: ${ct_max:-módulo não carregado})"
    fi

    local nofile
    nofile=$(awk '$1=="*" && $2=="soft" && $3=="nofile" {print $4}' /etc/security/limits.d/90-hardening.conf 2>/dev/null)
    if [ "${nofile:-0}" -ge 1048576 ]; then
        log_result PASS "File descriptors" "(${nofile})"
    else
        log_result FAIL "File descriptors" "(limits.d/90-hardening.conf ausente)"
    fi
}

check_kernel_modules() {
    section "Módulos de Kernel Bloqueados"

    local conf=/etc/modprobe.d/blacklist-hardening.conf
    if [ ! -f "$conf" ]; then
        log_result FAIL "blacklist-hardening.conf" "(não encontrado)"
        return
    fi

    local mod
    for mod in dccp sctp rds tipc cramfs freevxfs jffs2 hfs hfsplus udf; do
        if grep -qE "^install[[:space:]]+${mod}[[:space:]]+/bin/(false|true)" "$conf"; then
            if lsmod | grep -q "^${mod} "; then
                log_result WARN "Módulo bloqueado: $mod" "(ainda carregado — reinicie)"
            else
                log_result PASS "Módulo bloqueado: $mod"
            fi
        else
            log_result FAIL "Módulo bloqueado: $mod" "(fora do blacklist)"
        fi
    done
}

check_ssh() {
    section "SSH"

    if systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log_result PASS "SSH ativo"
    else
        log_result FAIL "SSH ativo" "(parado!)"
    fi

    if [ -f /etc/ssh/sshd_config.d/00-hardening.conf ]; then
        log_result PASS "Configuração própria" "(sshd_config.d/00-hardening.conf)"
    else
        log_result WARN "Configuração própria" "(00-hardening.conf ausente — servidor configurado pela versão antiga?)"
    fi

    # Configuração EFETIVA (considera todos os arquivos e a ordem de leitura)
    local eff
    eff=$(sshd -T 2>/dev/null)
    if [ -z "$eff" ]; then
        log_result FAIL "sshd -T" "(configuração inválida)"
        return
    fi

    local pair key expected actual
    for pair in "passwordauthentication:no" "kbdinteractiveauthentication:no" "permitemptypasswords:no" \
                "pubkeyauthentication:yes" "permitrootlogin:no" "x11forwarding:no" "maxauthtries:3"; do
        key="${pair%%:*}"
        expected="${pair##*:}"
        actual=$(awk -v k="$key" '$1==k {print $2; exit}' <<< "$eff")
        if [ "$actual" = "$expected" ]; then
            log_result PASS "$key $expected"
        else
            log_result FAIL "$key $expected" "(atual: ${actual:-?})"
        fi
    done

    local allow
    allow=$(awk '$1=="allowusers" {$1=""; print substr($0,2)}' <<< "$eff" | tr '\n' ' ')
    if [ -n "$allow" ]; then
        log_result PASS "AllowUsers" "($allow)"
    else
        log_result WARN "AllowUsers" "(qualquer usuário pode tentar logar)"
    fi

    local listen
    listen=$(awk '$1=="listenaddress" {print $2}' <<< "$eff")
    if grep -qE '^(0\.0\.0\.0|\[::\]):' <<< "$listen"; then
        log_result FAIL "SSH só em IPs específicos" "(escuta em todos os IPs)"
    else
        log_result PASS "SSH só em IPs específicos" "($(echo "$listen" | tr '\n' ' '))"
    fi

    local kex
    kex=$(awk '$1=="kexalgorithms" {print $2}' <<< "$eff")
    if grep -qE 'mlkem768x25519|sntrup761x25519' <<< "$kex"; then
        log_result PASS "Kex pós-quântico" "($(cut -d, -f1 <<< "$kex"))"
    else
        log_result WARN "Kex pós-quântico" "(não habilitado)"
    fi

    local f others=""
    for f in /etc/ssh/sshd_config.d/*.conf; do
        [ -e "$f" ] || continue
        [ "$(basename "$f")" = "00-hardening.conf" ] && continue
        others="$others $(basename "$f")"
    done
    if [ -n "$others" ]; then
        log_result WARN "Outros arquivos em sshd_config.d" "(${others# } — confira se não reabilitam senha)"
    else
        log_result PASS "Sem overrides em sshd_config.d"
    fi

    if command -v fail2ban-client &>/dev/null && fail2ban-client get sshd bantime 2>/dev/null | grep -q '^-1$'; then
        log_result WARN "Fail2Ban com ban permanente" "(pode banir seu próprio IP do Tailscale)"
    fi
}

check_tailscale() {
    section "Tailscale"

    if ! command -v tailscale &>/dev/null; then
        log_result FAIL "Tailscale instalado" "(não encontrado — sem ele não há SSH)"
        return
    fi
    log_result PASS "Tailscale instalado" "($(tailscale version 2>/dev/null | head -n 1))"

    if systemctl is-active --quiet tailscaled; then
        log_result PASS "tailscaled ativo"
    else
        log_result FAIL "tailscaled ativo" "(parado)"
    fi

    local ip4
    ip4=$(tailscale ip -4 2>/dev/null | head -n 1)
    if [ -n "$ip4" ]; then
        log_result PASS "Tailscale conectado" "($ip4)"
    else
        log_result FAIL "Tailscale conectado" "(execute: sudo tailscale up)"
        return
    fi

    # Chave que expira = servidor sai da rede = SSH inacessível
    local expiry
    expiry=$(tailscale status --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('Self',{}).get('KeyExpiry',''))" 2>/dev/null)
    if [ -z "$expiry" ]; then
        log_result PASS "Expiração da chave desativada"
    else
        log_result FAIL "Expiração da chave" "(expira em $expiry — desative em login.tailscale.com/admin/machines)"
    fi
}

check_firewall() {
    section "Firewall UFW"

    if ! command -v ufw &>/dev/null; then
        log_result FAIL "UFW instalado" "(não encontrado)"
        return
    fi

    local status verbose
    status=$(ufw status 2>/dev/null)
    verbose=$(ufw status verbose 2>/dev/null)

    if grep -q "Status: active" <<< "$status"; then
        log_result PASS "UFW ativo"
    else
        log_result FAIL "UFW ativo" "(execute: ufw enable)"
        return
    fi

    if grep -q "Default: deny (incoming)" <<< "$verbose"; then
        log_result PASS "Política padrão: bloquear entrada"
    else
        log_result FAIL "Política padrão: bloquear entrada"
    fi

    if grep -q "^IPV6=yes" /etc/default/ufw 2>/dev/null; then
        log_result PASS "UFW com IPv6"
    else
        log_result FAIL "UFW com IPv6" "(/etc/default/ufw)"
    fi

    if grep -q "tailscale0" <<< "$status"; then
        log_result PASS "Tailscale liberado no UFW"
    else
        log_result FAIL "Tailscale liberado no UFW" "(sem isso o SSH não funciona)"
    fi

    # Nada além de 80/443 aberto para a internet (fora do Tailscale)
    local extra
    extra=$(grep -E "ALLOW IN" <<< "$status" | grep -v "tailscale0" | grep -vE "^(80|443)(/tcp)?( \(v6\))? " | grep -v "Cloudflare" || true)
    if [ -n "$extra" ]; then
        log_result WARN "Regras além de 80/443" "($(echo "$extra" | awk '{print $1}' | sort -u | tr '\n' ' '))"
    else
        log_result PASS "Internet: apenas 80/443"
    fi

    local cf_rules public_web
    cf_rules=$(grep -c "Cloudflare" <<< "$status" || true)
    public_web=$(grep -E "^(80|443)/tcp( \(v6\))? +ALLOW IN +Anywhere" <<< "$status" || true)
    if [ "${cf_rules:-0}" -gt 0 ] && [ -z "$public_web" ]; then
        log_result PASS "80/443 somente Cloudflare" "(${cf_rules} regras)"
        if systemctl is-enabled --quiet cloudflare-update-firewall.timer 2>/dev/null; then
            log_result PASS "Atualização automática dos IPs Cloudflare" "(timer semanal)"
        else
            log_result WARN "Atualização automática dos IPs Cloudflare" "(timer desativado)"
        fi
    elif [ -n "$public_web" ]; then
        log_result WARN "80/443 abertos para todos" "(Cloudflare-only: sudo /usr/local/bin/cloudflare-update-firewall.sh --force)"
    else
        log_result WARN "80/443" "(nenhuma regra — nenhum site acessível)"
    fi
}

check_docker() {
    section "Docker"

    if ! command -v docker &>/dev/null; then
        log_result PASS "Docker não instalado" "(seções de Docker ignoradas)"
        return
    fi
    DOCKER_PRESENT=1

    if systemctl is-active --quiet docker; then
        log_result PASS "Docker ativo" "(v$(docker version --format '{{.Server.Version}}' 2>/dev/null))"
    else
        log_result FAIL "Docker ativo" "(parado)"
    fi

    local ip nnp lr
    ip=$(daemon_json ip)
    nnp=$(daemon_json no-new-privileges)
    lr=$(daemon_json live-restore)
    [ "$ip" = "127.0.0.1" ] \
        && log_result PASS "Bind padrão 127.0.0.1" "(porta sem IP explícito não vaza)" \
        || log_result FAIL "Bind padrão 127.0.0.1" "(daemon.json ip='${ip:-}')"
    [ "$nnp" = "true" ] \
        && log_result PASS "no-new-privileges" \
        || log_result WARN "no-new-privileges" "(daemon.json)"
    [ "$lr" = "true" ] \
        && log_result PASS "live-restore" \
        || log_result WARN "live-restore" "(daemon.json)"

    if [ -n "$(daemon_json log-opts)" ]; then
        log_result PASS "Rotação de logs dos containers"
    else
        log_result WARN "Rotação de logs dos containers" "(logs podem encher o disco)"
    fi

    if ss -tlnH | awk '{print $4}' | grep -qE ':(2375|2376)$'; then
        log_result FAIL "API do Docker exposta" "(porta 2375/2376 — risco crítico)"
    else
        log_result PASS "API do Docker não exposta"
    fi

    local fwb
    fwb=$(daemon_json firewall-backend)
    if [ "$fwb" = "nftables" ]; then
        log_result FAIL "Backend de firewall do Docker" "(nftables: DOCKER-USER não existe, proteção inativa)"
    fi
}

check_docker_user() {
    [ "$DOCKER_PRESENT" -eq 1 ] || return 0
    section "Firewall dos Containers (DOCKER-USER)"

    if systemctl is-enabled --quiet docker-user-firewall.service 2>/dev/null && \
       systemctl is-active --quiet docker-user-firewall.service 2>/dev/null; then
        log_result PASS "docker-user-firewall.service ativo"
    else
        log_result FAIL "docker-user-firewall.service ativo" "(containers podem estar expostos!)"
    fi

    local rules
    rules=$(iptables -S DOCKER-USER 2>/dev/null)
    if [ -z "$rules" ]; then
        log_result FAIL "Chain DOCKER-USER" "(não existe)"
        return
    fi

    if grep -qE -- "-i [a-z0-9]+ -j DROP" <<< "$rules"; then
        log_result PASS "Internet → containers bloqueado" "(DROP na interface pública)"
    else
        log_result FAIL "Internet → containers bloqueado" "(sem regra DROP)"
    fi

    if grep -q -- "--ctorigdstport" <<< "$rules"; then
        log_result PASS "Regra usa a porta publicada" "(ctorigdstport)"
    elif grep -q -- "--dport" <<< "$rules"; then
        log_result FAIL "Regra usa a porta publicada" "(usa --dport: compara a porta interna do container)"
    fi

    local with_src
    with_src=$(grep -c -- "-s .*--ctorigdstport" <<< "$rules" || true)
    if [ "${with_src:-0}" -gt 0 ]; then
        log_result PASS "Containers 80/443 somente Cloudflare" "(${with_src} regras IPv4)"
    else
        log_result WARN "Containers 80/443" "(abertos para qualquer IP)"
    fi

    if ip6tables -S DOCKER-USER 2>/dev/null | grep -q -- "-j DROP"; then
        log_result PASS "DOCKER-USER IPv6"
    else
        log_result WARN "DOCKER-USER IPv6" "(sem regras IPv6 — ok se o Docker não usa IPv6)"
    fi

    # Containers publicando portas em todos os IPs além de 80/443
    local exposed
    exposed=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | tr ',' '\n' \
        | grep -E '(0\.0\.0\.0|\[::\]|:::):[0-9]+->' \
        | grep -vE '(0\.0\.0\.0|\[::\]|:::):(80|443)->' || true)
    if [ -n "$exposed" ]; then
        log_result WARN "Portas publicadas em 0.0.0.0" "(bloqueadas pelo DOCKER-USER, mas prefira o IP do Tailscale)"
        echo "$exposed" | sed 's/^/           /' | head -n 10
    else
        log_result PASS "Nenhuma porta extra publicada em 0.0.0.0"
    fi
}

check_logging() {
    section "Logs"

    local cfg max storage
    cfg=$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null)
    max=$(grep -E '^SystemMaxUse=' <<< "$cfg" | tail -n 1 | cut -d= -f2)
    storage=$(grep -E '^Storage=' <<< "$cfg" | tail -n 1 | cut -d= -f2)

    if [ -n "$max" ]; then
        log_result PASS "Journald com limite" "($max)"
    else
        log_result WARN "Journald com limite" "(SystemMaxUse não definido)"
    fi
    if [ "$storage" = "persistent" ] || [ -d /var/log/journal ]; then
        log_result PASS "Journald persistente"
    else
        log_result WARN "Journald persistente" "(logs somem no reboot)"
    fi
}

check_exposure() {
    section "Exposição Pública"

    local public_ip
    public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    [ -n "$public_ip" ] || public_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')

    local ssh_port
    ssh_port=$(sshd -T 2>/dev/null | awk '$1=="port" {print $2; exit}')
    ssh_port=${ssh_port:-22}

    if ss -tlnH | awk '{print $4}' | grep -qE "^(0\.0\.0\.0|\*|\[::\]|${public_ip//./\\.}):${ssh_port}$"; then
        log_result FAIL "SSH exposto no IP público" "($public_ip:$ssh_port)"
    else
        log_result PASS "SSH fora do IP público" "($public_ip)"
    fi

    # Serviços do host (não-Docker) escutando em todos os IPs fora 80/443 e DNS local
    local listeners
    listeners=$(ss -tlnpH 2>/dev/null | awk '{print $4, $6}' \
        | grep -E '^(0\.0\.0\.0|\*|\[::\]):' \
        | grep -vE '^[^ ]+:(80|443) ' \
        | grep -v 'docker-proxy' || true)
    if [ -n "$listeners" ]; then
        log_result WARN "Serviços do host em todos os IPs" "(bloqueados pelo UFW, mas confira)"
        echo "$listeners" | sed -E 's/users:\(\("([^"]+)".*/(\1)/' | awk '{print "           " $1, $2}' | sort -u | head -n 10
    else
        log_result PASS "Nenhum serviço do host exposto além de 80/443"
    fi
}

# ════════════════════════════════════════════════════════
# RELATÓRIO
# ════════════════════════════════════════════════════════

show_report() {
    local score=0
    [ "$TOTAL" -gt 0 ] && score=$((PASS * 100 / TOTAL))

    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  RESULTADO — $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    printf "  ${COLOR_GREEN}✅ PASS${COLOR_RESET}  %d/%d\n" "$PASS" "$TOTAL"
    printf "  ${COLOR_RED}❌ FAIL${COLOR_RESET}  %d (corrigir)\n" "$FAIL"
    printf "  ${COLOR_YELLOW}⚠️  WARN${COLOR_RESET}  %d (avaliar)\n" "$WARN"
    echo ""
    if [ "$FAIL" -eq 0 ] && [ "$score" -ge 90 ]; then
        echo -e "  Score: ${COLOR_BOLD}${COLOR_GREEN}${score}% — Excelente${COLOR_RESET}"
    elif [ "$FAIL" -eq 0 ]; then
        echo -e "  Score: ${COLOR_BOLD}${COLOR_YELLOW}${score}% — Bom (revise os avisos)${COLOR_RESET}"
    else
        echo -e "  Score: ${COLOR_BOLD}${COLOR_RED}${score}% — Corrija os FAILs${COLOR_RESET}"
        echo ""
        grep "^\[FAIL\]" "$AUDIT_LOG" | sed 's/^\[FAIL\]/  ❌/' | head -n 20
    fi
    echo ""
    echo -e "  📄 Log: ${COLOR_CYAN}$AUDIT_LOG${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"

    echo "RESUMO: PASS=$PASS FAIL=$FAIL WARN=$WARN TOTAL=$TOTAL SCORE=${score}%" >> "$AUDIT_LOG"
}

main() {
    check_root

    echo ""
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  🔍 Auditoria de Segurança — $(hostname) — $(date '+%Y-%m-%d %H:%M')${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo "AUDITORIA: $(date '+%Y-%m-%d %H:%M:%S') | $(hostname)" > "$AUDIT_LOG"

    check_system
    check_sysctl
    check_kernel_modules
    check_ssh
    check_tailscale
    check_firewall
    check_docker
    check_docker_user
    check_logging
    check_exposure

    show_report
    [ "$FAIL" -eq 0 ]
}

main "$@"
