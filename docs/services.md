# Catalogue des services

[Documentation](README.md) · [Architecture](architecture.md) · [Exploitation](operations.md)

Le manifeste déclare 25 projets Compose. Lors de l’audit, 24 étaient lancés
pour 26 conteneurs ; tinyMediaManager était synchronisé mais non lancé. Le manifeste
reste la liste exécutable de référence :
[`inventory/stacks.manifest`](../inventory/stacks.manifest).

## Infrastructure

| Service | Rôle | Exposition |
|---|---|---|
| Nginx Proxy Manager | reverse proxy et TLS | `80`, `443`, admin LAN `81` |
| Pi-hole | DNS local et filtrage | DNS `53`, admin LAN `8085` |
| wg-easy | accès distant WireGuard | UDP `51820`, admin LAN `51821` |

## Monitoring

| Service | Rôle |
|---|---|
| Homarr | portail du homelab |
| Beszel | métriques hôte et conteneurs |
| Glances | vue système détaillée |
| Uptime Kuma | disponibilité et alertes |
| Dozzle | consultation des logs |
| Portainer | administration Docker |
| Freebox Dashboard | métriques de la Freebox |
| Gluetun | passerelle VPN et kill switch des téléchargements |

## Téléchargement

| Service | Usage | Réseau |
|---|---|---|
| qBittorrent | torrents | namespace Gluetun |
| SABnzbd | Usenet | namespace Gluetun |
| JDownloader | téléchargements directs | namespace Gluetun |
| slskd | client Soulseek | namespace Gluetun |
| Qui | gestion avancée de qBittorrent | réseaux `proxy` et `download` |

## Médias

| Service | Rôle |
|---|---|
| Prowlarr | indexeurs |
| FlareSolverr | résolution de protections web |
| Radarr / Sonarr | films et séries |
| Lidarr | musique |
| Bazarr | sous-titres |
| LazyLibrarian | livres |
| Seerr | demandes de contenus |
| tinyMediaManager | métadonnées et organisation |

## Piloter une sélection

```bash
./homelab stack list
./homelab stack up pihole
./homelab stack up infrastructure
./homelab stack status --all
```

## Ajouter un service

1. Créer `stacks/<catégorie>/<nom>/compose.yaml`.
2. Ajouter `.env.example` avec des valeurs non sensibles et `CHANGE_ME` pour
   les secrets obligatoires.
3. Utiliser uniquement des bind mounts pour les données persistantes.
4. Déclarer la stack dans `inventory/stacks.manifest` avec ses dépendances et
   montages requis.
5. Lancer `./homelab check`.
6. Synchroniser avec `./homelab stack sync <nom>`, compléter le `.env` sous
   `/srv/docker`, puis lancer `./homelab stack up <nom>`.

Une stack raccordée au reverse proxy rejoint le réseau externe `proxy`. Un
downloader partage le namespace de `gluetun` et le déclare comme dépendance
dans le manifeste.
