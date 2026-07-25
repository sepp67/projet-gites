# Contrat `grav-runtime`

Référence rapide du contrat exposé par [`grav-runtime`](https://github.com/sepp67/grav-runtime)
tel qu'utilisé par `projet-gites`, pour éviter de devoir rouvrir ce dépôt à chaque fois.
Public : mainteneurs de cette image applicative. En cas de doute, le dépôt `grav-runtime`
reste la source de vérité — ce document n'est qu'une synthèse.

## Ce que le runtime fournit

PHP-FPM (`php:8.3-fpm-alpine`) + Nginx dans un seul conteneur, Grav Core + Admin vendorisés
et vérifiés par somme de contrôle, les plugins techniques du bundle Admin (`admin2`, `login`,
`form`, `email`, `error`, `problems`, `flex-objects`, `api`, `github-markdown-alerts`,
`shortcode-core`), le thème `quark2`, un entrypoint qui supervise Nginx/PHP-FPM, un
mécanisme de seed, un bootstrap admin optionnel, et un healthcheck HTTP interne.

## Chemins internes

| Chemin | Rôle |
|---|---|
| `/var/www/html` | racine Grav |
| `/var/www/html/user/themes`, `/var/www/html/user/plugins` | fournis par l'image (runtime + image applicative), jamais montés |
| `/var/www/html/user/pages`, `/user/accounts`, `/user/data`, `/user/images` | répertoires persistants, montables séparément |
| `/var/www/html/user/config` | code versionné (fourni par `COPY`), pas un volume |
| `/opt/grav-seed/{pages,accounts,data,images}` | seed — contenu initial fourni par l'image applicative |

## Port et healthcheck

`80/tcp` HTTP uniquement (TLS géré par le reverse proxy externe, hors périmètre).
`GET /healthz` : endpoint technique minimal, ne passe jamais par Grav lui-même — prouve que
Nginx et PHP-FPM sont vivants et reliés, pas que le site rend correctement. C'est pourquoi
`ansible-role-grav-site` complète ce healthcheck par une vérification HTTP sur une page
réelle (voir [`release-and-rollback.md`](release-and-rollback.md)).

## Mécanisme de seed

`docker/seed-init.sh` traite chaque sous-répertoire persistant indépendamment, au démarrage :

```text
destination vide       → copie du contenu de /opt/grav-seed/<dir>, puis chown www-data
destination déjà peuplée → aucune copie, aucun écrasement
seed absent              → rien à faire
échec de la copie        → sortie en erreur, démarrage interrompu
```

Pas de fichier `.initialized` global : l'état est lu directement sur chaque répertoire.
`rsync --delete` n'est jamais utilisé — rien n'est jamais supprimé automatiquement. Détail
appliqué à `user/pages` dans ce dépôt : [`seed-lifecycle.md`](seed-lifecycle.md).

## Variables d'environnement reconnues

| Variable | Obligatoire | Rôle |
|---|---|---|
| `GRAV_ADMIN_USER` / `_PASSWORD` / `_EMAIL` | Toutes les trois ou aucune | Bootstrap du compte admin |
| `GRAV_ADMIN_FULLNAME` / `_TITLE` / `_LANGUAGE` | Non | Champs optionnels du compte |
| `GRAV_TIMEZONE` | Non | `date.timezone` PHP |

Aucune autre variable n'est lue par le runtime. Toute variable supplémentaire nécessaire à
`projet-gites` doit passer par `grav_extra_environment` côté rôle Ansible, jamais être
supposée reconnue par le runtime.

## Bootstrap administrateur

Politique stricte, appliquée par `docker/bootstrap-admin.sh` (exécuté en `www-data`) :
aucune des trois variables définie → bootstrap désactivé ; les trois définies → bootstrap
exécuté ; partiellement définies → le conteneur refuse de démarrer (exit ≠ 0). Un compte
déjà existant n'est jamais écrasé. Le mot de passe est transmis uniquement via stdin à la
CLI Grav, jamais en argument ni en log.

## Secrets

Montés individuellement, en lecture seule, **à plat** sous `user/config/<nom>` — jamais
générés par l'image. Voir [`secrets-and-config.md`](secrets-and-config.md) pour la
contrainte précise que cela impose à `projet-gites` (chemin plat, pas de sous-dossier).

## Permissions

`www-data`, uid/gid 82. `entrypoint.sh` corrige la propriété des chemins persistants au
démarrage, seulement si nécessaire (idempotent). Aucun `chmod 0777` nulle part.

## Arrêt

`entrypoint.sh` est PID 1, relaie `SIGTERM`/`SIGINT`/`SIGQUIT` à Nginx et PHP-FPM, attend
leur arrêt propre. `STOPSIGNAL SIGTERM` est déclaré explicitement dans le Dockerfile du
runtime (la base `php:8.3-fpm-alpine` déclare `SIGQUIT`, non pertinent ici).

## Ce que `projet-gites` ne doit jamais dupliquer

PHP, Nginx, Grav Core, l'entrypoint, le healthcheck natif, le bootstrap admin, la gestion
des permissions, la logique de seed générique — voir [`architecture.md`](architecture.md).
