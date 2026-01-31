#!/bin/bash

#########################################################
# PostgreSQL Cluster Management Tool
# Autor: Andre Luiz Faustino
# Data: 2026-01-27
# Versão: 1.0
# Descrição: Gerenciador completo de PostgreSQL
#########################################################

# ============================================
# VARIÁVEIS GLOBAIS
# ============================================

LOG_FILE="/var/log/postgres.log"
SCRIPT_VERSION="1.0"
BACKUP_DIR="$(dirname "$(readlink -f "$0")")/backup"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# ============================================
# FUNÇÕES DE UTILIDADE
# ============================================

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

press_enter() {
    echo ""
    read -p "Pressione ENTER para continuar..."
}

clear_screen() {
    clear
    show_header
}

# ============================================
# FUNÇÕES DE VALIDAÇÃO
# ============================================

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Este script precisa ser executado como root (sudo)"
        exit 1
    fi
}

is_postgresql_installed() {
    if command -v psql >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

detect_pg_version() {
    if is_postgresql_installed; then
        psql --version | grep -oP '\d+' | head -1
    else
        echo ""
    fi
}

get_config_dir() {
    local version="$1"
    local cluster="$2"
    echo "/etc/postgresql/$version/$cluster"
}

get_data_dir() {
    local version="$1"
    local cluster="$2"
    pg_lsclusters -h | grep "^$version.*$cluster" | awk '{print $6}'
}

detect_local_ip() {
    local ip=""
    
    # Método 1: Comando tailscale
    if command -v tailscale >/dev/null 2>&1; then
        ip=$(tailscale ip -4 2>/dev/null | head -1)
        if [ -n "$ip" ] && echo "$ip" | grep -qE '^100\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Método 2: Interface tailscale0
    if ip addr show tailscale0 >/dev/null 2>&1; then
        ip=$(ip addr show tailscale0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | grep '^100\.')
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Método 3: Buscar qualquer IP 100.x.x.x
    ip=$(ip addr | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | grep '^100\.' | head -1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    # Fallback: IP principal da máquina
    ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[0-9.]+')
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    
    echo "127.0.0.1"
    return 1
}

# ============================================
# INTERFACE - HEADER E MENUS
# ============================================

show_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║ PostgreSQL Cluster Management Tool                       ║"
    echo "║ Versão: ${SCRIPT_VERSION}                                              ║"
    echo "║ Autor: https://github.com/andreluizfaustino              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_main_menu() {
    clear_screen
    
    local pg_installed=false
    local pg_version=""
    
    if is_postgresql_installed; then
        pg_installed=true
        pg_version=$(detect_pg_version)
    fi
    
    echo ""
    
    if [ "$pg_installed" = true ]; then
        print_success "PostgreSQL v$pg_version instalado"
    else
        print_warning "PostgreSQL não instalado"
    fi
    
    echo ""
    
    COLUMNS=1
    PS3="
Escolha uma opção: "
    
    if [ "$pg_installed" = true ]; then
        options=(
            "Instalar PostgreSQL [JÁ INSTALADO]"
            "Desinstalar PostgreSQL"
            "Gerenciar Clusters"
            "Configurar Replicação"
            "Sair"
        )
    else
        options=(
            "Instalar PostgreSQL"
            "Desinstalar PostgreSQL [NÃO INSTALADO]"
            "Gerenciar Clusters [REQUER POSTGRESQL]"
            "Configurar Replicação [REQUER POSTGRESQL]"
            "Sair"
        )
    fi
    
    select opt in "${options[@]}"
    do
        case $REPLY in
            1)
                if [ "$pg_installed" = true ]; then
                    print_warning "PostgreSQL já está instalado!"
                    press_enter
                else
                    install_postgresql
                fi
                return
                ;;
            2)
                if [ "$pg_installed" = true ]; then
                    uninstall_postgresql
                else
                    print_warning "PostgreSQL não está instalado!"
                    press_enter
                fi
                return
                ;;
            3)
                if [ "$pg_installed" = true ]; then
                    menu_clusters
                else
                    print_error "PostgreSQL não está instalado!"
                    print_info "Instale o PostgreSQL primeiro (opção 1)"
                    press_enter
                fi
                return
                ;;
            4)
                if [ "$pg_installed" = true ]; then
                    menu_replication
                else
                    print_error "PostgreSQL não está instalado!"
                    print_info "Instale o PostgreSQL primeiro (opção 1)"
                    press_enter
                fi
                return
                ;;
            5)
                clear_screen
                echo ""
                print_success "Até logo!"
                echo ""
                log_message "Script finalizado"
                exit 0
                ;;
            *)
                print_error "Opção inválida!"
                sleep 1
                return
                ;;
        esac
    done
}

show_cluster_menu() {
    clear_screen
    echo ""
    print_info "GERENCIAMENTO DE CLUSTERS"
    echo ""
    
    # Listar clusters
    list_clusters
    
    echo ""
    
    COLUMNS=1
    PS3="
Escolha uma opção: "
    
    options=(
        "Adicionar"
        "Excluir"
        "Criar Backup"
        "Importar Backup"
        "Gerenciar Backups"
        "Usuarios"
        "Databases e Schemas"
        "Voltar"
    )
    
    select opt in "${options[@]}"
    do
        case $REPLY in
            1)
                add_cluster
                return
                ;;
            2)
                delete_cluster
                return
                ;;
            3)
                backup_cluster
                return
                ;;
            4)
                import_backup
                return
                ;;
            5)
                manage_backups
                return
                ;;
            6)
                manage_users
                return
                ;;
            7)
                manage_databases_schemas
                return
                ;;
            8)
                return 0
                ;;
            *)
                print_error "Opção inválida!"
                sleep 1
                return
                ;;
        esac
    done
}

# ============================================
# FUNÇÕES DE LISTAGEM
# ============================================

list_clusters() {
    local pg_version=$(detect_pg_version)
    
    echo ""
    print_info "Clusters PostgreSQL:"
    echo ""
    
    if [ -z "$pg_version" ]; then
        print_warning "PostgreSQL não está instalado"
        return 1
    fi
    
    if pg_lsclusters -h 2>/dev/null | grep -q "$pg_version"; then
        echo -e "${CYAN}Ver | Cluster | Porta | Status    | Usuário  | Diretório${NC}"
        echo "─────────────────────────────────────────────────────────────────"
        pg_lsclusters | grep "$pg_version"
        echo ""
        return 0
    else
        print_warning "Nenhum cluster encontrado"
        return 1
    fi
}

# ============================================
# INSTALAÇÃO DO POSTGRESQL
# ============================================

install_postgresql() {
    clear_screen
    echo ""
    
    if is_postgresql_installed; then
        local pg_version=$(detect_pg_version)
        print_warning "PostgreSQL v$pg_version já está instalado!"
        echo ""
        print_info "Para reinstalar, desinstale primeiro usando a opção 2"
        press_enter
        return 0
    fi
    
    # Detectar OS
    if [ ! -f /etc/os-release ]; then
        print_error "Sistema operacional não identificado"
        press_enter
        return 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
        print_error "Este script suporta apenas Ubuntu/Debian"
        print_info "Sistema detectado: $ID"
        press_enter
        return 1
    fi
    
    print_success "Sistema operacional: $ID $VERSION_ID"
    echo ""
    
    # Escolher versão com select
    print_info "Selecione a versão do PostgreSQL:"
    echo ""
    
    COLUMNS=1
    PS3="
Escolha a versão: "
    
    versions=(
        "PostgreSQL 16 - LTS até Nov/2028 (Recomendado)"
        "PostgreSQL 17 - Versão mais recente"
        "PostgreSQL 15 - LTS até Nov/2027"
        "PostgreSQL 14 - LTS até Nov/2026"
        "PostgreSQL 13 - LTS até Nov/2025"
        "PostgreSQL 12 - LTS até Nov/2024"
        "Cancelar"
    )
    
    select version_opt in "${versions[@]}"
    do
        case $REPLY in
            1) version_choice=16; break;;
            2) version_choice=17; break;;
            3) version_choice=15; break;;
            4) version_choice=14; break;;
            5) version_choice=13; break;;
            6) version_choice=12; break;;
            7) print_info "Instalação cancelada"; press_enter; return 0;;
            *) print_error "Opção inválida!"; continue;;
        esac
    done
    
    echo ""
    print_warning "Será instalado: PostgreSQL $version_choice"
    echo ""
    
    read -p "Confirma a instalação? (s/n): " confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        print_info "Instalação cancelada"
        press_enter
        return 0
    fi
    
    # Instalar
    echo ""
    print_info "Atualizando repositórios..."
    apt-get update -qq
    
    print_info "Instalando dependências..."
    apt-get install -y wget gnupg2 lsb-release curl ca-certificates -qq
    
    print_info "Adicionando repositório PostgreSQL..."
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - 2>/dev/null
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    
    print_info "Atualizando lista de pacotes..."
    apt-get update -qq
    
    print_info "Instalando PostgreSQL $version_choice..."
    apt-get install -y postgresql-$version_choice postgresql-contrib-$version_choice
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "PostgreSQL $version_choice instalado com sucesso!"
        echo ""
        
        # Verificar serviço
        if systemctl is-active --quiet postgresql; then
            print_success "Serviço PostgreSQL está rodando"
        else
            print_info "Iniciando serviço PostgreSQL..."
            systemctl start postgresql
            systemctl enable postgresql
        fi
        
        echo ""
        print_info "Clusters criados automaticamente:"
        pg_lsclusters
        echo ""
        
        log_message "PostgreSQL $version_choice instalado"
        press_enter
        return 0
    else
        print_error "Falha na instalação do PostgreSQL"
        press_enter
        return 1
    fi
}

# ============================================
# DESINSTALAÇÃO DO POSTGRESQL
# ============================================

uninstall_postgresql() {
    clear_screen
    echo ""
    print_warning "ATENÇÃO: DESINSTALAÇÃO DO POSTGRESQL"
    echo ""
    
    if ! is_postgresql_installed; then
        print_error "PostgreSQL não está instalado"
        press_enter
        return 1
    fi
    
    local pg_version=$(detect_pg_version)
    
    print_info "PostgreSQL instalado: Versão $pg_version"
    echo ""
    print_info "Clusters existentes:"
    pg_lsclusters
    echo ""
    
    print_warning "Esta ação irá:"
    echo "  • REMOVER COMPLETAMENTE o PostgreSQL"
    echo "  • EXCLUIR todos os clusters e dados"
    echo "  • REMOVER todos os pacotes relacionados"
    echo ""
    
    read -p "Tem CERTEZA que deseja desinstalar? (s/n): " confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        print_info "Desinstalação cancelada"
        press_enter
        return 0
    fi
    
    echo ""
    read -p "Digite 'DESINSTALAR' em maiúsculas para confirmar: " confirm2
    if [ "$confirm2" != "DESINSTALAR" ]; then
        print_info "Desinstalação cancelada"
        press_enter
        return 0
    fi
    
    echo ""
    print_info "Parando serviço PostgreSQL..."
    systemctl stop postgresql 2>/dev/null
    systemctl disable postgresql 2>/dev/null
    
    print_info "Removendo clusters..."
    local clusters=$(pg_lsclusters -h | grep "^$pg_version" | awk '{print $2}')
    for cluster in $clusters; do
        pg_dropcluster --stop-server $pg_version $cluster 2>/dev/null
        print_success "Cluster '$cluster' removido"
    done
    
    print_info "Desinstalando pacotes PostgreSQL..."
    apt-get --purge remove -y postgresql\* -qq 2>&1 | grep -v "^dpkg" | grep -v "^(Reading"
    
    print_info "Removendo dependências não utilizadas..."
    apt-get autoremove -y -qq
    
    print_info "Limpando arquivos de configuração..."
    rm -rf /etc/postgresql
    rm -rf /var/lib/postgresql
    rm -f /etc/apt/sources.list.d/pgdg.list
    
    if id postgres &>/dev/null; then
        userdel -r postgres 2>/dev/null || userdel postgres 2>/dev/null
    fi
    
    if getent group postgres &>/dev/null; then
        groupdel postgres 2>/dev/null
    fi
    
    rm -rf /var/log/postgresql
    
    print_info "Atualizando cache de pacotes..."
    apt-get update -qq
    
    echo ""
    print_success "PostgreSQL desinstalado com sucesso!"
    echo ""
    
    log_message "PostgreSQL $pg_version desinstalado"
    press_enter
    return 0
}

# ============================================
# GERENCIAMENTO DE CLUSTERS
# ============================================

add_cluster() {
    clear_screen
    echo ""
    print_info "ADICIONAR NOVO CLUSTER"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    # Listar clusters existentes
    list_clusters
    echo ""
    
    # Coletar informações
    read -p "Nome do novo cluster: " cluster_name
    if [ -z "$cluster_name" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se já existe
    if pg_lsclusters -h | grep -q "^$pg_version.*$cluster_name"; then
        print_error "Cluster '$cluster_name' já existe!"
        press_enter
        return 1
    fi
    
    read -p "Porta do cluster [padrão: 5432]: " port
    port=${port:-5432}
    
    # Validar porta
    if ! echo "$port" | grep -qE '^[0-9]+$' || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        print_error "Porta inválida: $port"
        press_enter
        return 1
    fi
    
    # Verificar se porta está em uso
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_error "Porta $port já está em uso!"
        press_enter
        return 1
    fi
    
    # Encoding com select
    echo ""
    print_info "Selecione o encoding:"
    echo ""
    
    COLUMNS=1
    PS3="
Escolha o encoding: "
    
    encodings=(
        "UTF8 (Recomendado)"
        "LATIN1"
        "SQL_ASCII"
    )
    
    select enc_opt in "${encodings[@]}"
    do
        case $REPLY in
            1) encoding="UTF8"; break;;
            2) encoding="LATIN1"; break;;
            3) encoding="SQL_ASCII"; break;;
            *) print_error "Opção inválida!"; continue;;
        esac
    done
    
    # Locale com select
    echo ""
    print_info "Selecione o locale:"
    echo ""
    
    COLUMNS=1
    PS3="
