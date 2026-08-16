#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FAILED=0

while IFS= read -r file; do
  case "$file" in
    */.env|*/secrets.json|*.pem|*.p12|*.pfx|*/id_rsa|*/id_ed25519)
      echo "Fichier sensible interdit: $file" >&2
      FAILED=1
      ;;
  esac
done < <(find . -type f -not -path './.git/*' -not -path './.import/*' -printf '%P\n')

PATTERN='-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}'
if grep -RIE --exclude-dir=.git --exclude-dir=.import -- "$PATTERN" .; then
  echo "Une signature de secret potentiel a été trouvée." >&2
  FAILED=1
fi

if ((FAILED)); then
  exit 1
fi

echo "Aucun secret évident détecté. Ce contrôle ne remplace pas un gestionnaire de secrets."
