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

## Monitoring

| Stack | Rôle | Accès attendu |
|---|---|---|
| `uptime-kuma` | disponibilité et alertes | via `proxy` |
| `portainer` | administration Docker | HTTPS 9443 sur le LAN |
| `beszel` | métriques de l’hôte et des conteneurs | via `proxy` |
| `dozzle` | consultation des logs Docker | via `proxy` |
| `freebox-dashboard` | supervision de la Freebox | port LAN configurable |
| `homarr` | portail des services | via `proxy` |
| `gluetun` | passerelle VPN et kill switch | via `proxy`, sans port hôte publié |

## Media stack

| Groupe | Stacks | Accès attendu |
|---|---|---|
| téléchargement | `qbittorrent`, `sabnzbd`, `jdownloader`, `slskd` | namespace réseau de Gluetun |
| indexation | `prowlarr`, `flaresolverr` | namespace réseau de Gluetun |
| automatisation | `radarr`, `sonarr`, `lidarr` | via `proxy` |
| enrichissement | `bazarr`, `lazylibrarian`, `seerr`, `tinymediamanager` | via `proxy` |

Ces stacks sont déployables explicitement, mais restent `inactive` dans le
manifeste afin que `--all` ne les démarre pas avant leur configuration. Le
détail des chemins et des flux est dans [Media stack](media-stack.md).

## Convention réseau

Les interfaces web destinées au reverse proxy rejoignent le réseau Docker
externe `proxy` et utilisent de préférence `expose`. Les ports publiés sur
l’hôte doivent être liés à l’adresse LAN, sauf les points d’entrée explicitement
publics. Les valeurs propres à l’hôte vivent dans les `.env`, jamais directement
dans de nouveaux fichiers Compose.
