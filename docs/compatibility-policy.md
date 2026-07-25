# Politique de compatibilité avec `grav-runtime`

Politique de certification et de versionnement entre `projet-gites` et `grav-runtime`,
et matrice de compatibilité effective. Public : opérateurs qui décident d'une mise à jour,
mainteneurs futurs. Cette politique est générique et réutilisable telle quelle pour tout
futur projet Grav construit sur `grav-runtime` (remplacer `projet-gites` par le nom du
projet concerné).

## Qui est responsable de la compatibilité

`grav-runtime` ne connaît jamais ses images filles. La responsabilité de garantir et de
**déclarer** la compatibilité est donc entièrement descendante : c'est `projet-gites` qui
certifie, pour lui-même, contre quelle(s) version(s) précise(s) de `grav-runtime` il a été
validé. Le runtime ne certifie jamais rien pour ses images filles.

## Quand la compatibilité est validée

1. À chaque publication d'un tag de `projet-gites` — la CI rejoue `tests/run-all.sh` (au
   moins les tests rapides, voir [`testing.md`](testing.md)) contre la version de
   `grav-runtime` référencée dans le `Dockerfile`.
2. Avant toute adoption d'une nouvelle version de `grav-runtime` dans le `FROM` du
   `Dockerfile` — jamais un simple bump de tag sans repasser la suite de tests complète,
   y compris une vérification de **rendu réel** (pas seulement build + `healthy`).

## Tests à rejouer lors d'une mise à jour du runtime

Build → démarrage + `healthy` → rendu réel de la page d'accueil (héritage `quark2`) →
pages `/gites/*` (galerie, `gite-item.html.twig`) → formulaire de contact (dépend du
plugin `form`, vendorisé par le runtime) → accès `/admin` (dépend de `admin2`/`quark2`) →
persistance des volumes existants inchangée.

## Changements du runtime à considérer comme potentiellement incompatibles

Même si le numéro de version ne l'indique pas explicitement :
- changement de version du Grav Core/Admin vendorisé ;
- changement de structure de `quark2` (fichiers/blocs Twig renommés ou déplacés — `gites-theme` n'a pas son propre `base.html.twig`, il hérite entièrement de celui de `quark2`) ;
- changement des chemins internes, du mécanisme de seed, ou des répertoires persistants ;
- changement du contrat de variables d'environnement, du healthcheck, du modèle de permissions/uid-gid, ou de la gestion des signaux.

## Déclaration officielle de compatibilité

```text
projet-gites 1.0.0
certifié avec
grav-runtime 1.0.2
```

Signification précise :
- cette combinaison exacte a été construite, démarrée, et a passé l'intégralité de
  `tests/run-all.sh` ;
- c'est la seule combinaison recommandée pour un déploiement de production à ce jour ;
- **ce n'est pas une garantie de compatibilité avec une autre version de runtime**, ni
  antérieure ni postérieure, même mineure — chaque nouvelle version de runtime nécessite
  une nouvelle certification explicite avant adoption.

## Matrice de compatibilité

| Version `projet-gites` | Version `grav-runtime` certifiée | Date | Suite de tests exécutée |
|---|---|---|---|
| `1.0.0` | `1.0.2` | (date de la première release) | `tests/run-all.sh` |

Cette table est mise à jour à chaque release (voir
[`release-and-rollback.md`](release-and-rollback.md)).

## Politique SemVer de `grav-runtime` (pour information)

Rappel de la règle appliquée par `grav-runtime` lui-même, utile pour interpréter un bump de
version avant de décider d'une mise à jour :

> Une image applicative déjà certifiée, sans aucune modification de son propre Dockerfile
> ni de son code, continue-t-elle de se comporter exactement à l'identique après ce
> changement ? Oui → **patch**. Capacité nouvelle sans rien changer pour l'existant →
> **minor**. Une image existante pourrait se comporter différemment ou échouer → **major**.

Un bump de version du Grav Core/Admin vendorisé n'est classé **minor** par `grav-runtime`
que si sa propre suite de tests démontre l'absence de rupture pour les mécanismes de
chaînage de thème/plugin — en l'absence de cette démonstration, il doit être traité comme
potentiellement **major** de ce côté-ci, quel que soit le numéro publié.
