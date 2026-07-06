#!/bin/bash
# ════════════════════════════════════════════════════════
# Traefik v3 + Portainer CE Setup
# Version: 1.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
#
# Instala Traefik v3 como reverse proxy com Let's Encrypt automático
# e Portainer CE para gerenciamento de containers Docker.
#
# Pré-requisitos:
#   - Docker instalado (rode 02-docker-and-netdata.sh antes)
#   - Cloudflare proxy ativo (nuvem laranja) nos domínios
#   - Cloudflare SSL/TLS: Full (Strict)
#
# Uso: sudo bash 04-traefik-and-portainer.sh
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
    log_error "Execute como root: sudo bash 04-traefik-and-portainer.sh"
    exit 1
fi

if ! command -v docker &>/dev/null || ! docker info &>/dev/null; then
    log_error "Docker não encontrado ou não está rodando."
    log_info  "  Execute primeiro: bash 02-docker-and-netdata.sh"
    exit 1
fi

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}  Traefik v3 + Portainer CE Setup${COLOR_RESET}"
echo -e "${COLOR_BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

# ════════════════════════════════════════════════════════
# CONFIGURAÇÃO INTERATIVA
# ════════════════════════════════════════════════════════

log_phase "Configuração"

# Email para Let's Encrypt
while true; do
    read -p "  Email para Let's Encrypt (notificações de expiração): " LE_EMAIL
    if [[ "$LE_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_success "Email: $LE_EMAIL"
        break
    else
        log_error "Email inválido. Tente novamente."
    fi
done
echo ""

# Detectar IP do Tailscale
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
if [ -z "$TAILSCALE_IP" ]; then
    log_warn "Tailscale não conectado — dashboard acessível em qualquer IP (via UFW)"
    TAILSCALE_IP="SEU_IP_TAILSCALE"
fi

# ════════════════════════════════════════════════════════
# ETAPA 1: REDE DOCKER COMPARTILHADA
# ════════════════════════════════════════════════════════

log_phase "Etapa 1/3: Rede Docker compartilhada"

if docker network inspect traefik_public &>/dev/null; then
    log_info "Rede 'traefik_public' já existe — pulando"
else
    docker network create traefik_public
    log_success "Rede 'traefik_public' criada"
fi
log_info "  Todos os serviços que precisam de rota HTTP devem usar esta rede"

# ════════════════════════════════════════════════════════
# ETAPA 2: TRAEFIK
# ════════════════════════════════════════════════════════

log_phase "Etapa 2/3: Traefik v3"

TRAEFIK_DIR="/opt/traefik"
mkdir -p "${TRAEFIK_DIR}/dynamic"
mkdir -p "${TRAEFIK_DIR}/logs"

# acme.json — armazena certificados Let's Encrypt (deve ser 600)
touch "${TRAEFIK_DIR}/acme.json"
chmod 600 "${TRAEFIK_DIR}/acme.json"
log_success "acme.json criado (chmod 600)"

# ────────────────────────────────────────────────────────
# traefik.yml — configuração estática
# ────────────────────────────────────────────────────────
cat > "${TRAEFIK_DIR}/traefik.yml" << EOF
# ════════════════════════════════════════════════════════
# Traefik v3 — Configuração Estática
# ════════════════════════════════════════════════════════

# API e Dashboard (acessível via Tailscale:8080)
api:
  dashboard: true
  insecure: true

# Entry Points
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"
    forwardedHeaders:
      # Confiar nos IPs da Cloudflare para obter o IP real do visitante
      # Traefik lerá X-Forwarded-For / CF-Connecting-IP dessas origens
      trustedIPs:
        # Cloudflare IPv4
        - "173.245.48.0/20"
        - "103.21.244.0/22"
        - "103.22.200.0/22"
        - "103.31.4.0/22"
        - "141.101.64.0/18"
        - "108.162.192.0/18"
        - "190.93.240.0/20"
        - "188.114.96.0/20"
        - "197.234.240.0/22"
        - "198.41.128.0/17"
        - "162.158.0.0/15"
        - "104.16.0.0/13"
        - "104.24.0.0/14"
        - "172.64.0.0/13"
        - "131.0.72.0/22"
        # Cloudflare IPv6
        - "2400:cb00::/32"
        - "2606:4700::/32"
        - "2803:f800::/32"
        - "2405:b500::/32"
        - "2405:8100::/32"
        - "2a06:98c0::/29"
        - "2c0f:f248::/32"

# Let's Encrypt — HTTP-01 challenge via Cloudflare proxy
certificatesResolvers:
  letsencrypt:
    acme:
      email: "${LE_EMAIL}"
      storage: /acme.json
      httpChallenge:
        entryPoint: web

# Docker provider — detecta containers automaticamente via labels
providers:
  docker:
    exposedByDefault: false
    network: traefik_public
    watch: true
  file:
    directory: /etc/traefik/dynamic
    watch: true

# Logs
log:
  level: INFO
  filePath: /var/log/traefik/traefik.log

accessLog:
  filePath: /var/log/traefik/access.log
  fields:
    headers:
      names:
        # Log o IP real do visitante (passado pela Cloudflare)
        CF-Connecting-IP: keep
        X-Forwarded-For: keep
        X-Real-IP: keep
EOF

log_success "traefik.yml gerado"

# ────────────────────────────────────────────────────────
# docker-compose.yml — Traefik
# ────────────────────────────────────────────────────────
cat > "${TRAEFIK_DIR}/docker-compose.yml" << 'TRAEFIK_COMPOSE'
services:
  traefik:
    image: traefik:v3
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"    # Dashboard — protegido pelo UFW (só Tailscale acessa)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - ./acme.json:/acme.json
      - ./logs:/var/log/traefik
    networks:
      - traefik_public
    labels:
      - "traefik.enable=false"    # Dashboard não roteado via Traefik (acesso direto porta 8080)

networks:
  traefik_public:
    external: true
TRAEFIK_COMPOSE

log_success "docker-compose.yml do Traefik gerado"

# Subir Traefik
log_info "Iniciando Traefik..."
cd "${TRAEFIK_DIR}" && docker compose up -d

sleep 5

if docker ps 2>/dev/null | grep -q "traefik"; then
    TRAEFIK_VERSION=$(docker exec traefik traefik version 2>/dev/null | head -1 || echo "v3")
    log_success "Traefik rodando — ${TRAEFIK_VERSION}"
else
    log_error "Traefik não iniciou. Verifique: docker compose -f ${TRAEFIK_DIR}/docker-compose.yml logs"
    exit 1
fi

# ════════════════════════════════════════════════════════
# ETAPA 3: PORTAINER
# ════════════════════════════════════════════════════════

log_phase "Etapa 3/3: Portainer CE"

PORTAINER_DIR="/opt/portainer"
mkdir -p "${PORTAINER_DIR}"

cat > "${PORTAINER_DIR}/docker-compose.yml" << 'PORTAINER_COMPOSE'
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"    # UI — protegido pelo UFW (só Tailscale acessa)
      - "9443:9443"    # UI HTTPS (opcional)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data

volumes:
  portainer_data: {}
PORTAINER_COMPOSE

log_info "Iniciando Portainer..."
cd "${PORTAINER_DIR}" && docker compose up -d

sleep 5

if docker ps 2>/dev/null | grep -q "portainer"; then
    log_success "Portainer rodando"
else
    log_error "Portainer não iniciou. Verifique: docker compose -f ${PORTAINER_DIR}/docker-compose.yml logs"
    exit 1
fi

# ════════════════════════════════════════════════════════
# RESUMO FINAL
# ════════════════════════════════════════════════════════

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_GREEN}  ✅ Traefik + Portainer instalados com sucesso!${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD}Acesso (via Tailscale — protegido pelo UFW):${COLOR_RESET}"
echo -e "    Traefik dashboard: ${COLOR_CYAN}http://${TAILSCALE_IP}:8080/dashboard/${COLOR_RESET}"
echo -e "    Portainer:         ${COLOR_CYAN}http://${TAILSCALE_IP}:9000${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD}Let's Encrypt:${COLOR_RESET}"
echo -e "    Email:     ${LE_EMAIL}"
echo -e "    Método:    HTTP-01 via Cloudflare proxy"
echo -e "    Storage:   ${TRAEFIK_DIR}/acme.json"
echo -e "    Renovação: automática (Traefik gerencia)"
echo ""
echo -e "  ${COLOR_BOLD}Configuração do Traefik:${COLOR_RESET}"
echo -e "    Diretório: ${TRAEFIK_DIR}/"
echo -e "    Config:    ${TRAEFIK_DIR}/traefik.yml"
echo -e "    Dinâmica:  ${TRAEFIK_DIR}/dynamic/"
echo -e "    Logs:      ${TRAEFIK_DIR}/logs/"
echo ""
echo -e "  ${COLOR_BOLD}Rede Docker compartilhada:${COLOR_RESET}"
echo -e "    traefik_public  ← todos os serviços expostos devem usar esta rede"
echo ""
echo -e "  ${COLOR_BOLD}Como expor um serviço via Traefik (labels no docker-compose):${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}networks:${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}  - traefik_public${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}labels:${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}  - \"traefik.enable=true\"${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}  - \"traefik.http.routers.NOME.rule=Host(\`dominio.com\`)\"${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}  - \"traefik.http.routers.NOME.tls.certresolver=letsencrypt\"${COLOR_RESET}"
echo -e "    ${COLOR_YELLOW}  - \"traefik.http.services.NOME.loadbalancer.server.port=PORTA_INTERNA\"${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_BOLD}Comandos úteis:${COLOR_RESET}"
echo -e "    docker compose -f ${TRAEFIK_DIR}/docker-compose.yml logs -f"
echo -e "    docker compose -f ${PORTAINER_DIR}/docker-compose.yml logs -f"
echo -e "    docker exec traefik traefik version"
echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
