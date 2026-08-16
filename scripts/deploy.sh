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
Usage: ./scripts/deploy.sh ACTION [--all | CATÉGORIE | STACK...]

Actions:
  list     Liste les stacks connues, regroupées par catégorie.
  sync     Clone les sources nécessaires et copie les configurations.
  up       Synchronise puis démarre/recrée les stacks.
  restart  Redémarre une ou plusieurs stacks déjà déployées.
  pull     Télécharge les images sans redémarrer.
  status   Affiche l'état Compose.

Exemples:
  ./scripts/deploy.sh sync infrastructure
  ./scripts/deploy.sh up nginx-proxy-manager pihole
  ./scripts/deploy.sh restart qbittorrent
  ./scripts/deploy.sh up --all
EOF
}

[[ -r "$MANIFEST" ]] || { echo "Manifest introuvable: $MANIFEST" >&2; exit 1; }

if [[ "$ACTION" == "help" ]]; then usage; exit 0; fi
if [[ "$ACTION" == "list" ]]; then
  awk -F'|' '!/^#/ && NF {printf "%-16s %-24s %s\n", $1, $2, $3}' "$MANIFEST"
  exit 0
fi

case "$ACTION" in sync|up|restart|pull|status) ;; *) usage >&2; exit 2 ;; esac

