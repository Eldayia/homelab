# Media stack

La media stack est découpée en un projet Compose par service. Chaque service
peut ainsi être synchronisé, recréé ou redémarré seul. Les stacks restent
`inactive` dans le manifeste tant que leurs réglages applicatifs et secrets ne
sont pas terminés : elles ne sont donc pas lancées par `deploy.sh up --all`.

## Stockage retenu

```text
/srv/docker/monitoring/gluetun      configuration VPN sur le SSD
/srv/docker/monitoring/homarr       configuration Homarr sur le SSD
/srv/docker/download/<service>      configurations des downloaders sur le SSD
/srv/docker/media/<service>         configurations des applications média
/srv/media/downloads/torrents       torrents incomplets et terminés sur le SSD
/srv/media/downloads/usenet         articles Usenet incomplets sur le SSD
/srv/media/downloads/jdownloader    téléchargements JDownloader en cours
/srv/media/downloads/slskd          téléchargements slskd en cours
/mnt/nas/downloads                  partage QNAP Download
/mnt/nas/multimedia                 bibliothèque finale QNAP Multimedia
```

Aucun Compose n’utilise de volume Docker nommé ou anonyme. Chaque donnée
persistante est un bind mount vers l’un de ces dossiers réels ou vers un
sous-dossier relatif comme `./config`. Le déploiement crée les dossiers locaux
manquants et refuse de démarrer si les montages SSD/NFS requis sont absents.

## Flux des fichiers

| Source | En cours | Terminé | Import final |
|---|---|---|---|
| qBittorrent | SSD | SSD | Radarr/Sonarr/Lidarr copient vers `Multimedia`; le torrent reste sur le SSD pour le seeding |
| SABnzbd | SSD | NAS `Download/usenet` | les applications média déplacent ou copient vers `Multimedia` |
| JDownloader | SSD | NAS `Download/jdownloader` | import manuel ou par une application compatible |
| slskd | SSD | NAS `Download/slskd` | Lidarr/LazyLibrarian ou classement manuel vers `Multimedia` |

Une copie qBittorrent du SSD vers le NAS ne peut pas utiliser de hardlink : les
deux emplacements sont sur des systèmes de fichiers différents. Ce choix est
volontaire afin de conserver le fichier source pour le partage torrent.

## Préparation et déploiement

Monter d’abord le SSD et les deux exports QNAP, puis synchroniser les stacks :

```bash
sudo ./scripts/configure-storage.sh
sudo ./scripts/configure-media-storage.sh

./scripts/deploy.sh sync gluetun download media
```

Compléter ensuite les fichiers `.env`, en particulier les identifiants de
service NordVPN dans `/srv/docker/monitoring/gluetun/.env`. Aucun secret réel
ne doit être ajouté au dépôt.

Le démarrage peut ensuite se faire service par service :

```bash
./scripts/deploy.sh up gluetun
./scripts/deploy.sh up qbittorrent
./scripts/deploy.sh up sabnzbd
./scripts/deploy.sh up radarr sonarr prowlarr
```

Ou par catégorie :

```bash
./scripts/deploy.sh up download
./scripts/deploy.sh up media
```

Les downloaders, Prowlarr et FlareSolverr partagent le réseau de Gluetun. Le
script démarre Gluetun automatiquement et attend qu’il soit sain. Après une
recréation de Gluetun, recréer ces consommateurs avec :

```bash
./scripts/deploy.sh up download prowlarr flaresolverr
```

## Chemins à configurer dans les applications

### qBittorrent

- dossier par défaut : `/data/torrents/complete` ;
- dossier incomplet : `/data/torrents/incomplete` ;
- catégories conseillées : `radarr`, `sonarr`, `lidarr`.

Radarr, Sonarr et Lidarr voient le même chemin `/data/torrents`. Il ne faut donc
pas ajouter de Remote Path Mapping.

### SABnzbd

- dossier temporaire : `/incomplete-downloads` ;
- dossier terminé : `/downloads` ;
- créer les catégories `radarr`, `sonarr` et `lidarr` sous `/downloads`.

Dans les applications média, le même contenu est visible sous `/data/usenet`.
Un Remote Path Mapping peut être nécessaire si SABnzbd annonce le chemin
`/downloads`; le faire correspondre à `/data/usenet`.

### JDownloader

- dossier de travail : `/output` ;
- destination NAS : `/nas-downloads`.

JDownloader doit être configuré avec Packagizer et/ou Event Scripter pour
déplacer un paquet terminé de `/output` vers `/nas-downloads`. Le Compose ne
peut pas déterminer à lui seul qu’un paquet est terminé.

### slskd

Les chemins sont fournis directement par l’environnement :

- incomplets : `/data/incomplete` ;
- terminés : `/data/downloads` ;
- partage en lecture seule : `/shares/multimedia`.

### Bibliothèques finales

Les racines conseillées sont :

| Application | Dossier racine |
|---|---|
| Radarr | `/data/media/Films` |
| Sonarr | `/data/media/Series` et éventuellement `/data/media/Animes` |
| Lidarr | `/data/media/Musique` |
| LazyLibrarian | `/books/Livres` |

## Réseau et reverse proxy

Aucun port de la media stack n’est publié directement sur l’hôte. Les services
utilisent uniquement `expose` et le réseau Docker externe `proxy`. Dans Nginx
Proxy Manager, utiliser les cibles suivantes :

| Service | Hôte Docker | Port |
|---|---|---|
| qBittorrent | `gluetun` | `8081` |
| SABnzbd | `gluetun` | `8080` |
| JDownloader | `gluetun` | `5800` |
| slskd | `gluetun` | `5030` |
| Prowlarr | `gluetun` | `9696` |
| Radarr | `radarr` | `7878` |
| Sonarr | `sonarr` | `8989` |
| Lidarr | `lidarr` | `8686` |
| Bazarr | `bazarr` | `6767` |
| Seerr | `seerr` | `5055` |

Pour les clients de téléchargement configurés dans les applications média,
les adresses sont `gluetun:8081` pour qBittorrent et `gluetun:8080` pour
SABnzbd. Prowlarr et FlareSolverr partageant le même namespace réseau, Prowlarr
peut joindre FlareSolverr sur `http://127.0.0.1:8191`.
