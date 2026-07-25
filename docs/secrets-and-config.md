# Configuration et secrets

Classification de tout ce qui vit sous `grav/user/config/`, et structure exacte attendue
des fichiers secrets. Public : mainteneurs de ce dépôt, personne qui gère les secrets côté
Ansible Vault. Détails volontairement tenus hors du README (structure de fichier secret,
procédures de test) pour ne pas alourdir le point d'entrée le plus consulté.

## Classification de `user/config`

| Fichier | Classification | Note |
|---|---|---|
| `system.yaml` | Configuration applicative immuable | Thème actif, alias home |
| `site.yaml` | Configuration applicative immuable | Contient encore des valeurs par défaut Grav non pertinentes (`Joe Bloggs`) — nettoyage éditorial possible, hors périmètre de cette migration |
| `media.yaml` | Configuration applicative immuable | Vide |
| `gites-photos-taxonomie.yaml` | Configuration applicative immuable | Taxonomie métier, non secrète |
| `plugins/api.yaml` | Configuration applicative immuable | Contient un `salt` généré automatiquement par Grav Admin — pas un secret d'authentification |
| `plugins/calendrier-disponibilites.yaml`, `plugins/login.yaml` | Configuration applicative immuable | Non secrètes |
| `plugins/email.yaml` | Configuration applicative immuable **partielle** | Voir ci-dessous — `server`/`port`/`encryption`/`user` en ont été retirés |
| `email-private.php` (jamais committé) | Secret, injecté par `grav_secrets` | Voir ci-dessous |
| `versions.yaml` | **Retiré du dépôt et de l'image** | Décrivait l'état d'une installation Grav autonome antérieure ; `grav-runtime` vide `user/config` à la construction et ne fournit aucun `versions.yaml` — en committer un ferait dire à l'image applicative des choses sur des versions techniques qu'elle ne maîtrise pas |
| `.htaccess` | **Retiré du dépôt et de l'image** | Format Apache, sans aucun effet sous le Nginx de `grav-runtime` ; la protection réelle de `user/config` est déjà assurée par `nginx.conf` du runtime |

## Stratégie SMTP (`plugins/email.yaml` / `email-private.php`)

### Mécanisme de fusion (vérifié dans le code, pas supposé)

`grav/user/plugins/contact/contact.php::loadEmailPrivateConfig()`, appelé à
`onPluginsInitialized()` :

```php
$path = $this->grav['locator']->findResource('user://config/email-private.php');
if (!$path || !file_exists($path)) {
    return;
}
$credentials = require $path;
if (!is_array($credentials)) {
    return;
}
foreach ($credentials as $key => $value) {
    $config->set("plugins.email.mailer.smtp.{$key}", $value);
}
```

- Le merge est générique sur `plugins.email.mailer.smtp.*` : `server`, `port`,
  `encryption`, `user`, `password` peuvent tous être fournis par `email-private.php`.
- `from`, `from_name`, `to`, `content_type` sont **hors de portée** de ce merge (préfixe
  codé en dur) — ils ne peuvent venir que d'`email.yaml`.

### Répartition retenue

```text
configuration SMTP publique/structurelle → email.yaml (image)
    engine: smtp
    content_type: text/html
    from / from_name / to (traités comme une adresse de contact publique du site,
      pas comme un identifiant technique d'infrastructure)

configuration SMTP technique/sensible → email-private.php (secret, grav_secrets)
    server, port, encryption, user, password
```

`server`/`port`/`user` identifient un compte technique réel (OVH), pas une donnée
générique : ils sont traités comme sensibles au même titre que le mot de passe, pas
seulement ce dernier.

### Structure attendue de `email-private.php`

```php
<?php
return [
    'server'     => 'ssl0.ovh.net',
    'port'       => '465',
    'encryption' => 'tls',
    'user'       => 'admin@lavallee.tech',
    'password'   => '__reel__',
];
```

Injecté en production via :

```yaml
grav_secrets:
  - name: email-private.php
    content: "{{ vaulted_email_private_php }}"
```

### Chemin — pourquoi `user/config/email-private.php` et pas `user/config/plugins/email-private.php`

`ansible-role-grav-site` valide `grav_secrets[].name` avec la regex
`^[A-Za-z0-9][A-Za-z0-9._-]*$`, qui interdit `/` — il ne peut monter un secret qu'à plat,
directement sous `user/config/`. Le code d'origine lisait
`user://config/plugins/email-private.php` (sous-dossier), incompatible avec ce mécanisme.
`contact.php` a donc été adapté pour lire `user://config/email-private.php` (chemin plat) —
c'est une **adaptation technique nécessaire à l'injection de secret**, pas une modification
fonctionnelle du formulaire de contact : le comportement observable côté visiteur est
inchangé.

### Comportements vérifiés (voir `tests/test-secrets.sh`)

| Cas | Comportement |
|---|---|
| Secret absent | Retour silencieux, aucun crash. `plugins.email.mailer.smtp.*` reste celui d'`email.yaml` seul (incomplet). Un envoi échouera à l'usage, sans log d'avertissement explicite. |
| Secret valide (tableau associatif) | Chargé et fusionné sans erreur. |
| Secret présent mais ne retournant pas un tableau (`null`, chaîne, absence de `return`) | `is_array()` échoue, retour silencieux, aucune surcharge appliquée, aucun crash. |
| Secret avec **erreur de syntaxe PHP** | **Risque réel et documenté** : `require` déclenche une `ParseError` non interceptée (pas de `try/catch`) → erreur fatale non catchée → le site entier peut répondre en 500 (`onPluginsInitialized` s'exécute à chaque requête, pas seulement sur le formulaire de contact). Vérifié empiriquement : `tests/fixtures/email-private.syntax-error.php` produit bien un HTTP 500 sur `/`. À traiter avec la même rigueur qu'un déploiement de code : revue avant tout changement du secret en production. |

Non-affichage du secret dans les logs : le code ne logue jamais explicitement le contenu de
`$credentials` ; vérifié empiriquement dans `tests/test-secrets.sh` (recherche de la valeur
de test dans `docker logs`).

## Comptes

`user/accounts/` n'est jamais présent dans ce dépôt (gitignoré). Aucun compte, mot de
passe ou hash n'est committé. Le compte administrateur est créé exclusivement via le
bootstrap `GRAV_ADMIN_*`/`grav_admin_*` (voir [`runtime-contract.md`](runtime-contract.md)).
