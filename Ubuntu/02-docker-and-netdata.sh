#!/bin/bash
# ════════════════════════════════════════════════════════
# Netdata Setup Script
# Version: 1.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
#
# Instala Docker (se necessário) e sobe o Netdata via Docker Compose.
#
# Uso: sudo bash netdata-setup.sh
# ════════════════════════════════════════════════════════

set -euo pipefail

# ════════════════════════════════════════════════════════
# CORES
# ════════════════════════════════════════════════════════

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'
COLOR_BLUE='\033[0;34m'

# ════════════════════════════════════════════════════════
# FUNÇÕES
# ════════════════════════════════════════════════════════

log_info()    { echo -e "${COLOR_CYAN}ℹ ${COLOR_RESET}$*"; }
log_success() { echo -e "${COLOR_GREEN}✅${COLOR_RESET} $*"; }
log_warn()    { echo -e "${COLOR_YELLOW}⚠️  ${COLOR_RESET}$*"; }
log_error()   { echo -e "${COLOR_RED}❌${COLOR_RESET} $*"; }
log_phase()   { echo -e "\n${COLOR_BOLD}${COLOR_BLUE}═══ $*${COLOR_RESET}\n"; }

# ════════════════════════════════════════════════════════
# VERIFICAÇÕES INICIAIS
# ════════════════════════════════════════════════════════

if [ "$EUID" -ne 0 ]; then
    log_error "Execute como root: sudo bash netdata-setup.sh"
    exit 1
fi

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}  Netdata Setup${COLOR_RESET}"
echo -e "${COLOR_BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

# ════════════════════════════════════════════════════════
# ETAPA 1: DOCKER
# ════════════════════════════════════════════════════════

log_phase "Etapa 1/3: Docker"

if command -v docker &>/dev/null && docker info &>/dev/null; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "desconhecido")
    log_success "Docker já instalado (v${DOCKER_VERSION}) — pulando instalação"
else
    log_info "Docker não encontrado. Instalando via script oficial..."

    if curl -fsSL https://get.docker.com | sh; then
        log_success "Docker instalado com sucesso"
    else
        log_error "Falha ao instalar Docker"
        exit 1
    fi

    systemctl enable docker
    systemctl start docker

    if ! docker info &>/dev/null; then
        log_error "Docker instalado mas não está respondendo"
        exit 1
    fi

    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "desconhecido")
    log_success "Docker Engine v${DOCKER_VERSION} rodando"

    # Adicionar usuário ubuntu ao grupo docker (se existir)
    if id ubuntu &>/dev/null; then
        usermod -aG docker ubuntu
        log_success "Usuário ubuntu adicionado ao grupo docker"
        log_info   "  ⚠️  Reconecte a sessão SSH para aplicar sem reboot"
    fi
fi

# Configurar daemon.json — regra master de segurança do Docker
# Faz todos os containers bindarem em 127.0.0.1 por padrão (não expoem portas externamente)
# Serviços públicos (Traefik) e Tailscale devem declarar bind explícito no docker-compose
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
    log_info    "  • Portainer/dashboards: bind explícito para IP Tailscale"
else
    log_error "Docker não respondeu após aplicar daemon.json"
    exit 1
fi

# ════════════════════════════════════════════════════════
# ETAPA 2: NETDATA
# ════════════════════════════════════════════════════════

log_phase "Etapa 2/3: Netdata"

NETDATA_DIR="/opt/netdata"
NETDATA_CONFIG_DIR="${NETDATA_DIR}/config"

log_info "Criando diretórios em ${NETDATA_DIR}..."
mkdir -p "${NETDATA_CONFIG_DIR}/go.d"

# Docker Compose — Netdata cobre host + Docker + Traefik em 1 container
    # Usa bind mount para /etc/netdata para permitir injetar configs
cat > "${NETDATA_DIR}/docker-compose.yml" << 'NETDATA_COMPOSE'
services:
  netdata:
    image: netdata/netdata:latest
    container_name: netdata
    restart: unless-stopped
    pid: host
    network_mode: host
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
      - NET_ADMIN
    security_opt:
      - apparmor:unconfined
    volumes:
      - ./config:/etc/netdata
      - netdata_lib:/var/lib/netdata
      - netdata_cache:/var/cache/netdata
      - /:/host/root:ro,rslave
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/os-release:/host/etc/os-release:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/run/fail2ban/fail2ban.sock:/var/run/fail2ban/fail2ban.sock:ro
    environment:
      - DOCKER_HOST=unix:///var/run/docker.sock

