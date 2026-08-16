# Reprise après sinistre

Cette procédure vise un hôte neuf ou de remplacement. Elle ne doit pas écraser
un `/srv/docker` existant sans sauvegarde préalable.

## 1. Préparer le système

1. Installer Debian/Raspberry Pi OS 13 arm64.
2. Créer l'utilisateur `eldayia` avec UID/GID 1000.
3. Installer sa clé SSH publique.
4. Cloner ce dépôt privé dans `~/homelab`.

La clé publique actuellement attendue est versionnée dans
`config/ssh/authorized_keys`. Aucune clé privée n'est stockée ici.

## 2. Installer l'hôte

```bash
cd ~/homelab
sudo ./scripts/install-host.sh
```

Le script installe les paquets, Docker, les dotfiles, les fichiers SSH, nftables
et systemd. Il n'active pas le pare-feu ni le timer de sauvegarde par défaut.

Reconnecte-toi avant la suite afin que l'appartenance au groupe `docker` et Zsh
soient prises en compte.

Si un SSD USB contient les médias ou d’autres données persistantes, monte-le
avant de déployer les stacks qui en dépendent :

```bash
sudo ./scripts/configure-storage.sh
findmnt /srv
```

L’assistant ne formate jamais le disque et refuse les partitions système.

## 3. Réseau statique

Depuis une console locale, ou en gardant une deuxième session SSH ouverte :

```bash
sudo ./scripts/configure-network.sh
sudo ./scripts/configure-network.sh --apply
```

La première commande affiche seulement le changement prévu. Vérifie ensuite :

```bash
ip -br address show eth0
ip route
getent hosts deb.debian.org
```

## 4. Activer le pare-feu

Garde la session SSH actuelle ouverte et teste une seconde connexion après :

```bash
sudo nft -c -f /etc/nftables.d/rpi-guard.nft
sudo systemctl enable --now rpi-firewall.service
sudo nft list table inet rpi_guard
```

Annulation d'urgence depuis la session restée ouverte :

```bash
sudo nft delete table inet rpi_guard
```

## 5. Monter le QNAP et ouvrir Restic

```bash
sudo QNAP_USER=rpi-backup ./scripts/configure-backup.sh
```

Le script demande sans les afficher :

- le mot de passe du partage QNAP ;
- le mot de passe du dépôt Restic.

Il crée `/root/.smb-qnap-backup` et
`/root/.config/restic/rpi-password` en mode `600`, ajoute le montage CIFS et
active le timer quotidien.

Contrôles :

```bash
mountpoint /mnt/qnap-backups
sudo RESTIC_PASSWORD_FILE=/root/.config/restic/rpi-password \
  restic -r /mnt/qnap-backups/restic-rpi snapshots
```

## 6. Restaurer les données

Sur l'hôte neuf, avant de lancer les stacks :

```bash
sudo ./scripts/restore-data.sh --snapshot latest --confirm
```

Le script refuse par défaut de restaurer si un conteneur tourne. Pour inspecter
sans écrire dans `/`, restaure d'abord dans un dossier temporaire :

```bash
sudo ./scripts/restore-data.sh \
  --snapshot latest \
  --target /srv/restic-inspection \
  --confirm
```

## 7. Synchroniser et démarrer

Les fichiers de configuration sont synchronisés par catégorie ou en totalité :

```bash
./scripts/deploy.sh sync --all
./scripts/deploy.sh up --all
```

Si aucune sauvegarde n'est disponible, `sync --all` crée les `.env` depuis les
modèles. Remplace chaque `CHANGE_ME`, puis relance `up --all`.

Dans ce cas, les entrées DNS locales Pi-hole à recréer sont aussi conservées
dans `stacks/infrastructure/pihole/dns-hosts.txt`. Le fichier ne contient aucun
mot de passe.

## 8. Vérifications finales

```bash
./scripts/verify.sh
./scripts/deploy.sh status --all
sudo systemctl --failed
sudo systemctl list-timers docker-restic-backup.timer
sudo nft list table inet rpi_guard
findmnt /srv
```

Teste ensuite Pi-hole, les domaines HTTPS, WireGuard, les moniteurs Kuma et un
cycle de sauvegarde manuel.
