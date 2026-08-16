#!/usr/bin/env bash

set -Eeuo pipefail

ORIGINAL_ARGS=("$@")

QNAP_HOST="${QNAP_HOST:-192.168.1.250}"
NFS_VERSION="${NFS_VERSION:-4.1}"
DOWNLOAD_EXPORT="${DOWNLOAD_EXPORT:-/Download}"
MULTIMEDIA_EXPORT="${MULTIMEDIA_EXPORT:-/Multimedia}"
DOWNLOAD_MOUNT="${DOWNLOAD_MOUNT:-/mnt/nas/downloads}"
MULTIMEDIA_MOUNT="${MULTIMEDIA_MOUNT:-/mnt/nas/multimedia}"
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/configure-media-storage.sh [options]

Monte durablement les partages QNAP Download et Multimedia en NFSv4.1.
La media-stack n'est ni installée ni démarrée par ce script.

Options:
  --yes       Applique la configuration après les contrôles, sans confirmation.
  -h, --help  Affiche cette aide.

Variables:
  QNAP_HOST         192.168.1.250
  NFS_VERSION       4.1
  DOWNLOAD_EXPORT   /Download
  MULTIMEDIA_EXPORT /Multimedia
  DOWNLOAD_MOUNT    /mnt/nas/downloads
  MULTIMEDIA_MOUNT  /mnt/nas/multimedia
EOF
}

while (($#)); do
  case "$1" in
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ((EUID != 0)); then
  exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"
fi

for command in mount.nfs mount umount mountpoint findmnt realpath awk mktemp; do
  command -v "$command" >/dev/null || {
    echo "Commande requise absente: $command" >&2
    echo "Installe le paquet nfs-common puis relance le script." >&2
    exit 1
  }
done

case "$NFS_VERSION" in
  4|4.0|4.1|4.2) ;;
  *) echo "Version NFS non prise en charge: $NFS_VERSION" >&2; exit 1 ;;
esac

[[ "$QNAP_HOST" != *[[:space:]]* ]] || {
  echo "QNAP_HOST contient des espaces." >&2
  exit 1
}

