# Notes de sécurité

Constats de sécurité concernant ce dépôt, sobres et publics par construction — le détail
technique de reproduction (le cas échéant) reste hors de ce dépôt. Public : mainteneurs,
opérateurs qui décident d'une mise à jour.

## SEC-GITES-001 — sélection du destinataire du formulaire de contact

**Statut : corrigé, en attente de release.**

### Défaut

Le formulaire de contact déterminait le propriétaire destinataire d'une demande à partir
d'une valeur transmise par le champ `gite` du formulaire. Avant ce correctif, ce champ était
de type `hidden` : prérempli côté serveur avec la route de la fiche affichée, mais jamais
revalidé à la soumission contre un ensemble fermé de valeurs acceptables. Le serveur faisait
donc confiance à une valeur intégralement réécrivable côté client avant l'envoi.

### Impact confirmé

Une valeur cachée pouvait sélectionner silencieusement un autre propriétaire valide que
celui correspondant à la fiche réellement affichée au visiteur.

### Limites du constat

- Aucune adresse arbitraire n'a été démontrée atteignable — seuls les propriétaires déjà
  publiquement associés à une fiche de gîte pouvaient être ciblés.
- Aucun accès à une donnée protégée n'a été démontré.
- Les différents propriétaires étaient déjà publiquement contactables depuis leurs propres
  fiches : le défaut portait sur l'intégrité de l'intention et la cohérence du routage
  (« je contacte le propriétaire du gîte que j'ai sous les yeux »), pas sur la
  confidentialité d'une adresse.
- Aucune donnée personnelle n'est reproduite dans ce dépôt ni dans cette note.

### Versions concernées

Toute version antérieure au correctif décrit ci-dessous — voir `git log` sur
`grav/user/plugins/contact/contact.php`, `grav/user/pages/05.contact/default.md` et
`grav/user/themes/gites-theme/templates/gite-item.html.twig` pour la commit exacte du
correctif. Numéro de version corrigée : à déterminer (voir `docs/release-and-rollback.md`
pour la prochaine release publiée).

### Correction

La sélection devient un choix **visible et obligatoire** (`select`, plus une option
générale explicite) parmi un ensemble d'identifiants publics que le serveur construit et
contrôle. Une seule méthode interne, `ContactPlugin::contactTable()`, produit une table
serveur structurée (identifiant public → libellé public, type gîte/général, page Grav, nom
de compte, adresse déjà validée) — le fournisseur d'options affichées, la validation de
soumission et la résolution du destinataire lisent tous les trois **exactement cette même
table**, jamais trois logiques recalculées séparément :

1. les options réellement affichées (`contactGiteOptionsProvider`, blueprint `data-options@`)
   n'exposent que l'identifiant et le libellé — jamais la page, le compte ni l'adresse ;
2. la validation de la valeur soumise (`onFormValidationProcessed`) — toute valeur absente,
   vide, inconnue ou malformée est rejetée, sans repli silencieux ;
3. la résolution du destinataire (`resolveProprietaireEmail`) — ne consulte que la table,
   jamais une valeur transmise par le client, jamais un nouvel appel à `pages->find()`.

**Identifiant `general` réservé.** L'option de contact général porte un identifiant réservé
(`general`), inséré dans la table *avant* tout parcours des pages de gîte — aucune page ne
peut donc jamais l'écraser (une page dont le slug vaut littéralement `general` est de toute
façon déjà exclue en amont, comme n'importe quel slug hors du format accepté). L'identifiant
`general` ne passe jamais par `pages->find()`.

**Collisions d'identifiant — échec fermé.** Une collision (deux pages éligibles, ou plus,
produisant le même identifiant public) n'est **plus** résolue par priorité au premier arrivé
dans l'ordre des pages. Elle est traitée comme une **erreur de configuration** et provoque
une **exclusion totale, indépendante de l'ordre** : les pages de gîte sont d'abord regroupées
par identifiant ; tout identifiant porté par plus d'une page est écarté intégralement, avant
même toute résolution d'adresse — aucune des pages concernées n'apparaît jamais dans les
options, aucune ne peut être sélectionnée, aucune ne peut recevoir d'e-mail, même si l'une
d'elles aurait par ailleurs un compte et une adresse valides. Une entrée générique (sans
adresse ni nom de compte) est journalisée. Une soumission forçant un identifiant collisionné
est rejetée exactement comme un identifiant inconnu.

