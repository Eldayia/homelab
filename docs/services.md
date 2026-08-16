# Catalogue des services

Le fichier `inventory/stacks.manifest` est la source de vérité utilisée par le
script de déploiement. Cette page décrit le rôle et l’exposition attendue des
services, sans contenir de secret ni de configuration Nginx Proxy Manager.

## Infrastructure

| Stack | Rôle | Accès attendu |
|---|---|---|
| `nginx-proxy-manager` | reverse proxy et certificats TLS | 80/443 publics, administration 81 sur le LAN |
| `pihole` | DNS et filtrage du LAN | TCP/UDP 53, administration 8085 sur le LAN |
| `wg-easy` | accès WireGuard au homelab | UDP 51820 public, administration 51821 sur le LAN |
| `homarr` | portail des services | via le réseau Docker `proxy` |

## Monitoring

| Stack | Rôle | Accès attendu |
|---|---|---|
| `uptime-kuma` | disponibilité et alertes | via `proxy` |
| `portainer` | administration Docker | HTTPS 9443 sur le LAN |
| `beszel` | métriques de l’hôte et des conteneurs | via `proxy` |
| `dozzle` | consultation des logs Docker | via `proxy` |
| `freebox-dashboard` | supervision de la Freebox | port LAN configurable |

## Media stack

La media stack n’est pas encore déployable depuis ce dépôt. Son Compose sera
intégré séparément et devra notamment définir Prowlarr, Sonarr et Radarr, leurs
volumes, leurs réseaux et les paramètres d’identité du processus.

## Convention réseau

Les interfaces web destinées au reverse proxy rejoignent le réseau Docker
externe `proxy` et utilisent de préférence `expose`. Les ports publiés sur
l’hôte doivent être liés à l’adresse LAN, sauf les points d’entrée explicitement
publics. Les valeurs propres à l’hôte vivent dans les `.env`, jamais directement
dans de nouveaux fichiers Compose.
