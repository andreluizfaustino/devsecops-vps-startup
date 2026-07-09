# 🛡️ VPS Hardening Scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange?logo=ubuntu)](https://ubuntu.com/)
[![Bash](https://img.shields.io/badge/Bash-5.0+-green?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Tailscale](https://img.shields.io/badge/Tailscale-VPN-blue?logo=tailscale)](https://tailscale.com/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Ready-orange?logo=cloudflare)](https://cloudflare.com/)

Scripts de hardening, segurança de rede e firewall para servidores Ubuntu em produção.

> 📖 **Documentação técnica completa:** [DOCS.md](DOCS.md)

---

## Scripts

| Script | Quando rodar | O que faz |
|---|---|---|
| `01-startup.sh` | Uma vez, ao provisionar a VPS | Hardening: SSH, UFW, kernel, Tailscale, Fail2Ban, Auditd |
| `02-docker.sh` | Após o reboot do 01 | Instala Docker + DOCKER-USER firewall com persistência via systemd |
| `03-cloudflare-update-ufw.sh` | Após o 02, e quando quiser atualizar | IPs Cloudflare no UFW + DOCKER-USER + timer mensal opcional |
| `_audit.sh` | A qualquer momento | Valida todas as configurações e gera score de saúde |

---

## Uso Rápido

```bash
# 1. Clonar o repositório na VPS
git clone https://github.com/andreluizfaustino/devsecops-vps-startup.git
cd devsecops-vps-startup/Ubuntu

# 2. Hardening principal (reboot automático ao final)
sudo bash 01-startup.sh

# 3. Reconectar via Tailscale e instalar Docker + firewall
sudo bash 02-docker.sh

# 4. Ativar modo Cloudflare-Only (UFW + DOCKER-USER + timer mensal)
sudo bash 03-cloudflare-update-ufw.sh

# 5. Validar tudo
sudo bash _audit.sh
```

**Score esperado após 01 + 02 + 03:** ~97% — 0 FAILs

---

## Arquitetura de Segurança

```
Internet
    │
    ├── Qualquer IP direto
    │       ├── porta 80/443 → DOCKER-USER aceita só IPs Cloudflare ✅
    │       ├── qualquer outra porta → DOCKER-USER DROP ❌
    │       └── SSH → UFW DENY (só via Tailscale) ❌
    │
    └── Tailscale VPN (100.x.x.x)
            └── tudo → ALLOW ✅ (admin e dispositivos autorizados)

Camadas de proteção (de fora para dentro):
  Cloudflare WAF → UFW (INPUT) → DOCKER-USER (FORWARD) → Fail2Ban → Aplicação
```

---

## Serviços systemd criados

| Serviço | Criado por | Quando executa | O que faz |
|---|---|---|---|
| `docker-user-firewall.service` | `02-docker.sh` | Boot (após Docker) | Aplica regras DOCKER-USER lendo IPs do UFW |
| `cloudflare-update-firewall.service` | `03-cloudflare-update-ufw.sh` | Chamado pelo timer | Atualiza IPs Cloudflare no UFW + DOCKER-USER |
| `cloudflare-update-firewall.timer` | `03-cloudflare-update-ufw.sh` | Mensalmente | Dispara o serviço acima automaticamente |

---

## Pré-requisitos

- Ubuntu 22.04 LTS ou 24.04 LTS
- Acesso root
- Conta no [Tailscale](https://tailscale.com) (gratuita)
- Par de chaves SSH (`ssh-keygen -t ed25519`)

---

## Documentação

Para detalhes completos de cada script, parâmetro e decisão técnica, consulte [DOCS.md](DOCS.md).

---

## Licença

MIT — veja [LICENSE](../LICENSE) para detalhes.

**Autor:** André Luiz Faustino · [@andreluizfaustino](https://github.com/andreluizfaustino)
