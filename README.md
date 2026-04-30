# NexusPlay

Plateforme de mini-jeux multijoueurs. Prototype d'architecture microservices haute disponibilité sur AWS, déployée via Terraform, conteneurisée en Docker, observée via Prometheus / Grafana / Alertmanager, déployée en continu via GitHub Actions.

<img width="514" height="497" alt="Capture d’écran 2026-04-30 à 14 43 50" src="https://github.com/user-attachments/assets/94243870-84de-4c74-af90-210caa6062fe" />


## Architecture

```
                       Internet
                          │
              nexusplay.local (BIND9 round-robin)
                          │
        ┌─────────────────┴─────────────────┐
        ▼                                   ▼
   nginx1 (EC2)                       nginx2 (EC2)
   reverse proxy                      reverse proxy
   + BIND9 primary                    + BIND9 secondary
        │                                   │
        └─────────────────┬─────────────────┘
                          │
            ┌─────────────┴─────────────┐
            ▼                           ▼
       frontend (EC2)             backend (EC2)
       1× container HTML          2 à 5× containers Node/Express
                                  (autoscaling Prometheus)
```

4 instances EC2 (`t2.micro`, AMI Amazon Linux 2023, region `us-east-1`, VPC default). Toutes provisionnées via Terraform.

## Stack technique

| Domaine | Outil |
|---|---|
| IaC | Terraform |
| Compute | EC2 |
| Containers | Docker + GHCR (registry GitHub) |
| Reverse proxy / LB | nginx (upstream `least_conn`, multi-replicas, failover) |
| Observabilité | Prometheus + Grafana + Alertmanager + node-exporter + cAdvisor |
| Autoscaling | Script bash `nexusplay-autoscale` (systemd timer 30s, lit Prometheus, scale 2→5 sur seuils CPU 70%/30%) |
| CI/CD | GitHub Actions (build → push GHCR → SSH deploy → k6 smoke) |
| Load testing | k6 (`k6/smoke.js` dans CI, `k6/load.js` standalone) |
| DNS HA | BIND9 primary/secondary (zone `nexusplay.local`, AXFR auto, round-robin sur 2 IPs nginx) |

## Endpoints publics

| URL | Service |
|---|---|
| http://44.202.153.219/ | Frontend (via nginx1) |
| http://44.202.153.219/api/hello | Backend (via nginx1) |
| http://44.202.153.219/health | Healthcheck nginx |
| http://13.221.229.161/ | Frontend (via nginx2) |
| http://44.202.153.219:3001 | Grafana (`admin` / `admin`) |
| http://44.202.153.219:9090 | Prometheus |
| http://44.202.153.219:9093 | Alertmanager |
| `dig @44.202.153.219 nexusplay.local` | DNS BIND9 primary |
| `dig @13.221.229.161 nexusplay.local` | DNS BIND9 secondary |

## Structure du repo

```
NexusPlay/
├── infra/                      # Terraform : VPC default, 3 SG, 4 EC2
│   ├── provider.tf
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── nginx/
│   ├── nginx.conf              # routing /, /api/, /health + upstream multi-replicas
│   └── nginx-main.conf         # remplace /etc/nginx/nginx.conf (vire le default server)
├── bind/                       # DNS BIND9 (critère 10 — Active/Backup)
│   ├── primary/
│   │   ├── named.conf          # config primary (nginx EC2)
│   │   └── nexusplay.local.zone
│   └── secondary/
│       └── named.conf          # config secondary (nginx2 EC2, AXFR)
├── services/
│   ├── frontend/               # HTML statique servi par nginx:alpine (port 3000)
│   └── backend/                # Node + Express, endpoints /health & /hello (port 8080)
├── observability/
│   ├── docker-compose.yml      # stack centrale (nginx EC2)
│   ├── prometheus/             # scrape config + règles d'alerte
│   ├── alertmanager/           # routes
│   ├── grafana/provisioning/   # datasource auto-provisionnée
│   ├── agents/                 # node-exporter + cAdvisor (frontend & backend EC2)
│   └── autoscaler/             # script bash + service systemd
├── k6/
│   ├── smoke.js                # 3 VUs × 20s, p95 < 500ms
│   └── load.js                 # 30 VUs × 2min (déclenche autoscaling)
├── .github/workflows/
│   └── ci-cd.yml               # build → push GHCR → SSH deploy → k6 smoke
└── docker-compose.yml          # dev local (frontend + backend)
```

## Mapping critères du sujet

