#!/bin/sh
# (8)(9) Aucune réécriture du contenu après redémarrage ; persistance des
# quatre volumes (pages, accounts, data, images) vérifiée séparément.
. "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
COMPOSE="docker compose -f tests/compose.test.yml -p projet-gites-test"
CONTAINER="projet-gites-test-stack"

cleanup() {
  $COMPOSE down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
log "démarrage du stack de test (4 volumes séparés)"
PROJET_GITES_TEST_IMAGE="$IMAGE" $COMPOSE up -d >/dev/null
wait_healthy "$CONTAINER" 30

log "écriture d'un marqueur dans chacun des 4 répertoires persistants"
docker exec "$CONTAINER" sh -c "echo persistence-marker-pages >> /var/www/html/user/pages/01.home/default.md"
docker exec "$CONTAINER" sh -c "echo persistence-marker-accounts > /var/www/html/user/accounts/.marker"
docker exec "$CONTAINER" sh -c "echo persistence-marker-data > /var/www/html/user/data/.marker"
docker exec "$CONTAINER" sh -c "echo persistence-marker-images > /var/www/html/user/images/.marker"

log "redémarrage du conteneur"
PROJET_GITES_TEST_IMAGE="$IMAGE" $COMPOSE restart >/dev/null
wait_healthy "$CONTAINER" 30

log "vérification des 4 marqueurs après redémarrage"
docker exec "$CONTAINER" grep -q persistence-marker-pages /var/www/html/user/pages/01.home/default.md \
  || fail "user/pages : marqueur perdu après redémarrage"
docker exec "$CONTAINER" grep -q persistence-marker-accounts /var/www/html/user/accounts/.marker \
  || fail "user/accounts : marqueur perdu après redémarrage"
docker exec "$CONTAINER" grep -q persistence-marker-data /var/www/html/user/data/.marker \
  || fail "user/data : marqueur perdu après redémarrage"
docker exec "$CONTAINER" grep -q persistence-marker-images /var/www/html/user/images/.marker \
  || fail "user/images : marqueur perdu après redémarrage"

log "persistance des 4 volumes confirmée"