**Critères d'éligibilité d'une page gîte** : enfant *direct* du sous-arbre configuré
(`plugins.contact.gites_root`), `routable()` (combine déjà publication et routabilité côté
Grav Core), du template métier attendu (`plugins.contact.gite_template`), identifiant public
conforme au format accepté (minuscules ASCII, chiffres, tiret simple, 1 à 64 caractères —
revalidé par ce plugin même si Grav dérive déjà le slug d'un nom de dossier, qui reste un
contenu du site), `proprietaire` renseigné, compte existant, adresse syntaxiquement valide
(`filter_var(..., FILTER_VALIDATE_EMAIL)`, déjà disponible en PHP — aucune dépendance
ajoutée). `visible` n'intervient jamais : cet attribut ne contrôle que la présence dans le
sommaire, pas la validité métier — une fiche publiée, routable, retirée du sommaire reste
contactable, décision explicite.

**Option générale conditionnelle.** L'option « Demande générale » n'existe dans la table —
et donc dans les options affichées — que si `plugins.email.to` est une adresse
syntaxiquement valide. Adresse absente, vide ou invalide : l'option disparaît purement et
simplement, et toute soumission forcée de `general` dans cet état est rejetée comme n'importe
quel identifiant inconnu — jamais un repli silencieux.

La présélection d'un gîte sur sa propre fiche (`gite-item.html.twig`, `setData()`) reste une
aide ergonomique côté client, jamais une preuve de sécurité — la validation serveur ne
s'appuie jamais sur elle.

**Attribution précise du honeypot** (souvent confondue) : le *type* de champ `honeypot` et
son rendu (normalement invisible) sont fournis par le plugin Form de Grav ; la *lecture* de
sa valeur et le *rejet* de la soumission sont un contrôle applicatif de ce plugin contact
(projet-gites) — Form ne rejette rien de lui-même sur ce champ, il le transporte comme
n'importe quel autre.

**Rejet CRLF applicatif.** `onFormValidationProcessed()` rejette désormais explicitement
toute valeur contenant `\r` ou `\n` dans `email` (qui alimente l'en-tête Reply-To) ou `nom`
(qui alimente le sujet) — avant tout traitement, avec un message générique qui ne réaffiche
jamais la valeur fautive, et sans rien journaliser de sensible. `message` n'est volontairement
pas concerné : les retours à la ligne y sont un usage légitime d'une zone de texte, et son
contenu est échappé (`|e`) dans le gabarit HTML de l'e-mail. **Constat historique conservé** :
avant ce durcissement, un CRLF dans `email` franchissait déjà la validation de champ du
plugin Form de Grav, mais était neutralisé en aval par la bibliothèque d'envoi (PHPMailer,
cœur Grav), qui supprimait l'en-tête Reply-To plutôt que d'y injecter le contenu — aucune
injection de Bcc/Cc n'a jamais été observée. Depuis ce durcissement, le rejet intervient plus
tôt : c'est ce plugin contact qui refuse la soumission, avant même que PHPMailer n'intervienne.
Attribution actuelle : rejet = ce plugin ; protection complémentaire observée en aval =
PHPMailer, qui n'est plus la seule barrière.

### Preuve de non-régression

`tests/test-contact-routing.sh` (voir `docs/testing.md`) automatise la reproduction
synthétique du comportement corrigé sur **60 assertions individuellement nommées**, en
sections : présentation du champ (y compris la non-substitution de l'option générale et
l'exclusion totale d'un identifiant en doublon ou en triplet, ordre normal et inversé),
routage nominal capturé via un SMTP jetable, entrées invalides, sécurité du formulaire,
réservation de `general` et collisions (exclusion fermée, indépendante de l'ordre),
éligibilité approfondie (page non routable, non publiée, profondeur inattendue, slug hors
format), validation des adresses propriétaires, disponibilité conditionnelle de l'option
générale, matrice détaillée XSS/CRLF (balise HTML acceptée puis échappée vs balise
`<script>` rejetée, six cas CR/LF/CRLF rejetés directement par le plugin dans `email` et
`nom`, contenu Unicode normal délivré sans protection nécessaire), et un cas synthétique à
deux formulaires dans une même requête. Rejoué contre l'image construite avant ce correctif,
ce script échoue dès sa première vérification — la preuve que le test couvre réellement le
défaut corrigé, pas seulement le nouveau comportement en surface.
