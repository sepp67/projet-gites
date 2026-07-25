# Architecture

Ce document donne la vue d'ensemble des trois couches qui composent le déploiement du
site des gîtes, et ce que chacune possède — ou ne possède jamais. Public : nouveaux
contributeurs, revue d'architecture. Si vous cherchez à *faire* quelque chose (builder,
tester, déployer), voir le [`README.md`](../README.md) ; ce document sert à *comprendre*
pourquoi le dépôt est structuré ainsi.

## Les trois couches

```text
grav-runtime (ghcr.io/sepp67/grav-runtime:1.0.2)
    │  socle technique générique — même image pour n'importe quel site Grav
    │
    └── projet-gites (ce dépôt, ghcr.io/sepp67/projet-gites)
            │  code et contenu propres au site des gîtes
            │
            └── ansible-role-grav-site:1.0.1
                    déploiement — génère le Compose de production, gère les
                    volumes, les secrets, le healthcheck, la version déployée
```

Chaque couche a une responsabilité exclusive, jamais partagée avec les deux autres :

| Couche | Possède | Ne possède jamais |
|---|---|---|
| `grav-runtime` | PHP-FPM, Nginx, Grav Core + Admin, plugins techniques (`admin2`, `login`, `email`, `form`, `api`, …), thème `quark2`, entrypoint, healthcheck, bootstrap admin, mécanisme de seed | Rien de propre à un site : aucun thème métier, aucune page, aucun domaine, aucun secret |
| `projet-gites` (ce dépôt) | Thème `gites-theme`, plugins métier (`contact`, `calendrier-disponibilites`), configuration versionnée du site, contenu initial (seed) | PHP, Nginx, Grav Core, l'entrypoint, le healthcheck, la logique de déploiement, tout secret réel |
| `ansible-role-grav-site` | Compose de production, répertoires persistants sur l'hôte, montage des secrets, attente du healthcheck, enregistrement de la version déployée | Toute connaissance du contenu métier — il ne sait déployer qu'une paire `grav_image`/`grav_version` |

Cette séparation n'est pas un détail d'implémentation : c'est ce qui permet de publier
`projet-gites` comme une image OCI indépendante, de la déployer sans aucune modification
du rôle Ansible, et de faire évoluer chaque couche à son propre rythme (voir
[`compatibility-policy.md`](compatibility-policy.md) pour la discipline de version entre
les deux premières couches).

## Ce que ce dépôt ne fait jamais

Reprendre PHP, Nginx, Grav Core, l'entrypoint, le healthcheck natif ou le bootstrap admin
(tout cela appartient à `grav-runtime`, voir [`runtime-contract.md`](runtime-contract.md)) ;
générer ou committer un Compose de production, ou dupliquer une tâche de déploiement
(tout cela appartient à `ansible-role-grav-site`, voir
[`release-and-rollback.md`](release-and-rollback.md)) ; gérer un reverse proxy, TLS, DNS
ou un pare-feu (infrastructure externe, hors périmètre des trois couches ci-dessus).

## Documents liés

- [`runtime-contract.md`](runtime-contract.md) — le contrat technique exposé par `grav-runtime`
- [`compatibility-policy.md`](compatibility-policy.md) — comment ce dépôt reste compatible avec `grav-runtime` dans le temps
- [`seed-lifecycle.md`](seed-lifecycle.md) — le cycle de vie du contenu initial
- [`secrets-and-config.md`](secrets-and-config.md) — classification de la configuration et des secrets
- [`testing.md`](testing.md) — la suite de tests
- [`release-and-rollback.md`](release-and-rollback.md) — le cycle complet build → publication → déploiement → mise à jour → rollback
