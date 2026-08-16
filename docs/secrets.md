# Secrets

## Principes

- aucun secret en clair dans Git, même si le dépôt est privé ;
- un fichier `.env` par stack, mode `600` ;
- mots de passe Restic, CIFS et URL Push Kuma sous `/root/.config` ou `/root` ;
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

# APP_KEY BookStack
printf 'base64:'
openssl rand -base64 32 | tr -d '\n'
printf '\n'
```

## Variables attendues

| Stack | Variables sensibles |
|---|---|
| Beszel | `BESZEL_TOKEN`, `BESZEL_KEY` fournis par le hub |
| BookStack | `APP_KEY`, `DB_PASSWORD`, `DB_ROOT_PASSWORD` |
| ConvertX | `JWT_SECRET` |
| Forgejo | `POSTGRES_PASSWORD` |
| Foundry VTT | `FOUNDRY_RELEASE_URL`, `secrets.json` |
| HedgeDoc | `POSTGRES_PASSWORD` utilisé aussi comme secret de session |
| Homarr | `SECRET_ENCRYPTION_KEY` |
| Kinklist | `DATA_ENCRYPTION_KEY`, `STATS_TOKEN` |
| NfoForge | `RATE_LIMIT_SALT`, `ADMIN_TOKEN`, clés API facultatives |
| Pi-hole | `PIHOLE_PASSWORD` |
| PrezForge | identifiants IGDB facultatifs |
| PsiTransfer | mots de passe administrateur et upload |
| Stirling PDF | identifiant et mot de passe initial |

Vaultwarden ne possède pas de secret dans le Compose actuel : ses comptes et
clés sont dans `stacks/vaultwarden/data`, restauré par Restic.

## Fichiers root hors dépôt

| Fichier | Usage | Mode |
|---|---|---:|
| `/root/.smb-qnap-backup` | identifiants CIFS QNAP | `600` |
| `/root/.config/restic/rpi-password` | déchiffrement Restic | `600` |
| `/root/.config/restic/kuma-push-url` | notification Push Kuma | `600` |

Ne partage jamais la sortie de `docker compose config` : Compose y remplace les
variables et peut afficher les secrets en clair.
