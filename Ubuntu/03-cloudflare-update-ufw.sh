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
    exit 0
fi

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
# RESULTADO FINAL
# ════════════════════════════════════════════════════════

TOTAL_CF=$(ufw status 2>/dev/null | grep -ic 'Cloudflare' || echo 0)

echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}  ✅ Atualização concluída!${COLOR_RESET}"
echo -e "${COLOR_BOLD}════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""
echo -e "  Regras Cloudflare ativas no UFW: ${COLOR_BOLD}${TOTAL_CF}${COLOR_RESET}"
echo -e "  Removidos: ${COLOR_RED}${#TO_REMOVE[@]}${COLOR_RESET} | Adicionados: ${COLOR_GREEN}${#TO_ADD[@]}${COLOR_RESET}"
echo ""
