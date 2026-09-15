#!/bin/sh
# SEC-GITES-001 — sélection visible et validation serveur fermée du
# destinataire du formulaire de contact (stratégie D).
#
# Historique du défaut : le champ `gite` était de type `hidden`, prérempli
# côté serveur avec la route de la fiche affichée, mais jamais revalidé à la
# soumission — une valeur cachée pouvait donc désigner silencieusement un
# autre propriétaire valide que celui de la fiche réellement affichée.
#
# Correctif : le champ devient un `select` visible et obligatoire, dont les
# options proviennent d'un fournisseur serveur (`data-options@`,
# ContactPlugin::contactGiteOptionsProvider) qui n'expose que l'identifiant
# public (slug de page) et le titre public d'une page réellement contactable
# (existe, sous-arbre attendu, template métier, publiée, `proprietaire`
# renseigné, compte existant et pourvu d'une adresse). La même liste sert de
# source de vérité à la validation de soumission (onFormValidationProcessed)
# et à la résolution du destinataire (resolveProprietaireEmail) : les trois
# usages ne peuvent pas diverger. Aucune valeur hors de cette liste fermée
# n'est jamais acceptée, et aucune valeur invalide ne déclenche plus
# silencieusement le repli global.
#
# Ce script est volontairement capable de détecter une régression : rejoué
# contre l'image construite AVANT ce correctif (`projet-gites:test` à l'état
# b27d7af), les sections B/C ci-dessous échouent — c'est la preuve que ce
# test couvre réellement le défaut corrigé, pas seulement le nouveau
# comportement en surface.
. "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
NETWORK="projet-gites-test-contact-net"
CONTAINER="projet-gites-test-contact"
MAILPIT="projet-gites-test-contact-mailpit"
PORT="18090"
MAILPIT_API_PORT="18091"
FIXTURE_EMAIL_PRIVATE="$REPO_ROOT/tests/fixtures/email-private.mailpit-contact-routing.php"
# Initialisé avant l'enregistrement du trap pour que cleanup() reste sûr sous
# `set -u` même si EXIT survient avant la création réelle du répertoire
# (mktemp) plus bas dans le script.
TMP=""

cleanup() {
  docker rm -f "$CONTAINER" "$MAILPIT" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -f "$FIXTURE_EMAIL_PRIVATE"
  # Suppression strictement gardée : jamais de glob, jamais un chemin vide ou
  # non résolu transmis à `rm -rf`. Sûre en cas d'échec avant ou après la
  # création de $TMP, en cas de succès complet, d'appel répété de cleanup(),
  # ou si le répertoire a déjà été supprimé entre-temps.
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
    rm -rf -- "$TMP"
  fi
}
trap cleanup EXIT
cleanup

# ---------------------------------------------------------------------------
# Environnement jetable : réseau dédié, Mailpit comme SMTP jetable (capture
# les e-mails réellement envoyés sans en délivrer aucun), deux comptes et
# trois pages synthétiques additionnelles créées uniquement dans le
# conteneur (jamais dans le dépôt) pour couvrir les cas d'exclusion.
# ---------------------------------------------------------------------------
docker network create "$NETWORK" >/dev/null

log "démarrage de Mailpit (SMTP jetable, capture uniquement)"
docker run -d --name "$MAILPIT" --network "$NETWORK" --network-alias mailpit-contact-routing \
  -p "$MAILPIT_API_PORT:8025" axllent/mailpit >/dev/null

cat > "$FIXTURE_EMAIL_PRIVATE" <<'EOF'
<?php
// Fixture de test dédiée à tests/test-contact-routing.sh — jamais un
// secret réel, jamais committée par ce script (supprimée en fin
// d'exécution, voir cleanup()).
return [
    'server'     => 'mailpit-contact-routing',
    'port'       => '1025',
    'encryption' => '',
    'user'       => '',
    'password'   => '',
];
EOF

log "démarrage du conteneur applicatif (sans volume nommé, jetable)"
docker run -d --name "$CONTAINER" --network "$NETWORK" -p "$PORT:80" \
  -e GRAV_ADMIN_USER=admin -e GRAV_ADMIN_PASSWORD=ChangeMe123 -e GRAV_ADMIN_EMAIL=admin@example.com \
  -v "$FIXTURE_EMAIL_PRIVATE:/var/www/html/user/config/email-private.php:ro" \
  "$IMAGE" >/dev/null
wait_healthy "$CONTAINER" 30

log "comptes propriétaires synthétiques (jamais dans le dépôt, uniquement dans ce conteneur jetable)"
docker exec "$CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-gite-1.yaml <<EOF
email: owner1@example.invalid
fullname: "Propriétaire Gîte 1 (synthétique, test)"
state: enabled
EOF'
docker exec "$CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-gite-2.yaml <<EOF
email: owner2@example.invalid
fullname: "Propriétaire Gîte 2 (synthétique, test)"
state: enabled
EOF'
docker exec "$CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-no-email.yaml <<EOF
fullname: "Compte sans adresse (synthétique, test)"
state: enabled
EOF'

log "pages synthétiques d'exclusion (jamais dans le dépôt, uniquement dans ce conteneur jetable)"
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/97.synth-no-email-owner && cat > /var/www/html/user/pages/03.gites/97.synth-no-email-owner/default.md <<EOF
---
title: "Synthétique — compte sans adresse"
template: gite-item
proprietaire: proprio-no-email
---
Page synthétique de test.
EOF'
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/98.synth-wrong-template && cat > /var/www/html/user/pages/03.gites/98.synth-wrong-template/default.md <<EOF
---
title: "Synthétique — mauvais template"
template: default
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/99.synth-no-owner && cat > /var/www/html/user/pages/03.gites/99.synth-no-owner/default.md <<EOF
---
title: "Synthétique — sans propriétaire"
template: gite-item
---
Page synthétique de test.
EOF'

