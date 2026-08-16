#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

export RESTIC_REPOSITORY="/mnt/qnap-backups/restic-rpi"
export RESTIC_PASSWORD_FILE="/root/.config/restic/rpi-password"

KUMA_FILE="/root/.config/restic/kuma-push-url"
LOCK_FILE="/run/docker-restic-backup.lock"

PAUSED=0
declare -a RUNNING_CONTAINERS=()

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    echo "Une sauvegarde est déjà en cours."
    exit 1
fi

notify_kuma() {
    local status="$1"
    local message="$2"
    local base_url

    [[ -s "$KUMA_FILE" ]] || return 0

    base_url="$(tr -d '\r\n' < "$KUMA_FILE")"
    base_url="${base_url%%\?*}"

    curl --fail --silent --show-error \
        --retry 5 \
        --retry-delay 5 \
        --max-time 15 \
        --get \
        --data-urlencode "status=$status" \
        --data-urlencode "msg=$message" \
        --data-urlencode "ping=" \
        "$base_url" >/dev/null || true
}

resume_containers() {
    if (( PAUSED == 1 )) && ((${#RUNNING_CONTAINERS[@]} > 0)); then
        echo "Reprise des conteneurs..."
        docker unpause "${RUNNING_CONTAINERS[@]}" >/dev/null 2>&1 || true
        PAUSED=0
        sleep 15
    fi
}

finish() {
    local result=$?

    trap - EXIT
    set +e

    resume_containers

    if (( result == 0 )); then
        notify_kuma "up" "Sauvegarde Docker réussie"
    else
        notify_kuma "down" "Échec sauvegarde Docker, code $result"
    fi

    exit "$result"
}

trap finish EXIT
trap 'exit 130' INT TERM

echo "Vérification du QNAP..."

stat /mnt/qnap-backups >/dev/null
mountpoint -q /mnt/qnap-backups

restic snapshots >/dev/null

echo "Mémorisation des conteneurs actifs..."

mapfile -t RUNNING_CONTAINERS < <(
    docker ps --format '{{.Names}}'
)

if ((${#RUNNING_CONTAINERS[@]} == 0)); then
    echo "Aucun conteneur actif détecté."
    exit 1
fi

echo "Pause temporaire des conteneurs..."

PAUSED=1
docker pause "${RUNNING_CONTAINERS[@]}" >/dev/null

sync

echo "Sauvegarde Restic..."

restic backup /srv/docker \
    --tag docker \
    --tag automatic

echo "Reprise des conteneurs..."

docker unpause "${RUNNING_CONTAINERS[@]}" >/dev/null
PAUSED=0

sleep 15

echo "Application de la rétention..."

restic forget \
    --keep-daily 7 \
    --keep-weekly 5 \
    --keep-monthly 12 \
    --keep-yearly 3

if [[ "$(date +%u)" == "7" ]]; then
    echo "Nettoyage hebdomadaire..."
    restic prune

    echo "Contrôle de 10 % des données..."
    restic check --read-data-subset=10%
else
    echo "Contrôle de la structure du dépôt..."
    restic check
fi

echo "Sauvegarde terminée."
