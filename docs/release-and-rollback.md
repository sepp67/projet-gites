# Release, mise à jour et rollback

Procédure complète : développement → build → test → tag Git → publication GHCR →
déploiement Ansible → mise à jour → rollback manuel. Public : opérateurs de déploiement.
Pour un exemple minimal de variables Ansible, voir le [`README.md`](../README.md).

## Cycle complet

```text
développement (compose.dev.yml)
    → build (docker build / CI)
    → tests (tests/run-all.sh, voir testing.md)
    → tag Git SemVer (vX.Y.Z)
    → publication GHCR (release.yml, déclenché uniquement par le tag)
    → certification (compatibility-policy.md, mise à jour de la matrice)
    → déploiement Ansible (ansible-role-grav-site:1.0.1)
    → mise à jour (rejouer avec un grav_version différent)
    → rollback manuel (rejouer avec un grav_version antérieur)
```

## Publication GHCR

`.github/workflows/release.yml` se déclenche **uniquement** sur un tag SemVer poussé :

```bash
git tag v1.0.0
git push origin v1.0.0
```

Tags OCI générés automatiquement (`docker/metadata-action`) : `1.0.0`, `1.0`, `1`, `latest`.
`latest` est publié par commodité mais **ne doit jamais être utilisé en déploiement** —
`ansible-role-grav-site` refuse d'ailleurs explicitement `grav_version: latest`
(`tasks/assert.yml` du rôle).

Avant de taguer : mettre à jour la matrice de compatibilité dans
[`compatibility-policy.md`](compatibility-policy.md) avec la version de `grav-runtime`
réellement testée pour cette release.

## Déploiement

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

Le rôle crée les répertoires persistants, dépose les secrets, génère `docker-compose.yml`
et `grav.env`, démarre le conteneur, attend `healthy` puis vérifie qu'une page réelle
répond, et enregistre la version déployée (`.deployed_version`,
`deployed_versions.log`). Détail complet des variables : README du rôle.

## Mise à jour

```yaml
grav_version: "1.0.1"   # au lieu de "1.0.0"
```

Rejouer le playbook. Le rôle télécharge la nouvelle image, recrée le conteneur, attend le
healthcheck. Les répertoires persistants (`pages`, `accounts`, `data`, `images`) sont des
répertoires de l'hôte, indépendants du cycle de vie du conteneur : **jamais** recréés ni
vidés par une mise à jour (vérifié en Phase 2, voir
[`tests/test-update-rollback.sh`](../tests/test-update-rollback.sh)). Le contenu de
`user/pages` déjà administré n'est jamais réécrit par le nouveau seed de l'image — voir
[`seed-lifecycle.md`](seed-lifecycle.md).

Avant toute mise à jour qui change la version de `grav-runtime` référencée dans le
`Dockerfile` : voir la procédure de certification dans
[`compatibility-policy.md`](compatibility-policy.md).

## Rollback

```yaml
grav_version: "1.0.0"   # valeur antérieure
```

Rejouer le playbook. Un rollback est, du point de vue du rôle, une mise à jour comme une
autre : même mécanisme, même garantie de non-perte des données persistantes.
`deployed_versions.log` (sur l'hôte cible) conserve l'historique horodaté de toutes les
versions déployées pour retrouver la version cible.

**Ce rollback est entièrement manuel.** Le rôle ne détecte, ne déclenche et n'automatise
aucun retour en arrière : c'est à l'opérateur de choisir la version cible et de rejouer
explicitement le playbook.

## Limites connues

- Le contenu de `user/pages` n'est jamais synchronisé automatiquement entre versions
  d'image — voir [`seed-lifecycle.md`](seed-lifecycle.md) pour les méthodes de migration
  volontaire si un jour nécessaire.
- `test-persistence.sh` et `test-update-rollback.sh` ne sont pas encore exécutés en CI
  (voir [`testing.md`](testing.md)) — à exécuter manuellement avant chaque release tant
  que cette automatisation n'est pas ajoutée.
- Le champ `from`/`from_name`/`to` d'`email.yaml` reste commun à tous les environnements
  (voir [`secrets-and-config.md`](secrets-and-config.md)) : seule la partie technique du
  SMTP varie par environnement via le secret.