log "pages/comptes synthétiques additionnels — durcissements (réservation, éligibilité, adresses, format de slug)"
docker exec "$CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-empty-email.yaml <<EOF
email: ""
fullname: "Compte adresse vide (synthétique, test)"
state: enabled
EOF'
docker exec "$CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-bad-email.yaml <<EOF
email: "not-an-email"
fullname: "Compte adresse invalide (synthétique, test)"
state: enabled
EOF'
docker exec "$CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-dup.yaml <<EOF
email: owner-dup@example.invalid
fullname: "Compte doublon (synthétique, test)"
state: enabled
EOF'
# Slug réservé "general" porté par une page de gîte : doit être exclu et
# journalisé, jamais autorisé à écraser l'option générale.
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/80.general && cat > /var/www/html/user/pages/03.gites/80.general/default.md <<EOF
---
title: "Collision avec l'\''identifiant réservé"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
# Identifiant hors du format accepté (espace, majuscule, ponctuation) —
# Grav ne normalise pas nécessairement un nom de dossier inhabituel en
# slug strictement conforme : validé explicitement par ce plugin.
docker exec "$CONTAINER" sh -c 'mkdir -p "/var/www/html/user/pages/03.gites/81.Gite_Format Invalide!" && cat > "/var/www/html/user/pages/03.gites/81.Gite_Format Invalide!/default.md" <<EOF
---
title: "Format de slug invalide"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
# Publiée mais explicitement non routable.
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/82.synth-not-routable && cat > /var/www/html/user/pages/03.gites/82.synth-not-routable/default.md <<EOF
---
title: "Synthétique — non routable"
template: gite-item
proprietaire: proprio-gite-1
routable: false
---
Page synthétique de test.
EOF'
# Non publiée (routable() en dépend déjà, mais couvre le cas nommément).
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/83.synth-unpublished && cat > /var/www/html/user/pages/03.gites/83.synth-unpublished/default.md <<EOF
---
title: "Synthétique — non publiée"
template: gite-item
proprietaire: proprio-gite-1
published: false
---
Page synthétique de test.
EOF'
# Compte sans adresse (chaîne vide, distincte du champ absent déjà couvert
# par synth-no-email-owner) et compte à adresse syntaxiquement invalide.
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/84.synth-empty-email && cat > /var/www/html/user/pages/03.gites/84.synth-empty-email/default.md <<EOF
---
title: "Synthétique — adresse vide"
template: gite-item
proprietaire: proprio-empty-email
---
Page synthétique de test.
EOF'
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/85.synth-bad-email && cat > /var/www/html/user/pages/03.gites/85.synth-bad-email/default.md <<EOF
---
title: "Synthétique — adresse invalide"
template: gite-item
proprietaire: proprio-bad-email
---
Page synthétique de test.
EOF'
# Profondeur inattendue : petit-enfant du sous-arbre des gîtes (enfant
# direct de gite-un), ne doit jamais être traité comme un gîte de premier
# niveau — seuls les enfants directs de gites_root le sont.
docker exec "$CONTAINER" sh -c 'mkdir -p "/var/www/html/user/pages/03.gites/01.gite-un/86.synth-grandchild" && cat > "/var/www/html/user/pages/03.gites/01.gite-un/86.synth-grandchild/default.md" <<EOF
---
title: "Synthétique — petit-enfant"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
# Doublon d'identifiant — politique fermée : deux (ou trois) pages
# distinctes produisant le même slug public sont TOUTES exclues (aucune
# option, aucune résolution), indépendamment de l'ordre de
# Pages::children() et indépendamment de la validité de leurs comptes
# respectifs. Grav dérive le slug du nom de dossier après le préfixe
# numérique — deux préfixes différents peuvent partager la même partie
# textuelle.
#
# Paire A ("synth-dup") : proprio-gite-1 (compte déjà valide) numéroté
# avant proprio-dup.
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/87.synth-dup && cat > /var/www/html/user/pages/03.gites/87.synth-dup/default.md <<EOF
---
title: "Doublon A — première page (numérotée avant)"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/88.synth-dup && cat > /var/www/html/user/pages/03.gites/88.synth-dup/default.md <<EOF
---
title: "Doublon A — seconde page (numérotée après)"
template: gite-item
proprietaire: proprio-dup
---
Page synthétique de test.
EOF'
# Paire B ("synth-dup-rev") : mêmes deux comptes que la paire A, mais
# ORDRE NUMÉRIQUE INVERSÉ — proprio-dup numéroté avant proprio-gite-1 —
# pour vérifier que le résultat (exclusion totale) ne dépend pas de
# l'ordre de Pages::children().
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/89.synth-dup-rev && cat > /var/www/html/user/pages/03.gites/89.synth-dup-rev/default.md <<EOF
---
title: "Doublon B — première page (ordre inversé)"
template: gite-item
proprietaire: proprio-dup
---
Page synthétique de test.
EOF'
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/90.synth-dup-rev && cat > /var/www/html/user/pages/03.gites/90.synth-dup-rev/default.md <<EOF
---
title: "Doublon B — seconde page (ordre inversé)"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
# Triplet ("synth-triple") : trois pages partageant le même identifiant,
# toutes avec un compte par ailleurs valide (proprio-gite-1) — vérifie
# qu'une collision à trois exclut également intégralement, sans
# tolérance particulière du seul fait que tous les comptes seraient
# individuellement valides.
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/91.synth-triple && cat > /var/www/html/user/pages/03.gites/91.synth-triple/default.md <<EOF
---
title: "Triplet — page 1"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/92.synth-triple && cat > /var/www/html/user/pages/03.gites/92.synth-triple/default.md <<EOF
---
title: "Triplet — page 2"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'
docker exec "$CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/03.gites/93.synth-triple && cat > /var/www/html/user/pages/03.gites/93.synth-triple/default.md <<EOF
---
title: "Triplet — page 3"
template: gite-item
proprietaire: proprio-gite-1
---
Page synthétique de test.
EOF'

docker exec "$CONTAINER" rm -rf /var/www/html/cache/*

# --- Aides -------------------------------------------------------------
# select_block URL : extrait le <select name="data[gite]">...</select> rendu.
select_block() {
  curl -s "http://localhost:$PORT$1" | python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'<select[^>]*name=\"data\[gite\]\"[^>]*>.*?</select>', html, re.S)
print(m.group(0) if m else '')
"
}

# render_and_extract_hidden URL JARFILE : GET la page, garde les champs
# hidden réels (nonce compris) dans un fichier de paires clé=valeur.
render_and_extract_hidden() {
  url="$1"; jar="$2"; out="$3"
  curl -s -c "$jar" -o "$out.html" "http://localhost:$PORT$url"
  grep -oE '<input[^>]*type="hidden"[^>]*>' "$out.html" | sed -E 's/.*name="([^"]*)".*value="([^"]*)".*/\1=\2/' > "$out.hidden"
}

# submit_contact LABEL RENDER_URL GITE_VALUE OMIT_GITE : soumet le
# formulaire avec le nonce réel extrait de RENDER_URL. Écrit le code HTTP
# dans $STATUS et le corps de réponse dans $RESP_FILE.
# Préfixe identifiable (pas un simple "tmp.XXXXXX") : permet de vérifier par
# préfixe contrôlé, sans glob générique, qu'aucun répertoire ne survit à
# cleanup() — voir la note de non-régression plus bas dans ce script.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/projet-gites-contact-routing.XXXXXX")"
submit_contact() {
  label="$1"; render_url="$2"; gite_value="$3"; omit_gite="${4:-no}"
  jar="$TMP/jar-$label"
  out="$TMP/form-$label"
  render_and_extract_hidden "$render_url" "$jar" "$out"

  set --
  while IFS='=' read -r hname hvalue; do
    [ -n "$hname" ] || continue
    set -- "$@" --data-urlencode "${hname}=${hvalue}"
  done < "$out.hidden"
  if [ "$omit_gite" != "omit" ]; then
    set -- "$@" --data-urlencode "data[gite]=${gite_value}"
  fi

  RESP_FILE="$TMP/resp-$label.html"
  hdr="$TMP/hdr-$label"
  curl -s -D "$hdr" -o "$RESP_FILE" -b "$jar" -c "$jar" -X POST "http://localhost:$PORT/contact" "$@" \
    --data-urlencode "data[nom]=Test $label" --data-urlencode "data[email]=visiteur@example.invalid" \
    --data-urlencode "data[telephone]=" --data-urlencode "data[date_arrivee]=" --data-urlencode "data[date_depart]=" \
    --data-urlencode "data[message]=Message de test ($label)." --data-urlencode "data[honeypot]="
  STATUS="$(head -1 "$hdr" | awk '{print $2}')"
}