Escolha o locale: "
    
    locales=(
        "pt_BR.UTF-8 (Português Brasil)"
        "en_US.UTF-8 (Inglês)"
        "C (Sem localização)"
    )
    
    select loc_opt in "${locales[@]}"
    do
        case $REPLY in
            1) locale="pt_BR.UTF-8"; break;;
            2) locale="en_US.UTF-8"; break;;
            3) locale="C"; break;;
            *) print_error "Opção inválida!"; continue;;
        esac
    done
    
    # Garantir que locale está instalado
    if [ "$locale" != "C" ]; then
        if ! locale -a | grep -qi "^${locale}$"; then
            print_info "Instalando locale '$locale'..."
            echo "${locale} UTF-8" >> /etc/locale.gen 2>/dev/null
            sed -i "s/^# *${locale}/${locale}/" /etc/locale.gen 2>/dev/null
            locale-gen "${locale}" >/dev/null 2>&1
        fi
    fi
    
    # Senha para usuário postgres
    echo ""
    print_info "Configure a senha para o usuário postgres:"
    read -sp "Senha: " postgres_password
    echo ""
    read -sp "Confirme a senha: " postgres_password2
    echo ""
    
    if [ "$postgres_password" != "$postgres_password2" ]; then
        print_error "As senhas não correspondem!"
        press_enter
        return 1
    fi
    
    if [ -z "$postgres_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Criar cluster
    echo ""
    print_info "Criando cluster '$cluster_name'..."
    
    sudo pg_createcluster -p $port --start $pg_version $cluster_name -- --encoding=$encoding --locale=$locale
    
    if [ $? -ne 0 ]; then
        print_error "Falha ao criar cluster '$cluster_name'"
        press_enter
        return 1
    fi
    
    print_success "Cluster '$cluster_name' criado!"
    
    # Detectar IP do Tailscale
    echo ""
    print_info "Detectando IP do Tailscale..."
    local tailscale_ip=$(detect_local_ip)
    
    if echo "$tailscale_ip" | grep -qE '^100\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        print_success "IP Tailscale detectado: $tailscale_ip"
    else
        print_warning "IP Tailscale não detectado, usando: $tailscale_ip"
    fi
    
    # Configurar postgresql.conf
    local config_dir=$(get_config_dir "$pg_version" "$cluster_name")
    local pg_conf="$config_dir/postgresql.conf"
    
    print_info "Configurando listen_addresses..."
    if grep -q "^listen_addresses" "$pg_conf"; then
        sed -i "s/^listen_addresses.*/listen_addresses = '127.0.0.1,$tailscale_ip'/" "$pg_conf"
    else
        echo "listen_addresses = '127.0.0.1,$tailscale_ip'" >> "$pg_conf"
    fi
    
    # Configurar pg_hba.conf
    local pg_hba="$config_dir/pg_hba.conf"
    
    print_info "Configurando pg_hba.conf para autenticação scram-sha-256..."
    
    # Backup do arquivo original
    cp "$pg_hba" "$pg_hba.bak"
    
    # Reescrever pg_hba.conf com regras de autenticação scram-sha-256
    cat > "$pg_hba" << EOF
# PostgreSQL Client Authentication Configuration File
# =====================================================
# Cluster: $cluster_name
# Configurado em: $(date '+%Y-%m-%d %H:%M:%S')
#
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Conexões locais via socket Unix (requer senha)
local   all             all                                     scram-sha-256

# Conexões localhost IPv4 (requer senha)
host    all             all             127.0.0.1/32            scram-sha-256

# Conexões localhost IPv6 (requer senha)
host    all             all             ::1/128                 scram-sha-256

# Conexões via Tailscale (requer senha)
host    all             all             $tailscale_ip/32        scram-sha-256
host    all             all             100.0.0.0/8             scram-sha-256

# Replication connections
local   replication     all                                     scram-sha-256
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256
host    replication     all             100.0.0.0/8             scram-sha-256
EOF
    
    print_success "pg_hba.conf configurado (backup: $pg_hba.bak)"
    
    # Definir senha do postgres
    print_info "Configurando senha do usuário postgres..."
    sudo -u postgres psql -p $port -c "ALTER USER postgres WITH PASSWORD '$postgres_password';" >/dev/null 2>&1
    
    # Reiniciar cluster
    print_info "Reiniciando cluster para aplicar configurações..."
    pg_ctlcluster $pg_version $cluster_name restart >/dev/null 2>&1
    
    echo ""
    print_success "Cluster '$cluster_name' configurado com sucesso!"
    echo ""
    print_info "Configurações aplicadas:"
    echo "  • Porta: $port"
    echo "  • Encoding: $encoding"
    echo "  • Locale: $locale"
    echo "  • Listen: 127.0.0.1, $tailscale_ip"
    echo "  • Senha: ********"
    echo ""
    print_info "Cluster ativo:"
    pg_lsclusters | grep "$pg_version.*$cluster_name"
    echo ""
    
    log_message "Cluster $cluster_name criado na porta $port com IP $tailscale_ip"
    press_enter
    return 0
}

