# Instructions locales — projet-gites

Avant toute action, lire le fichier `../CLAUDE.md`.

Ce dépôt produit l'image applicative du site des gîtes à partir de
`grav-runtime`.

## Invariants locaux

- conserver ici le thème, les plugins applicatifs, les pages initiales, les
  formulaires, les modèles et la logique métier du site ;
- conserver uniquement de la configuration publique dans l'image ;
- maintenir l'indépendance entre le code applicatif, le runtime, les données
  persistantes et le déploiement ;
- vérifier qu'un redéploiement ne remplace pas silencieusement le contenu
  persistant d'une instance existante ;
- tester les comportements propres au site et à ses formulaires.

## Référence historique

Avant de reprendre une fonctionnalité historique, consulter
`../4-projet-gites-poc/CLAUDE.md` et appliquer la méthode de comparaison qui
y est définie.

## Contrôles spécifiques

- construction de l'image applicative ;
- vérification des pages initiales et de la configuration publique ;
- tests du thème, des plugins, des formulaires et de la persistance ;
- vérification qu'aucun compte réel, secret ou donnée d'instance n'entre dans
  l'image.