mailpit_count() {
  curl -s "http://localhost:$MAILPIT_API_PORT/api/v1/messages" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('messages', [])))"
}

mailpit_clear() {
  curl -s -X DELETE "http://localhost:$MAILPIT_API_PORT/api/v1/messages" >/dev/null
}

mailpit_last_to() {
  curl -s "http://localhost:$MAILPIT_API_PORT/api/v1/messages" | python3 -c "
import json, sys
d = json.load(sys.stdin)
msgs = d.get('messages', [])
print(msgs[0]['To'][0]['Address'] if msgs and msgs[0].get('To') else '')
"
}

mailpit_last_reply_to() {
  curl -s "http://localhost:$MAILPIT_API_PORT/api/v1/messages" | python3 -c "
import json, sys
d = json.load(sys.stdin)
msgs = d.get('messages', [])
rt = msgs[0].get('ReplyTo') if msgs else None
print(rt[0]['Address'] if rt else '')
"
}

# mailpit_last_body : corps HTML/texte réel du dernier message capturé —
# ce qui a réellement été envoyé, pas ce qui a été soumis.
mailpit_last_body() {
  mid="$(curl -s "http://localhost:$MAILPIT_API_PORT/api/v1/messages" | python3 -c "import json,sys; d=json.load(sys.stdin); m=d.get('messages',[]); print(m[0]['ID'] if m else '')")"
  [ -n "$mid" ] || { echo ""; return; }
  curl -s "http://localhost:$MAILPIT_API_PORT/api/v1/message/$mid" | python3 -c "import json,sys; m=json.load(sys.stdin); print(m.get('HTML') or m.get('Text') or '')"
}

# submit_contact_custom LABEL RENDER_URL GITE_VALUE NOM EMAIL MESSAGE :
# variante de submit_contact avec des valeurs nom/email/message
# personnalisées (matrice XSS/CRLF). Mêmes sorties $STATUS / $RESP_FILE.
submit_contact_custom() {
  label="$1"; render_url="$2"; gite_value="$3"; nom_value="$4"; email_value="$5"; message_value="$6"
  jar="$TMP/jar-$label"
  out="$TMP/form-$label"
  render_and_extract_hidden "$render_url" "$jar" "$out"

  set --
  while IFS='=' read -r hname hvalue; do
    [ -n "$hname" ] || continue
    set -- "$@" --data-urlencode "${hname}=${hvalue}"
  done < "$out.hidden"
  set -- "$@" --data-urlencode "data[gite]=${gite_value}"

  RESP_FILE="$TMP/resp-$label.html"
  hdr="$TMP/hdr-$label"
  curl -s -D "$hdr" -o "$RESP_FILE" -b "$jar" -c "$jar" -X POST "http://localhost:$PORT/contact" "$@" \
    --data-urlencode "data[nom]=${nom_value}" --data-urlencode "data[email]=${email_value}" \
    --data-urlencode "data[telephone]=" --data-urlencode "data[date_arrivee]=" --data-urlencode "data[date_depart]=" \
    --data-urlencode "data[message]=${message_value}" --data-urlencode "data[honeypot]="
  STATUS="$(head -1 "$hdr" | awk '{print $2}')"
}

# grav_log_contains PATTERN : vrai si le journal serveur (grav['log'],
# jamais transmis au visiteur) contient ce motif — utilisé pour vérifier
# qu'une anomalie de configuration est bien signalée, sans jamais faire
# apparaître d'adresse dans les assertions elles-mêmes.
grav_log_contains() {
  docker exec "$CONTAINER" grep -qF "$1" /var/www/html/logs/grav.log 2>/dev/null
}

# ===========================================================================
# A. Présentation
# ===========================================================================
log "A1 — champ visible (select, pas hidden) sur /contact"
block_contact="$(select_block /contact)"
[ -n "$block_contact" ] || fail "A1 : aucun <select name=\"data[gite]\"> trouvé sur /contact"
echo "$block_contact" | grep -q '<select' || fail "A1 : le champ gite n'est pas un <select>"

log "A2 — label associé, présent et explicite"
contact_html="$(curl -s "http://localhost:$PORT/contact")"
echo "$contact_html" | grep -qF 'Gîte concerné' || fail "A2 : libellé 'Gîte concerné' absent"

log "A3 — les deux gîtes réels et l'option générale sont présents"
echo "$block_contact" | grep -qF 'value="gite-un"' || fail "A3 : option gite-un absente"
echo "$block_contact" | grep -qF 'value="gite-deux"' || fail "A3 : option gite-deux absente"
echo "$block_contact" | grep -qF 'value="general"' || fail "A3 : option générale absente"

log "A4 — aucune adresse ni identifiant de compte dans le HTML rendu"
for leak in "proprio-gite-1" "proprio-gite-2" "owner1@example.invalid" "owner2@example.invalid" "admin@lavallee.tech"; do
  echo "$contact_html" | grep -qF "$leak" && fail "A4 : '$leak' apparaît dans le HTML rendu de /contact"
done
log "A4 : aucune fuite de compte/adresse dans /contact"

log "A5 — pages synthétiques inéligibles absentes des options (sans propriétaire / mauvais template / compte sans adresse / non routable / non publiée / adresse vide ou invalide / profondeur inattendue / slug hors format)"
for leak in "synth-no-owner" "synth-wrong-template" "synth-no-email-owner" "synth-not-routable" "synth-unpublished" "synth-empty-email" "synth-bad-email" "synth-grandchild"; do
  echo "$block_contact" | grep -qF "value=\"$leak\"" && fail "A5 : option inattendue '$leak' présente (page non éligible)"
done
echo "$block_contact" | grep -qF 'Format Invalide' && fail "A5 : la page au slug hors format est présente dans les options"
log "A5 : les huit catégories de pages inéligibles sont toutes absentes des options"

log "A6 — fiche gîte 1 : gite-un présélectionné"
block_un="$(select_block /gites/gite-un)"
echo "$block_un" | grep -qF 'selected="selected" value="gite-un"' \
  || fail "A6 : gite-un n'est pas présélectionné sur /gites/gite-un"

log "A7 — fiche gîte 2 : gite-deux présélectionné"
block_deux="$(select_block /gites/gite-deux)"
echo "$block_deux" | grep -qF 'selected="selected" value="gite-deux"' \
  || fail "A7 : gite-deux n'est pas présélectionné sur /gites/gite-deux"