delete_cluster() {
    clear_screen
    echo ""
    print_info "EXCLUIR CLUSTER"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    # Listar clusters
    if ! list_clusters; then
        press_enter
        return 1
    fi
    
    echo ""
    read -p "Nome do cluster para excluir: " cluster_name
    
    if [ -z "$cluster_name" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se existe
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$cluster_name"; then
        print_error "Cluster '$cluster_name' não existe!"
        press_enter
        return 1
    fi
    
    # Verificar se cluster está em replicação
    local role=$(get_cluster_role "$pg_version" "$cluster_name")
    if [ "$role" = "PRIMARY" ] || [ "$role" = "STANDBY" ]; then
        echo ""
        print_error "IMPOSSÍVEL EXCLUIR: Cluster '$cluster_name' está em REPLICAÇÃO!"
        echo ""
        print_info "Função atual: $role"
        echo ""
        print_warning "Para excluir este cluster, você deve primeiro:"
        echo "  1. Ir para o menu 'Configurar Replicação' (opção 4)"
        echo "  2. Escolher 'Remover Replicação' (opção 2)"
        echo "  3. Isso irá converter ambos clusters para STANDALONE"
        echo "  4. Depois você poderá excluir o cluster"
        echo ""
        press_enter
        return 1
    fi
    
    # Confirmação dupla
    echo ""
    print_warning "ATENÇÃO: Esta ação irá EXCLUIR permanentemente o cluster '$cluster_name'!"
    echo ""
    read -p "Digite o nome do cluster para confirmar: " confirm
    
    if [ "$confirm" != "$cluster_name" ]; then
        print_warning "Nome não corresponde. Exclusão cancelada."
        press_enter
        return 1
    fi
    
    read -p "Tem CERTEZA que deseja continuar? (s/n): " confirm2
    if [ "$confirm2" != "s" ] && [ "$confirm2" != "S" ]; then
        print_info "Exclusão cancelada"
        press_enter
        return 0
    fi
    
    # Excluir cluster
    echo ""
    print_info "Excluindo cluster '$cluster_name'..."
    sudo pg_dropcluster --stop $pg_version $cluster_name
    
    if [ $? -eq 0 ]; then
        print_success "Cluster '$cluster_name' excluído com sucesso!"
        
        # Remover diretório de configuração residual se existir
        local config_dir="/etc/postgresql/$pg_version/$cluster_name"
        if [ -d "$config_dir" ]; then
            print_info "Removendo arquivos residuais de configuração..."
            rm -rf "$config_dir"
            print_success "Arquivos residuais removidos"
        fi
        
        log_message "Cluster $cluster_name excluído"
        press_enter
        return 0
    else
        print_error "Falha ao excluir cluster '$cluster_name'"
        press_enter
        return 1
    fi
}

# ============================================
# BACKUP E IMPORTAÇÃO DE CLUSTERS
# ============================================

list_backups() {
    local show_header=${1:-true}
    
    if [ "$show_header" = true ]; then
        echo ""
        print_info "Backups disponíveis em: $BACKUP_DIR"
        echo ""
    fi
    
    if [ ! -d "$BACKUP_DIR" ]; then
        if [ "$show_header" = true ]; then
            print_warning "Nenhum backup encontrado (diretório não existe)"
        fi
        return 1
    fi
    
    local backups=($(find "$BACKUP_DIR" -name "*.sql.gz" -type f 2>/dev/null | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        if [ "$show_header" = true ]; then
            print_warning "Nenhum backup encontrado"
        fi
        return 1
    fi
    
    if [ "$show_header" = true ]; then
        echo -e "${CYAN}Cluster       | Data/Hora         | Tamanho   | Arquivo${NC}"
        echo "───────────────────────────────────────────────────────────────────────"
    fi
    
    for backup in "${backups[@]}"; do
        local filename=$(basename "$backup")
        local cluster_name=$(echo "$filename" | cut -d'_' -f1)
        local date_part=$(echo "$filename" | cut -d'_' -f2)
        local time_part=$(echo "$filename" | cut -d'_' -f3 | cut -d'.' -f1)
        local formatted_date="${date_part:0:4}-${date_part:4:2}-${date_part:6:2}"
        local formatted_time="${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
        local size=$(du -h "$backup" | cut -f1)
        
        printf "%-13s | %s %s | %-9s | %s\n" "$cluster_name" "$formatted_date" "$formatted_time" "$size" "$filename"
    done
    
    echo ""
    return 0
}

backup_cluster() {
    clear_screen
    echo ""
    print_info "FAZER BACKUP DE CLUSTER"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    # Listar clusters
    list_clusters
    echo ""
    
    # Verificar se existem clusters
    if ! pg_lsclusters -h 2>/dev/null | grep -q "$pg_version"; then
        print_error "Nenhum cluster disponível para backup"
        press_enter
        return 1
    fi
    
    # Selecionar cluster
    read -p "Nome do cluster para backup: " cluster_name
    if [ -z "$cluster_name" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se cluster existe
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$cluster_name"; then
        print_error "Cluster '$cluster_name' não existe!"
        press_enter
        return 1
    fi
    
    # Obter porta do cluster
    local port=$(pg_lsclusters -h | grep "^$pg_version.*$cluster_name" | awk '{print $3}')
    
    # Solicitar senha do postgres
    echo ""
    print_info "Digite a senha do usuário postgres:"
    read -sp "Senha: " postgres_password
    echo ""
    
    if [ -z "$postgres_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Criar diretório de backup se não existir
    mkdir -p "$BACKUP_DIR"
    
    # Gerar nome do arquivo de backup
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${cluster_name}_${timestamp}.sql.gz"
    
    # Fazer backup
    echo ""
    print_info "Iniciando backup do cluster '$cluster_name'..."
    print_info "Arquivo: $(basename "$backup_file")"
    echo ""
    
    if sudo PGPASSWORD="$postgres_password" -u postgres pg_dumpall -p "$port" 2>/dev/null | gzip > "$backup_file"; then
        local backup_size=$(du -h "$backup_file" | cut -f1)
        echo ""
        print_success "Backup realizado com sucesso!"
        print_info "Arquivo: $(basename "$backup_file")"
        print_info "Tamanho: $backup_size"
        print_info "Local: $BACKUP_DIR"
        log_message "Backup do cluster $cluster_name criado: $(basename "$backup_file")"
    else
        rm -f "$backup_file" 2>/dev/null
        echo ""
        print_error "Falha ao criar backup!"
        print_warning "Verifique se a senha está correta"
    fi
    
    echo ""
    press_enter
    return 0
}

import_backup() {
    clear_screen
    echo ""
    print_info "IMPORTAR BACKUP PARA CLUSTER"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    # Listar backups disponíveis
    if ! list_backups; then
        print_error "Nenhum backup disponível para importação"
        press_enter
        return 1
    fi
    
    # Selecionar backup
    echo ""
    print_info "Digite o nome do arquivo de backup (ex: prod_20260128_143025.sql.gz):"
    read -p "Arquivo: " backup_filename
    
    if [ -z "$backup_filename" ]; then
        print_error "Nome do arquivo não pode ser vazio"
        press_enter
        return 1
    fi
    
    local backup_file="$BACKUP_DIR/$backup_filename"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Arquivo de backup não encontrado: $backup_filename"
        press_enter
        return 1
    fi
    
    # Listar clusters
    echo ""
    print_info "Clusters disponíveis:"
    echo ""
    list_clusters
    echo ""
    
    # Selecionar cluster de destino
    read -p "Nome do cluster de destino: " cluster_name
    if [ -z "$cluster_name" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se cluster existe
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$cluster_name"; then
        print_error "Cluster '$cluster_name' não existe!"
        press_enter
        return 1
    fi
    
    # Obter porta do cluster
    local port=$(pg_lsclusters -h | grep "^$pg_version.*$cluster_name" | awk '{print $3}')
    
    # Avisos e confirmação
    echo ""
    print_warning "ATENÇÃO:"
    echo "  • O backup será restaurado no cluster '$cluster_name'"
    echo "  • Todos os dados atuais serão SUBSTITUÍDOS"
    echo "  • Bancos de dados existentes serão REMOVIDOS"
    echo "  • Esta operação NÃO pode ser desfeita"
    echo ""
    
    read -p "Confirma a importação do backup? (s/n): " confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        print_info "Importação cancelada"
        press_enter
        return 0
    fi
    
    # Solicitar senha do postgres
    echo ""
    print_info "Digite a senha do usuário postgres:"
    read -sp "Senha: " postgres_password
    echo ""
    
    if [ -z "$postgres_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Importar backup
    echo ""
    print_info "Iniciando importação do backup..."
    print_info "Cluster de destino: $cluster_name"
    print_info "Porta: $port"
    echo ""
    
    # Parar conexões existentes e limpar banco
    print_info "Encerrando conexões ativas..."
    sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid();" > /dev/null 2>&1
    
    print_info "Restaurando backup..."
    if gunzip -c "$backup_file" | sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres > /dev/null 2>&1; then
        echo ""
        print_success "Backup importado com sucesso!"
        print_info "Cluster '$cluster_name' restaurado com os dados do backup"
        log_message "Backup $backup_filename importado para cluster $cluster_name"
    else
        echo ""
        print_error "Falha ao importar backup!"
        print_warning "Verifique se a senha está correta"
        print_warning "O cluster pode estar em estado inconsistente"
    fi
    
    echo ""
    press_enter
    return 0
}

manage_backups() {
    clear_screen
    echo ""
    print_info "GERENCIAR BACKUPS"
    echo ""
    
    # Listar backups
    if ! list_backups; then
        press_enter
        return 1
    fi
    
    echo ""
    
    COLUMNS=1
    PS3="
Escolha uma opção: "
    
    options=(
        "Excluir um backup específico"
        "Excluir todos os backups"
        "Voltar"
    )
    
    select opt in "${options[@]}"
    do
        case $REPLY in
            1)
                delete_specific_backup
                return
                ;;
            2)
                delete_all_backups
                return
                ;;
            3)
                return 0
                ;;
            *)
                print_error "Opção inválida!"
                sleep 1
                return
                ;;
        esac
    done
}

delete_specific_backup() {
    echo ""
    print_info "Digite o nome do arquivo de backup para excluir:"
    read -p "Arquivo: " backup_filename
    
    if [ -z "$backup_filename" ]; then
        print_error "Nome do arquivo não pode ser vazio"
        press_enter
        return 1
    fi
    
    local backup_file="$BACKUP_DIR/$backup_filename"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Arquivo de backup não encontrado: $backup_filename"
        press_enter
        return 1
    fi
    
    echo ""
    read -p "Confirma a exclusão do backup '$backup_filename'? (s/n): " confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        print_info "Exclusão cancelada"
        press_enter
        return 0
    fi
    
    rm -f "$backup_file"
    print_success "Backup excluído com sucesso!"
    log_message "Backup $backup_filename excluído"
    press_enter
    return 0
}

delete_all_backups() {
    echo ""
    print_warning "ATENÇÃO: Todos os backups serão EXCLUÍDOS permanentemente!"
    echo ""
    read -p "Tem CERTEZA que deseja continuar? (s/n): " confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        print_info "Exclusão cancelada"
        press_enter
        return 0
    fi
    
    echo ""
    read -p "Digite 'EXCLUIR TUDO' em maiúsculas para confirmar: " confirm2
    if [ "$confirm2" != "EXCLUIR TUDO" ]; then
        print_info "Exclusão cancelada"
        press_enter
        return 0
    fi
    
    rm -rf "$BACKUP_DIR"/*.sql.gz 2>/dev/null
    print_success "Todos os backups foram excluídos!"
    log_message "Todos os backups foram excluídos"
    press_enter
    return 0
}

# ============================================
# GESTÃO DE USUÁRIOS
# ============================================

list_cluster_users() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    echo ""
    print_info "Usuários do cluster '$cluster_name':"
    echo ""
    
    echo -e "${CYAN}Usuário       | Superuser | Criar DB | Criar Role | Validade${NC}"
    echo "───────────────────────────────────────────────────────────────────────"
    
    local users_data=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -F'|' -c "SELECT rolname, CASE WHEN rolsuper THEN 'SIM' ELSE 'NAO' END, CASE WHEN rolcreatedb THEN 'SIM' ELSE 'NAO' END, CASE WHEN rolcreaterole THEN 'SIM' ELSE 'NAO' END, COALESCE(rolvaliduntil::text, 'Sem limite') FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname;" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$users_data" ]; then
        echo "$users_data" | while IFS='|' read -r user super createdb createrole valid; do
            [ -n "$user" ] && printf "%-13s | %-9s | %-8s | %-10s | %s\n" "$user" "$super" "$createdb" "$createrole" "$valid"
        done
    else
        print_warning "Nenhum usuário encontrado ou erro ao consultar"
    fi
    
    echo ""
}

manage_users() {
    clear_screen
    echo ""
    print_info "GESTÃO DE USUÁRIOS"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    # Listar clusters
    list_clusters
    echo ""
    
    # Selecionar cluster
    read -p "Nome do cluster: " cluster_name
    if [ -z "$cluster_name" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se cluster existe
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$cluster_name"; then
        print_error "Cluster '$cluster_name' não existe!"
        press_enter
        return 1
    fi
    
    # Obter porta do cluster
    local port=$(pg_lsclusters -h | grep "^$pg_version.*$cluster_name" | awk '{print $3}')
    
    # Solicitar senha do postgres
    echo ""
    print_info "Digite a senha do usuário postgres do cluster '$cluster_name':"
    read -sp "Senha: " postgres_password
    echo ""
    
    if [ -z "$postgres_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Verificar senha
    if ! sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
        print_error "Senha incorreta!"
        press_enter
        return 1
    fi
    
    # Loop do menu de usuários
    while true; do
        clear_screen
        echo ""
        print_info "GESTÃO DE USUÁRIOS - Cluster: $cluster_name"
        
        list_cluster_users "$pg_version" "$cluster_name" "$port" "$postgres_password"
        
        echo ""
        
        COLUMNS=1
        PS3="
Escolha uma opção: "
        
        options=(
            "Adicionar"
            "Excluir"
            "Alterar Senha"
            "Voltar"
        )
        
        select opt in "${options[@]}"
        do
            case $REPLY in
                1)
                    add_user "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                2)
                    delete_user "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                3)
                    change_user_password "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                4)
                    return 0
                    ;;
                *)
                    print_error "Opção inválida!"
                    sleep 1
                    break
                    ;;
            esac
        done
        
        # Se retornou 0 de alguma função, volta ao menu principal
        if [ $? -eq 0 ] && [ "$REPLY" = "4" ]; then
            return 0
        fi
    done
}

add_user() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    clear_screen
    echo ""
    print_info "ADICIONAR USUÁRIO - Cluster: $cluster_name"
    echo ""
    
    # Nome do usuário
    read -p "Nome do novo usuário: " username
    if [ -z "$username" ]; then
        print_error "Nome do usuário não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se usuário já existe
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -c "SELECT 1 FROM pg_user WHERE usename='$username';" 2>/dev/null | grep -q 1; then
        print_error "Usuário '$username' já existe!"
        press_enter
        return 1
    fi
    
    # Senha
    echo ""
    print_info "Configure a senha para o usuário '$username':"
    read -sp "Senha: " user_password
    echo ""
    read -sp "Confirme a senha: " user_password2
    echo ""
    
    if [ "$user_password" != "$user_password2" ]; then
        print_error "As senhas não correspondem!"
        press_enter
        return 1
    fi
    
    if [ -z "$user_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Permissões
    echo ""
    print_info "SUPERUSER: Acesso total ao banco, pode modificar qualquer objeto e usuário"
    read -p "Este usuário será SUPERUSER? (s/n): " is_super
    
    echo ""
    print_info "CREATEDB: Permite criar novos bancos de dados"
    read -p "Pode criar DATABASES? (s/n): " can_createdb
    
    echo ""
    print_info "CREATEROLE: Permite criar e gerenciar outros usuários/roles"
    read -p "Pode criar ROLES? (s/n): " can_createrole
    
    echo ""
    print_info "SCHEMA: Cria namespace isolado com o nome do usuário para organização"
    read -p "Criar schema com o nome do usuário? (s/n): " create_schema
    
    # Montar comando CREATE USER
    local create_cmd="CREATE USER $username WITH PASSWORD '$user_password'"
    
    if [ "$is_super" = "s" ] || [ "$is_super" = "S" ]; then
        create_cmd="$create_cmd SUPERUSER"
    else
        create_cmd="$create_cmd NOSUPERUSER"
    fi
    
    if [ "$can_createdb" = "s" ] || [ "$can_createdb" = "S" ]; then
        create_cmd="$create_cmd CREATEDB"
    else
        create_cmd="$create_cmd NOCREATEDB"
    fi
    
    if [ "$can_createrole" = "s" ] || [ "$can_createrole" = "S" ]; then
        create_cmd="$create_cmd CREATEROLE"
    else
        create_cmd="$create_cmd NOCREATEROLE"
    fi
    
    create_cmd="$create_cmd;"
    
    # Criar usuário
    echo ""
    print_info "Criando usuário '$username'..."
    
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "$create_cmd" > /dev/null 2>&1; then
        print_success "Usuário '$username' criado com sucesso!"
        log_message "Usuário $username criado no cluster $cluster_name"
        
        # Criar schema se solicitado
        if [ "$create_schema" = "s" ] || [ "$create_schema" = "S" ]; then
            print_info "Criando schema '$username'..."
            
            if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "CREATE SCHEMA $username AUTHORIZATION $username;" > /dev/null 2>&1; then
                print_success "Schema '$username' criado com sucesso!"
                
                # Configurar search_path padrão
                print_info "Configurando search_path padrão..."
                if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "ALTER USER $username SET search_path TO $username, public;" > /dev/null 2>&1; then
                    print_success "Search_path configurado: $username, public"
                    log_message "Schema $username criado e configurado para usuário $username no cluster $cluster_name"
                else
                    print_warning "Falha ao configurar search_path"
                fi
            else
                print_error "Falha ao criar schema '$username'"
            fi
        fi
    else
        print_error "Falha ao criar usuário '$username'"
    fi
    
    echo ""
    press_enter
    return 0
}

delete_user() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    clear_screen
    echo ""
    print_info "EXCLUIR USUÁRIO - Cluster: $cluster_name"
    echo ""
    
    list_cluster_users "$pg_version" "$cluster_name" "$port" "$postgres_password"
    
    echo ""
    read -p "Nome do usuário para excluir: " username
    
    if [ -z "$username" ]; then
        print_error "Nome do usuário não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Não permitir excluir postgres
    if [ "$username" = "postgres" ]; then
        print_error "Não é permitido excluir o usuário 'postgres'!"
        press_enter
        return 1
    fi
    
    # Verificar se usuário existe
    if ! sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -c "SELECT 1 FROM pg_user WHERE usename='$username';" 2>/dev/null | grep -q 1; then
        print_error "Usuário '$username' não existe!"
        press_enter
        return 1
    fi
    
    # Verificar se usuário tem objetos dependentes
    echo ""
    print_info "Verificando objetos pertencentes ao usuário '$username'..."
    
    local owned_objects=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "
        SELECT 
            CASE 
                WHEN n.nspname IS NOT NULL THEN 'Schema: ' || n.nspname
                WHEN t.tablename IS NOT NULL THEN 'Table: ' || t.schemaname || '.' || t.tablename
                WHEN v.viewname IS NOT NULL THEN 'View: ' || v.schemaname || '.' || v.viewname
                WHEN p.proname IS NOT NULL THEN 'Function: ' || p.proname
            END as objeto
        FROM pg_user u
        LEFT JOIN pg_namespace n ON n.nspowner = u.usesysid
        LEFT JOIN pg_tables t ON t.tableowner = u.usename
        LEFT JOIN pg_views v ON v.viewowner = u.usename
        LEFT JOIN pg_proc p ON p.proowner = u.usesysid
        WHERE u.usename = '$username' AND (n.nspname IS NOT NULL OR t.tablename IS NOT NULL OR v.viewname IS NOT NULL OR p.proname IS NOT NULL)
        LIMIT 10;
    " 2>/dev/null)
    
    if [ -n "$owned_objects" ]; then
        echo ""
        print_warning "O usuário '$username' possui objetos no banco de dados:"
        echo ""
        echo "$owned_objects" | head -10
        if [ $(echo "$owned_objects" | wc -l) -gt 10 ]; then
            echo "... (e mais objetos)"
        fi
        echo ""
        
        print_warning "ATENÇÃO: Você precisa escolher o que fazer com esses objetos:"
        echo ""
        echo "1) DELETAR TUDO (CASCADE)"
        print_info "   Remove o usuário E todos os objetos que ele possui"
        print_warning "   PERDA DE DADOS: Schemas, tabelas e dados serão EXCLUÍDOS permanentemente!"
        echo ""
        
        echo "2) TRANSFERIR para 'postgres'"
        print_info "   Transfere a propriedade dos objetos para o usuário postgres"
        print_success "   PRESERVA DADOS: Schemas, tabelas e dados continuam existindo"
        echo ""
        
        echo "3) CANCELAR"
        print_info "   Não faz nada e volta ao menu"
        echo ""
        
        read -p "Escolha uma opção (1/2/3): " delete_option
        
        case $delete_option in
            1)
                # DELETE CASCADE
                echo ""
                print_warning "CONFIRMAÇÃO FINAL - DELETAR TUDO CASCADE"
                print_error "TODOS os objetos do usuário serão EXCLUÍDOS PERMANENTEMENTE!"
                echo ""
                read -p "Digite 'DELETAR TUDO' em maiúsculas para confirmar: " final_confirm
                
                if [ "$final_confirm" != "DELETAR TUDO" ]; then
                    print_info "Exclusão cancelada"
                    press_enter
                    return 0
                fi
                
                echo ""
                print_info "Removendo objetos do usuário '$username'..."
                if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "DROP OWNED BY $username CASCADE;" > /dev/null 2>&1; then
                    print_success "Objetos removidos com sucesso!"
                    
                    print_info "Excluindo usuário '$username'..."
                    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "DROP USER $username;" > /dev/null 2>&1; then
                        print_success "Usuário '$username' excluído com sucesso!"
                        log_message "Usuário $username excluído (CASCADE) do cluster $cluster_name"
                    else
                        print_error "Falha ao excluir usuário '$username'"
                    fi
                else
                    print_error "Falha ao remover objetos do usuário"
                fi
                ;;
                
            2)
                # TRANSFERIR para postgres
                echo ""
                print_info "Transferindo objetos do usuário '$username' para 'postgres'..."
                if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "REASSIGN OWNED BY $username TO postgres;" > /dev/null 2>&1; then
                    print_success "Objetos transferidos para 'postgres' com sucesso!"
                    
                    # Remover privilégios residuais
                    sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "DROP OWNED BY $username;" > /dev/null 2>&1
                    
                    print_info "Excluindo usuário '$username'..."
                    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "DROP USER $username;" > /dev/null 2>&1; then
                        print_success "Usuário '$username' excluído com sucesso!"
                        print_info "Objetos preservados sob propriedade do usuário 'postgres'"
                        log_message "Usuário $username excluído (objetos transferidos para postgres) do cluster $cluster_name"
                    else
                        print_error "Falha ao excluir usuário '$username'"
                    fi
                else
                    print_error "Falha ao transferir objetos"
                fi
                ;;
                
            3)
                print_info "Exclusão cancelada"
                press_enter
                return 0
                ;;
                
            *)
                print_error "Opção inválida! Exclusão cancelada."
                press_enter
                return 1
                ;;
        esac
        
    else
        # Usuário não tem objetos, pode deletar direto
        echo ""
        print_success "Usuário não possui objetos dependentes"
        echo ""
        print_warning "ATENÇÃO: O usuário '$username' será EXCLUÍDO permanentemente!"
        echo ""
        read -p "Digite o nome do usuário para confirmar: " confirm
        
        if [ "$confirm" != "$username" ]; then
            print_warning "Nome não corresponde. Exclusão cancelada."
            press_enter
            return 1
        fi
        
        read -p "Tem CERTEZA? (s/n): " confirm2
        if [ "$confirm2" != "s" ] && [ "$confirm2" != "S" ]; then
            print_info "Exclusão cancelada"
            press_enter
            return 0
        fi
        
        # Excluir usuário
        echo ""
        print_info "Excluindo usuário '$username'..."
        
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "DROP USER $username;" > /dev/null 2>&1; then
            print_success "Usuário '$username' excluído com sucesso!"
            log_message "Usuário $username excluído do cluster $cluster_name"
        else
            print_error "Falha ao excluir usuário '$username'"
        fi
    fi
    
    echo ""
    press_enter
    return 0
}

change_user_password() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    clear_screen
    echo ""
    print_info "ALTERAR SENHA DE USUÁRIO - Cluster: $cluster_name"
    echo ""
    
    list_cluster_users "$pg_version" "$cluster_name" "$port" "$postgres_password"
    
    echo ""
    read -p "Nome do usuário: " username
    
    if [ -z "$username" ]; then
        print_error "Nome do usuário não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se usuário existe
    if ! sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -c "SELECT 1 FROM pg_user WHERE usename='$username';" 2>/dev/null | grep -q 1; then
        print_error "Usuário '$username' não existe!"
        press_enter
        return 1
    fi
    
    # Nova senha
    echo ""
    print_info "Configure a nova senha para o usuário '$username':"
    read -sp "Nova senha: " new_password
    echo ""
    read -sp "Confirme a nova senha: " new_password2
    echo ""
    
    if [ "$new_password" != "$new_password2" ]; then
        print_error "As senhas não correspondem!"
        press_enter
        return 1
    fi
    
    if [ -z "$new_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Alterar senha
    echo ""
    print_info "Alterando senha do usuário '$username'..."
    
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "ALTER USER $username WITH PASSWORD '$new_password';" > /dev/null 2>&1; then
        print_success "Senha do usuário '$username' alterada com sucesso!"
        log_message "Senha do usuário $username alterada no cluster $cluster_name"
    else
        print_error "Falha ao alterar senha do usuário '$username'"
    fi
    
    echo ""
    press_enter
    return 0
}

# ============================================
# GESTÃO DE DATABASES E SCHEMAS
# ============================================

manage_databases_schemas() {
    clear_screen
    echo ""
    print_info "DATABASES E SCHEMAS"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    # Listar clusters
    list_clusters
    echo ""
    
    # Selecionar cluster
    read -p "Nome do cluster: " cluster_name
    if [ -z "$cluster_name" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se cluster existe
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$cluster_name"; then
        print_error "Cluster '$cluster_name' não existe!"
        press_enter
        return 1
    fi
    
    # Obter porta do cluster
    local port=$(pg_lsclusters -h | grep "^$pg_version.*$cluster_name" | awk '{print $3}')
    
    # Solicitar senha do postgres
    echo ""
    print_info "Digite a senha do usuário postgres do cluster '$cluster_name':"
    read -sp "Senha: " postgres_password
    echo ""
    
    if [ -z "$postgres_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Verificar senha
    if ! sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
        print_error "Senha incorreta!"
        press_enter
        return 1
    fi
    
    # Loop do menu databases e schemas
    while true; do
        clear_screen
        echo ""
        print_info "DATABASES E SCHEMAS - Cluster: $cluster_name"
        echo ""
        
        COLUMNS=1
        PS3="
Escolha uma opção: "
        
        options=(
            "Gerenciar Databases"
            "Gerenciar Schemas"
            "Gerenciar Permissões"
            "Voltar"
        )
        
        select opt in "${options[@]}"
        do
            case $REPLY in
                1)
                    menu_databases "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                2)
                    menu_schemas "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                3)
                    menu_permissions "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                4)
                    return 0
                    ;;
                *)
                    print_error "Opção inválida!"
                    sleep 1
                    break
                    ;;
            esac
        done
        
        if [ $? -eq 0 ] && [ "$REPLY" = "4" ]; then
            return 0
        fi
    done
}

# Funcionalidades de Databases
menu_databases() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    while true; do
        clear_screen
        echo ""
        print_info "GERENCIAR DATABASES - Cluster: $cluster_name"
        
        list_databases "$pg_version" "$cluster_name" "$port" "$postgres_password"
        
        echo ""
        
        COLUMNS=1
        PS3="
Escolha uma opção: "
        
        options=(
            "Criar Database"
            "Excluir Database"
            "Voltar"
        )
        
        select opt in "${options[@]}"
        do
            case $REPLY in
                1)
                    create_database "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                2)
                    delete_database "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                3)
                    return 0
                    ;;
                *)
                    print_error "Opção inválida!"
                    sleep 1
                    break
                    ;;
            esac
        done
        
        if [ $? -eq 0 ] && [ "$REPLY" = "3" ]; then
            return 0
        fi
    done
}

list_databases() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    echo ""
    print_info "Databases do cluster '$cluster_name':"
    echo ""
    
    echo -e "${CYAN}Database      | Owner     | Encoding | Tamanho  | Conexões${NC}"
    echo "────────────────────────────────────────────────────────────────"
    
    local db_data=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -F'|' -c "SELECT d.datname, pg_catalog.pg_get_userbyid(d.datdba), pg_encoding_to_char(d.encoding), pg_size_pretty(pg_database_size(d.datname)), (SELECT count(*) FROM pg_stat_activity WHERE datname = d.datname) || '/' || d.datconnlimit FROM pg_database d WHERE d.datistemplate = false ORDER BY d.datname;" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$db_data" ]; then
        echo "$db_data" | while IFS='|' read -r dbname owner encoding size conns; do
            [ -n "$dbname" ] && printf "%-13s | %-9s | %-8s | %-8s | %s\n" "$dbname" "$owner" "$encoding" "$size" "$conns"
        done
    else
        print_warning "Erro ao listar databases"
    fi
    
    echo ""
}

create_database() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    clear_screen
    echo ""
    print_info "CRIAR DATABASE - Cluster: $cluster_name"
    echo ""
    
    read -p "Nome do database: " db_name
    if [ -z "$db_name" ]; then
        print_error "Nome do database não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se já existe
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname='$db_name';" 2>/dev/null | grep -q 1; then
        print_error "Database '$db_name' já existe!"
        press_enter
        return 1
    fi
    
    # Listar usuários disponíveis
    local users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname;" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    
    echo ""
    print_info "OWNER: Usuário dono do database, tem controle total"
    echo "Usuários disponíveis: $users"
    read -p "Owner [postgres]: " db_owner
    db_owner=${db_owner:-postgres}
    
    echo ""
    print_info "ENCODING: Conjunto de caracteres (UTF8 recomendado)"
    read -p "Encoding [UTF8]: " db_encoding
    db_encoding=${db_encoding:-UTF8}
    
    echo ""
    print_info "TEMPLATE: Database modelo (template1 = com objetos padrão)"
    read -p "Template [template1]: " db_template
    db_template=${db_template:-template1}
    
    # Criar database
    echo ""
    print_info "Criando database '$db_name'..."
    
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "CREATE DATABASE $db_name WITH OWNER = $db_owner ENCODING = '$db_encoding' TEMPLATE = $db_template;" > /dev/null 2>&1; then
        print_success "Database '$db_name' criado com sucesso!"
        log_message "Database $db_name criado no cluster $cluster_name"
        
        # Configurar permissões
        echo ""
        print_info "PERMISSÕES: Conceder acesso a outros usuários agora?"
        read -p "Configurar permissões? (s/n): " config_perms
        
        if [ "$config_perms" = "s" ] || [ "$config_perms" = "S" ]; then
            local non_super_users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true AND rolsuper = false AND rolname != '$db_owner' ORDER BY rolname;" 2>/dev/null | tr '\n' ' ')
            
            if [ -n "$non_super_users" ]; then
                echo ""
                echo "Usuários disponíveis: $non_super_users"
                
                echo ""
                print_info "CONNECT: Permite conectar ao database"
                read -p "Conceder CONNECT para quais usuários? (separados por espaço ou ENTER): " connect_users
                
                echo ""
                print_info "CREATE: Permite criar schemas dentro do database"
                read -p "Conceder CREATE para quais usuários? (separados por espaço ou ENTER): " create_users
                
                # Aplicar CONNECT
                if [ -n "$connect_users" ]; then
                    for user in $connect_users; do
                        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "GRANT CONNECT ON DATABASE $db_name TO $user;" > /dev/null 2>&1; then
                            print_success "CONNECT concedido para '$user'"
                        fi
                    done
                fi
                
                # Aplicar CREATE
                if [ -n "$create_users" ]; then
                    for user in $create_users; do
                        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "GRANT CREATE ON DATABASE $db_name TO $user;" > /dev/null 2>&1; then
                            print_success "CREATE concedido para '$user'"
                        fi
                    done
                fi
            else
                print_warning "Não há usuários não-superusers para configurar"
            fi
        fi
    else
        print_error "Falha ao criar database '$db_name'"
    fi
    
    echo ""
    press_enter
    return 0
}

delete_database() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    clear_screen
    echo ""
    print_info "EXCLUIR DATABASE - Cluster: $cluster_name"
    echo ""
    
    list_databases "$pg_version" "$cluster_name" "$port" "$postgres_password"
    
    echo ""
    read -p "Nome do database para excluir: " db_name
    
    if [ -z "$db_name" ]; then
        print_error "Nome do database não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Proteção para databases do sistema
    if [ "$db_name" = "postgres" ] || [ "$db_name" = "template0" ] || [ "$db_name" = "template1" ]; then
        print_error "Não é permitido excluir o database '$db_name' (database do sistema)!"
        press_enter
        return 1
    fi
    
    # Verificar se existe
    if ! sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname='$db_name';" 2>/dev/null | grep -q 1; then
        print_error "Database '$db_name' não existe!"
        press_enter
        return 1
    fi
    
    # Confirmação
    echo ""
    print_warning "ATENÇÃO: O database '$db_name' será EXCLUÍDO permanentemente!"
    print_error "TODOS OS DADOS serão perdidos!"
    echo ""
    read -p "Digite o nome do database para confirmar: " confirm
    
    if [ "$confirm" != "$db_name" ]; then
        print_warning "Nome não corresponde. Exclusão cancelada."
        press_enter
        return 1
    fi
    
    read -p "Tem CERTEZA? (s/n): " confirm2
    if [ "$confirm2" != "s" ] && [ "$confirm2" != "S" ]; then
        print_info "Exclusão cancelada"
        press_enter
        return 0
    fi
    
    # Encerrar conexões ativas
    echo ""
    print_info "Encerrando conexões ativas no database '$db_name'..."
    sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name';" > /dev/null 2>&1
    
    # Excluir database
    print_info "Excluindo database '$db_name'..."
    
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "DROP DATABASE $db_name;" > /dev/null 2>&1; then
        print_success "Database '$db_name' excluído com sucesso!"
        log_message "Database $db_name excluído do cluster $cluster_name"
    else
        print_error "Falha ao excluir database '$db_name'"
    fi
    
    echo ""
    press_enter
    return 0
}

# Schemas
menu_schemas() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    while true; do
        clear_screen
        echo ""
        print_info "GERENCIAR SCHEMAS - Cluster: $cluster_name"
        echo ""
        
        # Selecionar database
        print_info "Selecione o database:"
        local databases=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null)
        
        if [ -z "$databases" ]; then
            print_error "Não há databases disponíveis"
            press_enter
            return 1
        fi
        
        echo "$databases" | nl
        echo ""
        read -p "Número do database: " db_num
        
        local selected_db=$(echo "$databases" | sed -n "${db_num}p")
        
        if [ -z "$selected_db" ]; then
            print_error "Database inválido"
            press_enter
            continue
        fi
        
        list_schemas "$pg_version" "$cluster_name" "$port" "$postgres_password" "$selected_db"
        
        echo ""
        
        COLUMNS=1
        PS3="
Escolha uma opção: "
        
        options=(
            "Criar Schema"
            "Excluir Schema"
            "Mudar Database"
            "Voltar"
        )
        
        select opt in "${options[@]}"
        do
            case $REPLY in
                1)
                    create_schema "$pg_version" "$cluster_name" "$port" "$postgres_password" "$selected_db"
                    break
                    ;;
                2)
                    delete_schema "$pg_version" "$cluster_name" "$port" "$postgres_password" "$selected_db"
                    break
                    ;;
                3)
                    break
                    ;;
                4)
                    return 0
                    ;;
                *)
                    print_error "Opção inválida!"
                    sleep 1
                    break
                    ;;
            esac
        done
        
        if [ $? -eq 0 ] && [ "$REPLY" = "4" ]; then
            return 0
        fi
    done
}

list_schemas() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    local db_name=$5
    
    echo ""
    print_info "Schemas do database '$db_name':"
    echo ""
    
    echo -e "${CYAN}Schema          | Owner     | Tabelas | Views | Funções${NC}"
    echo "────────────────────────────────────────────────────────────────"
    
    local schema_data=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -t -A -F'|' -c "SELECT n.nspname, pg_catalog.pg_get_userbyid(n.nspowner), (SELECT count(*) FROM pg_tables WHERE schemaname = n.nspname), (SELECT count(*) FROM pg_views WHERE schemaname = n.nspname), (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = n.oid) FROM pg_namespace n WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' ORDER BY n.nspname;" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$schema_data" ]; then
        echo "$schema_data" | while IFS='|' read -r schema owner tables views funcs; do
            [ -n "$schema" ] && printf "%-15s | %-9s | %-7s | %-5s | %s\n" "$schema" "$owner" "$tables" "$views" "$funcs"
        done
    else
        print_warning "Erro ao listar schemas"
    fi
    
    echo ""
}

create_schema() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    local db_name=$5
    
    clear_screen
    echo ""
    print_info "CRIAR SCHEMA - Database: $db_name"
    echo ""
    
    read -p "Nome do schema: " schema_name
    if [ -z "$schema_name" ]; then
        print_error "Nome do schema não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Verificar se já existe
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -t -c "SELECT 1 FROM pg_namespace WHERE nspname='$schema_name';" 2>/dev/null | grep -q 1; then
        print_error "Schema '$schema_name' já existe no database '$db_name'!"
        press_enter
        return 1
    fi
    
    # Listar usuários disponíveis
    local users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname;" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    
    echo ""
    print_info "OWNER: Usuário dono do schema, tem controle total"
    echo "Usuários disponíveis: $users"
    read -p "Owner [postgres]: " schema_owner
    schema_owner=${schema_owner:-postgres}
    
    # Criar schema
    echo ""
    print_info "Criando schema '$schema_name'..."
    
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "CREATE SCHEMA $schema_name AUTHORIZATION $schema_owner;" > /dev/null 2>&1; then
        print_success "Schema '$schema_name' criado com sucesso!"
        log_message "Schema $schema_name criado no database $db_name do cluster $cluster_name"
        
        # Configurar search_path
        echo ""
        print_info "SEARCH_PATH: Ordem de busca de objetos (schemas separados por vírgula)"
        read -p "Adicionar ao search_path do owner? (s/n): " set_search_path
        
        if [ "$set_search_path" = "s" ] || [ "$set_search_path" = "S" ]; then
            if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "ALTER ROLE $schema_owner IN DATABASE $db_name SET search_path TO $schema_name, public;" > /dev/null 2>&1; then
                print_success "search_path configurado para '$schema_owner'"
            fi
        fi
        
        # Configurar permissões
        echo ""
        print_info "PERMISSÕES: Conceder acesso a outros usuários agora?"
        read -p "Configurar permissões? (s/n): " config_perms
        
        if [ "$config_perms" = "s" ] || [ "$config_perms" = "S" ]; then
            local non_super_users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true AND rolsuper = false AND rolname != '$schema_owner' ORDER BY rolname;" 2>/dev/null | tr '\n' ' ')
            
            if [ -n "$non_super_users" ]; then
                echo ""
                echo "Usuários disponíveis: $non_super_users"
                
                echo ""
                print_info "USAGE: Permite usar objetos do schema (SELECT, INSERT, etc)"
                read -p "Conceder USAGE para quais usuários? (separados por espaço ou ENTER): " usage_users
                
                echo ""
                print_info "CREATE: Permite criar objetos dentro do schema"
                read -p "Conceder CREATE para quais usuários? (separados por espaço ou ENTER): " create_users
                
                # Aplicar USAGE
                if [ -n "$usage_users" ]; then
                    for user in $usage_users; do
                        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "GRANT USAGE ON SCHEMA $schema_name TO $user;" > /dev/null 2>&1; then
                            print_success "USAGE concedido para '$user'"
                        fi
                    done
                fi
                
                # Aplicar CREATE
                if [ -n "$create_users" ]; then
                    for user in $create_users; do
                        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "GRANT CREATE ON SCHEMA $schema_name TO $user;" > /dev/null 2>&1; then
                            print_success "CREATE concedido para '$user'"
                        fi
                    done
                fi
            else
                print_warning "Não há usuários não-superusers para configurar"
            fi
        fi
    else
        print_error "Falha ao criar schema '$schema_name'"
    fi
    
    echo ""
    press_enter
    return 0
}

delete_schema() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    local db_name=$5
    
    clear_screen
    echo ""
    print_info "EXCLUIR SCHEMA - Database: $db_name"
    echo ""
    
    list_schemas "$pg_version" "$cluster_name" "$port" "$postgres_password" "$db_name"
    
    echo ""
    read -p "Nome do schema para excluir: " schema_name
    
    if [ -z "$schema_name" ]; then
        print_error "Nome do schema não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Proteção para schemas do sistema
    if [ "$schema_name" = "public" ] || [ "$schema_name" = "pg_catalog" ] || [ "$schema_name" = "information_schema" ]; then
        print_error "Não é permitido excluir o schema '$schema_name' (schema do sistema)!"
        press_enter
        return 1
    fi
    
    # Verificar se existe
    if ! sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -t -c "SELECT 1 FROM pg_namespace WHERE nspname='$schema_name';" 2>/dev/null | grep -q 1; then
        print_error "Schema '$schema_name' não existe!"
        press_enter
        return 1
    fi
    
    # Verificar objetos dependentes
    echo ""
    print_info "Verificando objetos dependentes..."
    
    local tables=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -t -c "SELECT count(*) FROM pg_tables WHERE schemaname = '$schema_name';" 2>/dev/null | tr -d ' ')
    local views=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -t -c "SELECT count(*) FROM pg_views WHERE schemaname = '$schema_name';" 2>/dev/null | tr -d ' ')
    local funcs=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -t -c "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = '$schema_name';" 2>/dev/null | tr -d ' ')
    
    if [ "$tables" -gt 0 ] || [ "$views" -gt 0 ] || [ "$funcs" -gt 0 ]; then
        print_warning "ATENÇÃO: O schema '$schema_name' contém objetos:"
        echo "  - Tabelas: $tables"
        echo "  - Views: $views"
        echo "  - Funções: $funcs"
        echo ""
        
        print_info "O que fazer com os objetos?"
        echo "1) CASCADE - Excluir o schema e TODOS os objetos"
        echo "2) RESTRICT - Cancelar se houver objetos (seguro)"
        echo "3) CANCELAR - Não fazer nada"
        echo ""
        read -p "Escolha (1/2/3): " action
        
        case "$action" in
            1)
                cascade_opt="CASCADE"
                print_warning "CUIDADO: Todos os objetos serão EXCLUÍDOS permanentemente!"
                ;;
            2)
                cascade_opt="RESTRICT"
                ;;
            3|*)
                print_info "Exclusão cancelada"
                press_enter
                return 0
                ;;
        esac
    else
        cascade_opt="RESTRICT"
    fi
    
    # Confirmação
    echo ""
    print_warning "ATENÇÃO: O schema '$schema_name' será EXCLUÍDO!"
    if [ "$cascade_opt" = "CASCADE" ]; then
        print_error "TODOS OS DADOS serão perdidos!"
    fi
    echo ""
    read -p "Digite o nome do schema para confirmar: " confirm
    
    if [ "$confirm" != "$schema_name" ]; then
        print_warning "Nome não corresponde. Exclusão cancelada."
        press_enter
        return 1
    fi
    
    read -p "Tem CERTEZA? (s/n): " confirm2
    if [ "$confirm2" != "s" ] && [ "$confirm2" != "S" ]; then
        print_info "Exclusão cancelada"
        press_enter
        return 0
    fi
    
    # Excluir schema
    echo ""
    print_info "Excluindo schema '$schema_name'..."
    
    if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "DROP SCHEMA $schema_name $cascade_opt;" > /dev/null 2>&1; then
        print_success "Schema '$schema_name' excluído com sucesso!"
        log_message "Schema $schema_name excluído do database $db_name do cluster $cluster_name"
    else
        print_error "Falha ao excluir schema '$schema_name'"
        if [ "$cascade_opt" = "RESTRICT" ]; then
            print_warning "Use CASCADE se quiser excluir todos os objetos"
        fi
    fi
    
    echo ""
    press_enter
    return 0
}

# Permissões
menu_permissions() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    while true; do
        clear_screen
        echo ""
        print_info "GERENCIAR PERMISSÕES - Cluster: $cluster_name"
        echo ""
        
        COLUMNS=1
        PS3="
Escolha uma opção: "
        
        options=(
            "Permissões de Databases"
            "Permissões de Schemas"
            "Voltar"
        )
        
        select opt in "${options[@]}"
        do
            case $REPLY in
                1)
                    menu_database_permissions "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                2)
                    menu_schema_permissions "$pg_version" "$cluster_name" "$port" "$postgres_password"
                    break
                    ;;
                3)
                    return 0
                    ;;
                *)
                    print_error "Opção inválida!"
                    sleep 1
                    break
                    ;;
            esac
        done
        
        if [ $? -eq 0 ] && [ "$REPLY" = "3" ]; then
            return 0
        fi
    done
}

menu_database_permissions() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    clear_screen
    echo ""
    print_info "PERMISSÕES DE DATABASES - Cluster: $cluster_name"
    echo ""
    
    # Selecionar database
    list_databases "$pg_version" "$cluster_name" "$port" "$postgres_password"
    
    echo ""
    read -p "Nome do database: " db_name
    
    if [ -z "$db_name" ]; then
        print_error "Nome do database não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Listar permissões atuais
    echo ""
    print_info "Permissões do database '$db_name':"
    echo ""
    
    echo -e "${CYAN}Usuário    | CONNECT | CREATE${NC}"
    echo "──────────────────────────────────────"
    
    local perm_data=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -F'|' -c "SELECT r.rolname, CASE WHEN has_database_privilege(r.rolname, '$db_name', 'CONNECT') THEN 'SIM' ELSE 'NÃO' END AS connect, CASE WHEN has_database_privilege(r.rolname, '$db_name', 'CREATE') THEN 'SIM' ELSE 'NÃO' END AS create FROM pg_roles r WHERE r.rolcanlogin = true ORDER BY r.rolname;" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$perm_data" ]; then
        echo "$perm_data" | while IFS='|' read -r role connect create; do
            [ -n "$role" ] && printf "%-10s | %-7s | %s\n" "$role" "$connect" "$create"
        done
    fi
    
    echo ""
    
    COLUMNS=1
    PS3="
Escolha uma opção: "
    
    options=(
        "Conceder Permissões"
        "Revogar Permissões"
        "Voltar"
    )
    
    select opt in "${options[@]}"
    do
        case $REPLY in
            1)
                grant_database_permissions "$pg_version" "$cluster_name" "$port" "$postgres_password" "$db_name"
                break
                ;;
            2)
                revoke_database_permissions "$pg_version" "$cluster_name" "$port" "$postgres_password" "$db_name"
                break
                ;;
            3)
                return 0
                ;;
            *)
                print_error "Opção inválida!"
                sleep 1
                break
                ;;
        esac
    done
}

grant_database_permissions() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    local db_name=$5
    
    echo ""
    print_info "CONCEDER PERMISSÕES - Database: $db_name"
    echo ""
    
    # Listar usuários
    local users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname;" 2>/dev/null | tr '\n' ' ')
    
    echo "Usuários disponíveis: $users"
    echo ""
    read -p "Usuário: " user_name
    
    if [ -z "$user_name" ]; then
        print_error "Nome do usuário não pode ser vazio"
        press_enter
        return 1
    fi
    
    echo ""
    print_info "CONNECT: Permite conectar ao database"
    read -p "Conceder CONNECT? (s/n): " grant_connect
    
    echo ""
    print_info "CREATE: Permite criar schemas dentro do database"
    read -p "Conceder CREATE? (s/n): " grant_create
    
    echo ""
    
    # Aplicar permissões
    if [ "$grant_connect" = "s" ] || [ "$grant_connect" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "GRANT CONNECT ON DATABASE $db_name TO $user_name;" > /dev/null 2>&1; then
            print_success "CONNECT concedido para '$user_name'"
        else
            print_error "Falha ao conceder CONNECT"
        fi
    fi
    
    if [ "$grant_create" = "s" ] || [ "$grant_create" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "GRANT CREATE ON DATABASE $db_name TO $user_name;" > /dev/null 2>&1; then
            print_success "CREATE concedido para '$user_name'"
        else
            print_error "Falha ao conceder CREATE"
        fi
    fi
    
    echo ""
    press_enter
    return 0
}

revoke_database_permissions() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    local db_name=$5
    
    echo ""
    print_info "REVOGAR PERMISSÕES - Database: $db_name"
    echo ""
    
    # Listar usuários
    local users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname;" 2>/dev/null | tr '\n' ' ')
    
    echo "Usuários disponíveis: $users"
    echo ""
    read -p "Usuário: " user_name
    
    if [ -z "$user_name" ]; then
        print_error "Nome do usuário não pode ser vazio"
        press_enter
        return 1
    fi
    
    echo ""
    read -p "Revogar CONNECT? (s/n): " revoke_connect
    
    echo ""
    read -p "Revogar CREATE? (s/n): " revoke_create
    
    echo ""
    
    # Revogar permissões
    if [ "$revoke_connect" = "s" ] || [ "$revoke_connect" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "REVOKE CONNECT ON DATABASE $db_name FROM $user_name;" > /dev/null 2>&1; then
            print_success "CONNECT revogado de '$user_name'"
        else
            print_error "Falha ao revogar CONNECT"
        fi
    fi
    
    if [ "$revoke_create" = "s" ] || [ "$revoke_create" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -c "REVOKE CREATE ON DATABASE $db_name FROM $user_name;" > /dev/null 2>&1; then
            print_success "CREATE revogado de '$user_name'"
        else
            print_error "Falha ao revogar CREATE"
        fi
    fi
    
    echo ""
    press_enter
    return 0
}

menu_schema_permissions() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    
    clear_screen
    echo ""
    print_info "PERMISSÕES DE SCHEMAS - Cluster: $cluster_name"
    echo ""
    
    # Selecionar database
    print_info "Selecione o database:"
    local databases=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null)
    
    if [ -z "$databases" ]; then
        print_error "Não há databases disponíveis"
        press_enter
        return 1
    fi
    
    echo "$databases" | nl
    echo ""
    read -p "Número do database: " db_num
    
    local db_name=$(echo "$databases" | sed -n "${db_num}p")
    
    if [ -z "$db_name" ]; then
        print_error "Database inválido"
        press_enter
        return 1
    fi
    
    # Listar schemas
    list_schemas "$pg_version" "$cluster_name" "$port" "$postgres_password" "$db_name"
    
    echo ""
    read -p "Nome do schema: " schema_name
    
    if [ -z "$schema_name" ]; then
        print_error "Nome do schema não pode ser vazio"
        press_enter
        return 1
    fi
    
    # Listar permissões atuais
    echo ""
    print_info "Permissões do schema '$schema_name':"
    echo ""
    
    echo -e "${CYAN}Usuário    | USAGE | CREATE${NC}"
    echo "──────────────────────────────────────"
    
    local perm_data=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -t -A -F'|' -c "SELECT r.rolname, CASE WHEN has_schema_privilege(r.rolname, '$schema_name', 'USAGE') THEN 'SIM' ELSE 'NÃO' END AS usage, CASE WHEN has_schema_privilege(r.rolname, '$schema_name', 'CREATE') THEN 'SIM' ELSE 'NÃO' END AS create FROM pg_roles r WHERE r.rolcanlogin = true ORDER BY r.rolname;" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$perm_data" ]; then
        echo "$perm_data" | while IFS='|' read -r role usage create; do
            [ -n "$role" ] && printf "%-10s | %-5s | %s\n" "$role" "$usage" "$create"
        done
    fi
    
    echo ""
    
    COLUMNS=1
    PS3="
Escolha uma opção: "
    
    options=(
        "Conceder Permissões"
        "Revogar Permissões"
        "Voltar"
    )
    
    select opt in "${options[@]}"
    do
        case $REPLY in
            1)
                grant_schema_permissions "$pg_version" "$cluster_name" "$port" "$postgres_password" "$db_name" "$schema_name"
                break
                ;;
            2)
                revoke_schema_permissions "$pg_version" "$cluster_name" "$port" "$postgres_password" "$db_name" "$schema_name"
                break
                ;;
            3)
                return 0
                ;;
            *)
                print_error "Opção inválida!"
                sleep 1
                break
                ;;
        esac
    done
}

grant_schema_permissions() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    local db_name=$5
    local schema_name=$6
    
    echo ""
    print_info "CONCEDER PERMISSÕES - Schema: $schema_name"
    echo ""
    
    # Listar usuários
    local users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname;" 2>/dev/null | tr '\n' ' ')
    
    echo "Usuários disponíveis: $users"
    echo ""
    read -p "Usuário: " user_name
    
    if [ -z "$user_name" ]; then
        print_error "Nome do usuário não pode ser vazio"
        press_enter
        return 1
    fi
    
    echo ""
    print_info "USAGE: Permite usar objetos do schema (SELECT, INSERT, etc)"
    read -p "Conceder USAGE? (s/n): " grant_usage
    
    echo ""
    print_info "CREATE: Permite criar objetos dentro do schema"
    read -p "Conceder CREATE? (s/n): " grant_create
    
    echo ""
    
    # Aplicar permissões
    if [ "$grant_usage" = "s" ] || [ "$grant_usage" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "GRANT USAGE ON SCHEMA $schema_name TO $user_name;" > /dev/null 2>&1; then
            print_success "USAGE concedido para '$user_name'"
        else
            print_error "Falha ao conceder USAGE"
        fi
    fi
    
    if [ "$grant_create" = "s" ] || [ "$grant_create" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "GRANT CREATE ON SCHEMA $schema_name TO $user_name;" > /dev/null 2>&1; then
            print_success "CREATE concedido para '$user_name'"
        else
            print_error "Falha ao conceder CREATE"
        fi
    fi
    
    echo ""
    press_enter
    return 0
}

revoke_schema_permissions() {
    local pg_version=$1
    local cluster_name=$2
    local port=$3
    local postgres_password=$4
    local db_name=$5
    local schema_name=$6
    
    echo ""
    print_info "REVOGAR PERMISSÕES - Schema: $schema_name"
    echo ""
    
    # Listar usuários
    local users=$(sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d postgres -t -A -c "SELECT rolname FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname;" 2>/dev/null | tr '\n' ' ')
    
    echo "Usuários disponíveis: $users"
    echo ""
    read -p "Usuário: " user_name
    
    if [ -z "$user_name" ]; then
        print_error "Nome do usuário não pode ser vazio"
        press_enter
        return 1
    fi
    
    echo ""
    read -p "Revogar USAGE? (s/n): " revoke_usage
    
    echo ""
    read -p "Revogar CREATE? (s/n): " revoke_create
    
    echo ""
    
    # Revogar permissões
    if [ "$revoke_usage" = "s" ] || [ "$revoke_usage" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "REVOKE USAGE ON SCHEMA $schema_name FROM $user_name;" > /dev/null 2>&1; then
            print_success "USAGE revogado de '$user_name'"
        else
            print_error "Falha ao revogar USAGE"
        fi
    fi
    
    if [ "$revoke_create" = "s" ] || [ "$revoke_create" = "S" ]; then
        if sudo PGPASSWORD="$postgres_password" -u postgres psql -p "$port" -d "$db_name" -c "REVOKE CREATE ON SCHEMA $schema_name FROM $user_name;" > /dev/null 2>&1; then
            print_success "CREATE revogado de '$user_name'"
        else
            print_error "Falha ao revogar CREATE"
        fi
    fi
    
    echo ""
    press_enter
    return 0
}

# ============================================
# MENU DE CLUSTERS
# ============================================

menu_clusters() {
    while true; do
        show_cluster_menu
        
        # Se retornou do show_cluster_menu (que agora tem select integrado),
        # verificamos se deve voltar ao menu principal
        local last_reply=$?
        if [ $last_reply -eq 0 ]; then
            return 0
        fi
    done
}

# ============================================
# FUNÇÕES DE REPLICAÇÃO
# ============================================

get_cluster_role() {
    local version=$1
    local cluster=$2
    
    # Verificar se existe standby.signal
    local datadir=$(pg_lsclusters -h | grep "^$version.*$cluster" | awk '{print $6}')
    
    if [ -f "$datadir/standby.signal" ]; then
        echo "STANDBY"
        return 0
    fi
    
    # Verificar status no pg_lsclusters
    if pg_lsclusters -h | grep "^$version.*$cluster" | grep -q "recovery"; then
        echo "STANDBY"
        return 0
    fi
    
    # Verificar se postgresql.conf tem configurações de replicação PRIMARY
    local config_dir=$(get_config_dir "$version" "$cluster")
    local pg_conf="$config_dir/postgresql.conf"
    if [ -f "$pg_conf" ]; then
        # Verificar APENAS linhas não comentadas (que não começam com #)
        if grep -qE "^[[:space:]]*wal_level[[:space:]]*=[[:space:]]*replica" "$pg_conf"; then
            if grep -qE "^[[:space:]]*max_wal_senders[[:space:]]*=[[:space:]]*[1-9]" "$pg_conf"; then
                echo "PRIMARY"
                return 0
            fi
        fi
        # Verificar se tem max_wal_senders > 0 sem comentário
        if grep -qE "^[[:space:]]*max_wal_senders[[:space:]]*=[[:space:]]*[1-9]" "$pg_conf"; then
            echo "PRIMARY"
            return 0
        fi
    fi
    
    echo "STANDALONE"
}

list_clusters_with_role() {
    local pg_version=$(detect_pg_version)
    
    echo ""
    print_info "Clusters PostgreSQL:"
    echo ""
    
    if [ -z "$pg_version" ]; then
        print_warning "PostgreSQL não está instalado"
        return 1
    fi
    
    if pg_lsclusters -h 2>/dev/null | grep -q "$pg_version"; then
        echo -e "${CYAN}Ver | Cluster | Porta | Status      | Função    | Diretório${NC}"
        echo "────────────────────────────────────────────────────────────────────────────"
        
        while IFS= read -r line; do
            local version=$(echo "$line" | awk '{print $1}')
            local cluster=$(echo "$line" | awk '{print $2}')
            local port=$(echo "$line" | awk '{print $3}')
            local status=$(echo "$line" | awk '{print $4}')
            local datadir=$(echo "$line" | awk '{print $6}')
            
            local role=$(get_cluster_role "$version" "$cluster")
            
            if [ "$role" = "PRIMARY" ]; then
                echo -e "$version  $cluster     $port  $status  ${GREEN}PRIMARY${NC}   $datadir"
            elif [ "$role" = "STANDBY" ]; then
                echo -e "$version  $cluster     $port  $status  ${YELLOW}STANDBY${NC}   $datadir"
            else
                echo -e "$version  $cluster     $port  $status  ${GRAY}STANDALONE${NC} $datadir"
            fi
        done < <(pg_lsclusters -h | grep "^$pg_version")
        
        echo ""
        return 0
    else
        print_warning "Nenhum cluster encontrado"
        return 1
    fi
}

show_replication_menu() {
    clear_screen
    echo ""
    print_info "CONFIGURAR REPLICAÇÃO"
    echo ""
    
    list_clusters_with_role
    
    echo ""
    
    COLUMNS=1
    PS3="
Escolha uma opção: "
    
    options=(
        "Adicionar"
        "Excluir"
        "Ver Replicas"
        "Voltar"
    )
    
    select opt in "${options[@]}"
    do
        case $REPLY in
            1)
                create_replication
                return
                ;;
            2)
                remove_replication
                return
                ;;
            3)
                show_replication_status
                return
                ;;
            4)
                return 0
                ;;
            *)
                print_error "Opção inválida!"
                sleep 1
                return
                ;;
        esac
    done
}

configure_replication_params() {
    local mode=$1
    
    # Valores padrão
    SYNC_COMMIT="off"
    WAL_KEEP_SIZE="1GB"
    MAX_WAL_SENDERS="3"
    USE_REPLICATION_SLOT="sim"
    HOT_STANDBY_FEEDBACK="on"
    
    if [ "$mode" = "simples" ]; then
        clear_screen
        echo ""
        print_info "CONFIGURAR REPLICAÇÃO - MODO SIMPLES"
        echo ""
        echo -e "${YELLOW}PARÂMETROS DE REPLICAÇÃO${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
        echo ""
        echo "Synchronous Commit: $SYNC_COMMIT (assíncrono - mais rápido)"
        echo "WAL Keep Size: $WAL_KEEP_SIZE"
        echo "Max WAL Senders: $MAX_WAL_SENDERS"
        echo "Replication Slot: $USE_REPLICATION_SLOT"
        echo "Hot Standby Feedback: $HOT_STANDBY_FEEDBACK"
        echo ""
        press_enter
    else
        clear_screen
        echo ""
        print_info "CONFIGURAR REPLICAÇÃO - MODO AVANÇADO"
        echo ""
        echo -e "${YELLOW}PARÂMETROS DE REPLICAÇÃO${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
        echo ""
        
        # 1. Synchronous Commit
        echo -e "${YELLOW}[1/5] Synchronous Commit (Confirmação Síncrona)${NC}"
        echo -e "      ${YELLOW}• ON: Mais lento, máxima segurança (aguarda STANDBY confirmar)${NC}"
        echo -e "      ${YELLOW}• OFF: Mais rápido, pode perder transações em falha catastrófica${NC}"
        echo -e "      ${GRAY}Padrão: off | Opções: on/off${NC}"
        read -p "Digite: [off] " input
        SYNC_COMMIT=${input:-off}
        echo ""
        
        # 2. WAL Keep Size
        echo -e "${YELLOW}[2/5] WAL Keep Size (Espaço Reservado para WAL)${NC}"
        echo -e "      ${YELLOW}• Espaço em disco reservado para logs de transação${NC}"
        echo -e "      ${YELLOW}• Mais espaço = STANDBY pode ficar offline por mais tempo${NC}"
        echo -e "      ${GRAY}Padrão: 1GB | Exemplos: 512MB, 1GB, 2GB, 5GB${NC}"
        read -p "Digite: [1GB] " input
        WAL_KEEP_SIZE=${input:-1GB}
        echo ""
        
        # 3. Max WAL Senders
        echo -e "${YELLOW}[3/5] Max WAL Senders (Conexões STANDBY Simultâneas)${NC}"
        echo -e "      ${YELLOW}• Número máximo de STANDBYs que podem conectar simultaneamente${NC}"
        echo -e "      ${YELLOW}• Mais senders = mais memória usada (~64MB por sender)${NC}"
        echo -e "      ${GRAY}Padrão: 3 | Mínimo: 2 | Máximo: 10${NC}"
        read -p "Digite: [3] " input
        MAX_WAL_SENDERS=${input:-3}
        echo ""
        
        # 4. Replication Slot
        echo -e "${YELLOW}[4/5] Replication Slot (Garantir WAL não seja deletado)${NC}"
        echo -e "      ${YELLOW}• Impede PRIMARY deletar WAL antes do STANDBY processar${NC}"
        echo -e "      ${YELLOW}• Atenção: pode encher disco se STANDBY ficar offline muito tempo${NC}"
        echo -e "      ${GRAY}Padrão: sim | Opções: sim/não${NC}"
        read -p "Digite: [sim] " input
        USE_REPLICATION_SLOT=${input:-sim}
        echo ""
        
        # 5. Hot Standby Feedback
        echo -e "${YELLOW}[5/5] Hot Standby Feedback (Evitar conflitos de VACUUM)${NC}"
        echo -e "      ${YELLOW}• STANDBY informa PRIMARY sobre queries ativas${NC}"
        echo -e "      ${YELLOW}• Previne cancelamento de queries longas no STANDBY${NC}"
        echo -e "      ${GRAY}Padrão: on | Opções: on/off${NC}"
        read -p "Digite: [on] " input
        HOT_STANDBY_FEEDBACK=${input:-on}
        echo ""
    fi
}

create_replication() {
    clear_screen
    echo ""
    print_info "CRIAR REPLICAÇÃO"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    # Listar clusters
    list_clusters_with_role
    echo ""
    
    # Selecionar PRIMARY
    read -p "Nome do cluster PRIMARY: " primary_cluster
    if [ -z "$primary_cluster" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$primary_cluster"; then
        print_error "Cluster '$primary_cluster' não existe!"
        press_enter
        return 1
    fi
    
    local primary_role=$(get_cluster_role "$pg_version" "$primary_cluster")
    if [ "$primary_role" = "STANDBY" ]; then
        print_error "Cluster '$primary_cluster' já é STANDBY de outro cluster!"
        press_enter
        return 1
    fi
    
    # Selecionar STANDBY
    read -p "Nome do cluster STANDBY: " standby_cluster
    if [ -z "$standby_cluster" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    if [ "$standby_cluster" = "$primary_cluster" ]; then
        print_error "STANDBY não pode ser o mesmo que PRIMARY!"
        press_enter
        return 1
    fi
    
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$standby_cluster"; then
        print_error "Cluster '$standby_cluster' não existe!"
        press_enter
        return 1
    fi
    
    # Confirmar destruição do STANDBY
    echo ""
    print_warning "ATENÇÃO: O cluster '$standby_cluster' será DESTRUÍDO e recriado!"
    print_warning "Todos os dados do cluster '$standby_cluster' serão PERDIDOS!"
    echo ""
    read -p "Digite o nome do cluster STANDBY para confirmar: " confirm
    if [ "$confirm" != "$standby_cluster" ]; then
        print_info "Operação cancelada"
        press_enter
        return 0
    fi
    
    # Senha do replicator
    echo ""
    print_info "Configure a senha para o usuário replicator:"
    read -sp "Senha: " replicator_password
    echo ""
    read -sp "Confirme a senha: " replicator_password2
    echo ""
    
    if [ "$replicator_password" != "$replicator_password2" ]; then
        print_error "As senhas não correspondem!"
        press_enter
        return 1
    fi
    
    if [ -z "$replicator_password" ]; then
        print_error "A senha não pode ser vazia!"
        press_enter
        return 1
    fi
    
    # Escolher modo
    echo ""
    print_info "Escolha o modo de configuração:"
    echo ""
    echo "1) Modo Simples (Recomendado)"
    echo "2) Modo Avançado (Personalizar parâmetros)"
    echo ""
    read -p "Opção: " mode_choice
    
    if [ "$mode_choice" = "2" ]; then
        configure_replication_params "avancado"
    else
        configure_replication_params "simples"
    fi
    
    # Iniciar configuração
    echo ""
    print_info "Iniciando configuração da replicação..."
    echo ""
    
    setup_primary_for_replication "$pg_version" "$primary_cluster" "$replicator_password"
    setup_standby_for_replication "$pg_version" "$primary_cluster" "$standby_cluster" "$replicator_password"
    
    echo ""
    print_success "Replicação configurada com sucesso!"
    echo ""
    print_info "Status dos clusters:"
    list_clusters_with_role
    echo ""
    
    log_message "Replicação criada: $primary_cluster -> $standby_cluster"
    press_enter
}

setup_primary_for_replication() {
    local pg_version=$1
    local primary_cluster=$2
    local replicator_password=$3
    
    local primary_port=$(pg_lsclusters -h | grep "^$pg_version.*$primary_cluster" | awk '{print $3}')
    local config_dir=$(get_config_dir "$pg_version" "$primary_cluster")
    local pg_conf="$config_dir/postgresql.conf"
    local pg_hba="$config_dir/pg_hba.conf"
    local tailscale_ip=$(detect_local_ip)
    
    print_info "Configurando PRIMARY '$primary_cluster'..."
    
    # Temporariamente permitir conexões locais sem senha para admin
    print_info "Ajustando autenticação temporária..."
    cp "$pg_hba" "$pg_hba.tmp"
    sed -i '1i local   all             postgres                                peer' "$pg_hba"
    pg_ctlcluster $pg_version $primary_cluster reload >/dev/null 2>&1
    sleep 1
    
    # Criar usuário replicator
    print_info "Criando usuário replicator..."
    sudo -u postgres psql -p $primary_port -c "DROP ROLE IF EXISTS replicator;" >/dev/null 2>&1
    sudo -u postgres psql -p $primary_port -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '$replicator_password';" >/dev/null 2>&1
    
    # Restaurar pg_hba.conf
    cp "$pg_hba.tmp" "$pg_hba"
    chmod 640 "$pg_hba"
    chown postgres:postgres "$pg_hba"
    rm -f "$pg_hba.tmp"
    
    # Configurar postgresql.conf
    print_info "Configurando postgresql.conf..."
    
    # Backup
    cp "$pg_conf" "$pg_conf.bak.$(date +%Y%m%d_%H%M%S)"
    
    # Atualizar parâmetros (substituir se existir, adicionar se não existir)
    grep -q "^#*listen_addresses" "$pg_conf" && sed -i "s/^#*listen_addresses.*/listen_addresses = 'localhost,$tailscale_ip'/" "$pg_conf" || echo "listen_addresses = 'localhost,$tailscale_ip'" >> "$pg_conf"
    grep -q "^#*wal_level" "$pg_conf" && sed -i "s/^#*wal_level.*/wal_level = replica/" "$pg_conf" || echo "wal_level = replica" >> "$pg_conf"
    grep -q "^#*max_wal_senders" "$pg_conf" && sed -i "s/^#*max_wal_senders.*/max_wal_senders = $MAX_WAL_SENDERS/" "$pg_conf" || echo "max_wal_senders = $MAX_WAL_SENDERS" >> "$pg_conf"
    grep -q "^#*max_replication_slots" "$pg_conf" && sed -i "s/^#*max_replication_slots.*/max_replication_slots = 2/" "$pg_conf" || echo "max_replication_slots = 2" >> "$pg_conf"
    grep -q "^#*hot_standby" "$pg_conf" && sed -i "s/^#*hot_standby.*/hot_standby = on/" "$pg_conf" || echo "hot_standby = on" >> "$pg_conf"
    grep -q "^#*synchronous_commit" "$pg_conf" && sed -i "s/^#*synchronous_commit.*/synchronous_commit = $SYNC_COMMIT/" "$pg_conf" || echo "synchronous_commit = $SYNC_COMMIT" >> "$pg_conf"
    
    # WAL keep (depende da versão)
    if [ "$pg_version" -ge 13 ]; then
        grep -q "^#*wal_keep_size" "$pg_conf" && sed -i "s/^#*wal_keep_size.*/wal_keep_size = $WAL_KEEP_SIZE/" "$pg_conf" || echo "wal_keep_size = $WAL_KEEP_SIZE" >> "$pg_conf"
    else
        local segments=$((${WAL_KEEP_SIZE//[!0-9]/} * 64))
        grep -q "^#*wal_keep_segments" "$pg_conf" && sed -i "s/^#*wal_keep_segments.*/wal_keep_segments = $segments/" "$pg_conf" || echo "wal_keep_segments = $segments" >> "$pg_conf"
    fi
    
    # Configurar pg_hba.conf para replicação
    print_info "Configurando pg_hba.conf..."
    
    if ! grep -q "# Replication connections" "$pg_hba"; then
        echo "" >> "$pg_hba"
        echo "# Replication connections" >> "$pg_hba"
        echo "host    replication     replicator      127.0.0.1/32            scram-sha-256" >> "$pg_hba"
        echo "host    replication     replicator      $tailscale_ip/32        scram-sha-256" >> "$pg_hba"
        echo "host    replication     replicator      100.0.0.0/8             scram-sha-256" >> "$pg_hba"
    fi
    
    # Reiniciar PRIMARY
    print_info "Reiniciando PRIMARY..."
    pg_ctlcluster $pg_version $primary_cluster restart >/dev/null 2>&1
    
    # Aguardar PRIMARY aceitar conexões
    print_info "Aguardando PRIMARY aceitar conexões..."
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        # Verificar se o cluster está online primeiro
        if pg_lsclusters -h | grep "^$pg_version.*$primary_cluster" | grep -q "online"; then
            # Testar conexão de replicação via rede
            if PGPASSWORD="$replicator_password" psql -h $tailscale_ip -p $primary_port -U replicator -d postgres -c "IDENTIFY_SYSTEM" >/dev/null 2>&1; then
                print_success "PRIMARY configurado e aceitando conexões de replicação!"
                break
            fi
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    if [ $waited -ge $max_wait ]; then
        print_warning "PRIMARY não respondeu em ${max_wait}s, mas o pg_basebackup pode funcionar mesmo assim"
    fi
}

setup_standby_for_replication() {
    local pg_version=$1
    local primary_cluster=$2
    local standby_cluster=$3
    local replicator_password=$4
    
    local primary_port=$(pg_lsclusters -h | grep "^$pg_version.*$primary_cluster" | awk '{print $3}')
    local standby_port=$(pg_lsclusters -h | grep "^$pg_version.*$standby_cluster" | awk '{print $3}')
    local standby_datadir=$(pg_lsclusters -h | grep "^$pg_version.*$standby_cluster" | awk '{print $6}')
    local tailscale_ip=$(detect_local_ip)
    
    print_info "Configurando STANDBY '$standby_cluster'..."
    
    # Parar STANDBY
    print_info "Parando cluster STANDBY..."
    pg_ctlcluster $pg_version $standby_cluster stop >/dev/null 2>&1
    
    # Remover dados antigos
    print_info "Removendo dados antigos do STANDBY..."
    rm -rf "$standby_datadir"/*
    
    # pg_basebackup com PGPASSWORD
    print_info "Copiando dados do PRIMARY (pg_basebackup)..."
    sudo -u postgres bash -c "PGPASSWORD='$replicator_password' pg_basebackup -h $tailscale_ip -p $primary_port -U replicator -D '$standby_datadir' -Fp -Xs -P -R"
    
    if [ $? -ne 0 ]; then
        print_error "Falha no pg_basebackup!"
        press_enter
        return 1
    fi
    
    # Configurar porta do STANDBY
    print_info "Configurando porta do STANDBY..."
    echo "port = $standby_port" >> "$standby_datadir/postgresql.auto.conf"
    
    # Configurar parâmetros do STANDBY
    print_info "Configurando parâmetros do STANDBY..."
    echo "hot_standby = on" >> "$standby_datadir/postgresql.auto.conf"
    echo "hot_standby_feedback = $HOT_STANDBY_FEEDBACK" >> "$standby_datadir/postgresql.auto.conf"
    echo "primary_conninfo = 'host=$tailscale_ip port=$primary_port user=replicator password=$replicator_password'" >> "$standby_datadir/postgresql.auto.conf"
    
    # Criar replication slot se solicitado
    if [ "$USE_REPLICATION_SLOT" = "sim" ]; then
        print_info "Criando replication slot..."
        local slot_name="${standby_cluster}_slot"
        local primary_config_dir=$(get_config_dir "$pg_version" "$primary_cluster")
        local pg_hba="$primary_config_dir/pg_hba.conf"
        
        # Adicionar peer temporário
        sed -i '1i local   all             postgres                                peer' "$pg_hba"
        pg_ctlcluster $pg_version $primary_cluster reload >/dev/null 2>&1
        sleep 1
        
        # Criar slot
        sudo -u postgres psql -p $primary_port -c "SELECT pg_create_physical_replication_slot('$slot_name');" >/dev/null 2>&1
        
        # Remover peer temporário
        sed -i '/^local   all             postgres.*peer$/d' "$pg_hba"
        pg_ctlcluster $pg_version $primary_cluster reload >/dev/null 2>&1
        
        echo "primary_slot_name = '$slot_name'" >> "$standby_datadir/postgresql.auto.conf"
    fi
    
    # Ajustar permissões
    chown -R postgres:postgres "$standby_datadir"
    
    # Iniciar STANDBY
    print_info "Iniciando STANDBY..."
    pg_ctlcluster $pg_version $standby_cluster start >/dev/null 2>&1
    
    print_success "STANDBY configurado!"
}

remove_replication() {
    clear_screen
    echo ""
    print_info "REMOVER REPLICAÇÃO"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    list_clusters_with_role
    echo ""
    
    read -p "Nome do cluster STANDBY: " standby_cluster
    
    if [ -z "$standby_cluster" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$standby_cluster"; then
        print_error "Cluster '$standby_cluster' não existe!"
        press_enter
        return 1
    fi
    
    local role=$(get_cluster_role "$pg_version" "$standby_cluster")
    if [ "$role" != "STANDBY" ]; then
        print_error "Cluster '$standby_cluster' não é um STANDBY!"
        press_enter
        return 1
    fi
    
    # Detectar PRIMARY
    echo ""
    read -p "Nome do cluster PRIMARY: " primary_cluster
    
    if [ -z "$primary_cluster" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$primary_cluster"; then
        print_error "Cluster '$primary_cluster' não existe!"
        press_enter
        return 1
    fi
    
    local primary_role=$(get_cluster_role "$pg_version" "$primary_cluster")
    if [ "$primary_role" != "PRIMARY" ]; then
        print_error "Cluster '$primary_cluster' não é um PRIMARY!"
        press_enter
        return 1
    fi
    
    echo ""
    print_warning "Esta operação irá:"
    echo -e "  ${YELLOW}•${NC} Limpar replication slot e usuário replicator do PRIMARY"
    echo -e "  ${YELLOW}•${NC} Fazer backup completo do PRIMARY"
    echo -e "  ${YELLOW}•${NC} Reverter ambos clusters para modo STANDALONE"
    echo -e "  ${YELLOW}•${NC} Importar backup do PRIMARY no STANDBY (dados ficam idênticos)"
    echo ""
    read -p "Confirma? (s/n): " confirm
    
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        print_info "Operação cancelada"
        press_enter
        return 0
    fi
    
    local primary_port=$(pg_lsclusters -h | grep "^$pg_version.*$primary_cluster" | awk '{print $3}')
    local primary_datadir=$(pg_lsclusters -h | grep "^$pg_version.*$primary_cluster" | awk '{print $6}')
    local standby_port=$(pg_lsclusters -h | grep "^$pg_version.*$standby_cluster" | awk '{print $3}')
    local standby_datadir=$(pg_lsclusters -h | grep "^$pg_version.*$standby_cluster" | awk '{print $6}')
    
    # Criar diretório de backup
    local backup_dir="./backup"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/${primary_cluster}_$(date +%Y%m%d_%H%M%S).sql"
    
    echo ""
    print_info "========================================="
    print_info "ETAPA 1: LIMPANDO PRIMARY"
    print_info "========================================="
    echo ""
    
    # Adicionar peer temporário para operações sem senha
    local primary_config_dir=$(get_config_dir "$pg_version" "$primary_cluster")
    local pg_hba="$primary_config_dir/pg_hba.conf"
    sed -i '1i local   all             postgres                                peer' "$pg_hba"
    pg_ctlcluster $pg_version $primary_cluster reload >/dev/null 2>&1
    sleep 1
    
    # Remover replication slot do PRIMARY
    print_info "Removendo replication slot do PRIMARY..."
    local slot_name=$(sudo -u postgres psql -p $primary_port -tAc "SELECT slot_name FROM pg_replication_slots WHERE slot_type='physical' LIMIT 1;" 2>/dev/null | tr -d '\n')
    
    if [ -n "$slot_name" ]; then
        sudo -u postgres psql -p $primary_port -c "SELECT pg_drop_replication_slot('$slot_name');" >/dev/null 2>&1
        print_success "Replication slot '$slot_name' removido"
    else
        print_warning "Nenhum replication slot encontrado"
    fi
    
    # Remover usuário replicator do PRIMARY
    print_info "Removendo usuário replicator do PRIMARY..."
    sudo -u postgres psql -p $primary_port -c "DROP ROLE IF EXISTS replicator;" >/dev/null 2>&1
    print_success "Usuário replicator removido"
    
    # Fazer backup do PRIMARY
    echo ""
    print_info "Criando backup completo do PRIMARY..."
    print_info "Arquivo: $backup_file"
    sudo -u postgres pg_dumpall > "$backup_file"
    
    if [ $? -eq 0 ]; then
        local backup_size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup criado com sucesso! Tamanho: $backup_size"
    else
        print_error "Falha ao criar backup!"
        press_enter
        return 1
    fi
    
    # Parar PRIMARY
    echo ""
    print_info "Parando cluster PRIMARY..."
    pg_ctlcluster $pg_version $primary_cluster stop >/dev/null 2>&1
    print_success "PRIMARY parado"
    
    # Limpar pg_hba.conf do PRIMARY
    print_info "Limpando pg_hba.conf do PRIMARY..."
    sed -i '/^local   all             postgres.*peer$/d' "$primary_config_dir/pg_hba.conf"
    sed -i '/replicator/d' "$primary_config_dir/pg_hba.conf"
    
    # Reverter postgresql.conf do PRIMARY
    print_info "Revertendo postgresql.conf do PRIMARY..."
    sed -i '/wal_level = replica/d' "$primary_config_dir/postgresql.conf"
    sed -i '/max_wal_senders/d' "$primary_config_dir/postgresql.conf"
    sed -i '/wal_keep_size/d' "$primary_config_dir/postgresql.conf"
    sed -i '/max_replication_slots/d' "$primary_config_dir/postgresql.conf"
    
    # Iniciar PRIMARY
    print_info "Iniciando cluster PRIMARY como STANDALONE..."
    pg_ctlcluster $pg_version $primary_cluster start >/dev/null 2>&1
    print_success "PRIMARY iniciado como STANDALONE"
    
    echo ""
    print_info "========================================="
    print_info "ETAPA 2: CONFIGURANDO STANDBY"
    print_info "========================================="
    echo ""
    
    # Parar STANDBY
    print_info "Parando cluster STANDBY..."
    pg_ctlcluster $pg_version $standby_cluster stop >/dev/null 2>&1
    print_success "STANDBY parado"
    
    # Remover standby.signal
    print_info "Removendo standby.signal..."
    rm -f "$standby_datadir/standby.signal"
    
    # Limpar postgresql.auto.conf do STANDBY
    print_info "Limpando postgresql.auto.conf do STANDBY..."
    sed -i '/primary_conninfo/d' "$standby_datadir/postgresql.auto.conf"
    sed -i '/primary_slot_name/d' "$standby_datadir/postgresql.auto.conf"
    
    # Limpar pg_hba.conf do STANDBY
    print_info "Limpando pg_hba.conf do STANDBY..."
    local standby_config_dir=$(get_config_dir "$pg_version" "$standby_cluster")
    sed -i '/replicator/d' "$standby_config_dir/pg_hba.conf"
    
    # Reverter postgresql.conf do STANDBY
    print_info "Revertendo postgresql.conf do STANDBY..."
    sed -i '/hot_standby_feedback/d' "$standby_config_dir/postgresql.conf"
    
    # Adicionar peer temporário no STANDBY para import sem senha
    sed -i '1i local   all             postgres                                peer' "$standby_config_dir/pg_hba.conf"
    
    # Iniciar STANDBY
    print_info "Iniciando cluster STANDBY como STANDALONE..."
    pg_ctlcluster $pg_version $standby_cluster start >/dev/null 2>&1
    print_success "STANDBY iniciado como STANDALONE"
    
    # Aguardar cluster ficar pronto
    sleep 2
    
    # Importar backup no STANDBY
    echo ""
    print_info "Importando backup do PRIMARY no STANDBY..."
    print_warning "Isso pode demorar alguns minutos..."
    sudo -u postgres psql -p $standby_port -f "$backup_file" postgres >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "Backup importado com sucesso!"
    else
        print_error "Falha ao importar backup!"
        press_enter
        return 1
    fi
    
    # Remover peer temporário
    sed -i '/^local   all             postgres.*peer$/d' "$standby_config_dir/pg_hba.conf"
    pg_ctlcluster $pg_version $standby_cluster reload >/dev/null 2>&1
    
    echo ""
    print_info "========================================="
    print_success "REPLICAÇÃO REMOVIDA COM SUCESSO!"
    print_info "========================================="
    echo ""
    print_info "Ambos clusters agora são STANDALONE com dados idênticos"
    print_info "Backup: $backup_file"
    echo ""
    
    log_message "Replicação removida: $primary_cluster <-> $standby_cluster"
    press_enter
}

clean_replication_config() {
    clear_screen
    echo ""
    print_info "LIMPAR CONFIGURAÇÕES DE REPLICAÇÃO"
    echo ""
    print_warning "Use esta opção para limpar configurações de replicação de qualquer cluster"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    list_clusters_with_role
    echo ""
    
    read -p "Nome do cluster para limpar: " cluster_name
    
    if [ -z "$cluster_name" ]; then
        print_error "Nome do cluster não pode ser vazio"
        press_enter
        return 1
    fi
    
    if ! pg_lsclusters -h | grep -q "^$pg_version.*$cluster_name"; then
        print_error "Cluster '$cluster_name' não existe!"
        press_enter
        return 1
    fi
    
    local cluster_port=$(pg_lsclusters -h | grep "^$pg_version.*$cluster_name" | awk '{print $3}')
    local cluster_datadir=$(pg_lsclusters -h | grep "^$pg_version.*$cluster_name" | awk '{print $6}')
    local config_dir=$(get_config_dir "$pg_version" "$cluster_name")
    local pg_conf="$config_dir/postgresql.conf"
    local pg_hba="$config_dir/pg_hba.conf"
    local role=$(get_cluster_role "$pg_version" "$cluster_name")
    
    echo ""
    print_info "Cluster: $cluster_name"
    print_info "Função atual: $role"
    echo ""
    print_warning "Esta operação irá:"
    echo "  • Remover configurações de replicação PRIMARY"
    echo "  • Remover configurações de replicação STANDBY"
    echo "  • Remover replication slots"
    echo "  • Converter cluster para STANDALONE"
    echo ""
    read -p "Confirma? (s/n): " confirm
    
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        print_info "Operação cancelada"
        press_enter
        return 0
    fi
    
    echo ""
    
    # Iniciar cluster se estiver parado
    if ! pg_lsclusters -h | grep "^$pg_version.*$cluster_name" | grep -q "online"; then
        print_info "Iniciando cluster..."
        pg_ctlcluster $pg_version $cluster_name start >/dev/null 2>&1
        sleep 2
    fi
    
    # Remover standby.signal
    if [ -f "$cluster_datadir/standby.signal" ]; then
        print_info "Removendo standby.signal..."
        rm -f "$cluster_datadir/standby.signal"
        print_info "Promovendo para read/write..."
        pg_ctlcluster $pg_version $cluster_name promote >/dev/null 2>&1
        sleep 2
    fi
    
    # Limpar postgresql.auto.conf
    print_info "Limpando postgresql.auto.conf..."
    if [ -f "$cluster_datadir/postgresql.auto.conf" ]; then
        sed -i '/primary_conninfo/d' "$cluster_datadir/postgresql.auto.conf"
        sed -i '/primary_slot_name/d' "$cluster_datadir/postgresql.auto.conf"
        sed -i '/hot_standby_feedback/d' "$cluster_datadir/postgresql.auto.conf"
    fi
    
    # Limpar postgresql.conf
    print_info "Limpando postgresql.conf..."
    cp "$pg_conf" "$pg_conf.bak.clean.$(date +%Y%m%d_%H%M%S)"
    sed -i 's/^wal_level = replica/#wal_level = replica/' "$pg_conf"
    sed -i 's/^max_wal_senders = [0-9]*/#max_wal_senders = 10/' "$pg_conf"
    sed -i 's/^max_replication_slots = [0-9]*/#max_replication_slots = 10/' "$pg_conf"
    sed -i 's/^synchronous_commit = .*/#synchronous_commit = on/' "$pg_conf"
    sed -i 's/^wal_keep_size = .*/#wal_keep_size = 0/' "$pg_conf"
    sed -i 's/^wal_keep_segments = .*/#wal_keep_segments = 0/' "$pg_conf"
    
    # Limpar pg_hba.conf de replication entries
    print_info "Limpando pg_hba.conf..."
    cp "$pg_hba" "$pg_hba.bak.clean.$(date +%Y%m%d_%H%M%S)"
    sed -i '/# Replication connections/d' "$pg_hba"
    sed -i '/replication.*replicator/d' "$pg_hba"
    
    # Adicionar peer temporário para limpar replication slots
    sed -i '1i local   all             postgres                                peer' "$pg_hba"
    pg_ctlcluster $pg_version $cluster_name reload >/dev/null 2>&1
    sleep 1
    
    # Dropar replication slots
    print_info "Removendo replication slots..."
    local slots=$(sudo -u postgres psql -p $cluster_port -tAc "SELECT slot_name FROM pg_replication_slots;" 2>/dev/null)
    if [ -n "$slots" ]; then
        while read -r slot; do
            if [ -n "$slot" ]; then
                sudo -u postgres psql -p $cluster_port -c "SELECT pg_drop_replication_slot('$slot');" >/dev/null 2>&1
                print_success "Slot '$slot' removido"
            fi
        done <<< "$slots"
    fi
    
    # Dropar usuário replicator
    print_info "Removendo usuário replicator..."
    sudo -u postgres psql -p $cluster_port -c "DROP ROLE IF EXISTS replicator;" >/dev/null 2>&1
    
    # Remover peer temporário
    sed -i '/^local   all             postgres.*peer/d' "$pg_hba"
    
    # Reiniciar cluster
    print_info "Reiniciando cluster..."
    pg_ctlcluster $pg_version $cluster_name restart >/dev/null 2>&1
    
    echo ""
    print_success "Configurações de replicação limpas com sucesso!"
    echo ""
    print_info "Cluster '$cluster_name' agora é STANDALONE"
    print_info "Backups: $pg_conf.bak.clean.* e $pg_hba.bak.clean.*"
    echo ""
    
    log_message "Configurações de replicação limpas: $cluster_name"
    press_enter
}

show_replication_status() {
    clear_screen
    echo ""
    print_info "STATUS DA REPLICAÇÃO"
    echo ""
    
    local pg_version=$(detect_pg_version)
    
    list_clusters_with_role
    echo ""
    
    # Listar replication slots
    print_info "Replication Slots:"
    echo ""
    
    local clusters=$(pg_lsclusters -h | grep "^$pg_version" | awk '{print $2}')
    local found_slots=false
    
    for cluster in $clusters; do
        local port=$(pg_lsclusters -h | grep "^$pg_version.*$cluster" | awk '{print $3}')
        local role=$(get_cluster_role "$pg_version" "$cluster")
        
        if [ "$role" = "PRIMARY" ]; then
            # Adicionar peer temporário para consulta sem senha
            local config_dir=$(get_config_dir "$pg_version" "$cluster")
            local pg_hba="$config_dir/pg_hba.conf"
            sed -i '1i local   all             postgres                                peer' "$pg_hba"
            pg_ctlcluster $pg_version $cluster reload >/dev/null 2>&1
            sleep 1
            
            # Consultar slots
            local slots=$(sudo -u postgres psql -p $port -tAc "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;" 2>/dev/null)
            
            # Remover peer temporário
            sed -i '/^local   all             postgres.*peer$/d' "$pg_hba"
            pg_ctlcluster $pg_version $cluster reload >/dev/null 2>&1
            
            if [ -n "$slots" ]; then
                echo -e "${GREEN}PRIMARY:${NC} $cluster (porta $port)"
                echo "  Slot Name          | Ativo | LSN"
                echo "  ───────────────────┼───────┼────────────"
                echo "$slots" | while IFS='|' read -r slot active lsn; do
                    if [ "$active" = "t" ]; then
                        echo -e "  $slot | ${GREEN}Sim${NC}   | $lsn"
                    else
                        echo -e "  $slot | ${RED}Não${NC}   | $lsn"
                    fi
                done
                echo ""
                found_slots=true
            fi
        fi
    done
    
    if [ "$found_slots" = false ]; then
        print_warning "Nenhum replication slot encontrado"
    fi
    
    echo ""
    press_enter
}

menu_replication() {
    while true; do
        show_replication_menu
        
        local last_reply=$?
        if [ $last_reply -eq 0 ]; then
            return 0
        fi
    done
}

# ============================================
# FUNÇÃO PRINCIPAL
# ============================================

main() {
    check_root
    
    touch "$LOG_FILE" 2>/dev/null
    chmod 644 "$LOG_FILE" 2>/dev/null
    
    log_message "Script iniciado - Versão $SCRIPT_VERSION"
    
    while true; do
        show_main_menu
    done
}

# Executar
main
