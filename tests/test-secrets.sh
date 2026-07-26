#!/bin/sh
# (12)(13)(14) Absence de secrets/comptes dans l'image construite, et
# injection correcte du secret SMTP (user/config/email-private.php) selon
# les trois cas identifiés en Phase 1 : absent / valide / invalide.
#
# Incident corrigé ici : la version précédente de ce script grep-ait la
# sortie de `docker save` (couches compressées gzip, quasi jamais lisibles
# par un grep littéral — voir docs/testing.md) ET cherchait des motifs
# génériques ("admin@example.com") qui apparaissent légitimement dans la
# documentation des plugins techniques vendorisés par grav-runtime
# (api/email/login) — faux positif, jamais un secret. Corrigé pour :
#   (a) inspecter le FILESYSTEM FINAL réel de l'image (docker export d'un
#       conteneur créé mais jamais démarré), pas l'historique des couches
#       compressées, qui reste vérifié séparément et explicitement ;
#   (b) chercher des indicateurs précis (une sentinelle unique pour les
#       fixtures, un secret réel historiquement connu), jamais des termes
#       génériques (voir docs/secrets-and-config.md).
. "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
CONTAINER="projet-gites-test-secrets"
PORT="18083"

# Sentinelle unique, utilisée uniquement dans tests/fixtures/email-private.valid.php
# — ne doit jamais apparaître dans l'image, quelle que soit la méthode d'inspection.
FIXTURE_SENTINEL="CI_FIXTURE_SECRET_DO_NOT_SHIP_7f31c9"

# Secret réel historique : l'hôte SMTP OVH qui était hardcodé dans email.yaml
# avant la migration Phase 2 (voir docs/secrets-and-config.md). Sa présence
# dans l'image signalerait une régression réelle, pas un faux positif.
KNOWN_SECRET_HOST="ssl0.ovh.net"

ROOTFS_TAR="$(mktemp -u).tar"
ROOTFS_DIR="$(mktemp -d)"
CREATE_CID=""

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  [ -n "$CREATE_CID" ] && docker rm -f "$CREATE_CID" >/dev/null 2>&1 || true
  rm -f "$ROOTFS_TAR"
  rm -rf "$ROOTFS_DIR"
}
trap cleanup EXIT

# Échec avec preuve : motif recherché, fichiers concernés (chemin relatif),
# ligne de contexte — jamais un simple "échec" sans détail.
evidence_grep() {
  pattern="$1"
  dir="$2"
  label="$3"
  matches="$(grep -rIn "$pattern" "$dir" 2>/dev/null || true)"
  if [ -n "$matches" ]; then
    echo "[FAIL] motif détecté : $pattern" >&2
    echo "[FAIL] raison : $label" >&2
    echo "$matches" | while IFS= read -r line; do
      echo "  -> ${line#"$dir"/}" >&2
    done
    fail "$label"
  fi
}

# ---------------------------------------------------------------------------
# (12a) Filesystem final réel de l'image, via `docker create` + `docker
# export` : le conteneur n'est jamais démarré (l'entrypoint ne s'exécute
# pas), donc ce qu'on inspecte est exactement ce que livre l'image, rien de
# plus. C'est la bonne méthode pour chercher du contenu — contrairement à
# `docker save`, dont les couches restent compressées et donc quasiment
# invisibles à un grep littéral.
# ---------------------------------------------------------------------------
log "export du filesystem final de l'image (docker create + docker export)"
CREATE_CID="$(docker create "$IMAGE")"
docker export "$CREATE_CID" -o "$ROOTFS_TAR"
docker rm -f "$CREATE_CID" >/dev/null 2>&1
CREATE_CID=""
tar -xf "$ROOTFS_TAR" -C "$ROOTFS_DIR" 2>/dev/null

log "recherche de la sentinelle de fixture (ne doit jamais apparaître)"
evidence_grep "$FIXTURE_SENTINEL" "$ROOTFS_DIR" \
  "la sentinelle de fixture '$FIXTURE_SENTINEL' est présente dans le filesystem final de l'image"

