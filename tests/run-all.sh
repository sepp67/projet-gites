#!/bin/sh
# Exécute la suite de tests dans l'ordre, s'arrête au premier échec.
# Voir docs/testing.md pour le détail de ce que couvre chaque script.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

for script in test-build.sh test-startup.sh test-app-presence.sh test-secrets.sh test-persistence.sh test-update-rollback.sh; do
  echo "=================================================================="
  echo "== $script"
  echo "=================================================================="
  sh "$DIR/$script"
done

echo "=================================================================="
echo "Tous les tests ont réussi."
echo "=================================================================="