log "A8 — /contact autonome : aucun gîte présélectionné par défaut (option vide)"
echo "$block_contact" | grep -qF 'selected="selected" value=""' \
  || fail "A8 : /contact ne présélectionne pas l'option vide par défaut"

log "A9 — la page au slug réservé 'general' n'a pas écrasé l'option générale"
general_option_line="$(echo "$block_contact" | grep -F 'value="general"')"
echo "$general_option_line" | grep -qF 'Demande générale' \
  || fail "A9 : l'option 'general' ne porte plus son libellé standard — possible écrasement par la page de collision"
echo "$general_option_line" | grep -qF "Collision avec l'identifiant réservé" \
  && fail "A9 (RÉGRESSION) : le titre de la page de collision est apparu dans l'option générale"

log "A10 — identifiant en doublon (2 pages) : exclusion totale, aucune option, quel que soit l'ordre"
echo "$block_contact" | grep -qF 'value="synth-dup"' \
  && fail "A10 : l'identifiant 'synth-dup' (collisionné) est présent dans les options — attendu absent"
echo "$block_contact" | grep -qF 'value="synth-dup-rev"' \
  && fail "A10 : l'identifiant 'synth-dup-rev' (collisionné, ordre inversé) est présent dans les options — attendu absent"
echo "$block_contact" | grep -qF 'Doublon' \
  && fail "A10 : un libellé de page en collision est apparu dans les options"

log "A11 — identifiant en triplet (3 pages) : exclusion totale, aucune option"
echo "$block_contact" | grep -qF 'value="synth-triple"' \
  && fail "A11 : l'identifiant 'synth-triple' (collisionné à trois) est présent dans les options — attendu absent"
echo "$block_contact" | grep -qF 'Triplet' \
  && fail "A11 : un libellé de page en collision (triplet) est apparu dans les options"

log "présentation OK"

# ===========================================================================
# B. Routage nominal
# ===========================================================================
mailpit_clear
log "B1 — sélection gîte 1 depuis sa propre fiche -> propriétaire 1"
submit_contact "b1" "/gites/gite-un" "gite-un"
[ "$STATUS" = "302" ] || fail "B1 : soumission valide attendue 302, obtenu $STATUS"
[ "$(mailpit_last_to)" = "owner1@example.invalid" ] || fail "B1 : destinataire attendu owner1@example.invalid, obtenu '$(mailpit_last_to)'"
[ "$(mailpit_last_reply_to)" = "visiteur@example.invalid" ] || fail "B1 : Reply-To attendu visiteur@example.invalid"

mailpit_clear
log "B2 — sélection gîte 2 depuis sa propre fiche -> propriétaire 2"
submit_contact "b2" "/gites/gite-deux" "gite-deux"
[ "$STATUS" = "302" ] || fail "B2 : soumission valide attendue 302, obtenu $STATUS"
[ "$(mailpit_last_to)" = "owner2@example.invalid" ] || fail "B2 : destinataire attendu owner2@example.invalid, obtenu '$(mailpit_last_to)'"

mailpit_clear
log "B3 — changement visible de gîte 1 vers gîte 2 (choix explicite, légitime) -> propriétaire 2"
submit_contact "b3" "/gites/gite-un" "gite-deux"
[ "$STATUS" = "302" ] || fail "B3 : soumission valide attendue 302, obtenu $STATUS"
[ "$(mailpit_last_to)" = "owner2@example.invalid" ] || fail "B3 : destinataire attendu owner2@example.invalid, obtenu '$(mailpit_last_to)'"

mailpit_clear
log "B4 — contact général depuis /contact -> repli global explicite (plugins.email.to)"
submit_contact "b4" "/contact" "general"
[ "$STATUS" = "302" ] || fail "B4 : soumission valide attendue 302, obtenu $STATUS"
[ "$(mailpit_last_to)" = "admin@lavallee.tech" ] || fail "B4 : destinataire attendu admin@lavallee.tech, obtenu '$(mailpit_last_to)'"

log "routage nominal OK — 4 e-mails, chacun vers le seul destinataire attendu"

# ===========================================================================
# C. Entrées invalides — aucune ne doit produire d'e-mail
# ===========================================================================
mailpit_clear
log "C1 — champ gite absent"
submit_contact "c1" "/gites/gite-un" "" omit
[ "$STATUS" = "200" ] || fail "C1 : attendu 200 (validation échouée), obtenu $STATUS"

log "C2 — valeur vide"
submit_contact "c2" "/gites/gite-un" ""
[ "$STATUS" = "200" ] || fail "C2 : attendu 200 (validation échouée), obtenu $STATUS"

log "C3 — identifiant inconnu"
submit_contact "c3" "/gites/gite-un" "gite-inexistant"
[ "$STATUS" = "200" ] || fail "C3 : attendu 200 (validation échouée), obtenu $STATUS"

log "C4 — identifiant malformé"
submit_contact "c4" "/gites/gite-un" "../../etc/passwd"
[ "$STATUS" = "200" ] || fail "C4 : attendu 200 (validation échouée), obtenu $STATUS"

log "C5 — ancienne route brute (défaut historique SEC-GITES-001)"
submit_contact "c5" "/gites/gite-un" "/gites/gite-deux"
[ "$STATUS" = "200" ] || fail "C5 (RÉGRESSION SEC-GITES-001) : une route brute a été acceptée — attendu 200, obtenu $STATUS"

log "C6 — tentative d'utiliser un nom de compte Grav"
submit_contact "c6" "/gites/gite-un" "proprio-gite-2"
[ "$STATUS" = "200" ] || fail "C6 : attendu 200 (validation échouée), obtenu $STATUS"

log "C7 — tentative d'utiliser une adresse e-mail"
submit_contact "c7" "/gites/gite-un" "owner2@example.invalid"
[ "$STATUS" = "200" ] || fail "C7 : attendu 200 (validation échouée), obtenu $STATUS"

log "C8 — page hors du sous-arbre des gîtes"
submit_contact "c8" "/gites/gite-un" "admin"
[ "$STATUS" = "200" ] || fail "C8 : attendu 200 (validation échouée), obtenu $STATUS"

log "C9 — page sans propriétaire (synthétique)"
submit_contact "c9" "/gites/gite-un" "synth-no-owner"
[ "$STATUS" = "200" ] || fail "C9 : attendu 200 (validation échouée), obtenu $STATUS"

log "C10 — page avec mauvais template (synthétique)"
submit_contact "c10" "/gites/gite-un" "synth-wrong-template"
[ "$STATUS" = "200" ] || fail "C10 : attendu 200 (validation échouée), obtenu $STATUS"

log "C11 — compte propriétaire sans adresse (synthétique)"
submit_contact "c11" "/gites/gite-un" "synth-no-email-owner"
[ "$STATUS" = "200" ] || fail "C11 : attendu 200 (validation échouée), obtenu $STATUS"

sent="$(mailpit_count)"
[ "$sent" -eq 0 ] || fail "C : $sent e-mail(s) envoyé(s) alors qu'aucune des 11 entrées invalides ne devait en produire"
log "entrées invalides OK — 11 cas rejetés, 0 e-mail envoyé"

