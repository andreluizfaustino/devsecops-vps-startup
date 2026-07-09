#!/bin/bash
# ════════════════════════════════════════════════════════
# Docker Install + DOCKER-USER Firewall
# Version: 2.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
#
# O que faz:
#   1) Instala Docker Engine via repositório oficial apt
#   2) Cria script /usr/local/bin/docker-user-firewall.sh
#   3) Cria e habilita serviço systemd para persistência das regras
#
# Pré-requisitos:
#   - Ubuntu 22.04 LTS ou 24.04 LTS
#   - 01-startup.sh já executado (UFW + Tailscale ativos)
#
# Uso: sudo bash 02-docker.sh
# ════════════════════════════════════════════════════════

set -euo pipefail

# ════════════════════════════════════════════════════════
# CORES E FUNÇÕES
# ════════════════════════════════════════════════════════

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'
COLOR_BLUE='\033[0;34m'

log_info()    { echo -e "${COLOR_CYAN}ℹ ${COLOR_RESET}$*"; }
log_success() { echo -e "${COLOR_GREEN}✅${COLOR_RESET} $*"; }
log_warn()    { echo -e "${COLOR_YELLOW}⚠️  ${COLOR_RESET}$*"; }
log_error()   { echo -e "${COLOR_RED}❌${COLOR_RESET} $*"; }
log_phase()   { echo -e "\n${COLOR_BOLD}${COLOR_BLUE}═══ $*${COLOR_RESET}\n"; }

# ════════════════════════════════════════════════════════
# VERIFICAÇÕES INICIAIS
# ════════════════════════════════════════════════════════

if [ "$EUID" -ne 0 ]; then
    log_error "Execute como root: sudo bash 02-docker.sh"
    exit 1
fi

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}  Docker Install + DOCKER-USER Firewall${COLOR_RESET}"
echo -e "${COLOR_BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

# ════════════════════════════════════════════════════════
# ETAPA 1: INSTALAR DOCKER
# ════════════════════════════════════════════════════════

log_phase "Etapa 1/3: Docker Engine"

if command -v docker &>/dev/null && docker info &>/dev/null; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "desconhecido")
    log_success "Docker já instalado (v${DOCKER_VERSION}) — pulando instalação"
else
    echo ""
    read -p "  Deseja instalar o Docker Engine agora? [S/n]: " install_confirm
    install_confirm="${install_confirm:-S}"

    if [[ ! "$install_confirm" =~ ^[Ss]$ ]]; then
        log_warn "Instalação do Docker ignorada pelo usuário."
        log_warn "O Docker é necessário para as próximas etapas. Instale manualmente e rode o script novamente."
        exit 0
    fi

    log_info "Adicionando repositório oficial do Docker..."

    apt update -qq
    apt install -y -qq ca-certificates curl

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt update -qq

    log_info "Instalando pacotes Docker..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    if ! docker info &>/dev/null; then
        log_error "Docker instalado mas não está respondendo"
        log_info  "  Verifique: systemctl status docker"
        exit 1
    fi

    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "desconhecido")
    log_success "Docker Engine v${DOCKER_VERSION} rodando"
fi

# ────────────────────────────────────────────────────────
# daemon.json — bind padrão em 127.0.0.1
# Impede que containers sem bind explícito exponham portas ao mundo
# ────────────────────────────────────────────────────────
log_info "Configurando daemon.json (bind padrão = 127.0.0.1)..."

cat > /etc/docker/daemon.json << 'DAEMON_JSON'
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON_JSON

systemctl restart docker
sleep 3

if docker info &>/dev/null; then
    log_success "daemon.json aplicado — bind padrão: 127.0.0.1"
    log_info    "  • Containers sem bind explícito: só acessíveis via localhost"
    log_info    "  • Traefik (80/443): bind explícito para 0.0.0.0 (público)"
else
    log_error "Docker não respondeu após aplicar daemon.json"
    exit 1
fi

log_info "Status do serviço Docker:"
systemctl status docker --no-pager -l

# ════════════════════════════════════════════════════════
# ETAPA 2: CRIAR SCRIPT DOCKER-USER FIREWALL
# ════════════════════════════════════════════════════════

log_phase "Etapa 2/3: Script docker-user-firewall"

log_info "Criando /usr/local/bin/docker-user-firewall.sh..."

cat > /usr/local/bin/docker-user-firewall.sh <<'EOF'
#!/bin/bash
set -e

IFACE_PUBLIC="eth0"
IFACE_TAILSCALE="tailscale0"

# Limpa as chains antes de reaplicar (evita duplicar regras em restarts)
iptables  -F DOCKER-USER
ip6tables -F DOCKER-USER 2>/dev/null || true

