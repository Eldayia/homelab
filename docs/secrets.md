# Secrets

## Principes

- aucun secret en clair dans Git, même si le dépôt est privé ;
- un fichier `.env` par stack, mode `600` ;
- mot de passe Restic et URL Push Kuma sous `/root/.config` ;
- sauvegarde des secrets par Restic avec le reste de `/srv/docker` ;
- copie secondaire du mot de passe Restic dans un gestionnaire de mots de passe.

Le fichier `.gitignore` bloque les noms les plus courants et
`scripts/check-secrets.sh` recherche plusieurs formats de jetons connus.

## Génération

```bash
# Mot de passe long
openssl rand -base64 36

# Secret hexadécimal de 64 caractères
openssl rand -hex 32

```

## Variables attendues

| Stack | Variables sensibles |
|---|---|
| Beszel | `BESZEL_TOKEN`, `BESZEL_KEY` fournis par le hub |
| Homarr | `SECRET_ENCRYPTION_KEY` |
| Pi-hole | `PIHOLE_PASSWORD` |

Les futures variables sensibles de la media stack seront documentées lors de
l’intégration de son Compose.

## Fichiers root hors dépôt

| Fichier | Usage | Mode |
|---|---|---:|
| `/root/.config/restic/rpi-password` | déchiffrement Restic | `600` |
| `/root/.config/restic/kuma-push-url` | notification Push Kuma | `600` |

Ne partage jamais la sortie de `docker compose config` : Compose y remplace les
variables et peut afficher les secrets en clair.
