# Exploitation courante

## Conteneurs

```bash
./scripts/deploy.sh status --all
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker compose -f /srv/docker/monitoring/uptime-kuma/compose.yaml logs --tail=100
```

Pour mettre à jour une stack :

```bash
./scripts/deploy.sh pull nom-de-la-stack
./scripts/deploy.sh up nom-de-la-stack
```

Une catégorie entière peut être ciblée de la même façon :

```bash
./scripts/deploy.sh pull monitoring
./scripts/deploy.sh up monitoring
```

Le script synchronise les fichiers du dépôt sans écraser un `.env` existant.
La destination exacte est
`/srv/docker/<catégorie>/<stack>`. Toute nouvelle stack doit être ajoutée au
manifeste.

Pour redémarrer un seul service de la media-stack :

```bash
./scripts/deploy.sh restart qbittorrent
./scripts/deploy.sh restart radarr
```

Le déploiement d’un downloader démarre Gluetun si nécessaire. Après une
recréation manuelle de Gluetun, recréer les consommateurs de son namespace avec
`./scripts/deploy.sh up download prowlarr flaresolverr`.

## Sauvegarde

Le timer s'exécute à 04:30 avec un délai aléatoire maximal de 15 minutes.

```bash
systemctl list-timers docker-restic-backup.timer
sudo systemctl start docker-restic-backup.service
sudo journalctl -u docker-restic-backup.service -n 150 --no-pager
```

La rétention est de 7 sauvegardes quotidiennes, 5 hebdomadaires, 12 mensuelles
et 3 annuelles. Le dimanche, Restic exécute `prune` et lit 10 % des données ; les
autres jours, il vérifie la structure du dépôt.

## Sécurité

```bash
sudo sshd -t
sudo nft -c -f /etc/nftables.d/rpi-guard.nft
sudo nft list table inet rpi_guard
sudo ss -lntup
./scripts/check-secrets.sh
```

Garde NPM 81, Portainer 9443, Pi-hole 8085, wg-easy 51821, Cockpit 9090 et SSH
hors des redirections publiques.

## Contrôle après redémarrage

```bash
systemctl --failed
systemctl is-active docker rpi-firewall docker-restic-backup.timer
docker ps --format '{{.Names}}|{{.Status}}'
mountpoint /mnt/qnap-backups
findmnt -T /mnt/nas/downloads -o SOURCE,TARGET,FSTYPE,OPTIONS
findmnt -T /mnt/nas/multimedia -o SOURCE,TARGET,FSTYPE,OPTIONS
findmnt /srv
```
