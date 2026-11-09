# Stacks base: Traefik + Portainer

Camada de aplicação padrão para rodar **depois** do `Ubuntu/01-startup.sh` (com Docker e modo Cloudflare-only).

| Stack | O que é | Acesso |
|---|---|---|
| `traefik/` | Proxy reverso + `socket-proxy` (Traefik só lê a lista de containers) | 80/443 públicos (só Cloudflare chega) · painel `:8080` só no Tailscale |
| `portainer/` | Gerenciamento do Docker | `:9443` só no Tailscale |

Testado em produção em Ubuntu 26.04 (srv1301466, nov/2026).

---

## O que já vem configurado

**Traefik (`traefik.yml` + `dynamic/`)**

| Recurso | Detalhe |
|---|---|
| HTTPS | Certificado de Origem da Cloudflare (`dynamic/tls.yml`), TLS 1.2+; HTTP redireciona para HTTPS |
| IP real do visitante | `forwardedHeaders.trustedIPs` com as faixas da Cloudflare → `X-Forwarded-For` correto |
| Proteções globais | aplicadas a **todas** as aplicações pela entrada `websecure` (`dynamic/security.yml`): rate limit 30 req/s (pico 100) por `Cf-Connecting-Ip` · HSTS, nosniff, SAMEORIGIN · upload máx. 10 MB |
| Docker | sem `docker.sock` no Traefik: fala com o `socket-proxy`, que só permite leitura (rede interna isolada) |
| Logs | acesso em JSON com o IP real e o país do visitante |
| Painel | `http://<IP-Tailscale>:8080/dashboard/` |

**Portainer**: imagem `portainer-ce:lts`, publicado só no IP do Tailscale.

---

## Pré-requisitos

1. `01-startup.sh` executado com **Docker = S** e **Cloudflare-only = S**.
2. Domínio na Cloudflare com **SSL/TLS = Full (strict)**.
3. **Certificado de Origem** gerado na Cloudflare: *SSL/TLS → Origin Server → Create Certificate* (ECC, `*.dominio` + `dominio`, 15 anos). Guarde a chave privada no gerenciador de senhas (ela só aparece uma vez).

---

## Instalação

```bash
# 1. Copiar as stacks para /opt
sudo cp -r ~/devsecops-vps-startup/stacks/traefik ~/devsecops-vps-startup/stacks/portainer /opt/

# 2. IP do Tailscale nos .env
TS=$(tailscale ip -4)
echo "TS_IP=$TS" | sudo tee /opt/traefik/.env /opt/portainer/.env

# 3. Certificado de Origem (colar o conteúdo copiado da Cloudflare)
sudo nano /opt/traefik/certs/origin.pem      # Origin Certificate
sudo nano /opt/traefik/certs/origin.key      # Private Key
sudo chmod 600 /opt/traefik/certs/origin.key

# 4. Subir
sudo docker network create proxy
cd /opt/traefik   && sudo docker compose up -d
cd /opt/portainer && sudo docker compose up -d
```

**Primeiro acesso ao Portainer:** abra `https://<IP-Tailscale>:9443` **em até 5 minutos** e crie o admin (se passar, `sudo docker restart portainer`). O aviso de certificado é esperado: o acesso já é criptografado pelo Tailscale.

### Testes

```bash
# Painel do Traefik e rotas (do seu computador, com Tailscale)
curl -s http://<IP-Tailscale>:8080/api/http/routers

# socket-proxy: ler = 200, parar container = 403
sudo docker run --rm --network socket-proxy curlimages/curl -s -o /dev/null -w '%{http_code}\n' http://socket-proxy:2375/containers/json
sudo docker run --rm --network socket-proxy curlimages/curl -s -o /dev/null -w '%{http_code}\n' -X POST http://socket-proxy:2375/containers/x/stop

# Página de teste (remova depois: sudo docker rm -f whoami)
sudo docker run -d --name whoami --network proxy -l traefik.enable=true \
  -l 'traefik.http.routers.whoami.rule=Host(`dominio.com`)' \
  -l traefik.http.routers.whoami.entrypoints=websecure traefik/whoami
```

---

## Publicar uma aplicação

1. Cloudflare → DNS: `CNAME app → dominio`, **Proxied** (crie **antes** de abrir no navegador; resposta "não existe" fica em cache por até 30 min).
2. No compose da aplicação:

```yaml
services:
  app:
    image: ...
    restart: unless-stopped
    networks: [proxy]
    mem_limit: 1g          # sempre limite memória e CPU
    cpus: 1
    labels:
      - traefik.enable=true
      - traefik.http.routers.app.rule=Host(`app.dominio.com`)
      - traefik.http.routers.app.entrypoints=websecure
      - traefik.http.services.app.loadbalancer.server.port=<porta interna>

networks:
  proxy:
    external: true
```

- **Não** use `ports:` para aplicações públicas: o Traefik alcança pela rede `proxy`.
- Painéis administrativos: publique só no Tailscale (`"${TS_IP}:PORTA:PORTA"`), sem labels do Traefik.
- Limites específicos (ex.: rate limit no `/login`): crie um middleware nas labels da própria aplicação; as proteções globais continuam valendo.

---

## Manutenção

| Tarefa | Como |
|---|---|
| Atualizar imagens (mensal) | `cd /opt/traefik && sudo docker compose pull && sudo docker compose up -d` (idem Portainer) |
| Mudou `traefik.yml` | `sudo docker restart traefik` |
| Mudou `dynamic/*.yml` | recarrega sozinho |
| Faixas da Cloudflare | `trustedIPs` em `traefik.yml` é estático: compare com `/etc/cloudflare-ips.txt` (atualizado toda semana pelo timer) e, se mudar, edite e reinicie o Traefik |
| Renovar certificado | o de Origem vale 15 anos; anote a data de validade |

## Arquivos que **não** vão para o Git

`stacks/*/.env` (IP do servidor) e `traefik/certs/*` (certificado e chave privada).
