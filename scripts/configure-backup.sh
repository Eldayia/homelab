#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QNAP_HOST="${QNAP_HOST:-192.168.1.250}"
QNAP_SHARE="${QNAP_SHARE:-RaspberryBackups}"
QNAP_USER="${QNAP_USER:-rpi-backup}"
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

read_secret QNAP_PASSWORD "Mot de passe du compte QNAP $QNAP_USER: "
read_secret RESTIC_PASSWORD "Nouveau mot de passe du dépôt Restic (ou mot de passe existant): "

install -d -m 0700 /root/.config/restic "$MOUNT_POINT"
install -m 0600 /dev/null /root/.smb-qnap-backup
printf 'username=%s\npassword=%s\n' "$QNAP_USER" "$QNAP_PASSWORD" \
  >/root/.smb-qnap-backup

install -m 0600 /dev/null /root/.config/restic/rpi-password
printf '%s\n' "$RESTIC_PASSWORD" >/root/.config/restic/rpi-password

if [[ -n "${KUMA_PUSH_URL:-}" ]]; then
  install -m 0600 /dev/null /root/.config/restic/kuma-push-url
  printf '%s\n' "$KUMA_PUSH_URL" >/root/.config/restic/kuma-push-url
fi

FSTAB_LINE="//$QNAP_HOST/$QNAP_SHARE $MOUNT_POINT cifs credentials=/root/.smb-qnap-backup,vers=3.1.1,seal,uid=0,gid=0,file_mode=0600,dir_mode=0700,nofail,_netdev,x-systemd.automount,x-systemd.device-timeout=15s 0 0"

if grep -Eq "^[^#]+[[:space:]]+${MOUNT_POINT}[[:space:]]" /etc/fstab; then
  echo "Une entrée existe déjà pour $MOUNT_POINT; elle est conservée."
else
  printf '\n%s\n' "$FSTAB_LINE" >>/etc/fstab
fi

systemctl daemon-reload
mount "$MOUNT_POINT" || systemctl start "$(systemd-escape --path --suffix=automount "$MOUNT_POINT")"
mountpoint -q "$MOUNT_POINT"

export RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE=/root/.config/restic/rpi-password

if [[ ! -f "$RESTIC_REPOSITORY/config" ]]; then
  restic init
else
  restic snapshots --latest 1
fi

install -d -m 0700 /srv/docker/backup/dumps
install -m 0700 "$REPO_ROOT/scripts/backup.sh" /srv/docker/backup/backup.sh
install -m 0644 "$REPO_ROOT/config/systemd/docker-restic-backup.service" \
  /etc/systemd/system/docker-restic-backup.service
install -m 0644 "$REPO_ROOT/config/systemd/docker-restic-backup.timer" \
  /etc/systemd/system/docker-restic-backup.timer
systemctl daemon-reload
systemctl enable --now docker-restic-backup.timer

echo "Sauvegarde configurée. Test manuel: sudo systemctl start docker-restic-backup.service"