if ((${#REQUESTED[@]} == 0 && ALL == 0)); then
  echo "Indique --all ou au moins une stack." >&2
  exit 2
fi

command -v docker >/dev/null || { echo "Docker est requis." >&2; exit 1; }
command -v rsync >/dev/null || { echo "rsync est requis." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq est requis." >&2; exit 1; }
command -v findmnt >/dev/null || { echo "findmnt est requis." >&2; exit 1; }
command -v mountpoint >/dev/null || { echo "mountpoint est requis." >&2; exit 1; }

is_requested() {
  local category="$1" candidate="$2"
  local item
  ((ALL)) && return 0
  for item in "${REQUESTED[@]}"; do
    [[ "$candidate" == "$item" || "$category" == "$item" ]] && return 0
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
  local category="$1" name="$2" repository="$3" revision="$4"
  local source="$REPO_ROOT/stacks/$category/$name"
  local target="$HOMELAB_ROOT/$category/$name"
  local legacy_target="$HOMELAB_ROOT/$name"

  [[ -d "$source" ]] || { echo "Configuration absente: $source" >&2; exit 1; }

  if [[ -d "$legacy_target" && ! -e "$target" ]]; then
    mkdir -p "$(dirname "$target")"
    mv "$legacy_target" "$target"
    echo "Ancien emplacement migré: $legacy_target -> $target"
  elif [[ -d "$legacy_target" && -e "$target" &&
          -n "$(find "$legacy_target" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Deux emplacements existent pour $name:" >&2
    echo "  $legacy_target" >&2
    echo "  $target" >&2
    echo "Fusionne-les manuellement avant de poursuivre." >&2
    exit 1
  fi

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

assert_mounts_ready() {
  local mounts="$1"
  local mount_path filesystem
  local -a parsed_mounts

  [[ -n "$mounts" ]] || return 0
  IFS=',' read -r -a parsed_mounts <<<"$mounts"
  for mount_path in "${parsed_mounts[@]}"; do
    # Déclenche un éventuel automount systemd avant le contrôle effectif.
    stat "$mount_path" >/dev/null 2>&1 || true
    mountpoint -q "$mount_path" || {
      echo "Montage requis absent: $mount_path" >&2
      echo "Relance l'assistant de stockage correspondant avant ce service." >&2
      return 1
    }
    if [[ "$mount_path" == /mnt/nas/* ]]; then
      filesystem="$(findmnt -n -T "$mount_path" -o FSTYPE 2>/dev/null || true)"
      [[ "$filesystem" == "nfs" || "$filesystem" == "nfs4" ]] || {
        echo "Le chemin $mount_path n'est pas monté en NFS." >&2
        return 1
      }
    fi
  done
}

prepare_bind_mounts() {
  local target="$1"
  local compose_json source_path

  compose_json="$(docker compose --project-directory "$target" \
    "${COMPOSE_ARGS[@]}" config --format json)"

  if jq -e '[.services[].volumes[]? | select(.type == "volume")] | length > 0' \
      <<<"$compose_json" >/dev/null; then
    echo "Volume Docker nommé ou anonyme interdit dans $target." >&2
    return 1
  fi

  while IFS= read -r source_path; do
    [[ -n "$source_path" ]] || continue
    [[ -e "$source_path" ]] || mkdir -p "$source_path"
  done < <(jq -r '.services[].volumes[]? | select(.type == "bind") | .source' \
    <<<"$compose_json" | sort -u)
}

dependency_is_ready() {
  local dependency="$1"
  local state health

  state="$(docker inspect --format '{{.State.Status}}' "$dependency" 2>/dev/null || true)"
  [[ "$state" == "running" ]] || return 1
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
    "$dependency" 2>/dev/null || true)"
  [[ -z "$health" || "$health" == "healthy" ]]
}

wait_for_dependency() {
  local dependency="$1"
  local attempt
  for attempt in {1..60}; do
    dependency_is_ready "$dependency" && return 0
    sleep 2
  done
  echo "La dépendance $dependency n'est pas saine après 120 secondes." >&2
  return 1
}

start_dependency() {
  local dependency="$1"
  local record category name state files repository revision dependencies mounts target

  dependency_is_ready "$dependency" && return 0
  record="$(awk -F'|' -v wanted="$dependency" '$1 !~ /^#/ && $2 == wanted {print; exit}' \
    "$MANIFEST")"
  [[ -n "$record" ]] || { echo "Dépendance inconnue: $dependency" >&2; return 1; }
  IFS='|' read -r category name state files repository revision dependencies mounts <<<"$record"

  echo "Démarrage de la dépendance $dependency..."
  sync_stack "$category" "$name" "$repository" "$revision"
  target="$HOMELAB_ROOT/$category/$name"
  assert_secrets_ready "$target"
  assert_mounts_ready "$mounts"
  compose_args "$target" "$files"
  docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" config --quiet
  prepare_bind_mounts "$target"
  docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" \
    up -d --build --remove-orphans
  wait_for_dependency "$dependency"
}

ensure_dependencies() {
  local dependencies="$1"
  local dependency
  local -a parsed_dependencies

  [[ -n "$dependencies" ]] || return 0
  IFS=',' read -r -a parsed_dependencies <<<"$dependencies"
  for dependency in "${parsed_dependencies[@]}"; do
    start_dependency "$dependency"
  done
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
while IFS='|' read -r category name state files repository revision dependencies mounts; do
  [[ -n "$category" && "$category" != \#* ]] || continue
  is_requested "$category" "$name" || continue
  ((FOUND += 1))

  if ((ALL)) && [[ "$state" != "active" ]]; then
    continue
  fi

  target="$HOMELAB_ROOT/$category/$name"
  if [[ "$ACTION" == "sync" || "$ACTION" == "up" ]]; then
    sync_stack "$category" "$name" "$repository" "$revision"
  fi

  compose_args "$target" "$files"
  case "$ACTION" in
    sync)
      ;;
    up)
      assert_secrets_ready "$target"
      assert_mounts_ready "$mounts"
      ensure_dependencies "$dependencies"
      compose_args "$target" "$files"
      docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" \
        config --quiet
      prepare_bind_mounts "$target"
      docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" \
        up -d --build --remove-orphans
      ;;
    restart)
      assert_mounts_ready "$mounts"
      ensure_dependencies "$dependencies"
      compose_args "$target" "$files"
      docker compose --project-directory "$target" "${COMPOSE_ARGS[@]}" restart
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