volumes:
  netdata_lib: {}
  netdata_cache: {}
NETDATA_COMPOSE

log_info "Subindo Netdata (download da imagem pode demorar)..."
cd "${NETDATA_DIR}" && docker compose up -d

sleep 8

if docker ps 2>/dev/null | grep -q "netdata"; then
    log_success "Container Netdata rodando"
else
    log_error "Netdata não iniciou corretamente"
    log_info  "  Verifique: docker compose -f ${NETDATA_DIR}/docker-compose.yml logs"
    exit 1
fi

# ════════════════════════════════════════════════════════
# ETAPA 3: INTEGRAÇÃO UFW/IPTABLES
# ════════════════════════════════════════════════════════

log_phase "Etapa 3/3: Integração UFW/iptables"

# Netdata coleta iptables via go.d — mostra pacotes bloqueados por chain/rule em tempo real
# Útil para ver volume de ataques sendo dropados pelo UFW
cat > "${NETDATA_CONFIG_DIR}/go.d/iptables.conf" << 'IPTABLES_CONF'
jobs:
  - name: filter
    tables:
      - name: filter
        chains:
          - INPUT
          - FORWARD
          - OUTPUT
IPTABLES_CONF

log_success "Config iptables criada (nota: Ubuntu 22.04+ usa nftables — Conntrack disponível em Network > Firewall)"

# ════════════════════════════════════════════════════════
# ETAPA 4b: INTEGRAÇÃO FAIL2BAN
# ════════════════════════════════════════════════════════

log_phase "Etapa 3b: Integração Fail2Ban"

# Configuração explícita do collector Fail2Ban
cat > "${NETDATA_CONFIG_DIR}/go.d/fail2ban.conf" << 'FAIL2BAN_CONF'
jobs:
  - name: local
    socket: /var/run/fail2ban/fail2ban.sock
FAIL2BAN_CONF

log_success "Config Fail2Ban criada em ${NETDATA_CONFIG_DIR}/go.d/fail2ban.conf"

# Reiniciar Netdata para aplicar
log_info "Reiniciando Netdata para aplicar integração Fail2Ban..."
docker restart netdata > /dev/null 2>&1
sleep 5

if docker ps 2>/dev/null | grep -q "netdata"; then
    log_success "Netdata reiniciado com integração Fail2Ban ativa"
else
    log_warn "Netdata não respondeu após reinício — verifique manualmente"
fi
# ════════════════════════════════════════════════════════

# Detectar IP do Tailscale para exibir URL de acesso
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "IP_TAILSCALE")

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_GREEN}  ✅ Netdata instalado com sucesso!${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD}Acesso (via Tailscale):${COLOR_RESET}"
echo -e "    http://${TAILSCALE_IP}:19999"
echo ""
echo -e "  ${COLOR_BOLD}Cobertura:${COLOR_RESET}"
echo -e "    ${COLOR_GREEN}✅${COLOR_RESET} Host: CPU, RAM, disco, rede, processos"
echo -e "    ${COLOR_GREEN}✅${COLOR_RESET} Docker: métricas de todos os containers"
echo -e "    ${COLOR_GREEN}✅${COLOR_RESET} Traefik: requests, latência, status codes (automático)"
echo -e "    ${COLOR_GREEN}✅${COLOR_RESET} Fail2Ban: bans ativos e jails (automático)"
echo -e "    ${COLOR_GREEN}✅${COLOR_RESET} UFW/iptables: pacotes bloqueados por chain em tempo real"
echo ""
echo -e "  ${COLOR_BOLD}Arquivos:${COLOR_RESET}"
echo -e "    • Compose:  ${NETDATA_DIR}/docker-compose.yml"
echo -e "    • Config:   ${NETDATA_CONFIG_DIR}/"
echo ""
echo -e "  ${COLOR_BOLD}Comandos úteis:${COLOR_RESET}"
echo -e "    docker compose -f ${NETDATA_DIR}/docker-compose.yml ps"
echo -e "    docker compose -f ${NETDATA_DIR}/docker-compose.yml logs -f"
echo -e "    docker restart netdata"
echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
