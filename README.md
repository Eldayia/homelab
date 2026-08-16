# Docker Homelab

Ce dépôt est la source de vérité pour **installer, initialiser, configurer,
déployer et reconstruire** un homelab Docker. L’hôte actuel est un Raspberry Pi
4 sous Debian/Raspberry Pi OS arm64, mais l’organisation sépare volontairement
la configuration de l’hôte des stacks afin de pouvoir évoluer vers une autre
machine ou architecture.

## Organisation

```text
config/                 configuration système (réseau, SSH, nftables, systemd)
docs/                   architecture, exploitation et reprise après sinistre
inventory/              paquets et manifeste des stacks déployables
scripts/                installation, déploiement, sauvegarde et vérification
stacks/
├── infrastructure/     DNS, reverse proxy, VPN et portail
└── monitoring/         supervision, logs et administration Docker
```

Une catégorie `media-stack` sera ajoutée après intégration du Compose fourni
séparément.

### Stacks Docker

| Partie | Services actuels |
|---|---|
| Infrastructure | Pi-hole, Nginx Proxy Manager, wg-easy, Homarr |
| Monitoring | Uptime Kuma, Portainer, Beszel, Dozzle, Freebox Dashboard |
| Media stack | Prévue : Prowlarr, Sonarr, Radarr, à partir du Compose fourni séparément |

Les fichiers Compose et leurs modèles de variables sont versionnés. Les
données persistantes, bibliothèques multimédias et secrets restent hors de Git.

## Démarrage rapide

Sur l’hôte actuellement supporté et fraîchement installé :

```bash
git clone git@github.com:Eldayia/raspberrypi-homelab.git ~/homelab
cd ~/homelab

sudo ./scripts/install-host.sh
sudo ./scripts/configure-network.sh --apply
sudo ./scripts/configure-backup.sh

./scripts/deploy.sh list
./scripts/deploy.sh up infrastructure
./scripts/deploy.sh up monitoring
./scripts/verify.sh
```

Avant le premier démarrage, compléter les `.env` créés dans
`/srv/docker/<stack>`. Sur un hôte à reconstruire, restaurer les données avant
de lancer les conteneurs : voir
[la procédure de reprise](docs/disaster-recovery.md).

## Déploiement

Le script accepte aussi bien une catégorie qu’un nom de stack :

```bash
./scripts/deploy.sh list
./scripts/deploy.sh sync infrastructure
./scripts/deploy.sh up pihole uptime-kuma
./scripts/deploy.sh status --all
```

Le classement du dépôt ne modifie pas les chemins d’exécution : une stack reste
synchronisée dans `/srv/docker/<nom>`. Il est possible de changer cette racine
avec `HOMELAB_ROOT`.

## Portabilité

- plateforme validée : Raspberry Pi 4, Debian/Raspberry Pi OS 13, arm64 ;
- les images ajoutées doivent être multi-architecture ;
- adresses IP, UID/GID, fuseau horaire et chemins médias sont configurables par
  variables d’environnement ;
- les éléments spécifiques au Pi sont isolés dans `config/apt/raspi.sources` et
  documentés comme tels.

Une migration d’hôte doit commencer par la validation de
`scripts/install-host.sh`, du pare-feu, des montages et de la compatibilité des
images. Les détails sont dans [l’architecture](docs/architecture.md).

## Secrets et sauvegardes

Ne jamais versionner de `.env`, clé privée, certificat privé ou donnée
applicative. Les fichiers `.env.example` ne contiennent que des valeurs factices
ou des paramètres non sensibles. `scripts/check-secrets.sh` et
`scripts/verify.sh` doivent être lancés avant chaque commit.

Les données sous `/srv/docker` sont sauvegardées avec Restic vers le stockage
externe configuré. Voir [la gestion des secrets](docs/secrets.md) et
[l’exploitation courante](docs/operations.md).
