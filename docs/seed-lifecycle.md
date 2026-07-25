# Cycle de vie du contenu initial (`user/pages`)

Explique ce qui, dans `grav/user/pages/`, est du contenu de référence versionné et ce qui
devient une donnée métier vivante une fois déployé — et pourquoi ces deux états ne se
comportent pas de la même façon. Public : équipe éditoriale/admin, futurs développeurs qui
doivent comprendre pourquoi une correction Git ne se propage pas automatiquement à un site
déjà en ligne.

## Classification

`grav/user/pages/` (dans ce dépôt) n'est ni du code ni une donnée persistante au sens
strict : c'est un **contenu éditorial initial**, copié une seule fois dans le volume
persistant `user/pages` par le mécanisme de seed de `grav-runtime` (voir
[`runtime-contract.md`](runtime-contract.md)).

```text
pages présentes dans Git      → contenu initial de référence
pages présentes dans le volume → contenu métier vivant, administrable, jamais réécrit automatiquement
```

Le schéma de ce contenu (champs `header.galerie.photos`, `proprietaire`, etc.) est défini
par le thème (`gites-theme/blueprints/gite-item.yaml`) — le blueprint est du code, les
valeurs remplies dans les pages sont de la donnée.

## Ce que garantit le seed (vérifié sur le code de `grav-runtime`)

- Le seed n'agit **que** sur un volume `user/pages` vide au démarrage — `seed-init.sh`
  quitte immédiatement, sans rien copier, dès que le volume contient quoi que ce soit.
- Aucune étape du cycle de vie de l'image (build, `docker compose up`, mise à jour de tag)
  ne réinvoque une copie vers un volume déjà peuplé.
- **Conséquence : une mise à jour d'image ne modifie jamais automatiquement les pages déjà
  présentes dans le volume d'un site déjà déployé.**

## Conséquence opérationnelle à connaître

```text
Une correction dans grav/user/pages du dépôt Git ne se propage qu'aux NOUVELLES
instances (volume pages vide au premier démarrage). Un site déjà déployé ne reçoit
jamais cette correction automatiquement, quelle que soit la version d'image installée
ensuite.
```

Le seed est le bon mécanisme pour le **tout premier déploiement** d'une instance neuve. Ce
n'est pas un mécanisme de synchronisation de contenu dans la durée, et il ne doit jamais
être traité comme tel.

## Méthodes pour une migration de contenu volontaire (non implémentées ici)

Si une correction doit un jour être propagée à un site déjà déployé, plusieurs approches
sont possibles — aucune n'est automatique, toutes restent des actions manuelles et
explicites de l'opérateur :

- **Script de migration versionné** (ex. `migrations/0001-corriger-titre-gite-un.sh`),
  appliqué via `docker exec`, idempotent, avec trace de ce qui a été appliqué.
- **Commande Grav dédiée** (script PHP ou `bin/plugin` custom) pour une modification
  ciblée d'un champ précis, sans toucher au reste du contenu déjà administré.
- **Tâche Ansible dédiée**, mais **hors du rôle générique** `ansible-role-grav-site` — à
  écrire dans ce dépôt ou dans un playbook séparé, jamais dans le rôle lui-même.
- **Procédure manuelle documentée** (`docker cp` + sauvegarde préalable du volume),
  réservée aux corrections ponctuelles urgentes.

## Point ouvert

`grav/user/pages/02.typography/` est la page de démonstration standard de Grav, pas un
contenu métier des gîtes. Elle est actuellement incluse dans le seed sans décision
éditoriale explicite de la retirer — à trancher lors d'une prochaine itération de contenu,
pas une question d'architecture.
