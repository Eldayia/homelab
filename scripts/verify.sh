#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/inventory/stacks.manifest"

# Valeur factice utilisée uniquement par `docker compose config` pour les
# variables obligatoires volontairement laissées vides dans les exemples.
export DATA_ENCRYPTION_KEY="ci-validation-placeholder-at-least-32-chars"

"$REPO_ROOT/scripts/check-secrets.sh"

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name '*.sh' -print)

if command -v shellcheck >/dev/null 2>&1; then
  find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name '*.sh' -print0 | xargs -0 shellcheck
else
  echo "shellcheck absent: contrôle avancé ignoré."
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  TMP_ROOT="$(mktemp -d)"
  trap 'rm -rf -- "$TMP_ROOT"' EXIT

  while IFS='|' read -r category name _state files _repository _revision; do
    [[ -n "$category" && "$category" != \#* ]] || continue
    source_dir="$REPO_ROOT/stacks/$category/$name"
    test_dir="$TMP_ROOT/$name"
    cp -a "$source_dir" "$test_dir"
    [[ -f "$test_dir/.env.example" ]] && cp "$test_dir/.env.example" "$test_dir/.env"
    [[ -f "$test_dir/secrets.json.example" ]] && cp "$test_dir/secrets.json.example" "$test_dir/secrets.json"
    mkdir -p "$test_dir/source"

    IFS=',' read -r -a parsed <<<"$files"
    args=()
    for file in "${parsed[@]}"; do args+=(--file "$test_dir/$file"); done
    docker compose --project-directory "$test_dir" "${args[@]}" config --quiet
  done <"$MANIFEST"
else
  echo "Docker Compose absent: validation Compose ignorée."
fi

echo "Validation terminée."
