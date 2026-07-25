#!/bin/sh
# (5)(6)(7) Thème activé, plugins métier présents, contenu initial seedé,
# assets accessibles, rendu réel de l'application (pas seulement HTTP 200).
. "$(dirname "$0")/lib.sh"

CONTAINER="projet-gites-test-presence"
PORT="18081"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
log "démarrage d'un conteneur jetable (sans volumes) depuis $IMAGE"
# GRAV_ADMIN_* fournies : sans compte admin, le plugin Admin de grav-runtime
# redirige toutes les pages du site vers "/admin" (comportement natif de
# Grav Admin) — ce test vérifie le rendu réel du site, pas cet écran.
docker run -d --name "$CONTAINER" -p "$PORT:80" \
  -e GRAV_ADMIN_USER=admin \
  -e GRAV_ADMIN_PASSWORD=ChangeMe123 \
  -e GRAV_ADMIN_EMAIL=admin@example.com \
  "$IMAGE" >/dev/null
wait_healthy "$CONTAINER" 30

log "thème actif déclaré (system.yaml)"
docker exec "$CONTAINER" grep -q "theme: gites-theme" /var/www/html/user/config/system.yaml \
  || fail "system.yaml ne déclare pas gites-theme comme thème actif"

log "thème gites-theme et son parent quark2 présents dans l'image"
docker exec "$CONTAINER" test -d /var/www/html/user/themes/gites-theme \
  || fail "user/themes/gites-theme absent"
docker exec "$CONTAINER" test -d /var/www/html/user/themes/quark2 \
  || fail "user/themes/quark2 absent (fourni par grav-runtime)"

log "plugins métier présents"
for plugin in contact calendrier-disponibilites; do
  docker exec "$CONTAINER" test -d "/var/www/html/user/plugins/$plugin" \
    || fail "plugin métier '$plugin' absent de l'image"
done

log "contenu initial seedé dans le volume user/pages au premier démarrage"
docker exec "$CONTAINER" test -f /var/www/html/user/pages/01.home/default.md \
  || fail "seed non appliqué : user/pages/01.home/default.md absent"

log "rendu réel de la page d'accueil (héritage quark2 + contenu gîtes)"
html="$(curl -s "http://localhost:$PORT/")"
echo "$html" | grep -q "Nos gîtes" || fail "marqueur 'Nos gîtes' absent du rendu de la page d'accueil"

log "pages gîtes et contact répondent"
for path in /gites/gite-un /gites/gite-deux /contact; do
  status="$(http_status "http://localhost:$PORT$path")"
  [ "$status" = "200" ] || fail "$path : attendu 200, obtenu $status"
done

log "asset média d'un gîte accessible"
status="$(http_status "http://localhost:$PORT/user/pages/03.gites/01.gite-un/photo-1.jpg")"
[ "$status" = "200" ] || fail "photo-1.jpg : attendu 200, obtenu $status"

log "admin accessible"
status="$(http_status "http://localhost:$PORT/admin")"
[ "$status" = "200" ] || fail "/admin : attendu 200, obtenu $status"

log "présence applicative OK"
