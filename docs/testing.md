# Tests

Détail de ce que couvre chaque script de `tests/`. Public : contributeurs qui modifient le
code, CI. Pour simplement lancer les tests, voir le [`README.md`](../README.md)
(`sh tests/run-all.sh`).

## Structure

```text
tests/
├── compose.test.yml            # utilisé par test-persistence.sh et test-update-rollback.sh
├── fixtures/
│   ├── email-private.valid.php
│   ├── email-private.invalid-nonarray.php
│   └── email-private.syntax-error.php
├── lib.sh                      # helpers partagés (wait_healthy, log, fail, http_status)
├── test-build.sh
├── test-startup.sh
├── test-app-presence.sh
├── test-persistence.sh
├── test-update-rollback.sh
├── test-secrets.sh
└── run-all.sh                  # orchestrateur, s'arrête au premier échec
```

Chaque script échoue explicitement (code de sortie non nul) au premier écart constaté.

## Ce que couvre chaque script

| Script | Couvre |
|---|---|
| `test-build.sh` | Le `docker build` de l'image applicative réussit. |
| `test-startup.sh` | Démarrage, état `healthy`, page d'accueil en HTTP 200 (avec bootstrap admin fourni — voir note ci-dessous). |
| `test-app-presence.sh` | Thème `gites-theme` actif et `quark2` présent, plugins métier présents, contenu initial seedé, rendu réel de la page d'accueil (pas seulement HTTP 200), pages gîtes/contact répondent, un asset média est accessible, `/admin` répond. |
| `test-secrets.sh` | Aucun secret/placeholder connu dans les couches de l'image exportée ; aucun compte baké dans une image fraîche sans bootstrap ; les quatre comportements du secret `email-private.php` (absent / valide / invalide non-array / erreur de syntaxe) ; non-affichage du secret dans les logs. |
| `test-persistence.sh` | Un marqueur écrit dans chacun des 4 répertoires persistants (`pages`, `accounts`, `data`, `images`) survit à un redémarrage du conteneur. |
| `test-update-rollback.sh` | Une mise à jour d'image (A→B, mêmes volumes) préserve les données persistantes et active le nouveau code ; un rollback (B→A) préserve les mêmes données et réactive l'ancien code. L'image B est construite depuis une copie temporaire du dépôt — ce script ne modifie jamais les fichiers réels. |

## Note sur le bootstrap admin dans les tests

`test-startup.sh` et `test-app-presence.sh` démarrent le conteneur avec
`GRAV_ADMIN_USER`/`_PASSWORD`/`_EMAIL` renseignées, comme le fait toujours
`ansible-role-grav-site` en déploiement réel. Sans ces variables, le plugin Admin de
`grav-runtime` redirige lui-même **toutes** les pages du site vers `/admin` tant qu'aucun
compte n'existe — un comportement natif de Grav Admin (constaté empiriquement pendant
l'implémentation), pas un défaut de cette image. `test-secrets.sh` fournit les mêmes
variables pour les mêmes raisons dans ses propres cas de test.

## Ce qui est automatisé en CI et ce qui ne l'est pas

`.github/workflows/ci.yml` exécute `test-build.sh`, `test-startup.sh`,
`test-app-presence.sh` et `test-secrets.sh` sur chaque push et chaque pull request — rapides,
un seul état à la fois. `test-persistence.sh` et `test-update-rollback.sh` restent des
scripts à exécuter localement avant une release (scénarios à deux temps, plus longs) ; leur
automatisation en CI est un raffinement possible, non bloquant.

## Absence de secrets — ce qui est vérifié et comment

`test-secrets.sh` exporte l'image (`docker save`), extrait les couches et recherche des
valeurs de test/placeholder connues (`ChangeMe123`, `admin@example.com`). Ce n'est pas une
recherche exhaustive de tout secret possible : c'est une vérification de non-régression sur
les valeurs concrètes qui ont existé dans l'historique de ce projet. Avant toute release, une
relecture manuelle de `git diff` reste recommandée pour tout fichier sous `grav/user/config/`.