# ===========================================================================
# D. Sécurité et formulaire
# ===========================================================================
mailpit_clear
log "D1 — nonce/CSRF absent"
jar="$TMP/jar-d1"; out="$TMP/form-d1"
render_and_extract_hidden "/gites/gite-un" "$jar" "$out"
grep -v '^form-nonce=' "$out.hidden" > "$out.hidden.noncestripped" || true
set --
while IFS='=' read -r hname hvalue; do
  [ -n "$hname" ] || continue
  set -- "$@" --data-urlencode "${hname}=${hvalue}"
done < "$out.hidden.noncestripped"
d1_status="$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" -X POST "http://localhost:$PORT/contact" "$@" \
  --data-urlencode "data[gite]=gite-un" --data-urlencode "data[nom]=D1" \
  --data-urlencode "data[email]=visiteur@example.invalid" --data-urlencode "data[message]=msg" --data-urlencode "data[honeypot]=")"
[ "$d1_status" = "200" ] || fail "D1 : nonce absent, attendu 200 (rejeté par Grav Core), obtenu $d1_status"

log "D2 — nonce/CSRF invalide"
jar2="$TMP/jar-d2"; out2="$TMP/form-d2"
render_and_extract_hidden "/gites/gite-un" "$jar2" "$out2"
d2_status="$(curl -s -o /dev/null -w '%{http_code}' -b "$jar2" -c "$jar2" -X POST "http://localhost:$PORT/contact" \
  --data-urlencode "data[gite]=gite-un" --data-urlencode "data[nom]=D2" \
  --data-urlencode "data[email]=visiteur@example.invalid" --data-urlencode "data[message]=msg" --data-urlencode "data[honeypot]=" \
  --data-urlencode "form-nonce=deliberement-invalide")"
[ "$d2_status" = "200" ] || fail "D2 : nonce invalide, attendu 200 (rejeté par Grav Core), obtenu $d2_status"

log "D3 — honeypot rempli"
jar3="$TMP/jar-d3"; out3="$TMP/form-d3"
render_and_extract_hidden "/gites/gite-un" "$jar3" "$out3"
set --
while IFS='=' read -r hname hvalue; do
  [ -n "$hname" ] || continue
  set -- "$@" --data-urlencode "${hname}=${hvalue}"
done < "$out3.hidden"
d3_status="$(curl -s -o /dev/null -w '%{http_code}' -b "$jar3" -c "$jar3" -X POST "http://localhost:$PORT/contact" "$@" \
  --data-urlencode "data[gite]=gite-un" --data-urlencode "data[nom]=D3" \
  --data-urlencode "data[email]=visiteur@example.invalid" --data-urlencode "data[message]=msg" --data-urlencode "data[honeypot]=je-suis-un-robot")"
[ "$d3_status" = "200" ] || fail "D3 : honeypot rempli, attendu 200 (rejeté), obtenu $d3_status"

log "D4 — injection CRLF dans un champ (en-têtes de l'e-mail)"
jar4="$TMP/jar-d4"; out4="$TMP/form-d4"
render_and_extract_hidden "/gites/gite-un" "$jar4" "$out4"
set --
while IFS='=' read -r hname hvalue; do
  [ -n "$hname" ] || continue
  set -- "$@" --data-urlencode "${hname}=${hvalue}"
done < "$out4.hidden"
d4_status="$(curl -s -o /dev/null -w '%{http_code}' -b "$jar4" -c "$jar4" -X POST "http://localhost:$PORT/contact" "$@" \
  --data-urlencode "data[gite]=gite-un" \
  --data-urlencode "$(printf 'data[nom]=Injected\r\nBcc: attacker@evil.invalid')" \
  --data-urlencode "data[email]=visiteur@example.invalid" --data-urlencode "data[message]=msg" --data-urlencode "data[honeypot]=")"
[ "$d4_status" = "200" ] || fail "D4 : injection CRLF, attendu 200 (rejeté par la validation de champ de Grav Form), obtenu $d4_status"

sent_d="$(mailpit_count)"
[ "$sent_d" -eq 0 ] || fail "D : $sent_d e-mail(s) envoyé(s) alors qu'aucun des cas D1-D4 ne devait en produire"
log "sécurité et formulaire OK — nonce absent/invalide, honeypot et CRLF tous rejetés, 0 e-mail envoyé"

# ===========================================================================
# E. Réservation de `general` et collisions d'identifiants
# ===========================================================================
log "E1 — page au slug hors format : exclusion journalisée côté serveur"
grav_log_contains "hors du format accepté" \
  || fail "E1 : aucune entrée de journal ne signale le slug hors format"

log "E2 — page au slug réservé 'general' : exclusion journalisée côté serveur"
grav_log_contains "utilise le slug réservé 'general'" \
  || fail "E2 : aucune entrée de journal ne signale la collision avec l'identifiant réservé"

log "E3 — doublon d'identifiant (2 pages, ordre nominal) : exclusion journalisée côté serveur, sans adresse ni username"
grav_log_contains "identifiant public 'synth-dup' collisionné entre 2 pages" \
  || fail "E3 : aucune entrée de journal ne signale le doublon 'synth-dup'"
for leak in "owner1@example.invalid" "owner-dup@example.invalid" "proprio-gite-1" "proprio-dup"; do
  grav_log_contains "$leak" && fail "E3 : '$leak' apparaît dans le journal serveur — le diagnostic doit rester générique"
done

log "E3-bis — doublon d'identifiant, ordre inversé : même résultat (exclusion journalisée)"
grav_log_contains "identifiant public 'synth-dup-rev' collisionné entre 2 pages" \
  || fail "E3-bis : aucune entrée de journal ne signale le doublon 'synth-dup-rev' (ordre inversé)"

log "E3-ter — triplet d'identifiant (3 pages) : exclusion journalisée"
grav_log_contains "identifiant public 'synth-triple' collisionné entre 3 pages" \
  || fail "E3-ter : aucune entrée de journal ne signale le triplet 'synth-triple'"

mailpit_clear
log "E4 — soumission forcée de l'identifiant collisionné 'synth-dup' : rejetée, aucun destinataire, aucun e-mail"
submit_contact "e4" "/gites/gite-un" "synth-dup"
[ "$STATUS" = "200" ] || fail "E4 : attendu 200 (rejeté, identifiant collisionné), obtenu $STATUS"

log "E4-bis — soumission forcée de l'identifiant collisionné 'synth-dup-rev' (ordre inversé) : rejetée"
submit_contact "e4bis" "/gites/gite-un" "synth-dup-rev"
[ "$STATUS" = "200" ] || fail "E4-bis : attendu 200 (rejeté, identifiant collisionné), obtenu $STATUS"

log "E4-ter — soumission forcée de l'identifiant collisionné 'synth-triple' : rejetée"
submit_contact "e4ter" "/gites/gite-un" "synth-triple"
[ "$STATUS" = "200" ] || fail "E4-ter : attendu 200 (rejeté, identifiant collisionné), obtenu $STATUS"

