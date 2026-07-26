#!/bin/sh

set -eu

IMAGE_NAME="${IMAGE_NAME:-projet-gites:test}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-15}"

echo "[test] docker build -t ${IMAGE_NAME} ."

attempt=1

while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    echo "[test] tentative de build ${attempt}/${MAX_ATTEMPTS}"

    if docker build --pull -t "$IMAGE_NAME" .; then
        echo "[PASS] docker build réussi"
        exit 0
    fi

    if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
        echo "[FAIL] docker build a échoué après ${MAX_ATTEMPTS} tentatives"
        exit 1
    fi

    echo "[WARN] build échoué, nouvelle tentative dans ${RETRY_DELAY} secondes"
    sleep "$RETRY_DELAY"

    attempt=$((attempt + 1))
done