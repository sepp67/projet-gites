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

Le POC initial n’appartient plus au workspace actif. Le présent dépôt constitue
désormais la référence applicative du site des gîtes.

Lorsqu’un comportement historique doit être réintroduit :

1. décrire précisément le comportement recherché ;
2. vérifier qu’il reste pertinent dans l’architecture actuelle ;
3. identifier le composant qui en est aujourd’hui responsable ;
4. concevoir une adaptation compatible avec les contrats actuels ;
5. tester cette adaptation sans recopier automatiquement l’ancienne
   implémentation.

Ne jamais réintroduire une dépendance au POC ni recopier depuis une archive un
secret, un compte, une configuration d’instance ou une dépendance non validée.

## Contrôles spécifiques

- construction de l'image applicative ;
- vérification des pages initiales et de la configuration publique ;
- tests du thème, des plugins, des formulaires et de la persistance ;
- vérification qu'aucun compte réel, secret ou donnée d'instance n'entre dans
  l'image.