| # | Exigence | Couvert par | Statut |
|---|---|---|---|
| 1 | Microservices ≥ 2 | `services/frontend` + `services/backend`, conteneurs distincts | ✅ |
| 2 | Équilibrage de charge avec redondance | 2× nginx + upstream `least_conn` sur 3-5 backends + DNS round-robin BIND9 | ✅ |
| 3 | Scalabilité automatique | `observability/autoscaler/` : timer systemd 30s, lit Prometheus, scale 2→5 | ✅ |
| 4 | Monitoring centralisé | Stack Prometheus + Grafana + Alertmanager + node-exporter + cAdvisor | ✅ |
| 5 | Pipeline CI/CD | `.github/workflows/ci-cd.yml` (push main → build → GHCR → deploy → smoke) | ✅ |
| 6 | Tests de charge dans CI/CD | k6 `smoke.js` exécuté à chaque déploiement | ✅ |
| 7 | Cache | — | ❌ |
| 8 | Gestion des secrets | Secrets GitHub Actions (CI/CD) ; AWS Secrets Manager prévu (runtime) | 🟡 |
| 9 | Notifications incident | Alertmanager + 5 règles d'alerte (CPU/RAM/disk/instance down) | 🟡 (webhook factice) |
| 10 | DNS HA Active/Backup | BIND9 primary (`nginx`) + secondary (`nginx2`), zone `nexusplay.local`, AXFR auto, failover testé | ✅ |

## Reproduire le déploiement (depuis zéro)

### Prérequis
- AWS CLI configuré (Learner Lab credentials dans `~/.aws/credentials`)
- Terraform ≥ 1.5
- SSH key pair existante dans la région (ex. `vockey` ou `007`)
- Docker (pour test local)

### 1. Provisionner l'infra
```bash
cd infra
cp terraform.tfvars.example terraform.tfvars  # éditer key_name
terraform init
terraform apply
terraform output
```
→ 4 EC2 lancées, IPs publiques en sortie.

### 2. Déployer nginx (sur les 2 EC2 nginx)
```bash
for ip in $(terraform output -raw nginx_public_ip) $(terraform output -raw nginx2_public_ip); do
  cat ../nginx/nginx-main.conf | ssh -i ~/key.pem ec2-user@$ip 'sudo dnf install -y nginx && sudo tee /etc/nginx/nginx.conf >/dev/null'
  cat ../nginx/nginx.conf | ssh -i ~/key.pem ec2-user@$ip 'sudo tee /etc/nginx/conf.d/nexusplay.conf >/dev/null && sudo systemctl restart nginx'
done
```

### 3. Déployer les apps
Push sur la branche `main` → GitHub Actions build & déploie automatiquement les images frontend & backend depuis GHCR vers les EC2.

Pré-requis :
- Secrets GitHub : `SSH_PRIVATE_KEY`, `NGINX_HOST`, `NGINX2_HOST`, `FRONTEND_HOST`, `BACKEND_HOST`
- Workflow permissions : Read & Write
- Packages GHCR rendus publics après le 1er push

### 4. Déployer la stack obs
```bash
# Sur l'EC2 nginx (centre) :
scp -r observability ec2-user@<NGINX_IP>:~/
ssh ec2-user@<NGINX_IP> 'cd observability && sudo docker compose up -d'

# Sur frontend & backend (agents) :
scp -r observability/agents ec2-user@<IP>:~/
ssh ec2-user@<IP> 'cd agents && sudo docker compose up -d'
```

### 5. Déployer l'autoscaler (sur l'EC2 backend)
```bash
scp observability/autoscaler/* ec2-user@<BACKEND_IP>:~/
ssh ec2-user@<BACKEND_IP> 'bash install.sh'
```

### 6. Déployer BIND9 (DNS HA)

