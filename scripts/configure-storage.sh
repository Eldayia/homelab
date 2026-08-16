#!/usr/bin/env bash

set -Eeuo pipefail

ORIGINAL_ARGS=("$@")

DEVICE="${STORAGE_DEVICE:-}"
MOUNT_POINT="${STORAGE_MOUNT_POINT:-}"
OWNER="${STORAGE_OWNER:-${HOMELAB_USER:-${SUDO_USER:-eldayia}}}"
ASSUME_YES=0
FORMAT_DISK=0
FORMAT_PERFORMED=0

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/configure-storage.sh [options]

Monte de façon persistante une partition existante ou prépare explicitement un
disque USB entier avec une table GPT et une partition ext4.

Options:
  --device DEVICE       Partition à monter, par exemple /dev/sda1. Avec
                        --format, disque entier à effacer, par exemple /dev/sda.
  --format              EFFACE le disque sélectionné, crée une table GPT, une
                        partition ext4 unique, puis la monte.
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
    --format) FORMAT_DISK=1 ;;
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
  if ((FORMAT_DISK == 0)); then
    cat <<'EOF'
Action souhaitée:
  1) Monter une partition existante sans effacer de données
  2) EFFACER et préparer un disque USB entier en ext4
EOF
    read -r -p "Choix [1]: " storage_action
    case "${storage_action:-1}" in
      1) ;;
      2) FORMAT_DISK=1 ;;
      *) echo "Choix invalide." >&2; exit 2 ;;
    esac
  fi
  if ((FORMAT_DISK)); then
    read -r -p "Disque USB entier à EFFACER (exemple /dev/sda): " DEVICE
  else
    read -r -p "Partition du SSD à monter (exemple /dev/sda1): " DEVICE
  fi
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
ROOT_MAJMIN="$(findmnt --noheadings --raw --output MAJ:MIN / 2>/dev/null || true)"
BOOT_MAJMIN="$(findmnt --noheadings --raw --output MAJ:MIN /boot 2>/dev/null || true)"
BOOT_FIRMWARE_MAJMIN="$(findmnt --noheadings --raw --output MAJ:MIN /boot/firmware 2>/dev/null || true)"

