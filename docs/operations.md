# Exploitation du homelab

[Documentation](README.md) · [Services](services.md) · [Reprise](disaster-recovery.md)

## Tableau de bord en ligne de commande

```bash
cd ~/homelab
./homelab status
```

Pour une vue Docker compacte :

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

## Mettre à jour

Toujours télécharger, puis recréer la sélection :

```bash
git pull --ff-only
./homelab check
./homelab stack pull monitoring
./homelab stack up monitoring
./homelab status
```

Une cible peut être un service (`radarr`), une catégorie (`monitoring`) ou
`--all`. Le déploiement conserve les `.env` et les données déjà présentes sous
`/srv/docker`.

> [!TIP]
> Commencer par une catégorie limite l’impact d’une mise à jour. Utiliser
> `--all` uniquement lorsque le contrôle global est souhaité.

## Redémarrer ou recréer

```bash
# Redémarrage simple, sans changement de définition
./homelab stack restart radarr

# Resynchronisation du Compose et recréation
./homelab stack up radarr
```

Les downloaders, Prowlarr et FlareSolverr partagent le réseau de Gluetun. Si
Gluetun est recréé manuellement, recréer ses consommateurs :

```bash
./homelab stack up download prowlarr flaresolverr
```

## Lire les logs

```bash
docker logs --tail 100 radarr
docker logs --since 30m --follow gluetun
docker compose \
  --project-directory /srv/docker/monitoring/uptime-kuma \
  logs --tail 100
```

Diagnostic système :

```bash
systemctl --failed
journalctl -p warning -b --no-pager
df -h / /srv /mnt/nas/downloads /mnt/nas/multimedia
```

## Sauvegardes

Le timer démarre vers 04:30, avec un délai aléatoire maximal de 15 minutes.

```bash
./homelab backup status
sudo ./homelab backup run
./homelab backup logs
```

Restic conserve 7 sauvegardes quotidiennes, 5 hebdomadaires, 12 mensuelles et
3 annuelles. Le dimanche, il exécute aussi le nettoyage et un contrôle partiel
des données.

## Contrôle après redémarrage

```bash
systemctl --failed
systemctl is-active docker rpi-firewall docker-restic-backup.timer
findmnt /srv
findmnt -T /mnt/nas/downloads
findmnt -T /mnt/nas/multimedia
findmnt -T /mnt/qnap-backups
./homelab status
```

État attendu : aucun service systemd en échec, `/srv` en `ext4`, les trois
montages QNAP en `nfs4`, et les conteneurs déclarés dans le manifeste actifs.

## Contrôles de sécurité

```bash
./homelab check
sudo sshd -t
sudo nft -c -f /etc/nftables.d/rpi-guard.nft
sudo nft list table inet rpi_guard
sudo ss -lntup
```

Les interfaces NPM `81`, Portainer `9443`, Pi-hole `8085`, wg-easy `51821`,
Cockpit `9090` et SSH restent privées. Seuls HTTP/HTTPS et WireGuard sont
destinés à une redirection depuis Internet.

## Où intervenir ?

| Symptôme | Premier contrôle |
|---|---|
| interface web inaccessible | `docker logs SERVICE` puis réseau `proxy` |
| téléchargement sans réseau | santé et logs de `gluetun` |
| import Radarr/Sonarr impossible | montages `/srv` et `/mnt/nas/*` |
| sauvegarde en échec | `./homelab backup logs` puis `/mnt/qnap-backups` |
| Compose refusé | `.env` de la stack et placeholders `CHANGE_ME` |
| DNS local en panne | conteneur Pi-hole et occupation du port 53 |
