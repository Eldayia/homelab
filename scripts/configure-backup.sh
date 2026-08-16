#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QNAP_HOST="${QNAP_HOST:-192.168.1.250}"
QNAP_EXPORT="${QNAP_EXPORT:-/RaspberryBackups}"
NFS_VERSION="${NFS_VERSION:-4.1}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/qnap-backups}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-$MOUNT_POINT/restic-rpi}"

if ((EUID != 0)); then
  exec sudo -E bash "$0" "$@"
fi

read_secret() {
  local variable_name="$1"
  local prompt="$2"
  local current_value="${!variable_name:-}"

  if [[ -z "$current_value" ]]; then
    read -r -s -p "$prompt" current_value
    printf '\n'
  fi
  [[ -n "$current_value" && "$current_value" != *$'\n'* ]] || {
    echo "Valeur vide ou invalide pour $variable_name." >&2
    exit 1
  }
  printf -v "$variable_name" '%s' "$current_value"
}

install -d -m 0700 /root/.config/restic "$MOUNT_POINT"

command -v mount.nfs >/dev/null || {
  echo "Le client NFS est absent. Installe le paquet nfs-common puis relance le script." >&2
  exit 1
}

[[ "$QNAP_HOST" != *[[:space:]]* && "$QNAP_EXPORT" == /* &&
   "$QNAP_EXPORT" != *[[:space:]]* ]] || {
  echo "QNAP_HOST ou QNAP_EXPORT invalide." >&2
  exit 1
}

case "$NFS_VERSION" in
  4|4.0|4.1|4.2) ;;
  *) echo "Version NFS non prise en charge: $NFS_VERSION" >&2; exit 1 ;;
esac

if [[ -n "${KUMA_PUSH_URL:-}" ]]; then
  install -m 0600 /dev/null /root/.config/restic/kuma-push-url
  printf '%s\n' "$KUMA_PUSH_URL" >/root/.config/restic/kuma-push-url
fi

FSTAB_SOURCE="${QNAP_HOST}:${QNAP_EXPORT}"
FSTAB_OPTIONS="rw,vers=${NFS_VERSION},proto=tcp,nofail,_netdev,x-systemd.automount,x-systemd.device-timeout=15s,x-systemd.mount-timeout=30s"
FSTAB_LINE="$FSTAB_SOURCE $MOUNT_POINT nfs $FSTAB_OPTIONS 0 0"
CURRENT_FSTAB_LINE="$(awk -v target="$MOUNT_POINT" '$1 !~ /^#/ && $2 == target {print; exit}' /etc/fstab)"
FSTAB_CHANGED=0

restore_previous_mount() {
  ((FSTAB_CHANGED)) || return 0
  umount "$MOUNT_POINT" 2>/dev/null || true
  cp "$FSTAB_BACKUP" /etc/fstab
  systemctl daemon-reload
  mount "$MOUNT_POINT" 2>/dev/null || true
  echo "L'ancien /etc/fstab a été restauré." >&2
}

if [[ "$CURRENT_FSTAB_LINE" != "$FSTAB_LINE" ]]; then
  if mountpoint -q "$MOUNT_POINT"; then
    echo "Démontage de l'ancien partage sur $MOUNT_POINT..."
    umount "$MOUNT_POINT" || {
      echo "Impossible de démonter $MOUNT_POINT; vérifie qu'aucun processus ne l'utilise." >&2
      exit 1
    }
  fi

  FSTAB_BACKUP="/etc/fstab.backup.$(date +%Y%m%d-%H%M%S)"
  FSTAB_TEMP="$(mktemp)"
  cp /etc/fstab "$FSTAB_BACKUP"
  awk -v target="$MOUNT_POINT" '$1 ~ /^#/ || $2 != target' /etc/fstab >"$FSTAB_TEMP"
  printf '\n%s\n' "$FSTAB_LINE" >>"$FSTAB_TEMP"

  if ! findmnt --verify --tab-file "$FSTAB_TEMP" >/dev/null; then
    rm -f "$FSTAB_TEMP"
    echo "La nouvelle configuration NFS est invalide; /etc/fstab reste inchangé." >&2
    exit 1
  fi

  install -m 0644 "$FSTAB_TEMP" /etc/fstab
  rm -f "$FSTAB_TEMP"
  FSTAB_CHANGED=1
  echo "Sauvegarde de l'ancien fstab: $FSTAB_BACKUP"
fi

systemctl daemon-reload
if ! mount "$MOUNT_POINT"; then
  restore_previous_mount
  echo "Échec du montage NFS." >&2
  exit 1
fi

mountpoint -q "$MOUNT_POINT" || {
  restore_previous_mount
  echo "Le partage NFS n'est pas monté sur $MOUNT_POINT." >&2
  exit 1
}

MOUNT_FSTYPE="$(findmnt --noheadings --output FSTYPE --target "$MOUNT_POINT" | xargs)"
[[ "$MOUNT_FSTYPE" == nfs || "$MOUNT_FSTYPE" == nfs4 ]] || {
  restore_previous_mount
  echo "Le montage actif sur $MOUNT_POINT n'est pas de type NFS." >&2
  exit 1
}

WRITE_TEST="$MOUNT_POINT/.homelab-nfs-write-test"
if ! touch "$WRITE_TEST"; then
  restore_previous_mount
  echo "Le partage NFS est monté mais root ne peut pas y écrire." >&2
  echo "Autorise l'IP du Raspberry Pi en lecture/écriture dans les permissions NFS du QNAP." >&2
  exit 1
fi
rm -f "$WRITE_TEST"

# L'ancien secret SMB n'est plus utile après une migration réussie vers NFS.
rm -f /root/.smb-qnap-backup

export RESTIC_REPOSITORY
PERSISTENT_PASSWORD_FILE=/root/.config/restic/rpi-password
PASSWORD_CANDIDATE_FILE="$(mktemp)"
chmod 0600 "$PASSWORD_CANDIDATE_FILE"
trap 'rm -f "$PASSWORD_CANDIDATE_FILE"' EXIT

if [[ -n "${RESTIC_PASSWORD:-}" ]]; then
  printf '%s\n' "$RESTIC_PASSWORD" >"$PASSWORD_CANDIDATE_FILE"
elif [[ -s "$PERSISTENT_PASSWORD_FILE" ]]; then
  cp "$PERSISTENT_PASSWORD_FILE" "$PASSWORD_CANDIDATE_FILE"
else
  read_secret RESTIC_PASSWORD "Mot de passe du dépôt Restic: "
  printf '%s\n' "$RESTIC_PASSWORD" >"$PASSWORD_CANDIDATE_FILE"
fi

export RESTIC_PASSWORD_FILE="$PASSWORD_CANDIDATE_FILE"

if [[ ! -f "$RESTIC_REPOSITORY/config" ]]; then
  if ! restic init; then
    echo "Impossible d'initialiser le dépôt Restic; le mot de passe local reste inchangé." >&2
    exit 1
  fi
else
  if ! restic snapshots --latest 1; then
    [[ -t 0 ]] || {
      echo "Impossible d'ouvrir le dépôt Restic avec le mot de passe disponible." >&2
      echo "Le mot de passe local existant n'a pas été remplacé." >&2
      exit 1
    }

    echo "Le mot de passe enregistré ou fourni n'ouvre pas ce dépôt." >&2
    RESTIC_PASSWORD=""
    read_secret RESTIC_PASSWORD "Mot de passe EXISTANT du dépôt Restic: "
    printf '%s\n' "$RESTIC_PASSWORD" >"$PASSWORD_CANDIDATE_FILE"

    if ! restic snapshots --latest 1; then
      echo "Le dépôt reste inaccessible; aucun mot de passe local n'a été modifié." >&2
      exit 1
    fi
  fi
fi

install -m 0600 "$PASSWORD_CANDIDATE_FILE" "$PERSISTENT_PASSWORD_FILE"
export RESTIC_PASSWORD_FILE="$PERSISTENT_PASSWORD_FILE"
rm -f "$PASSWORD_CANDIDATE_FILE"
trap - EXIT

install -d -m 0700 /srv/docker/backup/dumps
install -m 0700 "$REPO_ROOT/scripts/backup.sh" /srv/docker/backup/backup.sh
install -m 0644 "$REPO_ROOT/config/systemd/docker-restic-backup.service" \
  /etc/systemd/system/docker-restic-backup.service
install -m 0644 "$REPO_ROOT/config/systemd/docker-restic-backup.timer" \
  /etc/systemd/system/docker-restic-backup.timer
systemctl daemon-reload
systemctl enable --now docker-restic-backup.timer

echo "Sauvegarde configurée. Test manuel: sudo systemctl start docker-restic-backup.service"
