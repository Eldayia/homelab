# État observé de `rpi4` · 18 août 2026

Cet inventaire est un instantané de contrôle. Le manifeste et les fichiers
Compose restent la source de vérité exécutable.

| Élément | État observé |
|---|---|
| système | Debian GNU/Linux 13 (Trixie), `aarch64` |
| utilisateur | `eldayia` |
| dépôt | `/home/eldayia/homelab`, révision `c88e48d` |
| Docker Compose | `v5.5.0` |
| stockage applicatif | SSD ext4 monté sur `/srv` |
| données Compose | `/srv/docker/<catégorie>/<service>` |
| sauvegarde | NFSv4.1 sur `/mnt/qnap-backups`, timer actif |
| médias | NFSv4.1 sur `/mnt/nas/downloads` et `/mnt/nas/multimedia` |
| Compose | 25 projets déployés, dont 24 lancés |
| conteneurs | 26 actifs ; tinyMediaManager était synchronisé mais non lancé |

## Écarts corrigés dans le dépôt

L’audit SSH a trouvé deux projets actifs mais absents du Git local :

- `monitoring/glances` ;
- `download/qui`.

Leurs définitions non secrètes ont été intégrées aux stacks et au manifeste.
Le réseau Docker externe `download`, utilisé par Qui, est désormais préparé
par l’installation et le déploiement.

## Arborescence validée

```text
/srv/
├── docker/
│   ├── backup/
│   ├── infrastructure/
│   ├── monitoring/
│   ├── download/
│   └── media/
└── media/downloads/
    ├── jdownloader/
    ├── slskd/
    ├── torrents/
    └── usenet/
```

Les anciennes mentions CIFS, les services historiques hors manifeste et les
versions devenues obsolètes ont été retirés de cet audit.
