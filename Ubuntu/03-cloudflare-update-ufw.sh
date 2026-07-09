#!/bin/bash
# ════════════════════════════════════════════════════════
# Cloudflare UFW Updater
# Version: 1.0.0
# Author: @andreluizfaustino
# Repository: https://github.com/andreluizfaustino/devsecops-vps-startup
#
# Atualiza as regras do UFW com os IPs oficiais da Cloudflare.
# Mostra quais IPs serão adicionados e quais serão removidos
# antes de aplicar qualquer mudança.
#
# Uso: sudo bash cloudflare-update-ufw.sh
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

# ════════════════════════════════════════════════════════
# VERIFICAÇÕES INICIAIS
# ════════════════════════════════════════════════════════

if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_RED}❌ Execute como root: sudo bash cloudflare-update-ufw.sh${COLOR_RESET}"
    exit 1
fi

if ! command -v ufw &>/dev/null; then
    echo -e "${COLOR_RED}❌ UFW não encontrado. Instale com: apt install ufw${COLOR_RESET}"
    exit 1
fi

if ! ufw status 2>/dev/null | grep -q "Status: active"; then
    echo -e "${COLOR_RED}❌ UFW não está ativo. Execute: ufw enable${COLOR_RESET}"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo -e "${COLOR_RED}❌ curl não encontrado. Instale com: apt install curl${COLOR_RESET}"
    exit 1
fi

# ════════════════════════════════════════════════════════
# BUSCAR IPS DA CLOUDFLARE
# ════════════════════════════════════════════════════════

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}  Cloudflare UFW Updater${COLOR_RESET}"
echo -e "${COLOR_BOLD}  $(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

# Pergunta inicial — permite chegar na seção do timer mesmo sem mudanças
read -p "  Deseja verificar e atualizar os IPs da Cloudflare agora? [S/n]: " update_confirm
update_confirm="${update_confirm:-S}"
echo ""

DO_UPDATE=false
if [[ "$update_confirm" =~ ^[Ss]$ ]]; then
    DO_UPDATE=true
fi

if $DO_UPDATE; then

echo -e "${COLOR_CYAN}ℹ Buscando IPs atuais da Cloudflare...${COLOR_RESET}"

