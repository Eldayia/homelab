#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/inventory/stacks.manifest"
HOMELAB_ROOT="${HOMELAB_ROOT:-/srv/docker}"
ACTION="${1:-list}"
shift || true

declare -a REQUESTED=()
ALL=0

for argument in "$@"; do
  case "$argument" in
    --all) ALL=1 ;;
    -h|--help) ACTION=help ;;
    *) REQUESTED+=("$argument") ;;
  esac
done

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy.sh ACTION [--all | STACK...]

Actions:
  list     Liste les stacks connues.
  sync     Clone les sources nécessaires et copie les configurations.
  up       Synchronise puis démarre/recrée les stacks.
  pull     Télécharge les images sans redémarrer.
  status   Affiche l'état Compose.

Exemples:
  ./scripts/deploy.sh sync --all
  ./scripts/deploy.sh up nginx-proxy-manager pihole
  ./scripts/deploy.sh up --all
EOF
}

[[ -r "$MANIFEST" ]] || { echo "Manifest introuvable: $MANIFEST" >&2; exit 1; }

if [[ "$ACTION" == "help" ]]; then usage; exit 0; fi
if [[ "$ACTION" == "list" ]]; then
  awk -F'|' '!/^#/ && NF {printf "%-24s %s\n", $1, $2}' "$MANIFEST"
  exit 0
fi

case "$ACTION" in sync|up|pull|status) ;; *) usage >&2; exit 2 ;; esac

if ((${#REQUESTED[@]} == 0 && ALL == 0)); then
  echo "Indique --all ou au moins une stack." >&2
  exit 2
fi

command -v docker >/dev/null || { echo "Docker est requis." >&2; exit 1; }
command -v rsync >/dev/null || { echo "rsync est requis." >&2; exit 1; }

is_requested() {
  local candidate="$1"
  local item
  ((ALL)) && return 0
  for item in "${REQUESTED[@]}"; do
    [[ "$candidate" == "$item" ]] && return 0
  done
  return 1
}

compose_args() {
  local target="$1"
  local files="$2"
  local file
  local -a parsed
  IFS=',' read -r -a parsed <<<"$files"
  COMPOSE_ARGS=()
  for file in "${parsed[@]}"; do
    COMPOSE_ARGS+=(--file "$target/$file")
  done
}

prepare_source() {
  local name="$1" target="$2" repository="$3" revision="$4"
  local source_dir="$target"

  [[ -n "$repository" ]] || return 0
  [[ "$name" == "psitransfer" ]] && source_dir="$target/source"

  if [[ ! -d "$source_dir/.git" ]]; then
    if [[ -e "$source_dir" && -n "$(find "$source_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
      echo "Le dossier source existe sans dépôt Git: $source_dir" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$source_dir")"
    git clone "$repository" "$source_dir"
    git -C "$source_dir" checkout --detach "$revision"
  else
    echo "Source existante conservée: $source_dir"
  fi
}

sync_stack() {
  local name="$1" repository="$2" revision="$3"
  local source="$REPO_ROOT/stacks/$name"
  local target="$HOMELAB_ROOT/$name"

  [[ -d "$source" ]] || { echo "Configuration absente: $source" >&2; exit 1; }
  prepare_source "$name" "$target" "$repository" "$revision"
  mkdir -p "$target"
  rsync -a \
    --exclude='.env.example' \
    --exclude='secrets.json.example' \
    "$source/" "$target/"

  if [[ -f "$source/.env.example" && ! -f "$target/.env" ]]; then
    install -m 0600 "$source/.env.example" "$target/.env"
    echo "À compléter avant démarrage: $target/.env"
  fi
  if [[ -f "$source/secrets.json.example" && ! -f "$target/secrets.json" ]]; then
    install -m 0600 "$source/secrets.json.example" "$target/secrets.json"
    echo "À compléter avant démarrage: $target/secrets.json"
  fi
}

assert_secrets_ready() {
  local target="$1"
  local file
  for file in "$target/.env" "$target/secrets.json"; do
    [[ -f "$file" ]] || continue
    if grep -v 'CHANGE_ME_OPTIONAL' "$file" | grep -q 'CHANGE_ME'; then
      echo "Placeholder non remplacé dans $file" >&2
      return 1
    fi
  done
}

if [[ "$ACTION" != "status" ]]; then
  docker network inspect proxy >/dev/null 2>&1 || docker network create proxy >/dev/null
fi

FOUND=0
while IFS='|' read -r name state files repository revision; do
  [[ -n "$name" && "$name" != \#* ]] || continue
  is_requested "$name" || continue
  ((FOUND += 1))

  if ((ALL)) && [[ "$state" != "active" ]]; then
    continue
  fi

  target="$HOMELAB_ROOT/$name"
  if [[ "$ACTION" == "sync" || "$ACTION" == "up" ]]; then
    sync_stack "$name" "$repository" "$revision"
  fi

  compose_args "$target" "$files"
  case "$ACTION" in
    sync)
      ;;
    up)
      assert_secrets_ready "$target"
      docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" \
        config --quiet
      docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" \
        up -d --build --remove-orphans
      ;;
    pull)
      docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" pull
      ;;
    status)
      printf '\n### %s\n' "$name"
      docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" ps
      ;;
  esac
done <"$MANIFEST"

((FOUND > 0)) || { echo "Aucune stack correspondante." >&2; exit 1; }
