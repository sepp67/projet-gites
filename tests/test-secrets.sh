#!/bin/sh
# (12)(13)(14) Absence de secrets/comptes dans l'image construite, et
# injection correcte du secret SMTP (user/config/email-private.php) selon
# les trois cas identifiés en Phase 1 : absent / valide / invalide.
. "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
CONTAINER="projet-gites-test-secrets"
PORT="18083"
IMAGE_TAR="$(mktemp -u).tar"
EXTRACT_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -f "$IMAGE_TAR"
  rm -rf "$EXTRACT_DIR"
}
trap cleanup EXIT

# --- (12) aucun secret dans les couches de l'image -------------------------
log "export de l'image et recherche de secrets/placeholders connus"
docker save "$IMAGE" -o "$IMAGE_TAR"
tar -xf "$IMAGE_TAR" -C "$EXTRACT_DIR"
if grep -rl "ChangeMe123\|admin@example.com\|lavallee.tech.*password" "$EXTRACT_DIR" >/dev/null 2>&1; then
  fail "des valeurs de test/placeholder ont été trouvées dans les couches de l'image"
fi
log "aucun secret/placeholder connu trouvé dans l'image"

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
log "vérification que la valeur du secret n'apparaît pas dans les logs du conteneur"
if docker logs "$CONTAINER" 2>&1 | grep -q "FIXTURE-SECRET-DO-NOT-REUSE"; then
  fail "la valeur du mot de passe de test apparaît en clair dans les logs du conteneur"
fi
log "secret absent des logs"
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