sent_e4="$(mailpit_count)"
[ "$sent_e4" -eq 0 ] || fail "E4 : $sent_e4 e-mail(s) envoyé(s) alors qu'aucun identifiant collisionné ne devait en produire"

mailpit_clear
log "E5 — 'general' ne peut jamais résoudre vers un propriétaire de gîte, même sélectionné depuis une fiche de gîte"
submit_contact "e5" "/gites/gite-un" "general"
[ "$STATUS" = "302" ] || fail "E5 : soumission valide attendue 302, obtenu $STATUS"
[ "$(mailpit_last_to)" = "admin@lavallee.tech" ] \
  || fail "E5 (RÉGRESSION) : 'general' n'a pas résolu vers l'adresse générale, obtenu '$(mailpit_last_to)'"
log "réservation de 'general' et collisions (fermées, y compris ordre inversé et triplet) OK"

# ===========================================================================
# F. Éligibilité approfondie — rejet à la soumission (défense en profondeur,
# au-delà de la simple absence des options — voir aussi A5)
# ===========================================================================
mailpit_clear
log "F1 — page publiée mais non routable (routable: false)"
submit_contact "f1" "/gites/gite-un" "synth-not-routable"
[ "$STATUS" = "200" ] || fail "F1 : attendu 200 (validation échouée), obtenu $STATUS"

log "F2 — page non publiée (routable() en dépend déjà — voir contact.php)"
submit_contact "f2" "/gites/gite-un" "synth-unpublished"
[ "$STATUS" = "200" ] || fail "F2 : attendu 200 (validation échouée), obtenu $STATUS"

log "F3 — profondeur inattendue : petit-enfant du sous-arbre, jamais un gîte de premier niveau"
submit_contact "f3" "/gites/gite-un" "synth-grandchild"
[ "$STATUS" = "200" ] || fail "F3 : attendu 200 (validation échouée), obtenu $STATUS"

log "F4 — identifiant hors du format accepté, soumis directement (défense en profondeur)"
submit_contact "f4" "/gites/gite-un" "gite_weird name!"
[ "$STATUS" = "200" ] || fail "F4 : attendu 200 (validation échouée), obtenu $STATUS"

sent_f="$(mailpit_count)"
[ "$sent_f" -eq 0 ] || fail "F : $sent_f e-mail(s) envoyé(s) alors qu'aucun des cas F1-F4 ne devait en produire"
log "éligibilité approfondie OK — 4 cas rejetés, 0 e-mail envoyé"

# ===========================================================================
# G. Validation des adresses propriétaires — rejet à la soumission
# ===========================================================================
mailpit_clear
log "G1 — compte propriétaire à adresse vide (distinct du champ absent, déjà C11)"
submit_contact "g1" "/gites/gite-un" "synth-empty-email"
[ "$STATUS" = "200" ] || fail "G1 : attendu 200 (validation échouée), obtenu $STATUS"

log "G2 — compte propriétaire à adresse syntaxiquement invalide"
submit_contact "g2" "/gites/gite-un" "synth-bad-email"
[ "$STATUS" = "200" ] || fail "G2 : attendu 200 (validation échouée), obtenu $STATUS"

sent_g="$(mailpit_count)"
[ "$sent_g" -eq 0 ] || fail "G : $sent_g e-mail(s) envoyé(s) alors qu'aucun des cas G1-G2 ne devait en produire"
log "validation des adresses propriétaires OK — 2 cas rejetés, 0 e-mail envoyé"

# ===========================================================================
# H. Option générale conditionnelle à une adresse serveur valide
# (plugins.email.to) — conteneurs jetables dédiés, réutilisant le même
# réseau et Mailpit déjà démarrés.
# ===========================================================================
run_general_address_scenario() {
  scenario_label="$1"; email_yaml_content="$2"
  h_container="projet-gites-test-contact-h-$scenario_label"
  h_fixture="$TMP/email-$scenario_label.yaml"
  printf '%s' "$email_yaml_content" > "$h_fixture"

  docker rm -f "$h_container" >/dev/null 2>&1 || true
  docker run -d --name "$h_container" --network "$NETWORK" -p "18092:80" \
    -e GRAV_ADMIN_USER=admin -e GRAV_ADMIN_PASSWORD=ChangeMe123 -e GRAV_ADMIN_EMAIL=admin@example.com \
    -v "$FIXTURE_EMAIL_PRIVATE:/var/www/html/user/config/email-private.php:ro" \
    -v "$h_fixture:/var/www/html/user/config/plugins/email.yaml:ro" \
    "$IMAGE" >/dev/null
  wait_healthy "$h_container" 30
  docker exec "$h_container" sh -c 'cat > /var/www/html/user/accounts/proprio-gite-1.yaml <<EOF
email: owner1@example.invalid
state: enabled
EOF'
  docker exec "$h_container" rm -rf /var/www/html/cache/*

  H_OPTIONS="$(curl -s "http://localhost:18092/contact" | python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'<select[^>]*name=\"data\[gite\]\"[^>]*>.*?</select>', html, re.S)
print(m.group(0) if m else '')
")"

  jar="$TMP/jar-h-$scenario_label"; out="$TMP/form-h-$scenario_label"
  curl -s -c "$jar" -o "$out.html" "http://localhost:18092/contact"
  grep -oE '<input[^>]*type="hidden"[^>]*>' "$out.html" | sed -E 's/.*name="([^"]*)".*value="([^"]*)".*/\1=\2/' > "$out.hidden"
  set --
  while IFS='=' read -r hname hvalue; do
    [ -n "$hname" ] || continue
    set -- "$@" --data-urlencode "${hname}=${hvalue}"
  done < "$out.hidden"
  H_FORCE_STATUS="$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" -X POST "http://localhost:18092/contact" "$@" \
    --data-urlencode "data[gite]=general" --data-urlencode "data[nom]=H-$scenario_label" \
    --data-urlencode "data[email]=visiteur@example.invalid" --data-urlencode "data[message]=msg" --data-urlencode "data[honeypot]=")"

  docker rm -f "$h_container" >/dev/null 2>&1
}

mailpit_clear
log "H1 — adresse générale absente (plugins.email.to non défini) : option absente, soumission forcée rejetée"
run_general_address_scenario "absent" "from: admin@lavallee.tech
from_name: 'Site Gîtes'
mailer:
  engine: smtp
content_type: text/html
"
echo "$H_OPTIONS" | grep -qF 'value="general"' && fail "H1 : l'option générale est présente alors qu'aucune adresse n'est configurée"
[ "$H_FORCE_STATUS" = "200" ] || fail "H1 : soumission forcée de 'general' sans adresse configurée, attendu 200, obtenu $H_FORCE_STATUS"

log "H2 — adresse générale vide (to: \"\") : option absente, soumission forcée rejetée"
run_general_address_scenario "empty" "from: admin@lavallee.tech
from_name: 'Site Gîtes'
to: \"\"
mailer:
  engine: smtp
