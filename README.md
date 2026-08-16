# projet-gites

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/GHCR-ready-blue)](https://ghcr.io/sepp67/projet-gites)

**Image applicative Grav pour le site des Gîtes (Alsace & Vosges).**

Ce dépôt contient **uniquement** la couche métier :
- thème
- plugins métier
- configuration non secrète
- contenu initial (seed)

Il s’appuie sur le socle technique [`grav-runtime`](https://github.com/sepp67/grav-runtime) et est déployé par le rôle [`ansible-role-grav-site`](https://github.com/sepp67/ansible-role-grav-site).

Cette séparation permet de faire évoluer le contenu du site sans toucher au runtime, et de déployer de façon identique en développement et en production.

## Architecture de la stack

```mermaid
graph TD
grav-runtime               →  socle technique (Nginx + PHP-FPM + Grav Core)
    └── projet-gites       →  contenu métier (ce dépôt)
            └── ansible-role-grav-site  →  déploiement + secrets + volumes
```

# projet-gites

Image applicative Grav du site des gîtes (Alsace & Vosges). Ce dépôt ne contient que le
code et le contenu propres au site : thème, plugins métier, configuration et contenu
initial. Il ne contient ni PHP, ni Nginx, ni Grav Core, ni logique de déploiement.

```text
ghcr.io/sepp67/grav-runtime:1.0.2   (socle technique générique)
        └── projet-gites            (ce dépôt : thème, plugins, config, contenu initial)
                └── ansible-role-grav-site:1.0.1   (déploiement, hors de ce dépôt)
```

Pour comprendre en détail pourquoi cette séparation existe et comment chaque couche
fonctionne, voir [`docs/architecture.md`](docs/architecture.md) et le reste de
[`docs/`](docs/). Ce README reste volontairement un guide de démarrage rapide.

## Prérequis

- Docker et Docker Compose (v2).
- Pour le déploiement : Ansible et [`ansible-role-grav-site`](https://github.com/sepp67/ansible-role-grav-site) version `1.0.1`, hors de ce dépôt.

## Build local

```bash
docker build -t projet-gites:local .
```

## Développement local

```bash
docker compose -f compose.dev.yml up -d --build

docker compose -f compose.dev.yml down -v
```
- Site : http://localhost:8080
- Admin : http://localhost:8080/admin (identifiants de test définis dans `compose.dev.yml`, jetables — voir le fichier)

`compose.dev.yml` est réservé au développement local : il n'est jamais utilisé en
production, et n'est pas une seconde implémentation du déploiement (voir
[`docs/deployment-model`](docs/architecture.md) et
[`docs/release-and-rollback.md`](docs/release-and-rollback.md)).

## Tests locaux

```bash
sh tests/run-all.sh
```

Détail de ce que couvre chaque script : [`docs/testing.md`](docs/testing.md).

## Publication GHCR

Déclenchée uniquement par un tag SemVer (`vX.Y.Z`) poussé sur `main` :

```bash
git tag v1.0.0
git push origin v1.0.0
```

Le workflow [`​.github/workflows/release.yml`](.github/workflows/release.yml) publie alors
`ghcr.io/sepp67/projet-gites` avec les tags `1.0.0`, `1.0`, `1` et `latest`. Procédure complète
et politique SemVer : [`docs/release-and-rollback.md`](docs/release-and-rollback.md).

## Déploiement avec `ansible-role-grav-site:1.0.1`

```yaml
- hosts: grav_servers
  become: true
  roles:
    - role: ansible-role-grav-site
      vars:
        grav_image: "ghcr.io/sepp67/projet-gites"
        grav_version: "1.0.0"

        grav_container_name: projet-gites
        grav_http_port: 8080

        grav_admin_user: admin
        grav_admin_email: admin@example.com
        grav_admin_password: "{{ vault_grav_admin_password }}"

        grav_secrets:
          - name: email-private.php
            content: "{{ vaulted_email_private_php }}"
```

`grav_version` doit toujours être un tag précis, jamais `latest`. Détail des variables,
mise à jour et rollback manuel : [`docs/release-and-rollback.md`](docs/release-and-rollback.md).

## Pour aller plus loin

| Document | Contenu |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Vue d'ensemble des trois couches (runtime / image applicative / déploiement) |
| [`docs/runtime-contract.md`](docs/runtime-contract.md) | Contrat exposé par `grav-runtime` tel qu'utilisé ici |
| [`docs/compatibility-policy.md`](docs/compatibility-policy.md) | Politique de certification et matrice de compatibilité avec `grav-runtime` |
| [`docs/seed-lifecycle.md`](docs/seed-lifecycle.md) | Cycle de vie du contenu initial (`user/pages`) |
| [`docs/secrets-and-config.md`](docs/secrets-and-config.md) | Classification de la configuration, structure des secrets |
| [`docs/testing.md`](docs/testing.md) | Détail de la suite de tests |
| [`docs/release-and-rollback.md`](docs/release-and-rollback.md) | Procédure complète de release, mise à jour et rollback |
