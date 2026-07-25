#!/bin/sh
# (10)(11) Mise à jour d'image A→B puis rollback B→A : dans les deux sens,
# les données persistantes ne sont jamais perdues, et le code servi
# correspond bien à l'image active à chaque étape.
#
# B est construite depuis une copie temporaire du dépôt (un marqueur ajouté
# au CSS du thème) : ce script ne modifie jamais les fichiers réels du dépôt.
. "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
COMPOSE="docker compose -f tests/compose.test.yml -p projet-gites-test-update"
CONTAINER="projet-gites-test-stack"
IMAGE_A="$IMAGE"
IMAGE_B="projet-gites:test-update-b"
TMP_BUILD_DIR="$(mktemp -d)"

cleanup() {
  $COMPOSE down -v >/dev/null 2>&1 || true
  docker rmi "$IMAGE_B" >/dev/null 2>&1 || true
  rm -rf "$TMP_BUILD_DIR"
}
trap cleanup EXIT

cleanup_partial() { :; }

log "construction de l'image B (version simulée) depuis une copie temporaire"
cp -a "$REPO_ROOT/." "$TMP_BUILD_DIR/"
echo "/* test-update-rollback marker */" >> "$TMP_BUILD_DIR/grav/user/themes/gites-theme/css/custom.css"
docker build -t "$IMAGE_B" "$TMP_BUILD_DIR" -q >/dev/null || fail "construction de l'image B a échoué"

$COMPOSE down -v >/dev/null 2>&1 || true

log "démarrage avec l'image A ($IMAGE_A)"
PROJET_GITES_TEST_IMAGE="$IMAGE_A" $COMPOSE up -d >/dev/null
wait_healthy "$CONTAINER" 30

log "écriture de marqueurs de persistance"
docker exec "$CONTAINER" sh -c "echo update-marker-pages >> /var/www/html/user/pages/01.home/default.md"
docker exec "$CONTAINER" sh -c "echo update-marker-accounts > /var/www/html/user/accounts/.marker"

log "mise à jour vers l'image B (mêmes volumes)"
PROJET_GITES_TEST_IMAGE="$IMAGE_B" $COMPOSE up -d >/dev/null
wait_healthy "$CONTAINER" 30

docker exec "$CONTAINER" grep -q update-marker-pages /var/www/html/user/pages/01.home/default.md \
  || fail "mise à jour A→B : données pages perdues"
docker exec "$CONTAINER" grep -q update-marker-accounts /var/www/html/user/accounts/.marker \
  || fail "mise à jour A→B : données accounts perdues"

new_css="$(curl -s "http://localhost:18082/user/themes/gites-theme/css/custom.css")"
echo "$new_css" | grep -q "test-update-rollback marker" \
  || fail "mise à jour A→B : le nouveau code (CSS) n'est pas actif"
log "mise à jour A→B : données intactes, nouveau code actif"

log "rollback vers l'image A (mêmes volumes)"
PROJET_GITES_TEST_IMAGE="$IMAGE_A" $COMPOSE up -d >/dev/null
wait_healthy "$CONTAINER" 30

docker exec "$CONTAINER" grep -q update-marker-pages /var/www/html/user/pages/01.home/default.md \
  || fail "rollback B→A : données pages perdues"
docker exec "$CONTAINER" grep -q update-marker-accounts /var/www/html/user/accounts/.marker \
  || fail "rollback B→A : données accounts perdues"

old_css="$(curl -s "http://localhost:18082/user/themes/gites-theme/css/custom.css")"
if echo "$old_css" | grep -q "test-update-rollback marker"; then
  fail "rollback B→A : le code de l'image B est encore actif"
fi
log "rollback B→A : données intactes, code de l'image A de nouveau actif"

log "mise à jour et rollback validés sans perte de données"
