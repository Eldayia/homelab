#!/usr/bin/env bash

set -Eeuo pipefail

ORIGINAL_ARGS=("$@")

SNAPSHOT="latest"
TARGET="/"
CONFIRMED=0
ALLOW_RUNNING=0

while (($#)); do
  case "$1" in
    --snapshot) SNAPSHOT="$2"; shift ;;
    --target) TARGET="$2"; shift ;;
    --confirm) CONFIRMED=1 ;;
    --allow-running-containers) ALLOW_RUNNING=1 ;;
    -h|--help)
      echo "Usage: sudo $0 [--snapshot ID|latest] [--target /] --confirm"
      exit 0
      ;;
    *) echo "Option inconnue: $1" >&2; exit 2 ;;
  esac
  shift
done

if ((EUID != 0)); then
  exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"
fi

((CONFIRMED)) || {
  echo "Restauration non lancée. Relancer avec --confirm après lecture de docs/disaster-recovery.md." >&2
  exit 2
}

mountpoint -q /mnt/qnap-backups || { echo "Le QNAP n'est pas monté." >&2; exit 1; }
[[ -s /root/.config/restic/rpi-password ]] || { echo "Mot de passe Restic absent." >&2; exit 1; }

if ((ALLOW_RUNNING == 0)) && [[ -n "$(docker ps --quiet 2>/dev/null)" ]]; then
  echo "Des conteneurs tournent. Arrête-les ou utilise explicitement --allow-running-containers." >&2
  exit 1
fi

export RESTIC_REPOSITORY=/mnt/qnap-backups/restic-rpi
export RESTIC_PASSWORD_FILE=/root/.config/restic/rpi-password

restic check
restic restore "$SNAPSHOT" --target "$TARGET" --include /srv/docker
echo "Restauration terminée dans $TARGET. Vérifie les droits et les fichiers .env avant de démarrer Docker Compose."