if ((FORMAT_DISK)); then
  [[ "$DEVICE_TYPE" == "disk" ]] || {
    echo "Avec --format, sélectionne le disque entier (exemple /dev/sda), pas une partition." >&2
    exit 1
  }

  for command in wipefs parted partprobe udevadm mkfs.ext4; do
    command -v "$command" >/dev/null || {
      echo "Commande requise pour le formatage absente: $command" >&2
      exit 1
    }
  done

  DISK_TRANSPORT="$(lsblk --nodeps --noheadings --output TRAN "$DEVICE" | xargs)"
  [[ "$DISK_TRANSPORT" == "usb" ]] || {
    echo "Refus de formater: $DEVICE n'est pas identifié comme un disque USB." >&2
    exit 1
  }

  while IFS= read -r descendant_majmin; do
    [[ -n "$descendant_majmin" ]] || continue
    if [[ "$descendant_majmin" == "$ROOT_MAJMIN" ||
          ( -n "$BOOT_MAJMIN" && "$descendant_majmin" == "$BOOT_MAJMIN" ) ||
          ( -n "$BOOT_FIRMWARE_MAJMIN" && "$descendant_majmin" == "$BOOT_FIRMWARE_MAJMIN" ) ]]; then
      echo "Refus absolu de formater le disque système: $DEVICE" >&2
      exit 1
    fi
  done < <(lsblk --noheadings --output MAJ:MIN "$DEVICE" | xargs -n1)

  MOUNTED_DESCENDANTS="$(lsblk --noheadings --raw --output MOUNTPOINTS "$DEVICE" | sed '/^[[:space:]]*$/d' || true)"
  [[ -z "$MOUNTED_DESCENDANTS" ]] || {
    echo "Refus de formater: une partition de $DEVICE est montée:" >&2
    echo "$MOUNTED_DESCENDANTS" >&2
    exit 1
  }

  while IFS= read -r old_uuid; do
    [[ -n "$old_uuid" ]] || continue
    if awk -v source="UUID=$old_uuid" '$1 !~ /^#/ && $1 == source {found=1} END {exit !found}' /etc/fstab; then
      echo "Refus de formater: UUID=$old_uuid est encore référencé dans /etc/fstab." >&2
      echo "Supprime ou commente d'abord explicitement cette ancienne entrée." >&2
      exit 1
    fi
  done < <(lsblk --noheadings --raw --output UUID "$DEVICE")

  if [[ -d "$MOUNT_POINT" &&
        -n "$(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Le dossier $MOUNT_POINT n'est pas vide; le montage masquerait son contenu." >&2
    exit 1
  fi
  if awk -v target="$MOUNT_POINT" '$1 !~ /^#/ && $2 == target {found=1} END {exit !found}' /etc/fstab; then
    echo "Une entrée /etc/fstab utilise déjà $MOUNT_POINT." >&2
    echo "Aucune suppression automatique n'est effectuée avant un formatage." >&2
    exit 1
  fi

  DISK_SIZE="$(lsblk --nodeps --noheadings --output SIZE "$DEVICE" | xargs)"
  DISK_MODEL="$(lsblk --nodeps --noheadings --output MODEL "$DEVICE" | xargs)"
  DISK_SERIAL="$(lsblk --nodeps --noheadings --output SERIAL "$DEVICE" | xargs)"

  cat <<EOF
╔══════════════════════════════════════════════════════════════════════╗
║ ATTENTION: FORMATAGE IRRÉVERSIBLE DU DISQUE                         ║
╚══════════════════════════════════════════════════════════════════════╝
  disque          : $DEVICE
  taille          : $DISK_SIZE
  modèle          : ${DISK_MODEL:-inconnu}
  numéro de série : ${DISK_SERIAL:-inconnu}
  transport       : $DISK_TRANSPORT
  destination     : $MOUNT_POINT
  résultat        : GPT + une partition ext4 utilisant tout le disque

Toutes les partitions et toutes les données de $DEVICE seront perdues.
EOF

  [[ -t 0 ]] || {
    echo "Le formatage exige une confirmation interactive." >&2
    exit 2
  }
  read -r -p "Pour confirmer, tape exactement: ERASE $DEVICE : " erase_confirmation
  [[ "$erase_confirmation" == "ERASE $DEVICE" ]] || {
    echo "Confirmation incorrecte; aucune donnée n'a été modifiée." >&2
    exit 2
  }

  echo "Effacement des signatures de $DEVICE..."
  wipefs --all "$DEVICE"
  parted --script --align optimal "$DEVICE" \
    mklabel gpt \
    mkpart homelab ext4 1MiB 100%
  partprobe "$DEVICE"
  udevadm settle

  NEW_PARTITION=""
  for _attempt in {1..10}; do
    NEW_PARTITION="$(lsblk --noheadings --raw --paths --output NAME,TYPE "$DEVICE" | awk '$2 == "part" {print $1; exit}')"
    [[ -n "$NEW_PARTITION" ]] && break
    partprobe "$DEVICE"
    udevadm settle
    sleep 1
  done
  [[ -n "$NEW_PARTITION" && -b "$NEW_PARTITION" ]] || {
    echo "La nouvelle partition n'est pas apparue après le partitionnement." >&2
    exit 1
  }

  echo "Création du système de fichiers ext4 sur $NEW_PARTITION..."
  mkfs.ext4 -F -L homelab "$NEW_PARTITION"
  udevadm settle
  DEVICE="$NEW_PARTITION"
  DEVICE_TYPE=part
  FORMAT_PERFORMED=1
else
  [[ "$DEVICE_TYPE" == "part" ]] || {
    echo "$DEVICE n'est pas une partition." >&2
    echo "Utilise --format pour préparer explicitement un disque USB entier." >&2
    exit 1
  }
fi

DEVICE_MAJMIN="$(lsblk --nodeps --noheadings --output MAJ:MIN "$DEVICE" | xargs)"

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

if ((FORMAT_PERFORMED)); then
  FORMAT_STATUS="Le disque vient d'être formaté en une partition ext4."
else
  FORMAT_STATUS="Aucun formatage et aucun partitionnement ne seront effectués."
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

$FORMAT_STATUS
EOF

if [[ -n "$TRANSPORT" && "$TRANSPORT" != "usb" ]]; then
  echo "ATTENTION: le transport détecté est '$TRANSPORT', pas 'usb'." >&2
elif [[ -z "$TRANSPORT" ]]; then
  echo "ATTENTION: le transport USB n'a pas pu être confirmé automatiquement." >&2
fi

if ((ASSUME_YES == 0 && FORMAT_PERFORMED == 0)); then
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
      /srv/docker /srv/media /srv/media/downloads
    install -d -o root -g root -m 0700 \
      /srv/docker/backup /srv/docker/backup/dumps
  else
    install -d -m 0775 /srv/docker /srv/media /srv/media/downloads
    install -d -m 0700 /srv/docker/backup /srv/docker/backup/dumps
  fi
fi

findmnt --target "$MOUNT_POINT" --output SOURCE,TARGET,FSTYPE,OPTIONS

if sudo -u "$OWNER" test -w "$MOUNT_POINT"; then
  echo "Montage terminé: $OWNER peut écrire dans $MOUNT_POINT."
else
  echo "Le SSD est monté, mais $OWNER ne peut pas écrire dans $MOUNT_POINT." >&2
  exit 1
fi