content_type: text/html
"
echo "$H_OPTIONS" | grep -qF 'value="general"' && fail "H2 : l'option générale est présente alors que l'adresse est vide"
[ "$H_FORCE_STATUS" = "200" ] || fail "H2 : soumission forcée de 'general' avec adresse vide, attendu 200, obtenu $H_FORCE_STATUS"

log "H3 — adresse générale syntaxiquement invalide : option absente, soumission forcée rejetée"
run_general_address_scenario "invalid" "from: admin@lavallee.tech
from_name: 'Site Gîtes'
to: \"not-an-email\"
mailer:
  engine: smtp
content_type: text/html
"
echo "$H_OPTIONS" | grep -qF 'value="general"' && fail "H3 : l'option générale est présente alors que l'adresse est invalide"
[ "$H_FORCE_STATUS" = "200" ] || fail "H3 : soumission forcée de 'general' avec adresse invalide, attendu 200, obtenu $H_FORCE_STATUS"

sent_h="$(mailpit_count)"
[ "$sent_h" -eq 0 ] || fail "H : $sent_h e-mail(s) envoyé(s) alors qu'aucun des cas H1-H3 ne devait en produire"
log "option générale conditionnelle OK — absente dans les 3 cas défaillants, aucune soumission forcée acceptée"

# ===========================================================================
# J. Matrice XSS / CRLF détaillée — attribution précise par cas
# ===========================================================================
mailpit_clear
log "J1 — balise HTML non-script dans nom : ACCEPTÉE par Grav Form, ÉCHAPPÉE à l'affichage (Twig, sujet + corps)"
submit_contact_custom "j1" "/gites/gite-un" "gite-un" '<b>bold</b>' "visiteur@example.invalid" "message normal"
[ "$STATUS" = "302" ] || fail "J1 : attendu 302 (accepté), obtenu $STATUS"
[ "$(mailpit_last_to)" = "owner1@example.invalid" ] || fail "J1 : destinataire inattendu"
body_j1="$(mailpit_last_body)"
echo "$body_j1" | grep -qF '<b>bold</b>' && fail "J1 (RÉGRESSION) : la balise HTML est présente non échappée dans le sujet/corps envoyé"
echo "$body_j1" | grep -qF '&lt;b&gt;bold&lt;/b&gt;' || fail "J1 : la balise attendue échappée n'apparaît pas — vérifier manuellement le sujet capturé par Mailpit"

mailpit_clear
log "J2 — balise <script> dans nom : REJETÉE par la validation de champ de Grav Form (aucun e-mail)"
submit_contact_custom "j2" "/gites/gite-un" "gite-un" '<script>alert(1)</script>' "visiteur@example.invalid" "message normal"
[ "$STATUS" = "200" ] || fail "J2 : attendu 200 (rejeté), obtenu $STATUS"

mailpit_clear
log "J3 — balise HTML non-script dans message : ACCEPTÉE par Grav Form, ÉCHAPPÉE par le filtre |e de contact-email.html.twig"
submit_contact_custom "j3" "/gites/gite-un" "gite-un" "Nom normal" "visiteur@example.invalid" '<b>bold</b> content'
[ "$STATUS" = "302" ] || fail "J3 : attendu 302 (accepté), obtenu $STATUS"
body_j3="$(mailpit_last_body)"
echo "$body_j3" | grep -qF '<b>bold</b>' && fail "J3 (RÉGRESSION) : la balise HTML est présente non échappée dans le corps envoyé"
echo "$body_j3" | grep -qF '&lt;b&gt;bold&lt;/b&gt;' || fail "J3 : le corps échappé attendu n'apparaît pas"

mailpit_clear
log "J4 — balise <script> dans message : REJETÉE par la validation de champ de Grav Form (aucun e-mail)"
submit_contact_custom "j4" "/gites/gite-un" "gite-un" "Nom normal" "visiteur@example.invalid" '<script>alert(2)</script>'
[ "$STATUS" = "200" ] || fail "J4 : attendu 200 (rejeté), obtenu $STATUS"

# J5.x — rejet CRLF explicite et applicatif (email/nom), voir
# ContactPlugin::onFormValidationProcessed(). Six cas distincts : CR seul,
# LF seul, CRLF, dans chacun des deux champs. Attribution après ce
# durcissement : le REJET est désormais un contrôle applicatif de ce
# plugin contact (projet-gites), avant tout traitement — PHPMailer
# (constat historique conservé en J5-historique ci-dessous) restait une
# protection complémentaire en aval, plus la seule barrière.
mailpit_clear
log "J5.1 — CR seul dans email : rejetée par le plugin, aucun e-mail, aucun en-tête, rien de sensible journalisé"
submit_contact_custom "j5-1" "/gites/gite-un" "gite-un" "Nom normal" "$(printf 'visiteur@example.invalid\rBcc: attacker@evil.invalid')" "message normal"
[ "$STATUS" = "200" ] || fail "J5.1 : attendu 200 (rejeté), obtenu $STATUS"

log "J5.2 — LF seul dans email : rejetée"
submit_contact_custom "j5-2" "/gites/gite-un" "gite-un" "Nom normal" "$(printf 'visiteur@example.invalid\nBcc: attacker@evil.invalid')" "message normal"
[ "$STATUS" = "200" ] || fail "J5.2 : attendu 200 (rejeté), obtenu $STATUS"

log "J5.3 — CRLF dans email : rejetée"
submit_contact_custom "j5-3" "/gites/gite-un" "gite-un" "Nom normal" "$(printf 'visiteur@example.invalid\r\nBcc: attacker@evil.invalid')" "message normal"
[ "$STATUS" = "200" ] || fail "J5.3 : attendu 200 (rejeté), obtenu $STATUS"

log "J5.4 — CR seul dans nom : rejetée"
submit_contact_custom "j5-4" "/gites/gite-un" "gite-un" "$(printf 'Injected\rBcc: attacker@evil.invalid')" "visiteur@example.invalid" "message normal"
[ "$STATUS" = "200" ] || fail "J5.4 : attendu 200 (rejeté), obtenu $STATUS"

log "J5.5 — LF seul dans nom : rejetée"
submit_contact_custom "j5-5" "/gites/gite-un" "gite-un" "$(printf 'Injected\nBcc: attacker@evil.invalid')" "visiteur@example.invalid" "message normal"
[ "$STATUS" = "200" ] || fail "J5.5 : attendu 200 (rejeté), obtenu $STATUS"

log "J5.6 — CRLF dans nom : rejetée"
submit_contact_custom "j5-6" "/gites/gite-un" "gite-un" "$(printf 'Injected\r\nBcc: attacker@evil.invalid')" "visiteur@example.invalid" "message normal"
[ "$STATUS" = "200" ] || fail "J5.6 : attendu 200 (rejeté), obtenu $STATUS"

