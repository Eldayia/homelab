# Exploitation courante

## Conteneurs

```bash
./scripts/deploy.sh status --all
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker compose -f /srv/docker/uptime-kuma/compose.yaml logs --tail=100
```

Pour mettre à jour une stack :

```bash
./scripts/deploy.sh pull nom-de-la-stack
./scripts/deploy.sh up nom-de-la-stack
```

Les applications maison sont des dépôts indépendants. Le script ne réinitialise
jamais un dépôt existant et ne détruit pas ses changements locaux.

miniPaint est construit localement depuis la version officielle `v4.14.3`,
épinglée au commit `a79733eb803fc97084ef0ee4faa96b031e69e1c0`. Une mise à jour
demande de modifier simultanément `MINIPAINT_REF`, le tag de l'image et les
labels de `stacks/minipaint/Dockerfile`.

Kinklist est épinglé au commit de durcissement
`fb371da4e5e46f9f52aa49a5043da725cbea1934`. Son conteneur s'appelle
`kinklist-app`, mais le service Compose conserve l'alias DNS `kinklist` attendu
par NPM. Foundry utilise `CONTAINER_PRESERVE_CONFIG=true` pour ne pas réécrire
son `config.json` lors des recréations.

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
```
