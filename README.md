# Lab load balancing avec NGINX et Docker

Petit lab pour comprendre comment fonctionne un load balancer (type F5 BIG-IP ou Radware Alteon) : une adresse d'entrée unique, un pool de serveurs derrière, de la répartition de charge, de la tolérance aux pannes et du SSL offloading.

Je l'ai monté pour pratiquer les notions de load balancing avant de travailler sur des équipements F5 en production.

## Architecture

```
          Client (navigateur / curl)
                     │
     http://IP:8080  │  https://IP:8443     ← VIP
                     │
            ┌─────────────────┐
            │   lb (NGINX)    │              ← reverse proxy / load balancer
            └─────────────────┘
               │           │
         ┌─────────┐  ┌─────────┐
         │  web1   │  │  web2   │            ← pool
         └─────────┘  └─────────┘
```

Les trois conteneurs utilisent l'image `nginx:alpine`. C'est la configuration qui change leur rôle :

- `web1` et `web2` gardent la config par défaut et servent simplement une page HTML ;
- `lb` reçoit le fichier `lb.conf` et transmet les requêtes au pool.

Seul `lb` est exposé vers l'extérieur. Les serveurs web ne sont joignables qu'à travers lui, sur le réseau interne créé par Docker Compose.

## Environnement

- VM Ubuntu Server 24.04 sous VMware Workstation
- Docker et Docker Compose (`docker.io`, `docker-compose-v2`)
- Administration en SSH depuis Windows

## Structure du repo

```
lab-lb/
├── docker-compose.yml      # les 3 conteneurs
├── lb.conf                 # config du load balancer (round robin + HTTPS)
├── configs/                # variantes pour tester les algorithmes
│   ├── lb-least_conn.conf
│   ├── lb-ip_hash.conf
│   └── lb-weight.conf
├── scripts/
│   └── generate-cert.sh    # certificat auto-signé pour le HTTPS
├── certs/                  # certificat et clé (non versionnés)
├── web1/index.html
└── web2/index.html
```

## Lancer le lab

```bash
git clone <url-du-repo>
cd lab-lb
./scripts/generate-cert.sh
docker compose up -d
docker compose ps
```

Les trois conteneurs doivent être en état `running`.

## Tests réalisés

### 1. Répartition (round robin)

```bash
for i in 1 2 3 4 5 6; do curl -s localhost:8080; echo; done
```

Résultat : les réponses alternent entre serveur 1 et serveur 2.

À noter : dans un navigateur, on voit souvent toujours le même serveur. Le navigateur envoie deux requêtes par chargement (la page et `favicon.ico`), donc le round robin envoie toujours la page au même serveur. `curl` est plus fiable pour observer l'alternance.

### 2. Panne d'un serveur

```bash
docker compose stop web1
for i in 1 2 3 4; do curl -s localhost:8080; echo; done
```

Résultat : toutes les requêtes sont servies par web2, le site reste disponible. Dans les logs (`docker compose logs lb`), on voit l'erreur `upstream timed out` sur web1 puis les réponses en 200.

Remise en service :

```bash
docker compose start web1
docker compose restart lb
```

### 3. Algorithmes de répartition

Pour changer d'algorithme :

```bash
cp configs/lb-ip_hash.conf lb.conf
docker compose restart lb
```

| Fichier | Algorithme | Résultat observé |
|---|---|---|
| `lb.conf` | Round robin (par défaut) | Alternance 1 / 2 |
| `lb-least_conn.conf` | Least connections | Alternance 1 / 2, car les requêtes du lab sont trop courtes pour qu'un serveur soit plus chargé que l'autre |
| `lb-ip_hash.conf` | Persistance par IP source | Toujours le même serveur pour un même client |
| `lb-weight.conf` | Poids (`weight=3` sur web1) | Environ 3 requêtes sur 4 vers web1 |

### 4. SSL offloading

```bash
for i in 1 2 3 4; do curl -sk https://localhost:8443; echo; done
```

Le client parle en HTTPS au load balancer, qui déchiffre puis parle en HTTP aux serveurs. Les serveurs n'ont rien à changer et un seul certificat est à gérer.

Dans le navigateur (`https://IP:8443`), un avertissement s'affiche car le certificat est auto-signé.

## Correspondance avec F5 et Alteon

| Dans le lab NGINX | F5 BIG-IP | Radware Alteon |
|---|---|---|
| `listen` + port publié | Virtual Server (VIP) | Virtual Service |
| `upstream pool_web` | Pool | Group |
| `server web1:80` | Pool member | Real Server |
| Détection passive des pannes | Health monitor (actif) | Health check |
| `least_conn`, `weight` | Load balancing method, Ratio | Métrique |
| `ip_hash` | Persistence | Persistence |
| `listen 443 ssl` | Client SSL profile | SSL offload |

## Limites et ce que j'ai retenu

- NGINX open source ne fait que de la détection **passive** : il découvre qu'un serveur est en panne quand une vraie requête échoue, donc le premier client subit le délai. Un F5 fait des health monitors **actifs** qui testent les serveurs en continu et retirent un serveur avant qu'un client tombe dessus.
- En SSL offloading, le trafic entre le load balancer et les serveurs passe en clair. Si ce n'est pas acceptable, on fait du SSL bridging (le LB rechiffre vers les serveurs). En passthrough, ce sont les serveurs qui déchiffrent et le LB ne voit pas le contenu.
- Le certificat est auto-signé et la clé privée n'est jamais versionnée (voir `.gitignore`).

## Arrêter le lab

```bash
docker compose down
```

## Auteur

Kone Awa Naki
