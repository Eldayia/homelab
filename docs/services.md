# Services et routes

## Services hébergés sur le Raspberry Pi

| Domaine | Backend NPM | Accès observé |
|---|---|---|
| `box.eldayia.fr` | `freebox-dashboard:3000` | liste d'accès 1 |
| `convert.daelyx.fr` | `convertx:3000` | public |
| `doc.daelyx.fr` | `bookstack:80` | public |
| `draw.daelyx.fr` | `excalidraw:80` | liste d'accès 2 |
| `git.daelyx.fr` | `forgejo:3000` | public |
| `hub.daelyx.fr` | `homarr:7575` | liste d'accès 1 |
| `jdr.daelyx.fr` | `foundryvtt:30000` | public |
| `kink.eldayia.fr` | `kinklist:3000` | public |
| `link.eldayia.fr` | `https://linkstack:443` | public |
| `logs.daelyx.fr` | `dozzle:8080` | liste d'accès 1 |
| `metube.daelyx.fr` | `metube:8081` | liste d'accès 2 |
| domaine à définir | `minipaint:80` | aucune route NPM observée |
| `monitor.daelyx.fr` | `beszel:8090` | liste d'accès 1 |
| `nfo.daelyx.fr` | `nfoforge:3000` | public |
| `notes.daelyx.fr` | `hedgedoc:3000` | public |
| `npm.eldayia.fr` | `nginx-proxy-manager:81` | liste d'accès 1 |
| `paste.daelyx.fr` | `hastebin:7777` | liste d'accès 2 |
| `pdf.daelyx.fr` | `stirling-pdf:8080` | public |
| `pihole.eldayia.fr` | `pihole:80` | liste d'accès 1 |
| `prez.daelyx.fr` | `prezforge:3000` | public |
| `status.daelyx.fr` | `uptime-kuma:3001` | public |
| `tools.daelyx.fr` | `it-tools:80` | public |
| `transfer.daelyx.fr` | `psitransfer:3000` | public |
| `vault.eldayia.fr` | `vaultwarden:80` | public |
| `vpn.eldayia.fr` | `192.168.1.240:51821` | liste d'accès 1 |

Toutes les routes observées forcent SSL et autorisent les WebSockets. NPM porte
également des routes vers le QNAP `192.168.1.250` (Sonarr, Radarr, qBittorrent,
QTS, etc.). Leur reconstruction dépend de la base NPM restaurée par Restic.

La route `jdr.daelyx.fr` a été vérifiée après l'export principal : elle cible
`foundryvtt:30000`, force SSL et autorise les WebSockets.

## Données à restaurer

Chaque bind mount relatif au Compose vit dans `/srv/docker/<stack>`. Les bases
Forgejo et HedgeDoc sont PostgreSQL, BookStack utilise MariaDB. Le script de
sauvegarde produit aussi des dumps SQL cohérents avant de figer brièvement les
conteneurs et de lancer Restic.