log "recherche de l'hôte SMTP historiquement hardcodé ($KNOWN_SECRET_HOST)"
evidence_grep "$KNOWN_SECRET_HOST" "$ROOTFS_DIR" \
  "l'hôte SMTP '$KNOWN_SECRET_HOST' est présent dans le filesystem final — régression : il ne devrait exister que dans email-private.php, jamais dans l'image (voir docs/secrets-and-config.md)"

log "absence des fichiers secrets réels (email-private.php, security-private.php)"
found_secret_files="$(find "$ROOTFS_DIR" -iname "email-private.php" -o -iname "security-private.php" 2>/dev/null)"
if [ -n "$found_secret_files" ]; then
  echo "[FAIL] fichiers secrets présents dans le filesystem final :" >&2
  echo "$found_secret_files" >&2
  fail "email-private.php ou security-private.php trouvé dans l'image"
fi

log "user/accounts vide dans le filesystem final (aucun compte baké)"
accounts_dir="$ROOTFS_DIR/var/www/html/user/accounts"
if [ -d "$accounts_dir" ] && [ -n "$(ls -A "$accounts_dir" 2>/dev/null)" ]; then
  echo "[FAIL] contenu inattendu dans user/accounts :" >&2
  ls -la "$accounts_dir" >&2
  fail "user/accounts n'est pas vide dans le filesystem final de l'image"
fi

log "filesystem final : aucune sentinelle, aucun secret réel connu, aucun compte"