**Primary** (sur l'EC2 nginx) :
```bash
scp -i 007.pem bind/primary/named.conf            ec2-user@<NGINX_IP>:/tmp/
scp -i 007.pem bind/primary/nexusplay.local.zone  ec2-user@<NGINX_IP>:/tmp/
ssh -i 007.pem ec2-user@<NGINX_IP> '
  sudo dnf install -y bind bind-utils
  sudo mv /tmp/named.conf /etc/named.conf
  sudo mv /tmp/nexusplay.local.zone /var/named/
  sudo chown root:named /etc/named.conf /var/named/nexusplay.local.zone
  sudo chmod 640 /etc/named.conf /var/named/nexusplay.local.zone
  sudo named-checkconf && sudo named-checkzone nexusplay.local /var/named/nexusplay.local.zone
  sudo systemctl enable --now named && sudo systemctl restart named
'
```

**Secondary** (sur l'EC2 nginx2) :
```bash
scp -i 007.pem bind/secondary/named.conf ec2-user@<NGINX2_IP>:/tmp/
ssh -i 007.pem ec2-user@<NGINX2_IP> '
  sudo dnf install -y bind bind-utils
  sudo mv /tmp/named.conf /etc/named.conf
  sudo chown root:named /etc/named.conf && sudo chmod 640 /etc/named.conf
  sudo mkdir -p /var/named/slaves && sudo chown named:named /var/named/slaves
  sudo named-checkconf
  sudo systemctl enable --now named && sudo systemctl restart named
'
```

Pour mettre à jour la zone : éditer `bind/primary/nexusplay.local.zone`, **incrémenter le serial** dans le SOA, re-pousser, puis `sudo rndc reload` côté primary. Le secondary se synchronise automatiquement (NOTIFY + AXFR).

## Tests & démos

> IPs publiques actuelles :
> - nginx1 : `44.202.153.219`
> - nginx2 : `13.221.229.161`
> - frontend : `3.88.174.245`
> - backend : `34.239.120.50`

### 1. Vue d'ensemble de l'infra

```bash
# IPs et état des EC2
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name,PublicIpAddress]' \
  --output table

# Conteneurs sur chaque EC2
for ip in 44.202.153.219 13.221.229.161 3.88.174.245 34.239.120.50; do
  echo "=== $ip ==="
  ssh -i 007.pem -o StrictHostKeyChecking=no ec2-user@$ip 'sudo docker ps --format "{{.Names}}\t{{.Status}}"'
done

# Targets Prometheus
curl -s http://44.202.153.219:9090/api/v1/targets | python3 -c "
import sys,json
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(f\"{t['labels']['job']:<15} {t['labels']['instance']:<25} {t['health']}\")"
```

### 2. Smoke test (k6 — 20s, exécuté dans le CI)

```bash
k6 run --env BASE_URL=http://44.202.153.219 k6/smoke.js
```
→ Vérifie p95 < 500ms et error rate < 1%.

### 3. Test de charge (k6 — 2 min)

```bash
k6 run --env BASE_URL=http://44.202.153.219 k6/load.js
```
→ 30 VUs constants, ~9 000 requêtes, valide les SLO sous charge.

### 4. Load balancing applicatif (round-robin entre les backends)

```bash
for i in $(seq 1 9); do
  curl -s http://44.202.153.219/api/hello | python3 -c "import sys,json;print(json.load(sys.stdin)['hostname'])"
done
```
→ Doit renvoyer 2 ou 3 `hostname` différents qui alternent (un par container).

### 5. Redondance nginx (les 2 nginx servent l'app)

```bash
echo "=== nginx1 ===" && curl -s http://44.202.153.219/api/hello
echo "=== nginx2 ===" && curl -s http://13.221.229.161/api/hello
```

### 6. DNS HA — failover BIND9

```bash
# Primary répond
dig @44.202.153.219 nexusplay.local +short

# Stop primary
ssh -i 007.pem ec2-user@44.202.153.219 'sudo systemctl stop named'

# Primary KO (timeout attendu), secondary répond toujours
dig @44.202.153.219 nexusplay.local +short +timeout=2
dig @13.221.229.161 nexusplay.local +short

# Restaurer
ssh -i 007.pem ec2-user@44.202.153.219 'sudo systemctl start named'
```

### 7. Autoscaling (scale-up forcé via CPU saturé)

**Terminal 1** — surveiller l'autoscaler :
```bash
ssh -i 007.pem ec2-user@34.239.120.50 'sudo tail -f /var/log/nexusplay-autoscale.log'
```

**Terminal 2** — saturer le CPU :
```bash
ssh -i 007.pem ec2-user@34.239.120.50 'yes > /dev/null & yes > /dev/null & yes > /dev/null &'
```
→ Attends ~30-60s, le terminal 1 affiche `SCALE UP → backend-3` puis éventuellement `backend-4`, `backend-5`.

**Arrêter la charge** :
```bash
ssh -i 007.pem ec2-user@34.239.120.50 'pkill yes'
```
→ Après ~1 min, le terminal 1 affiche `SCALE DOWN` jusqu'au retour à 2 replicas.

### 8. Pipeline CI/CD complet

```bash
# Modifier un truc visible dans le frontend
sed -i '' 's/NexusPlay/NexusPlay v3/' services/frontend/index.html

git add services/frontend/index.html
git commit -m "test: bump v3"
git push

# Suivre le pipeline (gh CLI requis)
gh run watch

# Après ~3 min, vérifier le déploiement
curl -s http://44.202.153.219/ | grep "<title>"
```

### 9. UIs à ouvrir dans le navigateur

```bash
open http://44.202.153.219/              # frontend
open http://44.202.153.219:3001          # Grafana (admin/admin)
open http://44.202.153.219:9090          # Prometheus
open http://44.202.153.219:9093          # Alertmanager
```

### 10. Démo soutenance — séquence "happy path" en 2 min

```bash
# (1) Vue d'ensemble
aws ec2 describe-instances --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name,PublicIpAddress]' --output table

# (2) Microservices + LB applicatif
for i in $(seq 1 6); do curl -s http://44.202.153.219/api/hello | python3 -c "import sys,json;print(json.load(sys.stdin)['hostname'])"; done

# (3) DNS HA
dig @44.202.153.219 nexusplay.local +short
dig @13.221.229.161 nexusplay.local +short

# (4) SLO sous charge
k6 run --env BASE_URL=http://44.202.153.219 k6/smoke.js
```
→ En 2 minutes : infra, microservices, LB, DNS HA, SLO respectés.
