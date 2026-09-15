#!/bin/sh
# Non-régression ciblée du nettoyage de $TMP dans test-contact-routing.sh
# (voir AUDIT FIX-GITES-R1, item 10 : le répertoire créé par `mktemp -d`
# n'était jamais supprimé par cleanup()). Reproduit le même motif exact
# (initialisation avant trap, préfixe identifiable, suppression strictement
# gardée) dans des sous-shells jetables, séparés et rapides (aucun conteneur
# Docker), pour vérifier le motif en isolation avant de vérifier son
# comportement réel dans la suite complète (voir docs/testing.md, mesure
# avant/après autour de `sh tests/run-all.sh`).
. "$(dirname "$0")/lib.sh"

count_residual() {
  # Comptage par préfixe contrôlé uniquement — jamais un glob générique
  # (/tmp/tmp.*), jamais un listage ni une suppression d'autre chose sous
  # /tmp. `find` avec un motif explicite plutôt qu'un glob shell : ne casse
  # pas sous `set -u` si aucune correspondance n'existe.
  find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'projet-gites-contact-routing.*' 2>/dev/null | wc -l | tr -d ' '
}

# --- Cas 1 : sortie anticipée AVANT toute création de TMP ------------------
log "cas 1/5 — sortie anticipée avant la création de \$TMP : cleanup() sûr sous set -u, aucun répertoire créé"
before="$(count_residual)"
case1_status=0
sh -c '
  set -eu
  TMP=""
  cleanup() {
    if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
      rm -rf -- "$TMP"
    fi
  }
  trap cleanup EXIT
  exit 7
' || case1_status=$?
[ "$case1_status" -eq 7 ] || fail "cas 1/5 : code de sortie attendu 7 (non masqué par cleanup), obtenu $case1_status"
after="$(count_residual)"
[ "$before" = "$after" ] || fail "cas 1/5 : nombre de répertoires contrôlés changé sans qu'aucun n'ait été créé ($before -> $after)"
log "cas 1/5 OK : code de sortie préservé (7), aucun répertoire résiduel"

# --- Cas 2 : sortie anticipée APRÈS création de TMP (échec synthétique) ---
log "cas 2/5 — sortie anticipée après création de \$TMP (échec synthétique) : répertoire supprimé, code de sortie préservé"
before="$(count_residual)"
case2_status=0
sh -c '
  set -eu
  TMP=""
  cleanup() {
    if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
      rm -rf -- "$TMP"
    fi
  }
  trap cleanup EXIT
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/projet-gites-contact-routing.XXXXXX")"
  : > "$TMP/marker"
  exit 3
' || case2_status=$?
[ "$case2_status" -eq 3 ] || fail "cas 2/5 : code de sortie attendu 3 (non masqué par cleanup), obtenu $case2_status"
after="$(count_residual)"
[ "$before" = "$after" ] || fail "cas 2/5 : répertoire résiduel après échec synthétique postérieur à la création de \$TMP ($before -> $after)"
log "cas 2/5 OK : code de sortie préservé (3), répertoire supprimé"

# --- Cas 3 : succès complet -------------------------------------------------
log "cas 3/5 — succès complet : répertoire supprimé, code de sortie 0 préservé"
before="$(count_residual)"
case3_status=0
sh -c '
  set -eu
  TMP=""
  cleanup() {
    if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
      rm -rf -- "$TMP"
    fi
  }
  trap cleanup EXIT
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/projet-gites-contact-routing.XXXXXX")"
  : > "$TMP/marker"
' || case3_status=$?
[ "$case3_status" -eq 0 ] || fail "cas 3/5 : code de sortie attendu 0, obtenu $case3_status"
after="$(count_residual)"
[ "$before" = "$after" ] || fail "cas 3/5 : répertoire résiduel après succès complet ($before -> $after)"
log "cas 3/5 OK"

# --- Cas 4 : cleanup() appelée plusieurs fois (comme au début du script réel,
# qui appelle cleanup() une première fois avant le trap, voir ligne 43) -----
log "cas 4/5 — appel répété de cleanup() : jamais d'erreur, répertoire absent après le dernier appel"
case4_status=0
sh -c '
  set -eu
  TMP=""
  cleanup() {
    if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
      rm -rf -- "$TMP"
    fi
  }
  cleanup
  cleanup
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/projet-gites-contact-routing.XXXXXX")"
  cleanup
  cleanup
  [ ! -d "$TMP" ]
' || case4_status=$?
[ "$case4_status" -eq 0 ] || fail "cas 4/5 : appel répété de cleanup() n'est pas idempotent/sûr (répertoire encore présent ou erreur, code $case4_status)"
log "cas 4/5 OK"

# --- Cas 5 : répertoire déjà absent (supprimé entre-temps par autre chose) -
log "cas 5/5 — répertoire déjà absent au moment de cleanup() : aucune erreur, rm -rf jamais appelé sur un chemin vide"
case5_status=0
sh -c '
  set -eu
  TMP=""
  cleanup() {
    if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
      rm -rf -- "$TMP"
    fi
  }
  trap cleanup EXIT
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/projet-gites-contact-routing.XXXXXX")"
  rmdir "$TMP"
' || case5_status=$?
[ "$case5_status" -eq 0 ] || fail "cas 5/5 : cleanup() a échoué face à un répertoire déjà absent (code $case5_status)"
log "cas 5/5 OK"

log "nettoyage de \$TMP : les 5 cas de non-régression passent (préfixe contrôlé uniquement, aucun glob générique utilisé pour ce contrôle)"