CF_IPV4_RAW=$(curl -s --max-time 30 https://www.cloudflare.com/ips-v4 2>/dev/null | grep -E '^[0-9]' || true)
CF_IPV6_RAW=$(curl -s --max-time 30 https://www.cloudflare.com/ips-v6 2>/dev/null | grep -E '^[0-9a-fA-F]' || true)

if [ -z "$CF_IPV4_RAW" ] || [ -z "$CF_IPV6_RAW" ]; then
    echo -e "${COLOR_RED}❌ Falha ao buscar IPs da Cloudflare. Verifique a conexão.${COLOR_RESET}"
    exit 1
fi

# Arrays com IPs novos
mapfile -t CF_NEW_IPS <<< "$(echo -e "${CF_IPV4_RAW}\n${CF_IPV6_RAW}" | grep -v '^$' | sort)"

IPV4_COUNT=$(echo "$CF_IPV4_RAW" | wc -l | tr -d ' ')
IPV6_COUNT=$(echo "$CF_IPV6_RAW" | wc -l | tr -d ' ')

echo -e "${COLOR_GREEN}✅ IPs obtidos: ${IPV4_COUNT} ranges IPv4 + ${IPV6_COUNT} ranges IPv6${COLOR_RESET}"

# ════════════════════════════════════════════════════════
# LER IPS ATUAIS NO UFW
# ════════════════════════════════════════════════════════

echo ""
echo -e "${COLOR_CYAN}ℹ Lendo regras Cloudflare atuais no UFW...${COLOR_RESET}"

# Extrai IPs que estão atualmente configurados como Cloudflare no UFW
# Formato da linha: "80/tcp ALLOW IN 173.245.48.0/20 # Cloudflare IPv4"
mapfile -t UFW_CURRENT_IPS <<< "$(ufw status 2>/dev/null \
    | grep -i 'Cloudflare' \
    | awk '{print $3}' \
    | grep -E '^[0-9a-fA-F]' \
    | sort -u || true)"

# Remover entradas vazias
CLEAN_CURRENT=()
for ip in "${UFW_CURRENT_IPS[@]}"; do
    [ -n "$ip" ] && CLEAN_CURRENT+=("$ip")
done

# ════════════════════════════════════════════════════════
# CALCULAR DIFF
# ════════════════════════════════════════════════════════

TO_ADD=()
TO_REMOVE=()

# IPs novos que não estão no UFW → adicionar
for ip in "${CF_NEW_IPS[@]}"; do
    [ -z "$ip" ] && continue
    found=0
    for current in "${CLEAN_CURRENT[@]}"; do
        [ "$ip" = "$current" ] && found=1 && break
    done
    [ "$found" -eq 0 ] && TO_ADD+=("$ip")
done

# IPs no UFW que não estão na lista nova → remover
for current in "${CLEAN_CURRENT[@]}"; do
    [ -z "$current" ] && continue
    found=0
    for ip in "${CF_NEW_IPS[@]}"; do
        [ "$current" = "$ip" ] && found=1 && break
    done
    [ "$found" -eq 0 ] && TO_REMOVE+=("$current")
done

# ════════════════════════════════════════════════════════
# EXIBIR RESUMO DAS MUDANÇAS
# ════════════════════════════════════════════════════════

echo ""
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_BOLD}  Resumo das mudanças${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

echo -e "  IPs atualmente no UFW (Cloudflare): ${COLOR_BOLD}${#CLEAN_CURRENT[@]}${COLOR_RESET}"
echo -e "  IPs na lista atual da Cloudflare:   ${COLOR_BOLD}${#CF_NEW_IPS[@]}${COLOR_RESET}"
echo ""

if [ ${#TO_REMOVE[@]} -gt 0 ]; then
    echo -e "  ${COLOR_RED}${COLOR_BOLD}❌ IPs a REMOVER (${#TO_REMOVE[@]}):${COLOR_RESET}"
    for ip in "${TO_REMOVE[@]}"; do
        echo -e "     ${COLOR_RED}− $ip${COLOR_RESET}"
    done
    echo ""
else
    echo -e "  ${COLOR_GREEN}✅ Nenhum IP a remover${COLOR_RESET}"
    echo ""
fi

if [ ${#TO_ADD[@]} -gt 0 ]; then
    echo -e "  ${COLOR_GREEN}${COLOR_BOLD}✅ IPs a ADICIONAR (${#TO_ADD[@]}):${COLOR_RESET}"
    for ip in "${TO_ADD[@]}"; do
        echo -e "     ${COLOR_GREEN}+ $ip${COLOR_RESET}"
    done
    echo ""
else
    echo -e "  ${COLOR_GREEN}✅ Nenhum IP a adicionar${COLOR_RESET}"
    echo ""
fi

# Sem mudanças
if [ ${#TO_ADD[@]} -eq 0 ] && [ ${#TO_REMOVE[@]} -eq 0 ]; then
    echo -e "${COLOR_GREEN}✅ UFW já está atualizado com os IPs atuais da Cloudflare. Nada a fazer.${COLOR_RESET}"
    echo ""
fi

if [ ${#TO_ADD[@]} -gt 0 ] || [ ${#TO_REMOVE[@]} -gt 0 ]; then

# ════════════════════════════════════════════════════════
# CONFIRMAÇÃO
# ════════════════════════════════════════════════════════

echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
read -p "  Aplicar as mudanças acima? [s/N]: " confirm
echo ""

if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${COLOR_YELLOW}⚠️  Operação cancelada. Nenhuma regra foi alterada.${COLOR_RESET}"
    echo ""
    exit 0
fi

# ════════════════════════════════════════════════════════
# REMOVER REGRAS PÚBLICAS (Anywhere) para 80 e 443
# Garante que somente IPs Cloudflare possam acessar HTTP/HTTPS
# ════════════════════════════════════════════════════════

echo -e "${COLOR_CYAN}ℹ Removendo regras públicas (Anywhere) para 80 e 443...${COLOR_RESET}"

# Remover em loop até não existir mais (UFW reindexas após cada delete)
for port in 80 443; do
    while ufw status numbered 2>/dev/null | grep -qE "^\[ *[0-9]+\] +${port}/tcp +ALLOW IN +Anywhere *$"; do
        num=$(ufw status numbered 2>/dev/null \
            | grep -E "^\[ *[0-9]+\] +${port}/tcp +ALLOW IN +Anywhere *$" \
            | awk -F'[][]' '{print $2}' | head -1)
        [ -z "$num" ] && break
        ufw --force delete "$num" > /dev/null 2>&1 && \
            echo -e "  ${COLOR_RED}− Removida regra pública: ${port}/tcp ALLOW Anywhere${COLOR_RESET}" || break
    done
done
echo ""

# ════════════════════════════════════════════════════════
# REMOVER IPS OBSOLETOS
# ════════════════════════════════════════════════════════

if [ ${#TO_REMOVE[@]} -gt 0 ]; then
    echo -e "${COLOR_CYAN}ℹ Removendo IPs obsoletos...${COLOR_RESET}"

    for ip_to_remove in "${TO_REMOVE[@]}"; do
        [ -z "$ip_to_remove" ] && continue

        # Pega os números das regras de trás para frente (para não deslocar índices)
        mapfile -t rule_nums <<< "$(ufw status numbered 2>/dev/null \
            | grep -F "$ip_to_remove" \
            | grep -i 'Cloudflare' \
            | awk -F'[][]' '{print $2}' \
            | sort -rn || true)"

        for num in "${rule_nums[@]}"; do
            [ -z "$num" ] && continue
            ufw --force delete "$num" > /dev/null 2>&1 && \
                echo -e "  ${COLOR_RED}− Removido: $ip_to_remove (regra #$num)${COLOR_RESET}" || \
                echo -e "  ${COLOR_YELLOW}⚠️  Não foi possível remover regra #$num ($ip_to_remove)${COLOR_RESET}"
        done
    done
    echo ""
fi

# ════════════════════════════════════════════════════════
# ADICIONAR IPS NOVOS
# ════════════════════════════════════════════════════════

if [ ${#TO_ADD[@]} -gt 0 ]; then
    echo -e "${COLOR_CYAN}ℹ Adicionando novos IPs...${COLOR_RESET}"

    for ip in "${TO_ADD[@]}"; do
        [ -z "$ip" ] && continue

        # Detectar IPv4 ou IPv6 pelo formato
        if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]'; then
            comment="Cloudflare IPv4"
        else
            comment="Cloudflare IPv6"
        fi

        ufw allow from "$ip" to any port 80  proto tcp comment "$comment" > /dev/null 2>&1
        ufw allow from "$ip" to any port 443 proto tcp comment "$comment" > /dev/null 2>&1
        echo -e "  ${COLOR_GREEN}+ Adicionado: $ip ($comment)${COLOR_RESET}"
    done
    echo ""
fi

# ════════════════════════════════════════════════════════
# ATUALIZAR DOCKER-USER
# ════════════════════════════════════════════════════════

if systemctl is-enabled docker-user-firewall.service &>/dev/null 2>&1; then
    echo -e "${COLOR_CYAN}ℹ Reaplicando regras DOCKER-USER com IPs Cloudflare atualizados...${COLOR_RESET}"
    systemctl restart docker-user-firewall.service
    echo -e "${COLOR_GREEN}✅ DOCKER-USER atualizado — acesso direto por IP bloqueado${COLOR_RESET}"
    echo ""
fi

TOTAL_CF=$(ufw status 2>/dev/null | grep -ic 'Cloudflare' || echo 0)

echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}  ✅ Atualização concluída!${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "  Regras Cloudflare ativas no UFW: ${COLOR_BOLD}${TOTAL_CF}${COLOR_RESET}"
echo -e "  Removidos: ${COLOR_RED}${#TO_REMOVE[@]}${COLOR_RESET} | Adicionados: ${COLOR_GREEN}${#TO_ADD[@]}${COLOR_RESET}"
echo ""

fi # fim bloco mudanças
fi # fim bloco DO_UPDATE

# ════════════════════════════════════════════════════════
# ATUALIZAÇÃO AUTOMÁTICA MENSAL (OPCIONAL)
# ════════════════════════════════════════════════════════

AUTO_SCRIPT="/usr/local/bin/cloudflare-update-firewall.sh"
AUTO_SERVICE="/etc/systemd/system/cloudflare-update-firewall.service"
AUTO_TIMER="/etc/systemd/system/cloudflare-update-firewall.timer"

# Verificar se o timer já existe
if systemctl is-enabled cloudflare-update-firewall.timer &>/dev/null 2>&1; then
    echo -e "${COLOR_GREEN}✅ Atualização automática mensal já está configurada.${COLOR_RESET}"
    echo -e "   Próxima execução: $(systemctl list-timers cloudflare-update-firewall.timer --no-pager 2>/dev/null | awk 'NR==2{print $1, $2}' || echo 'ver: systemctl list-timers')"
    echo ""
else
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}  Atualização Automática Mensal${COLOR_RESET}"
    echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo ""
    echo "  Deseja criar um serviço que atualize os IPs da Cloudflare"
    echo "  automaticamente todo mês? (UFW + DOCKER-USER)"
    echo ""
    read -p "  Criar atualização automática mensal? [S/n]: " auto_confirm
    auto_confirm="${auto_confirm:-S}"
    echo ""

    if [[ "$auto_confirm" =~ ^[Ss]$ ]]; then

        # ── Script não-interativo de atualização ─────────────
        echo -e "${COLOR_CYAN}ℹ Criando script de atualização automática...${COLOR_RESET}"

        cat > "$AUTO_SCRIPT" << 'AUTO_SH'
#!/bin/bash
# cloudflare-update-firewall.sh
# Atualização automática não-interativa dos IPs da Cloudflare.
# Executado mensalmente pelo systemd timer.

set -euo pipefail

LOG_PREFIX="[cloudflare-update-firewall]"

log() { echo "$LOG_PREFIX $*"; }

# Buscar IPs da Cloudflare
CF_IPV4=$(curl -s --max-time 30 https://www.cloudflare.com/ips-v4 2>/dev/null | grep -E '^[0-9]' || true)
CF_IPV6=$(curl -s --max-time 30 https://www.cloudflare.com/ips-v6 2>/dev/null | grep -E '^[0-9a-fA-F]' || true)

if [ -z "$CF_IPV4" ] || [ -z "$CF_IPV6" ]; then
    log "ERRO: Falha ao buscar IPs da Cloudflare. Abortando."
    exit 1
fi

mapfile -t CF_NEW_IPS <<< "$(echo -e "${CF_IPV4}\n${CF_IPV6}" | grep -v '^$' | sort)"
log "IPs obtidos: $(echo "$CF_IPV4" | wc -l | tr -d ' ') IPv4 + $(echo "$CF_IPV6" | wc -l | tr -d ' ') IPv6"

# Remover regras Anywhere para 80/443 (caso existam)
for port in 80 443; do
    while ufw status numbered 2>/dev/null | grep -qE "^\[ *[0-9]+\] +${port}/tcp +ALLOW IN +Anywhere *$"; do
        num=$(ufw status numbered 2>/dev/null \
            | grep -E "^\[ *[0-9]+\] +${port}/tcp +ALLOW IN +Anywhere *$" \
            | awk -F'[][]' '{print $2}' | head -1)
        [ -z "$num" ] && break
        ufw --force delete "$num" > /dev/null 2>&1 || break
    done
done

# Obter IPs atuais do UFW
mapfile -t UFW_CURRENT <<< "$(ufw status 2>/dev/null | grep -i 'Cloudflare' | awk '{print $3}' | grep -E '^[0-9a-fA-F]' | sort -u || true)"

# Remover IPs obsoletos
for current in "${UFW_CURRENT[@]}"; do
    [ -z "$current" ] && continue
    found=0
    for ip in "${CF_NEW_IPS[@]}"; do
        [ "$current" = "$ip" ] && found=1 && break
    done
    if [ "$found" -eq 0 ]; then
        mapfile -t rule_nums <<< "$(ufw status numbered 2>/dev/null | grep -F "$current" | grep -i 'Cloudflare' | awk -F'[][]' '{print $2}' | sort -rn || true)"
        for num in "${rule_nums[@]}"; do
            [ -z "$num" ] && continue
            ufw --force delete "$num" > /dev/null 2>&1 || true
        done
        log "Removido: $current"
    fi
done

# Adicionar IPs novos
added=0
for ip in "${CF_NEW_IPS[@]}"; do
    [ -z "$ip" ] && continue
    already=0
    for current in "${UFW_CURRENT[@]}"; do
        [ "$ip" = "$current" ] && already=1 && break
    done
    if [ "$already" -eq 0 ]; then
        if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]'; then
            comment="Cloudflare IPv4"
        else
            comment="Cloudflare IPv6"
        fi
        ufw allow from "$ip" to any port 80  proto tcp comment "$comment" > /dev/null 2>&1
        ufw allow from "$ip" to any port 443 proto tcp comment "$comment" > /dev/null 2>&1
        log "Adicionado: $ip ($comment)"
        added=$((added + 1))
    fi
done

[ "$added" -eq 0 ] && log "Nenhum IP novo adicionado."

# Atualizar DOCKER-USER
if systemctl is-enabled docker-user-firewall.service &>/dev/null 2>&1; then
    systemctl restart docker-user-firewall.service
    log "DOCKER-USER atualizado."
fi

log "Concluído em $(date '+%Y-%m-%d %H:%M:%S')"
AUTO_SH

        chmod +x "$AUTO_SCRIPT"
        echo -e "${COLOR_GREEN}✅ Script criado: $AUTO_SCRIPT${COLOR_RESET}"

        # ── Serviço systemd ──────────────────────────────────
        cat > "$AUTO_SERVICE" << 'AUTO_SVC'
[Unit]
Description=Atualiza IPs da Cloudflare no UFW e DOCKER-USER
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cloudflare-update-firewall.sh
StandardOutput=journal
StandardError=journal
AUTO_SVC

        echo -e "${COLOR_GREEN}✅ Serviço criado: $AUTO_SERVICE${COLOR_RESET}"

        # ── Timer systemd (mensal, persistent) ──────────────
        cat > "$AUTO_TIMER" << 'AUTO_TMR'
[Unit]
Description=Executa atualização de IPs Cloudflare mensalmente

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
AUTO_TMR

        echo -e "${COLOR_GREEN}✅ Timer criado: $AUTO_TIMER${COLOR_RESET}"

        # ── Ativar timer ─────────────────────────────────────
        systemctl daemon-reload
        systemctl enable --now cloudflare-update-firewall.timer

        echo ""
        echo -e "${COLOR_GREEN}✅ Atualização automática mensal ativa!${COLOR_RESET}"
        echo ""
        echo -e "  Agendamento:"
        systemctl list-timers cloudflare-update-firewall.timer --no-pager 2>/dev/null || true
        echo ""
        echo -e "  Comandos úteis:"
        echo -e "    • Ver próxima execução : systemctl list-timers cloudflare-update-firewall.timer"
        echo -e "    • Forçar execução agora: systemctl start cloudflare-update-firewall.service"
        echo -e "    • Ver logs             : journalctl -u cloudflare-update-firewall.service -f"
        echo -e "    • Desativar            : systemctl disable --now cloudflare-update-firewall.timer"
        echo ""
    else
        echo -e "${COLOR_YELLOW}⚠️  Atualização automática não configurada.${COLOR_RESET}"
        echo -e "  Para configurar depois, rode: bash 03-cloudflare-update-ufw.sh"
        echo ""
    fi
fi
