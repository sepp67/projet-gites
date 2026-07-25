#!/bin/sh
# (1) Le build de l'image applicative doit réussir.
. "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
log "docker build -t $IMAGE ."
docker build -t "$IMAGE" . || fail "docker build a échoué"
log "build OK"