# ---------------------------------------------------------------------------
# (12b) Historique des couches, en complément — défense en profondeur.
# `docker export` ne montre que l'état final fusionné : si un secret avait
# été copié puis supprimé dans une couche ultérieure, il resterait invisible
# à ce niveau mais toujours présent dans l'image (couche antérieure jamais
# purgée). On décompresse donc explicitement chaque couche de `docker save`
# et on y cherche la sentinelle — seule elle, motif non générique, sans
# risque de faux positif sur du contenu vendorisé légitime.
# ---------------------------------------------------------------------------
log "recherche de la sentinelle dans l'historique des couches (docker save, décompressé)"
SAVE_TAR="$(mktemp -u).tar"
SAVE_DIR="$(mktemp -d)"
docker save "$IMAGE" -o "$SAVE_TAR"
tar -xf "$SAVE_TAR" -C "$SAVE_DIR"
layer_hit=""
for blob in "$SAVE_DIR"/blobs/sha256/*; do
  if gzip -t "$blob" 2>/dev/null; then
    if zcat "$blob" 2>/dev/null | grep -qa "$FIXTURE_SENTINEL"; then
      layer_hit="$blob"
      break
    fi
  elif grep -qa "$FIXTURE_SENTINEL" "$blob" 2>/dev/null; then
    layer_hit="$blob"
    break
  fi
done
rm -f "$SAVE_TAR"
rm -rf "$SAVE_DIR"
if [ -n "$layer_hit" ]; then
  echo "[FAIL] sentinelle trouvée dans une couche historique : $layer_hit" >&2
  fail "la sentinelle de fixture apparaît dans l'historique des couches Docker (voir chemin ci-dessus)"
fi
log "historique des couches : sentinelle absente"

# --- (13) aucun compte committé dans l'image (fraîche, sans volume) -------
log "vérification qu'aucun compte n'est baké dans l'image (conteneur sans volume)"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" -p "$PORT:80" "$IMAGE" >/dev/null
wait_healthy "$CONTAINER" 30
account_count="$(docker exec "$CONTAINER" sh -c 'ls -A /var/www/html/user/accounts 2>/dev/null | wc -l')"
[ "$account_count" -eq 0 ] || fail "des comptes sont présents alors qu'aucune variable GRAV_ADMIN_* n'a été fournie"
log "aucun compte présent sans bootstrap explicite"
docker rm -f "$CONTAINER" >/dev/null 2>&1

# Comptes de bootstrap réutilisés pour les cas 1/4, 2/4, 3/4 ci-dessous :
# sans compte admin, grav-runtime redirige "/contact" vers "/admin" (même
# comportement natif que celui déjà traité dans test-startup.sh), ce qui
# n'a rien à voir avec la validité du secret SMTP testée ici.
ADMIN_ENV="-e GRAV_ADMIN_USER=admin -e GRAV_ADMIN_PASSWORD=ChangeMe123 -e GRAV_ADMIN_EMAIL=admin@example.com"

# --- (14a) secret absent : pas de crash --------------------------------
log "cas 1/4 : secret absent — le site doit rester fonctionnel"
docker run -d --name "$CONTAINER" -p "$PORT:80" $ADMIN_ENV "$IMAGE" >/dev/null
wait_healthy "$CONTAINER" 30
status="$(http_status "http://localhost:$PORT/contact")"
[ "$status" = "200" ] || fail "secret absent : page contact attendue 200, obtenu $status"
docker rm -f "$CONTAINER" >/dev/null 2>&1

# --- (14b) secret valide : lu au chemin plat attendu, sans crash --------
log "cas 2/4 : secret valide monté à plat sous user/config/email-private.php"
docker run -d --name "$CONTAINER" -p "$PORT:80" $ADMIN_ENV \
  -v "$REPO_ROOT/tests/fixtures/email-private.valid.php:/var/www/html/user/config/email-private.php:ro" \
  "$IMAGE" >/dev/null
wait_healthy "$CONTAINER" 30
status="$(http_status "http://localhost:$PORT/contact")"
[ "$status" = "200" ] || fail "secret valide : page contact attendue 200, obtenu $status"
docker exec "$CONTAINER" test -f /var/www/html/user/config/email-private.php \
  || fail "le secret n'est pas présent au chemin résolu par user://config/email-private.php"
is_array="$(docker exec "$CONTAINER" php -r 'var_export(is_array(require "/var/www/html/user/config/email-private.php"));')"
[ "$is_array" = "true" ] || fail "le fixture valide ne satisfait pas is_array(), comme l'exige contact.php"
log "secret valide chargé sans erreur, forme conforme à ce qu'attend contact.php"

# --- (14b bis) non-affichage du secret dans les logs --------------------
log "vérification que la sentinelle n'apparaît pas dans les logs du conteneur"
if docker logs "$CONTAINER" 2>&1 | grep -q "$FIXTURE_SENTINEL"; then
  fail "la sentinelle de fixture apparaît en clair dans les logs du conteneur"
fi
log "sentinelle absente des logs"
docker rm -f "$CONTAINER" >/dev/null 2>&1

# --- (14c) secret présent mais invalide (non-array) : pas de crash ------
log "cas 3/4 : secret présent mais invalide (ne retourne pas un tableau) — ne doit pas planter"
docker run -d --name "$CONTAINER" -p "$PORT:80" $ADMIN_ENV \
  -v "$REPO_ROOT/tests/fixtures/email-private.invalid-nonarray.php:/var/www/html/user/config/email-private.php:ro" \
  "$IMAGE" >/dev/null
wait_healthy "$CONTAINER" 30
status="$(http_status "http://localhost:$PORT/contact")"
[ "$status" = "200" ] || fail "secret invalide (non-array) : page contact attendue 200, obtenu $status"
log "secret invalide (non-array) ignoré silencieusement, comme attendu"
docker rm -f "$CONTAINER" >/dev/null 2>&1

# --- (14d) risque connu et documenté : erreur de syntaxe PHP -----------
log "cas 4/4 (risque connu, non bloquant) : secret avec erreur de syntaxe PHP"
docker run -d --name "$CONTAINER" -p "$PORT:80" $ADMIN_ENV \
  -v "$REPO_ROOT/tests/fixtures/email-private.syntax-error.php:/var/www/html/user/config/email-private.php:ro" \
  "$IMAGE" >/dev/null
sleep 5
status="$(http_status "http://localhost:$PORT/" || echo "000")"
if [ "$status" = "500" ] || [ "$status" = "000" ]; then
  log "comportement conforme au risque documenté (docs/secrets-and-config.md) : le site échoue sur un secret syntaxiquement invalide (HTTP $status)"
else
  log "AVERTISSEMENT : comportement différent du risque documenté (HTTP $status) — à revalider dans docs/secrets-and-config.md"
fi
docker rm -f "$CONTAINER" >/dev/null 2>&1

log "tests secrets terminés"
