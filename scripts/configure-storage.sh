#!/usr/bin/env bash

set -Eeuo pipefail

ORIGINAL_ARGS=("$@")

DEVICE="${STORAGE_DEVICE:-}"
MOUNT_POINT="${STORAGE_MOUNT_POINT:-}"
OWNER="${STORAGE_OWNER:-${HOMELAB_USER:-${SUDO_USER:-eldayia}}}"
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/configure-storage.sh [options]

Monte de façon persistante une partition déjà formatée. Ce script ne crée pas
de partition et ne formate jamais de disque.

Options:
  --device DEVICE       Partition à monter, par exemple /dev/sda1.
  --mount-point PATH    Point de montage. Sans cette option, l'assistant propose
                        /srv (tout le homelab) ou /srv/media (médias seuls).
  --owner USER          Propriétaire du stockage (défaut: HOMELAB_USER,
                        SUDO_USER ou eldayia).
  --yes                 Accepte le récapitulatif sans question interactive.
  -h, --help            Affiche cette aide.

Variables équivalentes:
  STORAGE_DEVICE, STORAGE_MOUNT_POINT, STORAGE_OWNER
EOF
}

while (($#)); do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || { echo "Valeur manquante pour --device." >&2; exit 2; }
      DEVICE="$2"
      shift
      ;;
    --mount-point)
      [[ $# -ge 2 ]] || { echo "Valeur manquante pour --mount-point." >&2; exit 2; }
      MOUNT_POINT="$2"
      shift
      ;;
    --owner)
      [[ $# -ge 2 ]] || { echo "Valeur manquante pour --owner." >&2; exit 2; }
      OWNER="$2"
      shift
      ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ((EUID != 0)); then
  exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"
fi

for command in lsblk blkid findmnt mount readlink realpath; do
  command -v "$command" >/dev/null || {
    echo "Commande requise absente: $command" >&2
    exit 1
  }
done

id "$OWNER" >/dev/null 2>&1 || {
  echo "Utilisateur introuvable: $OWNER" >&2
  exit 1
}

echo "Partitions détectées:"
lsblk --paths --output NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL,TRAN
printf '\n'

if [[ -z "$DEVICE" ]]; then
  [[ -t 0 ]] || {
    echo "Utilise --device dans un contexte non interactif." >&2
    exit 2
  }
  read -r -p "Partition du SSD à monter (exemple /dev/sda1): " DEVICE
fi

if [[ -z "$MOUNT_POINT" ]]; then
  [[ -t 0 ]] || {
    echo "Utilise --mount-point dans un contexte non interactif." >&2
    exit 2
  }
  cat <<'EOF'
Disposition du stockage:
  1) /srv       Tous les volumes applicatifs et les médias sur le SSD (recommandé)
  2) /srv/media Médias uniquement; les autres données Docker restent sur la carte SD
  3) autre      Saisir un point de montage personnalisé sous /srv ou /mnt
EOF
  read -r -p "Choix [1]: " layout_choice
  case "${layout_choice:-1}" in
    1) MOUNT_POINT=/srv ;;
    2) MOUNT_POINT=/srv/media ;;
    3) read -r -p "Point de montage absolu: " MOUNT_POINT ;;
    *) echo "Choix invalide." >&2; exit 2 ;;
  esac
fi