# 1. Permite respostas a conexões já estabelecidas
iptables  -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

# 2. Libera tudo via Tailscale VPN
iptables  -A DOCKER-USER -i "$IFACE_TAILSCALE" -j ACCEPT
ip6tables -A DOCKER-USER -i "$IFACE_TAILSCALE" -j ACCEPT 2>/dev/null || true

# 3. Libera 80/443 apenas para IPs da Cloudflare (lidos do UFW)
#    IPv4 → iptables | IPv6 → ip6tables
#    Fallback: abre para todos se o 03-cloudflare-update-ufw.sh ainda não foi executado
CF_IPS=$(ufw status 2>/dev/null | grep -i 'Cloudflare' | awk '{print $3}' | grep -E '^[0-9a-fA-F]' | sort -u || true)

if [ -n "$CF_IPS" ]; then
    while IFS= read -r cf_ip; do
        [ -z "$cf_ip" ] && continue
        if echo "$cf_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]'; then
            ipt="iptables"
        else
            ipt="ip6tables"
        fi
        $ipt -A DOCKER-USER -i "$IFACE_PUBLIC" -s "$cf_ip" -p tcp --dport 80  -j ACCEPT 2>/dev/null || true
        $ipt -A DOCKER-USER -i "$IFACE_PUBLIC" -s "$cf_ip" -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    done <<< "$CF_IPS"
else
    # Fallback: 03-cloudflare-update-ufw.sh ainda não foi executado
    iptables -A DOCKER-USER -i "$IFACE_PUBLIC" -p tcp --dport 80  -j ACCEPT
    iptables -A DOCKER-USER -i "$IFACE_PUBLIC" -p tcp --dport 443 -j ACCEPT
fi

# 4. Bloqueia todo o resto vindo da internet
iptables  -A DOCKER-USER -i "$IFACE_PUBLIC" -j DROP
ip6tables -A DOCKER-USER -i "$IFACE_PUBLIC" -j DROP 2>/dev/null || true

# 5. Devolve fluxo interno entre containers
iptables  -A DOCKER-USER -j RETURN
ip6tables -A DOCKER-USER -j RETURN 2>/dev/null || true
EOF

chmod +x /usr/local/bin/docker-user-firewall.sh
log_success "Script criado: /usr/local/bin/docker-user-firewall.sh"

# ════════════════════════════════════════════════════════
# ETAPA 3: SERVIÇO SYSTEMD + ATIVAÇÃO
# ════════════════════════════════════════════════════════

log_phase "Etapa 3/3: Serviço systemd + ativação"

log_info "Criando /etc/systemd/system/docker-user-firewall.service..."

cat > /etc/systemd/system/docker-user-firewall.service <<'EOF'
[Unit]
Description=Reaplica regras da chain DOCKER-USER
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/docker-user-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

log_success "Serviço criado"

log_info "Habilitando e iniciando serviço..."
systemctl daemon-reload
systemctl enable docker-user-firewall.service
systemctl start docker-user-firewall.service

if systemctl is-active --quiet docker-user-firewall.service; then
    log_success "Serviço docker-user-firewall ativo e habilitado no boot"
else
    log_error "Serviço não iniciou corretamente"
    log_info  "  Verifique: journalctl -u docker-user-firewall.service -n 30"
    exit 1
fi

echo ""
log_info "Regras ativas na chain DOCKER-USER:"
iptables -L DOCKER-USER -n -v --line-numbers

# ════════════════════════════════════════════════════════
# RESUMO FINAL
# ════════════════════════════════════════════════════════

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_GREEN}  ✅ Docker + DOCKER-USER Firewall configurados!${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo "  🐳 Docker Engine v$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'desconhecido')"
echo ""
echo "  🔒 DOCKER-USER — regras aplicadas:"
echo "    ✅ ESTABLISHED,RELATED → ACCEPT"
echo "    ✅ tailscale0 → ACCEPT"
echo "    ✅ eth0 TCP :80 → ACCEPT"
echo "    ✅ eth0 TCP :443 → ACCEPT"
echo "    ❌ eth0 → DROP"
echo "    ↩  RETURN"
echo ""
echo "  ⚙️  Persistência: docker-user-firewall.service (ativo no boot)"
echo ""
echo "  📋 Comandos úteis:"
echo "    • Ver regras     : iptables -L DOCKER-USER -n -v"
echo "    • Logs do serviço: journalctl -u docker-user-firewall.service -f"
echo "    • Reaplicar      : systemctl restart docker-user-firewall.service"
echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_YELLOW}Próximo passo: bash 03-cloudflare-update-ufw.sh${COLOR_RESET}"
echo ""
