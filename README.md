# Raspberry Pi 4 Homelab

Dépôt de reconstruction du Raspberry Pi 4 `rpi4` (`192.168.1.240`). Il a été
constitué depuis l'état réel de la machine les 7 et 8 août 2026.

Le dépôt contient les fichiers Compose, le pare-feu, les unités systemd, les
dotfiles et les scripts nécessaires à la remise en service. Les données
persistantes et les secrets restent hors de Git et sont restaurés depuis le
dépôt Restic chiffré du QNAP (`192.168.1.250`).

## Reprise rapide

Sur un Raspberry Pi fraîchement installé avec Debian/Raspberry Pi OS 13 arm64 :

```bash
git clone git@github.com:Eldayia/raspberrypi-homelab.git ~/homelab
cd ~/homelab

sudo ./scripts/install-host.sh
sudo ./scripts/configure-network.sh --apply
sudo ./scripts/configure-backup.sh
sudo ./scripts/restore-data.sh --confirm

./scripts/deploy.sh up --all
./scripts/verify.sh
```

Ne lance pas ces commandes à l'aveugle sur un hôte déjà rempli. La procédure
détaillée, l'ordre des opérations et les points de contrôle sont dans
[docs/disaster-recovery.md](docs/disaster-recovery.md).

## Contenu

- `stacks/` : 26 stacks actives, dont miniPaint construit localement pour ARM64 ;
- `config/` : nftables, SSH, systemd, dépôts APT et exemples réseau/QNAP ;
- `dotfiles/` : Zsh, Bash, Git, Neovim et tableau de bord SSH ;
- `scripts/install-host.sh` : paquets, Docker, shell et configuration système ;
- `scripts/deploy.sh` : synchronisation et démarrage sélectif des stacks ;
- `scripts/configure-backup.sh` : montage CIFS, Restic et timer quotidien ;
- `scripts/restore-data.sh` : restauration protégée de `/srv/docker` ;
- `scripts/verify.sh` : syntaxe shell, Compose et recherche de secrets ;
- `inventory/` : versions, paquets et révisions applicatives auditées.

## Utilisation courante

```bash
# Lister les stacks
./scripts/deploy.sh list

# Copier les configurations sans démarrer les conteneurs
./scripts/deploy.sh sync --all

# Déployer seulement quelques services
./scripts/deploy.sh up nginx-proxy-manager pihole uptime-kuma

# Voir l'état de toutes les stacks actives
./scripts/deploy.sh status --all

# Vérifier le dépôt avant chaque commit
./scripts/verify.sh
```

## Règle de sécurité

Le dépôt GitHub doit rester privé, mais cela ne rend pas acceptable le stockage
des secrets en clair. Les fichiers `.env`, `secrets.json`, clés privées,
certificats privés et données applicatives sont ignorés. Les modèles
`.env.example` documentent uniquement les variables attendues.

Voir [docs/secrets.md](docs/secrets.md) et
[docs/architecture.md](docs/architecture.md).