sent_j5="$(mailpit_count)"
[ "$sent_j5" -eq 0 ] || fail "J5 : $sent_j5 e-mail(s) envoyé(s) alors qu'aucun des 6 cas CR/LF/CRLF ne devait en produire"
for leak in "attacker@evil.invalid" "Injected"; do
  grav_log_contains "$leak" && fail "J5 : '$leak' apparaît dans le journal serveur — la valeur fautive ne doit jamais y être réaffichée"
done
log "J5 : les 6 cas CR/LF/CRLF (email × nom) rejetés par le plugin, 0 e-mail, aucune valeur fautive journalisée"

mailpit_clear
log "J5-historique — constat conservé : avant ce durcissement, un CRLF dans email franchissait la validation de champ de Grav Form mais était neutralisé par PHPMailer (Reply-To supprimé, aucun Bcc/Cc injecté). Revérifié ici : la requête n'atteint même plus PHPMailer, elle est rejetée en amont par le plugin (J5.3 ci-dessus) — PHPMailer reste une protection complémentaire observée, plus la seule barrière."

mailpit_clear
log "J7 — caractères Unicode normaux (accents, japonais, émojis) dans nom et message : ACCEPTÉS et délivrés fidèlement, aucune protection nécessaire"
submit_contact_custom "j7" "/gites/gite-un" "gite-un" 'Théo Müller — 日本語 émojis 🏡' "visiteur@example.invalid" 'Café à côté, très bien situé — 素晴らしい 🎉'
[ "$STATUS" = "302" ] || fail "J7 : attendu 302 (accepté), obtenu $STATUS"
body_j7="$(mailpit_last_body)"
echo "$body_j7" | grep -qF '素晴らしい' || fail "J7 : le contenu Unicode n'a pas été délivré fidèlement"

sent_j="$(mailpit_count)"
log "matrice XSS/CRLF détaillée OK (4 cas XSS + 6 cas CRLF + 1 cas Unicode = 11 cas, $sent_j e-mail(s) parmi les cas acceptés de ce dernier bloc)"

# ===========================================================================
# K. Deux formulaires rendus dans une même requête — vérification empirique,
# pas seulement théorique, de l'absence de fuite de présélection entre deux
# instances de contact_form. Nécessite un template de test synthétique
# (jamais commité — écrit uniquement dans ce conteneur jetable) : aucune
# page réelle du site n'embarque deux formulaires aujourd'hui.
#
# Portée assumée : ceci démontre l'ABSENCE DE FUITE OBSERVÉE dans un cas
# construit qui imite la structure réelle (deux inclusions successives de
# forms('contact-form') + setData() + rendu immédiat sur UNE même page).
# Cela ne démontre pas l'absence de partage d'instance au niveau de
# l'objet Form lui-même (voir le rapport : le cœur Grav met en cache
# activement cette instance par route+nom) — seulement que l'EFFET visible
# (une présélection erronée) ne se produit pas, très probablement parce que
# Twig rend chaque bloc immédiatement et de façon synchrone avant que le
# bloc suivant ne modifie l'objet. Formulation retenue : « Aucun partage
# incorrect n'a été observé dans la structure actuelle, qui rend une seule
# fiche de gîte par requête. Le comportement avec plusieurs inclusions a
# été observé une fois, dans un cas construit, pas démontré comme une
# garantie générale. »
# ===========================================================================
K_CONTAINER="projet-gites-test-contact-k-multiform"
docker rm -f "$K_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$K_CONTAINER" --network "$NETWORK" -p "18093:80" \
  -e GRAV_ADMIN_USER=admin -e GRAV_ADMIN_PASSWORD=ChangeMe123 -e GRAV_ADMIN_EMAIL=admin@example.com \
  "$IMAGE" >/dev/null
wait_healthy "$K_CONTAINER" 30
docker exec "$K_CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-gite-1.yaml <<EOF
email: owner1@example.invalid
state: enabled
EOF'
docker exec "$K_CONTAINER" sh -c 'cat > /var/www/html/user/accounts/proprio-gite-2.yaml <<EOF
email: owner2@example.invalid
state: enabled
EOF'
docker exec "$K_CONTAINER" sh -c 'mkdir -p /var/www/html/user/pages/09.synth-multiform && cat > /var/www/html/user/pages/09.synth-multiform/default.md <<EOF
---
title: "Synthétique — deux formulaires"
template: default
---
EOF'
# Gabarit de test écrit uniquement dans ce conteneur jetable — remplace
# temporairement default.html.twig, jamais commité, jamais dans le dépôt.
docker exec "$K_CONTAINER" sh -c 'cat > /var/www/html/user/themes/gites-theme/templates/default.html.twig <<'"'"'EOF'"'"'
{% extends "partials/base.html.twig" %}
{% block content %}
<div id="k-form-one">
{% set kf1 = forms("contact-form") %}
{% do kf1.setData("gite", "gite-un") %}
{% include "forms/form.html.twig" with { form: kf1 } %}
</div>
<div id="k-form-two">
{% set kf2 = forms("contact-form") %}
{% do kf2.setData("gite", "gite-deux") %}
{% include "forms/form.html.twig" with { form: kf2 } %}
</div>
{% endblock %}
EOF'
docker exec "$K_CONTAINER" rm -rf /var/www/html/cache/*
sleep 1

K_HTML="$(curl -s "http://localhost:18093/synth-multiform")"
K_SEL_ONE="$(echo "$K_HTML" | python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'id=\"k-form-one\".*?id=\"k-form-two\"', html, re.S)
sel = re.search(r'<select[^>]*name=\"data\[gite\]\"[^>]*>.*?</select>', m.group(0), re.S) if m else None
sel_val = re.search(r'selected=\"selected\" value=\"([^\"]*)\"', sel.group(0)) if sel else None
print(sel_val.group(1) if sel_val else '')
")"
K_SEL_TWO="$(echo "$K_HTML" | python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'id=\"k-form-two\".*', html, re.S)
sel = re.search(r'<select[^>]*name=\"data\[gite\]\"[^>]*>.*?</select>', m.group(0), re.S) if m else None
sel_val = re.search(r'selected=\"selected\" value=\"([^\"]*)\"', sel.group(0)) if sel else None
print(sel_val.group(1) if sel_val else '')
")"
docker rm -f "$K_CONTAINER" >/dev/null 2>&1

log "K1 — deux formulaires rendus dans la même requête : présélections observées = '$K_SEL_ONE' / '$K_SEL_TWO'"
[ "$K_SEL_ONE" = "gite-un" ] || fail "K1 : présélection du premier formulaire attendue 'gite-un', obtenue '$K_SEL_ONE' — fuite possible entre instances Form partagées"
[ "$K_SEL_TWO" = "gite-deux" ] || fail "K1 : présélection du second formulaire attendue 'gite-deux', obtenue '$K_SEL_TWO' — fuite possible entre instances Form partagées"
log "K1 : aucune fuite observée dans ce cas construit (voir la limite formulée ci-dessus dans le script : ceci démontre l'absence d'effet visible dans ce cas précis, pas une garantie générale)"

log "tests contact-routing (SEC-GITES-001) terminés"