[[ "$DEVICE" == /dev/* ]] || {
  echo "Le périphérique doit être un chemin sous /dev." >&2
  exit 1
}

DEVICE="$(readlink -f -- "$DEVICE")"
[[ -b "$DEVICE" ]] || {
  echo "Ce chemin n'est pas un périphérique bloc: $DEVICE" >&2
  exit 1
}

DEVICE_TYPE="$(lsblk --nodeps --noheadings --output TYPE "$DEVICE" | xargs)"
[[ "$DEVICE_TYPE" == "part" ]] || {
  echo "$DEVICE n'est pas une partition." >&2
  echo "Le script refuse de monter un disque entier ou de le partitionner automatiquement." >&2
  exit 1
}

DEVICE_MAJMIN="$(lsblk --nodeps --noheadings --output MAJ:MIN "$DEVICE" | xargs)"
ROOT_MAJMIN="$(findmnt --noheadings --raw --output MAJ:MIN / 2>/dev/null || true)"
BOOT_MAJMIN="$(findmnt --noheadings --raw --output MAJ:MIN /boot 2>/dev/null || true)"
BOOT_FIRMWARE_MAJMIN="$(findmnt --noheadings --raw --output MAJ:MIN /boot/firmware 2>/dev/null || true)"

if [[ "$DEVICE_MAJMIN" == "$ROOT_MAJMIN" ]]; then
  echo "Refus de modifier la partition racine: $DEVICE" >&2
  exit 1
fi

if [[ -n "$BOOT_MAJMIN" && "$DEVICE_MAJMIN" == "$BOOT_MAJMIN" ]] ||
   [[ -n "$BOOT_FIRMWARE_MAJMIN" && "$DEVICE_MAJMIN" == "$BOOT_FIRMWARE_MAJMIN" ]]; then
  echo "Refus de modifier une partition de démarrage: $DEVICE" >&2
  exit 1
fi

FSTYPE="$(blkid -s TYPE -o value "$DEVICE" || true)"
UUID="$(blkid -s UUID -o value "$DEVICE" || true)"
LABEL="$(blkid -s LABEL -o value "$DEVICE" || true)"
SIZE="$(lsblk --nodeps --noheadings --output SIZE "$DEVICE" | xargs)"
TRANSPORT="$(lsblk --inverse --noheadings --output TRAN "$DEVICE" | sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q}')"

if [[ -z "$FSTYPE" || -z "$UUID" ]]; then
  cat >&2 <<EOF
La partition $DEVICE ne possède pas de système de fichiers ou d'UUID lisible.
Aucune écriture n'a été effectuée. Pour un SSD neuf, crée d'abord une table de
partitions et un système de fichiers (ext4 recommandé), après avoir vérifié
avec certitude le nom du disque.
EOF
  exit 1
fi

case "$FSTYPE" in
  ext2|ext3|ext4)
    FSTAB_TYPE="$FSTYPE"
    MOUNT_OPTIONS="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10s"
    FSCK_PASS=2
    POSIX_PERMISSIONS=1
    ;;
  xfs|btrfs)
    FSTAB_TYPE="$FSTYPE"
    MOUNT_OPTIONS="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10s"
    FSCK_PASS=0
    POSIX_PERMISSIONS=1
    ;;
  ntfs)
    command -v mount.ntfs-3g >/dev/null || {
      echo "Le paquet ntfs-3g est requis pour monter cette partition NTFS." >&2
      exit 1
    }
    OWNER_UID="$(id -u "$OWNER")"
    OWNER_GID="$(id -g "$OWNER")"
    FSTAB_TYPE="ntfs-3g"
    MOUNT_OPTIONS="defaults,nofail,x-systemd.automount,x-systemd.device-timeout=10s,uid=$OWNER_UID,gid=$OWNER_GID,umask=002"
    FSCK_PASS=0
    POSIX_PERMISSIONS=0
    ;;
  *)
    echo "Système de fichiers non pris en charge par l'assistant: $FSTYPE" >&2
    echo "Formats acceptés: ext2/3/4, xfs, btrfs et ntfs." >&2
    exit 1
    ;;
esac

[[ "$MOUNT_POINT" == /* ]] || {
  echo "Le point de montage doit être un chemin absolu." >&2
  exit 1
}
MOUNT_POINT="$(realpath -m -- "$MOUNT_POINT")"
[[ "$MOUNT_POINT" != *[[:space:]]* ]] || {
  echo "Les espaces ne sont pas acceptés dans le point de montage." >&2
  exit 1
}
case "$MOUNT_POINT" in
  /srv|/srv/*|/mnt/*) ;;
  *)
    echo "Par sécurité, le point de montage doit être situé sous /srv ou /mnt." >&2
    exit 1
    ;;
esac

CURRENT_MOUNT="$(findmnt --noheadings --output TARGET --source "$DEVICE" 2>/dev/null | head -n1 || true)"
if [[ -n "$CURRENT_MOUNT" && "$CURRENT_MOUNT" != "$MOUNT_POINT" ]]; then
  echo "$DEVICE est déjà monté sur $CURRENT_MOUNT." >&2
  echo "Démonte-le explicitement avant de changer son point de montage." >&2
  exit 1
fi

if [[ -d "$MOUNT_POINT" && -z "$CURRENT_MOUNT" &&
      -n "$(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Le dossier $MOUNT_POINT n'est pas vide; le montage masquerait son contenu." >&2
  exit 1
fi

FSTAB_LINE="UUID=$UUID $MOUNT_POINT $FSTAB_TYPE $MOUNT_OPTIONS 0 $FSCK_PASS"

if awk -v source="UUID=$UUID" '$1 !~ /^#/ && $1 == source {found=1} END {exit !found}' /etc/fstab; then
  EXISTING_LINE="$(awk -v source="UUID=$UUID" '$1 !~ /^#/ && $1 == source {print; exit}' /etc/fstab)"
  [[ "$EXISTING_LINE" == "$FSTAB_LINE" ]] || {
    echo "Une entrée /etc/fstab différente existe déjà pour UUID=$UUID:" >&2
    echo "$EXISTING_LINE" >&2
    echo "Aucune modification automatique n'est effectuée." >&2
    exit 1
  }
  FSTAB_ACTION="conserver l'entrée /etc/fstab existante"
elif awk -v target="$MOUNT_POINT" '$1 !~ /^#/ && $2 == target {found=1} END {exit !found}' /etc/fstab; then
  echo "Une autre source utilise déjà $MOUNT_POINT dans /etc/fstab." >&2
  echo "Aucune modification automatique n'est effectuée." >&2
  exit 1
else
  FSTAB_ACTION="ajouter une entrée persistante à /etc/fstab"
fi

cat <<EOF
Configuration proposée:
  partition       : $DEVICE
  transport       : ${TRANSPORT:-inconnu}
  taille          : $SIZE
  label           : ${LABEL:-aucun}
  système         : $FSTYPE
  UUID            : $UUID
  point de montage: $MOUNT_POINT
  propriétaire    : $OWNER
  action fstab    : $FSTAB_ACTION

Aucun formatage et aucun partitionnement ne seront effectués.
EOF

if [[ -n "$TRANSPORT" && "$TRANSPORT" != "usb" ]]; then
  echo "ATTENTION: le transport détecté est '$TRANSPORT', pas 'usb'." >&2
elif [[ -z "$TRANSPORT" ]]; then
  echo "ATTENTION: le transport USB n'a pas pu être confirmé automatiquement." >&2
fi

if ((ASSUME_YES == 0)); then
  [[ -t 0 ]] || {
    echo "Utilise --yes après avoir vérifié le récapitulatif." >&2
    exit 2
  }
  read -r -p "Appliquer cette configuration ? [y/N] " answer
  [[ "$answer" =~ ^[yYoO]$ ]] || {
    echo "Configuration annulée."
    exit 0
  }
fi

install -d -m 0755 "$MOUNT_POINT"
FSTAB_CHANGED=0

if [[ "$FSTAB_ACTION" == ajouter* ]]; then
  FSTAB_BACKUP="/etc/fstab.homelab-$(date +%Y%m%d-%H%M%S).bak"
  cp --preserve=mode,ownership,timestamps /etc/fstab "$FSTAB_BACKUP"
  printf '\n# Homelab USB storage (%s)\n%s\n' "$DEVICE" "$FSTAB_LINE" >>/etc/fstab
  FSTAB_CHANGED=1

  if ! findmnt --verify --verbose >/dev/null; then
    cp "$FSTAB_BACKUP" /etc/fstab
    echo "Validation de /etc/fstab échouée; la sauvegarde a été restaurée." >&2
    exit 1
  fi
  echo "Sauvegarde de /etc/fstab: $FSTAB_BACKUP"
fi

if [[ -z "$CURRENT_MOUNT" ]]; then
  if ! mount "$MOUNT_POINT"; then
    if ((FSTAB_CHANGED)); then
      cp "$FSTAB_BACKUP" /etc/fstab
      echo "Échec du montage; la sauvegarde de /etc/fstab a été restaurée." >&2
    else
      echo "Échec du montage avec l'entrée /etc/fstab existante." >&2
    fi
    exit 1
  fi
fi

if ((POSIX_PERMISSIONS)); then
  chown "$OWNER:$(id -gn "$OWNER")" "$MOUNT_POINT"
  chmod 0775 "$MOUNT_POINT"
fi

if [[ "$MOUNT_POINT" == "/srv" ]]; then
  if ((POSIX_PERMISSIONS)); then
    install -d -o "$OWNER" -g "$(id -gn "$OWNER")" -m 0775 \
      /srv/docker /srv/media
  else
    install -d -m 0775 /srv/docker /srv/media
  fi
fi

findmnt --target "$MOUNT_POINT" --output SOURCE,TARGET,FSTYPE,OPTIONS

if sudo -u "$OWNER" test -w "$MOUNT_POINT"; then
  echo "Montage terminé: $OWNER peut écrire dans $MOUNT_POINT."
else
  echo "Le SSD est monté, mais $OWNER ne peut pas écrire dans $MOUNT_POINT." >&2
  exit 1
fi
