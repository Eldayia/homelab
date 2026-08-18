# Architecture

[Documentation](README.md) · [Services](services.md) · [Exploitation](operations.md)

## Vue d’ensemble

```mermaid
flowchart LR
  Internet["Internet / routeur"] -->|"TCP 80/443"| NPM["Nginx Proxy Manager"]
  Internet -->|"UDP 51820"| WG["WireGuard / wg-easy"]
  LAN["Réseau local"] --> PI["Pi-hole DNS"]
  WG --> LAN
  PI --> NPM
  NPM --> PROXY["Réseau Docker proxy"]
  PROXY --> INFRA["Infrastructure"]
  PROXY --> MON["Monitoring"]
  PROXY --> MEDIA["Media stack"]
  VPN["Gluetun / kill switch"] --> DOWNLOAD["Downloaders"]
  DOWNLOAD --> SSD["SSD /srv/media/downloads"]
  DOWNLOAD --> NASMEDIA["NFS Download / Multimedia"]
  INFRA --> DATA["Données /srv/docker"]
  MON --> DATA
  DATA --> RESTIC["Sauvegarde Restic"]
  RESTIC --> NAS["Stockage externe"]
```

## Séparation des responsabilités

- `config/` décrit le système hôte : APT, réseau, SSH, pare-feu et systemd ;
- `stacks/<catégorie>/<stack>/` contient uniquement la définition déployable ;
- `inventory/stacks.manifest` sélectionne les stacks connues et actives ;
- `/srv/docker/<catégorie>/<stack>` reçoit les Compose, secrets locaux et données ;
- Restic sauvegarde l’état qui ne peut pas être reconstruit depuis Git.

Le script conserve désormais le niveau de catégorie sous `/srv/docker`. Il
migre une ancienne destination non catégorisée lors du premier `sync`, sans
écraser une destination déjà présente.

## Hôte actuel et portabilité

La plateforme validée est un Raspberry Pi 4 arm64 sous Debian/Raspberry Pi OS
13, avec Docker Engine et le plugin Compose. L’adresse actuelle est documentée
dans `config/network.env.example`, mais les Compose utilisent des variables
pour les liaisons dépendantes de l’hôte.

Pour migrer vers un autre matériel :

1. vérifier que l’OS fournit les paquets de `inventory/apt-packages.txt` ;
2. vérifier la prise en charge de l’architecture par chaque image ;
3. adapter le réseau, le pare-feu, les montages et les unités systemd ;
4. restaurer `/srv/docker`, puis valider les Compose avant leur démarrage.

Les fichiers `config/apt/raspi.sources`, `rpi-guard.nft` et
`rpi-firewall.service` restent spécifiques à l’hôte actuel.

## Réseau

Le réseau Docker externe `proxy` relie Nginx Proxy Manager aux interfaces web.
Le réseau externe `download` relie Qui aux composants de téléchargement qui en
ont besoin. L’installation et le déploiement créent ces deux réseaux si
nécessaire. Les services d’administration
directe sont liés à l’adresse LAN paramétrée ; seuls HTTP/HTTPS et WireGuard
sont destinés à une redirection depuis Internet.

Pi-hole publie TCP/UDP 53 sur l’hôte. wg-easy utilise le réseau hôte et
`/dev/net/tun`. Les autres services privilégient `expose` et le réseau `proxy`.

Les downloaders, Prowlarr et FlareSolverr partagent le namespace réseau du
conteneur `gluetun`. Gluetun est seul raccordé à `proxy` pour ces interfaces ;
aucun port de la media-stack n’est publié directement sur l’hôte. Chaque
service reste un projet Compose autonome et le manifeste déclare sa dépendance
à Gluetun.

## État et données

Git permet de reconstruire l’hôte et les définitions Docker, mais pas l’état des
applications. La reprise complète dépend donc de ce dépôt et de la sauvegarde
Restic chiffrée contenant `/srv/docker` et ses secrets locaux.
