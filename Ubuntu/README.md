# 🛡️ VPS Startup Hardening Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange?logo=ubuntu)](https://ubuntu.com/)
[![Bash](https://img.shields.io/badge/Bash-5.0+-green?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Tailscale](https://img.shields.io/badge/Tailscale-VPN-blue?logo=tailscale)](https://tailscale.com/)

Script automatizado de hardening para servidores Ubuntu VPS com **14 fases de segurança**, integração com **Tailscale VPN** e sistema de checkpoint para retomar execução em caso de falha.

**🎯 Economia: 85-90% do tempo vs. configuração manual**  
**⏱️ Tempo de execução: ~15-20 minutos**

---

## 📋 Índice

- [Features](#-features)
- [Para Quem é Este Script](#-para-quem-é-este-script)
- [Pré-requisitos](#-pré-requisitos)
- [Instalação Rápida](#-instalação-rápida)
- [As 14 Fases de Hardening](#-as-14-fases-de-hardening)
- [Configuração Interativa](#-configuração-interativa)
- [Exemplos de Uso](#-exemplos-de-uso)
- [Providers Testados](#-providers-testados)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)
- [Roadmap](#-roadmap)
- [Contribuindo](#-contribuindo)
- [Licença](#-licença)
- [Contato](#-contato)

---

## 🚀 Features

### Segurança Core
- ✅ **SSH via Tailscale VPN apenas** - Zero exposição pública
- ✅ **Firewall UFW** - HTTP/HTTPS público, resto privado
- ✅ **Fail2Ban** - Proteção contra brute-force
- ✅ **Kernel Hardening** - ASLR, ptrace restrito, core dumps desabilitados
- ✅ **Criptografia forte** - Ed25519, ChaCha20-Poly1305

### Performance
- ⚡ **BBR Congestion Control** - 2-25x mais throughput
- ⚡ **TCP Tuning** - Buffers 16MB, connection queue 4096
- ⚡ **1M File Descriptors** - Suporta APIs de alto tráfego

### Automação
- 🔄 **Sistema de Checkpoint** - Pause e continue de onde parou
- 📊 **Logging Completo** - Todos os comandos com timestamp
- 📈 **Progress Bar Visual** - Acompanhe em tempo real
- 🤝 **Configuração Interativa** - Guiado passo a passo

### Opcionais Avançados
- 🛡️ **Auditd** - Monitora acessos a arquivos críticos
- 🛡️ **AppArmor** - Mandatory Access Control
- 🛡️ **Unattended Upgrades** - Patches automáticos de segurança
- 🛡️ **Logging Avançado** - Logrotate + journald otimizado

---

## 👥 Para Quem é Este Script

- **Desenvolvedores** que gerenciam suas próprias VPS
- **Product Builders** criando ambientes rapidamente
- **Empreendedores** sem time de DevOps dedicado
- **Freelancers** mantendo múltiplos servidores
- **Equipes pequenas** sem budget para ferramentas enterprise

---

## 📦 Pré-requisitos

### No Servidor (VPS)
- Ubuntu 22.04 LTS ou 24.04 LTS
- Acesso root via console (web ou SSH)
- Mínimo 1GB RAM (recomendado 2GB+)
- Conexão com internet

### No Seu Computador Local
- Conta no [Tailscale](https://tailscale.com) (gratuita para até 20 dispositivos)
- Par de chaves SSH (`ssh-keygen -t ed25519`)
- Cliente Tailscale instalado

---

## ⚡ Instalação Rápida

### 1. Conectar ao Servidor

```bash
# Via SSH temporário ou console web do provider
ssh root@SEU_IP_PUBLICO
```

### 2. Baixar o Script

```bash
# Clone o repositório
git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
cd devsecops-vps-startup

# Ou baixe direto
wget https://raw.githubusercontent.com/andreluizfaustino/devsecops-vps-startup/main/startup.sh
chmod +x startup.sh
```

### 3. Preparar Chave SSH

**No seu computador local:**

```bash
# Gerar chave (se não tiver)
ssh-keygen -t ed25519 -C "seu-email@example.com"

# Copiar chave pública
cat ~/.ssh/id_ed25519.pub
# ou no macOS:
cat ~/.ssh/id_ed25519.pub | pbcopy
```

### 4. Executar o Script

```bash
sudo bash startup.sh
```

### 5. Seguir o Assistente Interativo

O script fará perguntas sobre:
- Usuário SSH (root/ubuntu/customizado)
- Senha do usuário
- Porta SSH (padrão: 2222)
- Tamanho do SWAP (padrão: 2GB)
- Chave SSH pública (cole aqui)
- Componentes opcionais (Auditd, AppArmor, etc.)

### 6. Autenticar no Tailscale

Durante a **Fase 9**, o script mostrará uma URL:

```
⚠️  AÇÃO NECESSÁRIA: Autenticação Tailscale

Abra este link no seu navegador:
https://login.tailscale.com/a/xxxxxxxxxxxxxxxx
```

1. Abra o link no navegador
2. Faça login na sua conta Tailscale
3. Autorize o dispositivo
4. Pressione ENTER no terminal

### 7. Conectar via SSH Seguro

Após conclusão (~15-20 min), conecte via Tailscale:

```bash
# No seu computador, conecte ao Tailscale
tailscale up

# Acesse via IP Tailscale
ssh ubuntu@100.64.x.x -p 2222
```

✅ **Pronto!** Seu servidor está seguro e pronto para produção.

---

## 🔐 As 14 Fases de Hardening

| Fase | Nome | O Que Faz | Tempo |
|------|------|-----------|-------|
| **1** | Usuário SSH | Cria/configura usuário não-root | ~10s |
| **2** | Timezone | Configura America/Sao_Paulo | ~5s |
| **3** | System Update | `apt update && upgrade` completo | ~3-5min |
| **4** | Unattended Upgrades* | Atualizações automáticas de segurança | ~2min |
| **5** | Kernel Security | ASLR, ptrace, core dumps | ~10s |
| **6** | Network Hardening | BBR, TCP tuning, 1M file descriptors | ~30s |
| **7** | SWAP | Cria swapfile configurável | ~1-2min |
| **8** | Chave SSH | Configura authorized_keys | ~5s |
| **9** | **Tailscale** | Instala e conecta VPN mesh | ~2-3min |
| **10** | **SSH Hardening** | SSH escuta APENAS no IP Tailscale | ~30s |
| **11** | Fail2Ban | Proteção brute-force | ~1min |
| **12** | **UFW Firewall** | HTTP/HTTPS público, resto via Tailscale | ~30s |
| **13** | Auditd* | Monitora arquivos críticos | ~2min |
| **14** | AppArmor* | Mandatory Access Control | ~1min |

\* *Componentes opcionais*

---

## 🎛️ Configuração Interativa

### Exemplo de Configuração

```
════════════════════════════════════════════════════════
  CONFIGURAÇÃO INICIAL DO SISTEMA
════════════════════════════════════════════════════════

ETAPA 1/5: Configurar usuário SSH
Escolha qual usuário terá acesso SSH:
  1) root (manterá acesso root com chave SSH)
  2) ubuntu (criar/usar usuário ubuntu - recomendado) ✅
  3) outro (especificar nome de usuário customizado)

Opção [1-3]: 2

ETAPA 2/5: Definir senha para usuário ubuntu
Digite a nova senha: ********
Repita a senha: ********

ETAPA 3/5: Configurar porta SSH
Digite a porta SSH desejada [padrão: 2222]: 2222

ETAPA 4/5: Configurar SWAP
Digite o tamanho do SWAP em GB [padrão: 2]: 4

ETAPA 5/5: Configurar autenticação SSH
Cole sua chave pública SSH: ssh-ed25519 AAAAC3NzaC...

════════════════════════════════════════════════════════
  COMPONENTES OPCIONAIS DE SEGURANÇA
════════════════════════════════════════════════════════

[1] Unattended Upgrades (atualizações automáticas)
    Instalar? [S/n]: S

[2] Auditd (monitoramento avançado)
    Instalar? [S/n]: S

[3] AppArmor (controle de acesso obrigatório)
    ⚠️  ATENÇÃO: Pode causar lentidão em alguns serviços
    Instalar? [S/n]: n

[4] Logging Avançado (logrotate + journald)
    Instalar? [S/n]: S
```

---

## 💡 Exemplos de Uso

### Caso 1: Servidor para Docker + Coolify

```bash
# 1. Execute o script de hardening
sudo bash startup.sh

# 2. Após conclusão, instale Docker
curl -fsSL https://get.docker.com | sh

# 3. Instale Coolify
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

# 4. Acesse Coolify via IP público na porta 8000
# Firewall já permite acesso (se necessário, ajuste UFW)
```

### Caso 2: API Node.js com PostgreSQL

```bash
# 1. Execute o script de hardening
sudo bash startup.sh

# 2. PostgreSQL via Docker (acessível apenas via Tailscale)
docker run -d --name postgres \
  -e POSTGRES_PASSWORD=senhasegura \
  -v postgres_data:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:16-alpine

# 3. API Node.js com Nginx + Certbot
sudo apt install nginx certbot python3-certbot-nginx
sudo certbot --nginx -d api.seudominio.com
```

### Caso 3: Múltiplos Servidores

```bash
# Use o mesmo script em todas as VPS
# Todas aparecerão na mesma rede Tailscale

# VPS 1 - Produção
ssh ubuntu@100.64.1.10 -p 2222

# VPS 2 - Staging
ssh ubuntu@100.64.1.11 -p 2222

# VPS 3 - Testes
ssh ubuntu@100.64.1.12 -p 2222
```

---

## ☁️ Providers Testados

| Provider | Status | Notas |
|----------|--------|-------|
| **Hostinger** | ✅ Testado | Funciona perfeitamente |
| **DigitalOcean** | ✅ Testado | Funciona perfeitamente |
| **Hetzner** | ✅ Testado | Funciona perfeitamente |
| **Vultr** | ✅ Testado | Funciona perfeitamente |
| **Linode/Akamai** | ✅ Testado | Funciona perfeitamente |
| **AWS Lightsail** | ⚠️ Não testado | Deve funcionar |
| **GCP Compute** | ⚠️ Não testado | Deve funcionar |
| **Azure VMs** | ⚠️ Não testado | Deve funcionar |

---

## 🔧 Troubleshooting

### ❌ Problema: Perdi o acesso SSH!

**Causa:** Você não conectou ao Tailscale antes de tentar acessar.

**Solução:**
1. Conecte-se ao Tailscale no seu computador:
   ```bash
   tailscale up
   ```
2. Verifique se o servidor aparece:
   ```bash
   tailscale status
   ```
3. Tente SSH novamente usando o IP Tailscale:
   ```bash
   ssh ubuntu@100.64.x.x -p 2222
   ```

**Plano B:** Acesse via console web do provider.

---

### ❌ Problema: Tailscale não está conectado

**Verificar status:**
```bash
sudo tailscale status
```

**Se mostrar "Logged out":**
```bash
sudo tailscale up
# Abra a URL gerada no navegador
```

---

### ❌ Problema: O script falhou na fase X

**O sistema de checkpoint te protege!**

```bash
# Execute novamente
sudo bash startup.sh

# Você verá:
# "Checkpoint encontrado! 7 de 14 fases concluídas."
# Opções:
#   1) Continuar de onde parou  ← escolha essa
#   2) Recomeçar do zero
#   3) Sair
```

---

### ❌ Problema: Como ver os logs detalhados?

```bash
# Log completo da execução
cat logs/startup-YYYYMMDD_HHMMSS.log

# Apenas erros
cat logs/startup-errors.log

# Informações do servidor configurado
cat /root/server-info.txt
```

---

### ❌ Problema: Firewall bloqueou uma porta que preciso

**Liberar porta temporariamente:**
```bash
# Apenas via Tailscale (recomendado)
sudo ufw allow in on tailscale0 to any port 3000

# Ou público (use com cautela!)
sudo ufw allow 3000/tcp comment 'Minha aplicação'
```

---

### ❌ Problema: Como restaurar configuração SSH anterior?

```bash
# O script cria backups automáticos
ls -la /etc/ssh/sshd_config.backup.*

# Restaurar
sudo cp /etc/ssh/sshd_config.backup.YYYYMMDD_HHMMSS /etc/ssh/sshd_config
sudo systemctl restart sshd
```

---

## ❓ FAQ

### P: Posso usar em Debian ao invés de Ubuntu?

**R:** O script foi projetado para Ubuntu. Pode funcionar em Debian, mas não é garantido. Você verá um aviso na execução.

---

### P: Preciso do Tailscale? Posso pular essa parte?

**R:** Não. O Tailscale é essencial para a arquitetura de segurança do script. O SSH fica configurado para escutar **apenas** no IP do Tailscale. Sem ele, você perde acesso SSH.

---

### P: Posso mudar a porta SSH depois?

**R:** Sim. Edite `/etc/ssh/sshd_config`, mude a linha `Port XXXX` e reinicie: `sudo systemctl restart sshd`. Não esqueça de atualizar o Fail2Ban também em `/etc/fail2ban/jail.local`.

---

### P: Como adicionar outro usuário com acesso SSH?

**R:** 
```bash
# Criar usuário
sudo useradd -m -s /bin/bash -G sudo novoUsuario
sudo passwd novoUsuario

# Adicionar chave SSH
sudo mkdir -p /home/novoUsuario/.ssh
sudo nano /home/novoUsuario/.ssh/authorized_keys
# Cole a chave pública
sudo chmod 700 /home/novoUsuario/.ssh
sudo chmod 600 /home/novoUsuario/.ssh/authorized_keys
sudo chown -R novoUsuario:novoUsuario /home/novoUsuario/.ssh

# Adicionar ao AllowUsers no SSH
sudo nano /etc/ssh/sshd_config
# Altere linha: AllowUsers ubuntu novoUsuario
sudo systemctl restart sshd
```

---

### P: Quanto de RAM o script precisa?

**R:** Mínimo 1GB, recomendado 2GB+. O script usa pouca memória, mas as atualizações do sistema (`apt upgrade`) podem precisar de mais RAM temporariamente.

---

### P: Posso executar o script em um servidor já em produção?

**R:** ⚠️ **Não recomendado.** O script faz mudanças profundas no sistema (SSH, firewall, kernel). Teste em uma VPS de staging primeiro. Se precisar rodar em produção, faça backup completo antes.

---

## 🤝 Contribuindo

Contribuições são muito bem-vindas! Este é um projeto open-source mantido pela comunidade.

### Como Contribuir

1. **Fork** o repositório
2. Crie uma **branch** para sua feature:
   ```bash
   git checkout -b feature/minha-feature
   ```
3. **Commit** suas mudanças:
   ```bash
   git commit -m 'feat: adiciona suporte para Debian'
   ```
4. **Push** para a branch:
   ```bash
   git push origin feature/minha-feature
   ```
5. Abra um **Pull Request**

### Diretrizes

- ✅ Teste em VPS real antes de submeter PR
- ✅ Mantenha compatibilidade com Ubuntu 22.04/24.04
- ✅ Atualize README.md se adicionar features
- ✅ Siga o estilo de código existente
- ✅ Use mensagens de commit descritivas ([Conventional Commits](https://www.conventionalcommits.org/))

### Tipos de Contribuição

- 🐛 **Reportar bugs** - Abra uma issue descrevendo o problema
- 💡 **Sugerir features** - Abra uma issue com a tag `enhancement`
- 📖 **Melhorar documentação** - PRs para README, comentários no código
- 🧪 **Testar em novos providers** - Reporte compatibilidade
- 🌍 **Traduções** - Ajude a traduzir a documentação

---

## 📜 Licença

Este projeto está licenciado sob a **MIT License** - veja o arquivo [LICENSE](LICENSE) para detalhes.

**TL;DR:** Você pode usar, copiar, modificar e distribuir este software livremente, inclusive para fins comerciais, desde que mantenha o aviso de copyright.

---

## ⚠️ Aviso Importante

Este script modifica configurações críticas do sistema operacional. 

- ✅ **Recomendado:** Testar em VPS não-produção primeiro
- ⚠️ **Risco:** Configuração incorreta pode bloquear acesso SSH
- 📋 **Backup:** Sempre tenha acesso ao console web do provider
- 🚫 **Sem Garantias:** Fornecido "como está", sem garantias de qualquer tipo

**Use por sua conta e risco. Os autores não se responsabilizam por perda de acesso ou dados.**

---

## 📞 Contato

**Autor:** André Luiz Faustino  
**GitHub:** [@andreluizfaustino](https://github.com/andreluizfaustino)  
**Repositório:** [devsecops-vps-startup](https://github.com/andreluizfaustino/devsecops-vps-startup)

### Suporte

- 🐛 **Bugs:** Abra uma [issue](https://github.com/andreluizfaustino/devsecops-vps-startup/issues)
- 💬 **Discussões:** Use as [Discussions](https://github.com/andreluizfaustino/devsecops-vps-startup/discussions)
- 📧 **Email:** Para questões privadas apenas

---

## 🌟 Agradecimentos

Este script é resultado de anos de experiência em DevOps e segurança, com contribuições da comunidade.

**Agradecimentos especiais:**
- Time do [Tailscale](https://tailscale.com/) pelo produto incrível
- Comunidade [Ubuntu](https://ubuntu.com/) pela documentação
- Todos os contribuidores e testadores

---

## ⭐ Star History

Se este projeto te ajudou, considere dar uma ⭐ no repositório!

[![Star History Chart](https://api.star-history.com/svg?repos=andreluizfaustino/devsecops-vps-startup&type=Date)](https://star-history.com/#andreluizfaustino/devsecops-vps-startup&Date)

---

**Made with ❤️ by developers, for developers**

---

**Tags:** `ubuntu` `security` `hardening` `vps` `tailscale` `devops` `ssh` `firewall` `automation` `bash` `linux` `sysadmin` `devsecops`
