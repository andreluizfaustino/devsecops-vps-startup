# PostgreSQL Cluster Management Tool

[![Version](https://img.shields.io/badge/version-1.0-blue.svg)](https://github.com/andreluizfaustino/devsecops-vps-startup)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12--17-336791.svg)](https://www.postgresql.org/)

Script Bash completo para gerenciamento de clusters PostgreSQL em ambientes Ubuntu/Debian. Oferece uma interface interativa para instalação, configuração, backup, gerenciamento de usuários, databases, schemas e permissões.

## 📋 Índice

- [Características](#-características)
- [Pré-requisitos](#-pré-requisitos)
- [Instalação](#-instalação)
- [Uso](#-uso)
- [Funcionalidades](#-funcionalidades)
- [Estrutura de Menus](#-estrutura-de-menus)
- [Exemplos de Uso](#-exemplos-de-uso)
- [Arquitetura](#-arquitetura)
- [Segurança](#-segurança)
- [Troubleshooting](#-troubleshooting)
- [Contribuindo](#-contribuindo)
- [Autor](#-autor)

## 🚀 Características

### Gerenciamento de Clusters
- ✅ Criar clusters com configuração customizada
- ✅ Listar todos os clusters ativos
- ✅ Excluir clusters com limpeza completa
- ✅ Configuração automática de autenticação (pg_hba.conf)
- ✅ Suporte a múltiplas versões (PostgreSQL 12-17)

### Backup & Restore
- ✅ Backup completo (pg_dumpall) com compressão gzip
- ✅ Importação de backups com validação
- ✅ Gerenciamento de backups (listar, excluir)
- ✅ Nomenclatura padronizada: `{cluster}_{YYYYMMDD}_{HHMMSS}.sql.gz`

### Gerenciamento de Usuários
- ✅ Criar usuários com permissões customizadas (SUPERUSER, CREATEDB, CREATEROLE)
- ✅ Criar schema automaticamente durante criação do usuário
- ✅ Excluir usuários com detecção de dependências
- ✅ Opções CASCADE ou REASSIGN OWNED BY
- ✅ Alterar senhas de usuários existentes

### Gerenciamento de Databases
- ✅ Criar databases com owner, encoding e template customizáveis
- ✅ Listar databases com informações detalhadas (tamanho, conexões, encoding)
- ✅ Excluir databases com proteção para objetos do sistema
- ✅ Configurar permissões CONNECT e CREATE durante criação
- ✅ Encerramento automático de conexões ativas

### Gerenciamento de Schemas
- ✅ Criar schemas com owner personalizado
- ✅ Configurar search_path automaticamente
- ✅ Listar schemas com contagem de objetos (tabelas, views, funções)
- ✅ Excluir schemas com opções CASCADE/RESTRICT
- ✅ Configurar permissões USAGE e CREATE durante criação

### Gerenciamento de Permissões
- ✅ Visualizar permissões atuais de databases e schemas
- ✅ Conceder/revogar CONNECT e CREATE em databases
- ✅ Conceder/revogar USAGE e CREATE em schemas
- ✅ Interface intuitiva com explicações contextuais

### Segurança
- ✅ Proteção de objetos do sistema (postgres, template0, template1, public, pg_catalog)
- ✅ Dupla confirmação para operações destrutivas
- ✅ Detecção automática de dependências
- ✅ Validação de entrada em todas as operações
- ✅ Logging completo de todas as operações

## 📦 Pré-requisitos

### Sistema Operacional
- Ubuntu 18.04+ ou Debian 9+
- Acesso root ou sudo

### Dependências
```bash
# Instaladas automaticamente pelo script
- postgresql-common (pg_createcluster, pg_dropcluster, pg_lsclusters)
- postgresql-{version}
- postgresql-client-{version}
```

## 🔧 Instalação

### 1. Clone o repositório
```bash
git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
cd devsecops-vps-startup/Postgres
```

### 2. Dê permissão de execução
```bash
chmod +x setup.sh
```

### 3. Execute o script
```bash
sudo bash setup.sh
```

## 💻 Uso

### Execução Principal
```bash
sudo bash setup.sh
```

### Menu Principal
```
╔════════════════════════════════════════════════════════════════╗
║          GERENCIAMENTO DE POSTGRESQL                           ║
║          Versão: 1.0                                          ║
║          Autor: Andre Luiz Faustino                           ║
║          https://github.com/andreluizfaustino                 ║
╚════════════════════════════════════════════════════════════════╝

1) Instalar PostgreSQL
2) Desinstalar PostgreSQL
3) Gerenciar Clusters
4) Voltar
```

## 📚 Funcionalidades

### 1. Instalação do PostgreSQL

Instala uma versão específica do PostgreSQL com configuração automática.

**Versões suportadas:**
- PostgreSQL 12
- PostgreSQL 13
- PostgreSQL 14
- PostgreSQL 15
- PostgreSQL 16
- PostgreSQL 17

**Processo:**
1. Verifica se já está instalado
2. Adiciona repositório oficial PostgreSQL
3. Instala versão selecionada
4. Cria cluster padrão (main) automaticamente
5. Configura autenticação

### 2. Desinstalação do PostgreSQL

Remove completamente o PostgreSQL do sistema.

**Opções:**
- **Manter dados:** Remove apenas binários
- **Remover tudo (CASCADE):** Remove binários e todos os dados

**Limpeza completa:**
- Remove pacotes PostgreSQL
- Remove diretórios de dados
- Remove configurações
- Remove logs

### 3. Gerenciamento de Clusters

#### 3.1 Criar Cluster

Cria um novo cluster PostgreSQL isolado.

**Parâmetros:**
- Nome do cluster
- Porta (padrão: 5432)
- Senha do usuário postgres

**Exemplo:**
```bash
Nome do cluster: production
Porta [5432]: 5432
Senha: ********
```

**Configuração automática:**
- Estrutura de diretórios
- Arquivo de configuração (postgresql.conf)
- Autenticação (pg_hba.conf)
- Inicialização do cluster

#### 3.2 Listar Clusters

Exibe todos os clusters PostgreSQL no sistema.

**Informações exibidas:**
```
Ver  Cluster   Port  Status   Owner    Data directory
15   main      5432  online   postgres /var/lib/postgresql/15/main
15   test      5433  online   postgres /var/lib/postgresql/15/test
```

#### 3.3 Excluir Cluster

Remove um cluster específico.

**Processo:**
1. Solicita confirmação digitando o nome do cluster
2. Para o cluster
3. Remove diretórios de dados
4. Remove configurações
5. Remove arquivos residuais

**Proteção:** Clusters do sistema (main em produção) podem ter proteção adicional.

#### 3.4 Backup de Cluster

Cria backup completo de um cluster usando `pg_dumpall`.

**Características:**
- Backup global (todos os databases, usuários, roles)
- Compressão automática com gzip
- Nomenclatura: `{cluster}_{YYYYMMDD}_{HHMMSS}.sql.gz`
- Armazenamento em `./backup/`

**Exemplo:**
```bash
Nome do cluster: production
Senha postgres: ********

✓ Backup criado: production_20260128_143022.sql.gz (125 MB)
```

#### 3.5 Importar Backup

Restaura um backup em um cluster.

**Processo:**
1. Lista backups disponíveis
2. Encerra conexões ativas
3. Descomprime e restaura via psql
4. Valida integridade

**Aviso:** Operação destrutiva, sobrescreve dados existentes.

#### 3.6 Gerenciar Backups

Menu para gerenciamento de arquivos de backup.

**Opções:**
- Listar backups (nome, tamanho, data)
- Excluir backup específico
- Excluir todos os backups (com confirmação)

#### 3.7 Gerenciar Usuários

Menu completo para CRUD de usuários PostgreSQL.

##### Criar Usuário

**Parâmetros:**
- Nome do usuário
- Senha (com confirmação)
- Permissões:
  - SUPERUSER: Acesso total ao cluster
  - CREATEDB: Pode criar databases
  - CREATEROLE: Pode criar outros usuários
- Opção de criar schema automaticamente

**Exemplo:**
```bash
Nome do usuário: app_user
Senha: ********
Confirme a senha: ********

SUPERUSER: Acesso total ao cluster
Criar usuário SUPERUSER? (s/n): n

CREATEDB: Permite criar novos databases
Criar usuário CREATEDB? (s/n): s

CREATEROLE: Permite criar outros usuários
Criar usuário CREATEROLE? (s/n): n

SCHEMA: Criar schema com o nome do usuário
Criar schema para o usuário? (s/n): s

✓ Usuário 'app_user' criado com sucesso!
✓ Schema 'app_user' criado!
✓ search_path configurado
```

##### Excluir Usuário

Exclui usuário com detecção de dependências.

**Processo:**
1. Verifica objetos do usuário (schemas, tabelas, views, funções)
2. Se houver dependências, oferece opções:
   - **CASCADE:** Remove usuário e todos os objetos
   - **REASSIGN OWNED BY:** Transfere objetos para outro usuário
   - **CANCELAR:** Aborta operação

**Exemplo com dependências:**
```bash
Nome do usuário: app_user

ATENÇÃO: O usuário 'app_user' possui objetos:
  - Schemas: 1 (app_user)
  - Tabelas: 5
  - Views: 2
  - Funções: 3

O que fazer com os objetos?
1) CASCADE - Excluir o usuário e TODOS os objetos
2) REASSIGN OWNED BY - Transferir objetos para outro usuário
3) CANCELAR - Não fazer nada

Escolha (1/2/3): 2

Usuário para receber os objetos: postgres
Digite o nome do usuário para confirmar: app_user
Tem CERTEZA? (s/n): s

✓ Objetos transferidos para 'postgres'
✓ Usuário 'app_user' excluído com sucesso!
```

##### Alterar Senha

Altera a senha de um usuário existente.

**Exemplo:**
```bash
Nome do usuário: app_user
Nova senha: ********
Confirme a senha: ********

✓ Senha alterada com sucesso!
```

#### 3.8 Databases e Schemas

Menu completo para gerenciamento de databases, schemas e permissões.

##### Gerenciar Databases

###### Criar Database

**Parâmetros:**
- Nome do database
- Owner (dono do database)
- Encoding (padrão: UTF8)
- Template (padrão: template1)
- Permissões opcionais (CONNECT, CREATE)

**Exemplo:**
```bash
Nome do database: myapp_db

OWNER: Usuário dono do database, tem controle total
Usuários disponíveis: postgres, app_user, readonly_user
Owner [postgres]: app_user

ENCODING: Conjunto de caracteres (UTF8 recomendado)
Encoding [UTF8]: UTF8

TEMPLATE: Database modelo (template1 = com objetos padrão)
Template [template1]: template1

✓ Database 'myapp_db' criado com sucesso!

PERMISSÕES: Conceder acesso a outros usuários agora?
Configurar permissões? (s/n): s

Usuários disponíveis: readonly_user

CONNECT: Permite conectar ao database
Conceder CONNECT para quais usuários? (separados por espaço ou ENTER): readonly_user

CREATE: Permite criar schemas dentro do database
Conceder CREATE para quais usuários? (separados por espaço ou ENTER): 

✓ CONNECT concedido para 'readonly_user'
```

###### Listar Databases

Exibe informações detalhadas de todos os databases.

**Informações:**
```
Database      | Owner     | Encoding | Tamanho  | Conexões
──────────────────────────────────────────────────────────
postgres      | postgres  | UTF8     | 8025 kB  | 2/100
myapp_db      | app_user  | UTF8     | 125 MB   | 5/100
test_db       | postgres  | UTF8     | 15 MB    | 0/-1
```

###### Excluir Database

Remove um database com proteções.

**Proteções:**
- Databases do sistema não podem ser excluídos (postgres, template0, template1)
- Dupla confirmação (digitar nome + s/n)
- Encerra conexões ativas automaticamente

**Exemplo:**
```bash
Nome do database para excluir: test_db

ATENÇÃO: O database 'test_db' será EXCLUÍDO permanentemente!
TODOS OS DADOS serão perdidos!

Digite o nome do database para confirmar: test_db
Tem CERTEZA? (s/n): s

✓ Encerrando conexões ativas...
✓ Database 'test_db' excluído com sucesso!
```

##### Gerenciar Schemas

###### Criar Schema

**Parâmetros:**
- Nome do schema
- Owner (dono do schema)
- Configuração de search_path
- Permissões opcionais (USAGE, CREATE)

**Exemplo:**
```bash
Database selecionado: myapp_db
Nome do schema: api

OWNER: Usuário dono do schema, tem controle total
Usuários disponíveis: postgres, app_user
Owner [postgres]: app_user

✓ Schema 'api' criado com sucesso!

SEARCH_PATH: Ordem de busca de objetos (schemas separados por vírgula)
Adicionar ao search_path do owner? (s/n): s

✓ search_path configurado para 'app_user'

PERMISSÕES: Conceder acesso a outros usuários agora?
Configurar permissões? (s/n): s

Usuários disponíveis: readonly_user

USAGE: Permite usar objetos do schema (SELECT, INSERT, etc)
Conceder USAGE para quais usuários? (separados por espaço ou ENTER): readonly_user

CREATE: Permite criar objetos dentro do schema
Conceder CREATE para quais usuários? (separados por espaço ou ENTER): 

✓ USAGE concedido para 'readonly_user'
```

###### Listar Schemas

Exibe schemas com contagem de objetos.

**Informações:**
```
Schema          | Owner     | Tabelas | Views | Funções
──────────────────────────────────────────────────────────
public          | postgres  | 3       | 1     | 5
api             | app_user  | 12      | 4     | 8
reports         | app_user  | 5       | 10    | 2
```

###### Excluir Schema

Remove schema com detecção de dependências.

**Proteções:**
- Schemas do sistema não podem ser excluídos (public, pg_catalog, information_schema)
- Detecção de objetos (tabelas, views, funções)
- Opções CASCADE ou RESTRICT
- Dupla confirmação

**Exemplo:**
```bash
Nome do schema para excluir: old_api

ATENÇÃO: O schema 'old_api' contém objetos:
  - Tabelas: 8
  - Views: 3
  - Funções: 5

O que fazer com os objetos?
1) CASCADE - Excluir o schema e TODOS os objetos
2) RESTRICT - Cancelar se houver objetos (seguro)
3) CANCELAR - Não fazer nada

Escolha (1/2/3): 1

CUIDADO: Todos os objetos serão EXCLUÍDOS permanentemente!

ATENÇÃO: O schema 'old_api' será EXCLUÍDO!
TODOS OS DADOS serão perdidos!

Digite o nome do schema para confirmar: old_api
Tem CERTEZA? (s/n): s

✓ Schema 'old_api' excluído com sucesso!
```

##### Gerenciar Permissões

Menu dedicado para visualizar e modificar permissões.

###### Permissões de Databases

**Visualizar Permissões:**
```
Database: myapp_db

Usuário    | CONNECT | CREATE
──────────────────────────────────────
postgres   | SIM     | SIM
app_user   | SIM     | SIM
readonly   | SIM     | NÃO
```

**Conceder Permissões:**
```bash
Usuário: readonly_user

CONNECT: Permite conectar ao database
Conceder CONNECT? (s/n): s

CREATE: Permite criar schemas dentro do database
Conceder CREATE? (s/n): n

✓ CONNECT concedido para 'readonly_user'
```

**Revogar Permissões:**
```bash
Usuário: old_app

Revogar CONNECT? (s/n): s
Revogar CREATE? (s/n): s

✓ CONNECT revogado de 'old_app'
✓ CREATE revogado de 'old_app'
```

###### Permissões de Schemas

**Visualizar Permissões:**
```
Schema: api

Usuário    | USAGE | CREATE
──────────────────────────────────────
postgres   | SIM   | SIM
app_user   | SIM   | SIM
readonly   | SIM   | NÃO
```

**Conceder/Revogar:** Mesmo processo das permissões de databases.

## 📊 Estrutura de Menus

```
Menu Principal
├── Instalar PostgreSQL
│   └── Seleção de versão (12-17)
├── Desinstalar PostgreSQL
│   └── Opção CASCADE (remover dados)
└── Gerenciar Clusters
    ├── Criar Cluster
    ├── Listar Clusters
    ├── Excluir Cluster
    ├── Backup de Cluster
    ├── Importar Backup
    ├── Gerenciar Backups
    │   ├── Listar Backups
    │   ├── Excluir Backup Específico
    │   └── Excluir Todos os Backups
    ├── Gerenciar Usuários
    │   ├── Listar Usuários
    │   ├── Criar Usuário
    │   ├── Excluir Usuário
    │   └── Alterar Senha
    └── Databases e Schemas
        ├── Gerenciar Databases
        │   ├── Listar Databases
        │   ├── Criar Database
        │   └── Excluir Database
        ├── Gerenciar Schemas
        │   ├── Listar Schemas
        │   ├── Criar Schema
        │   └── Excluir Schema
        └── Gerenciar Permissões
            ├── Permissões de Databases
            │   ├── Visualizar
            │   ├── Conceder
            │   └── Revogar
            └── Permissões de Schemas
                ├── Visualizar
                ├── Conceder
                └── Revogar
```

## 🎯 Exemplos de Uso

### Cenário 1: Configuração Inicial de Produção

```bash
# 1. Instalar PostgreSQL 15
sudo bash setup.sh
> Opção 1 (Instalar PostgreSQL)
> Versão 15

# 2. Criar cluster de produção
> Opção 3 (Gerenciar Clusters)
> Opção 1 (Criar Cluster)
Nome: production
Porta: 5432
Senha: [senha-segura]

# 3. Criar usuário da aplicação
> Opção 6 (Gerenciar Usuários)
> Opção 2 (Criar Usuário)
Nome: app_production
SUPERUSER: n
CREATEDB: s
CREATEROLE: n
Criar schema: s

# 4. Criar database da aplicação
> Opção 7 (Databases e Schemas)
> Opção 1 (Gerenciar Databases)
> Opção 1 (Criar Database)
Nome: app_db
Owner: app_production
Encoding: UTF8
Template: template1
```

### Cenário 2: Backup e Restore

```bash
# 1. Fazer backup do cluster production
> Opção 3 (Gerenciar Clusters)
> Opção 4 (Backup de Cluster)
Cluster: production
Senha: [senha]

# Resultado: production_20260128_143022.sql.gz

# 2. Criar cluster de teste
> Opção 1 (Criar Cluster)
Nome: test
Porta: 5433

# 3. Importar backup no teste
> Opção 5 (Importar Backup)
Cluster: test
Backup: production_20260128_143022.sql.gz
```

### Cenário 3: Gerenciamento de Permissões

```bash
# 1. Criar usuário read-only
> Opção 6 (Gerenciar Usuários)
> Opção 2 (Criar Usuário)
Nome: readonly_user
SUPERUSER: n
CREATEDB: n
CREATEROLE: n
Criar schema: n

# 2. Conceder CONNECT no database
> Opção 7 (Databases e Schemas)
> Opção 3 (Gerenciar Permissões)
> Opção 1 (Permissões de Databases)
Database: app_db
> Opção 1 (Conceder Permissões)
Usuário: readonly_user
CONNECT: s
CREATE: n

# 3. Conceder USAGE no schema
> Opção 2 (Permissões de Schemas)
Database: app_db
Schema: public
> Opção 1 (Conceder Permissões)
Usuário: readonly_user
USAGE: s
CREATE: n
```

### Cenário 4: Migração de Objetos

```bash
# Usuário com objetos precisa ser removido
> Opção 6 (Gerenciar Usuários)
> Opção 3 (Excluir Usuário)
Nome: old_app_user

# Sistema detecta:
Schemas: 1 (old_app_schema)
Tabelas: 15
Views: 5
Funções: 8

# Escolher opção 2 (REASSIGN OWNED BY)
Usuário destino: new_app_user
Confirmar: old_app_user

# Objetos transferidos, usuário removido
```

## 🏗️ Arquitetura

### Estrutura de Arquivos

```
Postgres/
├── setup.sh           # Script principal
├── README.md          # Esta documentação
├── backup/            # Diretórios de backups (criado automaticamente)
└── postgres_mgmt.log  # Log de operações (criado automaticamente)
```

### Organização do Código

```bash
# Seções principais do setup.sh

# 1. VARIÁVEIS GLOBAIS (linhas 12-25)
- LOG_FILE, SCRIPT_VERSION, BACKUP_DIR
- Cores para output

# 2. FUNÇÕES DE UTILIDADE (linhas 30-66)
- print_info, print_success, print_error
- log_message, press_enter, clear_screen

# 3. FUNÇÕES DE VALIDAÇÃO (linhas 68-147)
- check_root, is_postgresql_installed
- detect_pg_version, get_config_dir

# 4. INTERFACE (linhas 149-250)
- show_header, show_main_menu, show_cluster_menu

# 5. INSTALAÇÃO (linhas 360-460)
- install_postgresql

# 6. DESINSTALAÇÃO (linhas 462-540)
- uninstall_postgresql

# 7. GERENCIAMENTO DE CLUSTERS (linhas 542-860)
- add_cluster, delete_cluster, list_clusters

# 8. BACKUP E IMPORTAÇÃO (linhas 862-1240)
- backup_cluster, import_backup, manage_backups

# 9. GESTÃO DE USUÁRIOS (linhas 1242-1757)
- list_cluster_users, add_user, delete_user
- change_user_password

# 10. GESTÃO DE DATABASES E SCHEMAS (linhas 1758-2450)
- manage_databases_schemas
- create_database, delete_database
- create_schema, delete_schema
- manage_permissions

# 11. MENU DE CLUSTERS (linhas 2451+)
- menu_clusters (loop principal)
```

### Fluxo de Execução

```
Início
  │
  ├─> Verificação de Root
  │
  ├─> Detecção PostgreSQL
  │
  ├─> Menu Principal
  │   │
  │   ├─> Instalar
  │   │   └─> Adicionar repo → Instalar pacotes → Criar cluster
  │   │
  │   ├─> Desinstalar
  │   │   └─> Parar serviços → Remover pacotes → Limpar dados
  │   │
  │   └─> Gerenciar Clusters
  │       │
  │       ├─> CRUD de Clusters
  │       ├─> Backup/Restore
  │       ├─> Gerenciamento de Usuários
  │       └─> Databases/Schemas/Permissões
  │
  └─> Saída
```

## 🔒 Segurança

### Boas Práticas Implementadas

1. **Validação de Entrada**
   - Todos os inputs são validados
   - Proteção contra SQL injection em nomes
   - Confirmação dupla para operações destrutivas

2. **Proteção de Objetos do Sistema**
   ```bash
   # Databases protegidos
   postgres, template0, template1
   
   # Schemas protegidos
   public, pg_catalog, information_schema
   ```

3. **Gestão de Senhas**
   - Senhas nunca aparecem em logs
   - Input de senha com `-sp` (silent password)
   - Variável PGPASSWORD limpa após uso

4. **Autenticação Segura**
   - pg_hba.conf configurado com `scram-sha-256`
   - Acesso local via socket Unix
   - Rede privada (Tailscale) configurável

5. **Logging**
   - Todas as operações logadas em `postgres_mgmt.log`
   - Timestamp completo
   - Identificação de usuário e ação

6. **Detecção de Dependências**
   - Verifica objetos antes de excluir
   - Opções CASCADE com avisos explícitos
   - Possibilidade de transferir ownership

### Configuração de Autenticação

O script configura automaticamente o `pg_hba.conf`:

```
# Conexões locais via socket Unix
local   all             all                                     scram-sha-256

# Conexões localhost
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256

# Conexões via rede privada (exemplo Tailscale)
host    all             all             100.0.0.0/8             scram-sha-256
```

### Recomendações de Segurança

1. **Senhas Fortes**
   - Mínimo 12 caracteres
   - Mistura de maiúsculas, minúsculas, números e símbolos
   - Não reutilizar senhas

2. **Backups**
   - Fazer backups regulares
   - Armazenar backups em local seguro
   - Testar restore periodicamente
   - Criptografar backups sensíveis

3. **Permissões Mínimas**
   - Princípio do menor privilégio
   - Evitar criar superusers desnecessários
   - Usar roles específicos por aplicação

4. **Auditoria**
   - Revisar logs periodicamente
   - Monitorar acessos não autorizados
   - Verificar permissões regularmente

5. **Atualizações**
   - Manter PostgreSQL atualizado
   - Aplicar patches de segurança
   - Monitorar CVEs

## 🐛 Troubleshooting

### Problema: "Password authentication failed"

**Causa:** Senha incorreta ou pg_hba.conf mal configurado.

**Solução:**
```bash
# 1. Verificar pg_hba.conf
sudo cat /etc/postgresql/{version}/{cluster}/pg_hba.conf

# 2. Resetar senha do postgres
sudo -u postgres psql -p {porta}
ALTER USER postgres WITH PASSWORD 'nova_senha';

# 3. Recarregar configuração
sudo systemctl reload postgresql
```

### Problema: "Cluster já existe"

**Causa:** Tentativa de criar cluster com nome duplicado.

**Solução:**
```bash
# Listar clusters existentes
pg_lsclusters

# Usar nome diferente ou excluir cluster antigo
sudo bash setup.sh
> Opção 3 > Opção 3 (Excluir Cluster)
```

### Problema: "Database não aparece no DBeaver"

**Causa:** Cache do cliente ou filtro de visualização.

**Solução:**
1. Refresh na conexão (F5 ou botão direito > Refresh)
2. Verificar filtro: Connection Settings > Filter > Show all databases
3. Desconectar e reconectar
4. Invalidar cache: Database > Driver Manager > Reset

### Problema: "Cannot drop database because other users are connected"

**Causa:** Conexões ativas no database.

**Solução:** O script já encerra conexões automaticamente, mas manualmente:
```bash
# Encerrar todas as conexões
sudo -u postgres psql -p {porta} -d postgres
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = 'nome_database';

# Depois tentar excluir novamente
```

### Problema: "Erro ao importar backup"

**Causa:** Backup corrompido ou incompatível.

**Solução:**
```bash
# 1. Verificar integridade do arquivo
gunzip -t backup_file.sql.gz

# 2. Verificar tamanho
ls -lh backup/

# 3. Testar descompressão manual
gunzip -c backup_file.sql.gz | head -n 20

# 4. Se OK, tentar importação manual
gunzip -c backup_file.sql.gz | sudo -u postgres psql -p {porta}
```

### Problema: "Permissão negada ao acessar schema"

**Causa:** Falta permissão USAGE no schema.

**Solução:**
```bash
# Via script
> Databases e Schemas > Gerenciar Permissões > Schemas
> Conceder USAGE

# Manualmente
GRANT USAGE ON SCHEMA schema_name TO user_name;
GRANT SELECT ON ALL TABLES IN SCHEMA schema_name TO user_name;
```

### Problema: Script trava ou não responde

**Causa:** Operação longa ou processo travado.

**Solução:**
```bash
# 1. Verificar processos PostgreSQL
ps aux | grep postgres

# 2. Verificar logs
tail -f /var/log/postgresql/postgresql-{version}-{cluster}.log

# 3. Se necessário, cancelar (Ctrl+C) e verificar estado
pg_lsclusters
```

## 📈 Performance

### Otimizações Implementadas

1. **Backups Comprimidos**
   - Uso de gzip para reduzir tamanho
   - Nomenclatura padronizada com timestamp

2. **Queries Otimizadas**
   - Uso de pg_catalog para consultas rápidas
   - Índices nativos do PostgreSQL

3. **Operações em Lote**
   - Concessão de múltiplas permissões de uma vez
   - Validação agrupada

### Benchmarks

**Ambiente de teste:**
- Ubuntu 22.04
- PostgreSQL 15
- Database 100MB

**Operações:**
- Backup: ~5-10 segundos
- Restore: ~15-20 segundos
- Criar database: <1 segundo
- Listar 50 databases: <1 segundo

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

### Guidelines

- Seguir estilo de código existente
- Adicionar comentários em português
- Testar em Ubuntu/Debian
- Atualizar documentação se necessário

## 📝 Changelog

### [1.0] - 2026-01-28

#### Adicionado
- Sistema completo de gerenciamento de clusters
- Backup e restore com compressão
- CRUD completo de usuários com detecção de dependências
- CRUD completo de databases com proteções
- CRUD completo de schemas com CASCADE/RESTRICT
- Sistema de permissões granular (CONNECT, CREATE, USAGE)
- Logging completo de operações
- Validação extensiva de entrada
- Proteção de objetos do sistema
- Documentação completa

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo `LICENSE` para mais detalhes.

## 👤 Autor

**Andre Luiz Faustino**

- GitHub: [@andreluizfaustino](https://github.com/andreluizfaustino)
- LinkedIn: [andreluizfsantos](https://www.linkedin.com/in/andreluizfsantos/)

## 🙏 Agradecimentos

- Comunidade PostgreSQL pela excelente documentação
- Contribuidores do projeto
- Todos que reportaram bugs e sugeriram melhorias

---

**Nota:** Este projeto é mantido de forma independente e não é oficialmente afiliado ao PostgreSQL Global Development Group.
