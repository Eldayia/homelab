# Inventaire audité les 7 et 8 août 2026

- Hôte : `rpi4`, `192.168.1.240/24`, arm64 ;
- OS : Debian GNU/Linux 13.6 (Trixie) ;
- noyau : `6.18.39+rpt-rpi-v8` ;
- Docker Engine : `29.7.1` ;
- Docker Compose : `5.4.0` ;
- Python : `3.13.5` ;
- Node.js : `20.19.2`, npm `9.2.0` ;
- Git : `2.47.3` ;
- Neovim : `0.10.4` ;
- Restic : `0.18.0` ;
- shell utilisateur : Zsh `5.9` ;
- 27 conteneurs actifs dans 26 projets Compose ;
- timer Restic actif, dernier lancement observé avec succès le 7 août 2026 à
  04:32:55 ;
- pare-feu `rpi-firewall.service` actif et activé au démarrage ;
- partage CIFS : `//192.168.1.250/RaspberryBackups` monté sur
  `/mnt/qnap-backups` avec SMB 3.1.1 et chiffrement (`seal`).

Les révisions exactes des applications clonées figurent dans
`inventory/stacks.manifest`.

Le 8 août, l'audit a été actualisé après le durcissement de Kinklist, le passage
de wg-easy en réseau hôte, le raccordement de Pi-hole au réseau `proxy`,
l'activation de `CONTAINER_PRESERVE_CONFIG` pour Foundry et l'installation de
miniPaint `4.14.3` en build ARM64 local.