for export_path in "$DOWNLOAD_EXPORT" "$MULTIMEDIA_EXPORT"; do
  [[ "$export_path" == /* && "$export_path" != *[[:space:]]* ]] || {
    echo "Chemin d'export NFS invalide: $export_path" >&2
    exit 1
  }
done

DOWNLOAD_MOUNT="$(realpath -m -- "$DOWNLOAD_MOUNT")"
MULTIMEDIA_MOUNT="$(realpath -m -- "$MULTIMEDIA_MOUNT")"
for mount_path in "$DOWNLOAD_MOUNT" "$MULTIMEDIA_MOUNT"; do
  case "$mount_path" in
    /mnt/*) ;;
    *) echo "Le point de montage doit être situé sous /mnt: $mount_path" >&2; exit 1 ;;
  esac
  [[ "$mount_path" != *[[:space:]]* ]] || {
    echo "Les espaces ne sont pas acceptés dans un point de montage." >&2
    exit 1
  }
done

[[ "$DOWNLOAD_MOUNT" != "$MULTIMEDIA_MOUNT" ]] || {
  echo "Les deux exports ne peuvent pas utiliser le même point de montage." >&2
  exit 1
}

DOWNLOAD_SOURCE="${QNAP_HOST}:${DOWNLOAD_EXPORT}"
MULTIMEDIA_SOURCE="${QNAP_HOST}:${MULTIMEDIA_EXPORT}"
NFS_OPTIONS="rw,vers=${NFS_VERSION},proto=tcp,resvport,nofail,_netdev,x-systemd.automount,x-systemd.device-timeout=15s,x-systemd.mount-timeout=30s"
DOWNLOAD_LINE="$DOWNLOAD_SOURCE $DOWNLOAD_MOUNT nfs $NFS_OPTIONS 0 0"
MULTIMEDIA_LINE="$MULTIMEDIA_SOURCE $MULTIMEDIA_MOUNT nfs $NFS_OPTIONS 0 0"

cat <<EOF
Configuration proposée:
  téléchargements : $DOWNLOAD_SOURCE -> $DOWNLOAD_MOUNT
  médiathèque      : $MULTIMEDIA_SOURCE -> $MULTIMEDIA_MOUNT
  protocole        : NFSv$NFS_VERSION sur TCP

Dans QTS, les deux exports doivent autoriser l'IP du Raspberry Pi en écriture
et écraser tous les utilisateurs vers l'identité media-docker.
EOF

if ((ASSUME_YES == 0)); then
  [[ -t 0 ]] || {
    echo "Utilise --yes dans un contexte non interactif." >&2
    exit 2
  }
  read -r -p "Tester les exports puis modifier /etc/fstab ? [y/N] " confirmation
  [[ "$confirmation" =~ ^[yY]$ ]] || exit 0
fi

install -d -m 0755 "$DOWNLOAD_MOUNT" "$MULTIMEDIA_MOUNT"

for mount_path in "$DOWNLOAD_MOUNT" "$MULTIMEDIA_MOUNT"; do
  if ! mountpoint -q "$mount_path" &&
     [[ -n "$(find "$mount_path" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Refus de masquer un dossier non vide: $mount_path" >&2
    exit 1
  fi
done

TEST_ROOT="$(mktemp -d)"
DOWNLOAD_TEST="$TEST_ROOT/downloads"
MULTIMEDIA_TEST="$TEST_ROOT/multimedia"
install -d -m 0700 "$DOWNLOAD_TEST" "$MULTIMEDIA_TEST"

cleanup() {
  mountpoint -q "$DOWNLOAD_TEST" 2>/dev/null && umount "$DOWNLOAD_TEST" || true
  mountpoint -q "$MULTIMEDIA_TEST" 2>/dev/null && umount "$MULTIMEDIA_TEST" || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

test_export() {
  local source="$1"
  local target="$2"
  local write_test="$target/.homelab-nfs-write-test"

  echo "Test de $source..."
  mount -t nfs -o "rw,vers=$NFS_VERSION,proto=tcp,resvport" "$source" "$target"
  if ! touch "$write_test"; then
    echo "Le partage $source est monté mais media-docker ne peut pas y écrire." >&2
    echo "Vérifie le squash, l'UID/GID anonyme et les droits du dossier dans QTS." >&2
    exit 1
  fi
  rm -f "$write_test"
  umount "$target"
}

test_export "$DOWNLOAD_SOURCE" "$DOWNLOAD_TEST"
test_export "$MULTIMEDIA_SOURCE" "$MULTIMEDIA_TEST"

DOWNLOAD_WAS_MOUNTED=0
MULTIMEDIA_WAS_MOUNTED=0
mountpoint -q "$DOWNLOAD_MOUNT" && DOWNLOAD_WAS_MOUNTED=1
mountpoint -q "$MULTIMEDIA_MOUNT" && MULTIMEDIA_WAS_MOUNTED=1

if ((DOWNLOAD_WAS_MOUNTED)); then
  umount "$DOWNLOAD_MOUNT" || {
    echo "Impossible de démonter $DOWNLOAD_MOUNT; un processus l'utilise." >&2
    exit 1
  }
fi
if ((MULTIMEDIA_WAS_MOUNTED)); then
  umount "$MULTIMEDIA_MOUNT" || {
    ((DOWNLOAD_WAS_MOUNTED)) && mount "$DOWNLOAD_MOUNT" 2>/dev/null || true
    echo "Impossible de démonter $MULTIMEDIA_MOUNT; un processus l'utilise." >&2
    exit 1
  }
fi

FSTAB_BACKUP="/etc/fstab.backup.$(date +%Y%m%d-%H%M%S)"
FSTAB_TEMP="$(mktemp)"
cp /etc/fstab "$FSTAB_BACKUP"
awk -v download="$DOWNLOAD_MOUNT" -v multimedia="$MULTIMEDIA_MOUNT" \
  '$1 ~ /^#/ || ($2 != download && $2 != multimedia)' /etc/fstab >"$FSTAB_TEMP"
printf '\n%s\n%s\n' "$DOWNLOAD_LINE" "$MULTIMEDIA_LINE" >>"$FSTAB_TEMP"

if ! findmnt --verify --tab-file "$FSTAB_TEMP" >/dev/null; then
  rm -f "$FSTAB_TEMP"
  ((DOWNLOAD_WAS_MOUNTED)) && mount "$DOWNLOAD_MOUNT" 2>/dev/null || true
  ((MULTIMEDIA_WAS_MOUNTED)) && mount "$MULTIMEDIA_MOUNT" 2>/dev/null || true
  echo "La configuration générée est invalide; /etc/fstab reste inchangé." >&2
  exit 1
fi

install -m 0644 "$FSTAB_TEMP" /etc/fstab
rm -f "$FSTAB_TEMP"
systemctl daemon-reload

rollback() {
  umount "$DOWNLOAD_MOUNT" 2>/dev/null || true
  umount "$MULTIMEDIA_MOUNT" 2>/dev/null || true
  cp "$FSTAB_BACKUP" /etc/fstab
  systemctl daemon-reload
  ((DOWNLOAD_WAS_MOUNTED)) && mount "$DOWNLOAD_MOUNT" 2>/dev/null || true
  ((MULTIMEDIA_WAS_MOUNTED)) && mount "$MULTIMEDIA_MOUNT" 2>/dev/null || true
  echo "Échec du montage; l'ancien /etc/fstab a été restauré." >&2
}

if ! mount "$DOWNLOAD_MOUNT" || ! mount "$MULTIMEDIA_MOUNT"; then
  rollback
  exit 1
fi

for mount_path in "$DOWNLOAD_MOUNT" "$MULTIMEDIA_MOUNT"; do
  fstype="$(findmnt --noheadings --output FSTYPE --target "$mount_path" | xargs)"
  if [[ "$fstype" != nfs && "$fstype" != nfs4 ]]; then
    rollback
    exit 1
  fi
done

trap - EXIT
cleanup

echo "Montages NFS configurés. Sauvegarde de fstab: $FSTAB_BACKUP"
findmnt --target "$DOWNLOAD_MOUNT" --output SOURCE,TARGET,FSTYPE,OPTIONS
findmnt --target "$MULTIMEDIA_MOUNT" --output SOURCE,TARGET,FSTYPE,OPTIONS
