<?php

namespace Grav\Plugin;

use Grav\Common\Data\Blueprint;
use Grav\Common\Data\ValidationException;
use Grav\Common\Grav;
use Grav\Common\Page\Interfaces\PageInterface;
use Grav\Common\Plugin;
use RocketTheme\Toolbox\Event\Event;

class ContactPlugin extends Plugin
{
    /**
     * Identifiant public réservé au contact général (hors gîte
     * spécifique). Aucune page de gîte ne peut jamais produire cet
     * identifiant : voir eligibleGitePages(), qui l'exclut avant même de
     * construire la table serveur — jamais un simple ordre de priorité
     * qui pourrait laisser une page l'écraser.
     */
    private const GENERAL_ID = 'general';

    /**
     * Format accepté pour un identifiant public de gîte : ASCII minuscule,
     * chiffres, tiret simple comme séparateur, 1 à 64 caractères, jamais
     * de tiret en tête/fin, jamais deux tirets consécutifs. Exclut par
     * construction `/`, `.` de navigation, l'espace, la casse mixte —
     * aucune ambiguïté de comparaison n'est donc possible : toutes les
     * comparaisons de ce plugin sont des égalités de chaîne strictes.
     * Grav garantit déjà qu'un slug de page est un segment de chemin
     * unique dérivé du nom de dossier, mais ce nom de dossier reste un
     * contenu du site, pas une donnée produite par ce plugin : il est
     * revalidé ici, à la frontière de confiance de ce plugin.
     */
    private const SLUG_PATTERN = '/^[a-z0-9]+(-[a-z0-9]+)*$/';
    private const SLUG_MAX_LENGTH = 64;

    public static function getSubscribedEvents(): array
    {
        return [
            'onPluginsInitialized' => ['onPluginsInitialized', 0],
        ];
    }

    public function onPluginsInitialized(): void
    {
        $this->loadEmailPrivateConfig();

        // Le champ `gite` du formulaire utilise `data-options@` (frontmatter
        // de /contact) pour obtenir ses options dynamiquement. Depuis le
        // durcissement de Blueprint (allowlist des callables `Class::method`
        // admissibles via un `data-*@`), tout fournisseur hors du cœur Grav
        // doit s'enregistrer explicitement ici, avant tout rendu de page —
        // seule cette unique méthode statique est autorisée, rien de plus
        // large (voir contactGiteOptionsProvider() ci-dessous : elle ne
        // retourne que des paires identifiant => libellé public). Si ce
        // plugin est désactivé, cet appel ne s'exécute jamais : le champ se
        // rend alors sans options (`data-options@` refusé par l'allowlist),
        // pas d'erreur, pas de fuite — juste un formulaire de fait
        // inutilisable, cohérent avec un site où le contact serait
        // délibérément coupé.
        Blueprint::addAllowedDynamicCallable(self::class . '::contactGiteOptionsProvider');

        $this->enable([
            'onTwigInitialized' => ['onTwigInitialized', 0],
            'onFormValidationProcessed' => ['onFormValidationProcessed', 0],
        ]);
    }

    public function onFormValidationProcessed(Event $event): void
    {
        $form = $event['form'];
        if ($form->getName() !== 'contact-form') {
            return;
        }

        // Honeypot — attribution précise (voir docs/security-notes.md) :
        // le TYPE de champ `honeypot` et son rendu (normalement invisible)
        // sont fournis par le plugin Form de Grav ; la LECTURE de sa valeur
        // et le REJET de la soumission ci-dessous sont un contrôle
        // applicatif de CE plugin (contact, projet-gites) — Form ne rejette
        // rien de lui-même sur ce champ, il se contente de le transporter
        // comme n'importe quel autre. Le cycle d'événements
        // (onFormValidationProcessed, ValidationException) est
        // l'infrastructure de Form.
        if ($form->value('honeypot')) {
            throw new ValidationException('Votre demande n\'a pas pu être traitée.');
        }

        // Rejet applicatif explicite d'un caractère de saut de ligne dans les
        // champs qui alimentent un en-tête d'e-mail — `email` (Reply-To) et
        // `nom` (Subject). Ne dépend plus uniquement de PHPMailer : une
        // injection CRLF est refusée ICI, avant tout traitement, avec un
        // message générique qui ne réaffiche jamais la valeur fautive.
        // `message` n'est volontairement pas concerné : les retours à la
        // ligne y sont un usage légitime d'une zone de texte, et son
        // contenu est échappé (`|e`) dans le gabarit HTML de l'e-mail, pas
        // inséré dans un en-tête.
        //
        // Attribution après ce durcissement (voir docs/security-notes.md) :
        // le rejet lui-même est un contrôle applicatif de ce plugin contact
        // (projet-gites) ; PHPMailer (cœur Grav) reste une protection
        // complémentaire observée en aval, plus la seule barrière.
        foreach (['email' => 'E-mail', 'nom' => 'Nom'] as $headerField => $headerLabel) {
            $headerValue = $form->value($headerField);
            if (is_string($headerValue) && preg_match('/\r|\n/', $headerValue) === 1) {
                throw new ValidationException(sprintf(
                    "Le champ « %s » contient un caractère non autorisé.",
                    $headerLabel
                ));
            }
        }

        $debut = $form->value('date_arrivee');
        $fin = $form->value('date_depart');

        if ($debut && $fin && $fin < $debut) {
            throw new ValidationException("La date de départ doit être postérieure ou égale à la date d'arrivée.");
        }

        // Cœur de SEC-GITES-001 : la sélection reste une valeur cliente,
        // jamais acceptée telle quelle. Elle doit correspondre à une clé
        // de la table serveur (voir contactTable()) — la même table qui a
        // servi à construire les options affichées. Toute valeur absente,
        // vide, inconnue ou malformée est rejetée ici, avant tout
        // traitement — jamais un repli silencieux vers plugins.email.to.
        $giteId = $form->value('gite');
        if (!is_string($giteId) || $giteId === '' || !array_key_exists($giteId, self::contactTable())) {
            throw new ValidationException("Le gîte sélectionné n'est pas valide. Merci de choisir une option dans la liste proposée.");
        }
    }

    private function loadEmailPrivateConfig(): void
    {
        $path = $this->grav['locator']->findResource('user://config/email-private.php');
        if (!$path || !file_exists($path)) {
            return;
        }

        $credentials = require $path;
        if (!is_array($credentials)) {
            return;
        }

        $config = $this->grav['config'];
        foreach ($credentials as $key => $value) {
            $config->set("plugins.email.mailer.smtp.{$key}", $value);
        }
    }

    public function onTwigInitialized(): void
    {
        $twig = $this->grav['twig']->twig();
        $twig->addFunction(
            new \Twig\TwigFunction('proprietaire_email', [self::class, 'resolveProprietaireEmail'])
        );
        $twig->addFunction(
            new \Twig\TwigFunction('contact_gite_label', [self::class, 'resolveGiteLabel'])
        );
    }

    /**
     * Fournisseur d'options dynamique du champ `gite` (voir `data-options@`
     * dans le frontmatter de /contact). Seule méthode de ce plugin exposée
     * au blueprint — elle ne retourne QUE ce qui doit apparaître au
     * navigateur (identifiant public, libellé public), jamais la page,
     * jamais le compte, jamais l'adresse : ces trois derniers champs de
     * contactTable() ne quittent jamais cette méthode. Ajoute une option
     * vide en tête pour qu'aucun gîte ne soit sélectionné par défaut sur
     * /contact autonome (une fiche de gîte écrase ensuite ce défaut via
     * setData(), simple aide ergonomique côté client — voir
     * gite-item.html.twig).
     *
     * @return array<string,string>
     */
    public static function contactGiteOptionsProvider(): array
    {
        $options = ['' => '— Contacter ce gîte —'];
        foreach (self::contactTable() as $id => $entry) {
            $options[$id] = $entry['label'];
        }

        return $options;
    }

    /**
     * Résolution du destinataire — lit exclusivement la table serveur
     * (jamais pages->find() ni accounts->load() directement ici : ces
     * accès n'existent que dans la construction de la table elle-même).
     * `general` ne provoque jamais de recherche de page : son entrée dans
     * la table a `page => null` par construction.
     */
    public static function resolveProprietaireEmail(?string $giteId): ?string
    {
        if (!$giteId) {
            return null;
        }

        return self::contactTable()[$giteId]['email'] ?? null;
    }

    /**
     * Titre public du gîte sélectionné, pour l'affichage (courriel envoyé
     * au propriétaire) — jamais utilisé pour la résolution du
     * destinataire.
     */
    public static function resolveGiteLabel(?string $giteId): ?string
    {
        if (!$giteId) {
            return null;
        }

        return self::contactTable()[$giteId]['label'] ?? null;
    }

    /**
     * Table serveur unique et structurée : identifiant public => libellé
     * public, type (gite/general), page Grav, nom de compte, adresse déjà
     * validée. Seule source de vérité : le fournisseur d'options affichées
     * (ci-dessus), la validation de soumission et la résolution du
     * destinataire lisent tous les trois EXACTEMENT cette même table —
     * aucune méthode ne recalcule une correspondance différente avec
     * d'autres filtres.
     *
     * Ordre de construction : `general` est réservé EN PREMIER (si
     * l'adresse globale est syntaxiquement valide), avant tout parcours
     * des pages de gîte — aucune page ne peut donc jamais l'écraser
     * (`general` est de toute façon déjà exclu comme slug de gîte possible
     * par eligibleGitePages(), avant même d'atteindre cette méthode).
     *
     * Politique de collision — ÉCHEC FERMÉ, indépendant de l'ordre de
     * Pages::children() ET indépendant de la validité respective des
     * comptes : la détection se fait en regroupant TOUTES les pages
     * éligibles (au sens de eligibleGitePages() : sous-arbre, routable,
     * template, slug conforme, proprietaire renseigné) par identifiant
     * AVANT toute résolution d'adresse. Si un identifiant est porté par
     * plus d'une page, il est exclu intégralement — aucune des pages
     * concernées n'est jamais proposée en option, ne peut jamais être
     * sélectionnée, ni recevoir d'e-mail — même si une seule des deux
     * aurait par ailleurs un compte et une adresse valides. Une collision
     * est une erreur de configuration traitée par exclusion totale,
     * jamais par priorité au premier arrivé ni au premier valide (voir
     * docs/security-notes.md).
     *
     * @return array<string, array{label:string, type:string, page:?PageInterface, account:?string, email:?string}>
     */
    private static function contactTable(): array
    {
        $table = [];

        $generalEmail = self::validatedGeneralAddress();
        if ($generalEmail !== null) {
            $table[self::GENERAL_ID] = [
                'label' => 'Contacter l\'administrateur du site',
                'type' => 'general',
                'page' => null,
                'account' => null,
                'email' => $generalEmail,
            ];
        }

        // Regroupement par identifiant, avant toute résolution d'adresse.
        $byId = [];
        foreach (self::eligibleGitePages() as $page) {
            $byId[$page->slug()][] = $page;
        }

        foreach ($byId as $id => $pages) {
            if (count($pages) > 1) {
                self::logConfigWarning(sprintf(
                    "identifiant public '%s' collisionné entre %d pages (%s) — exclu intégralement, aucune option, aucune résolution possible",
                    $id,
                    count($pages),
                    implode(', ', array_map(static fn (PageInterface $p): string => $p->route(), $pages))
                ));
                continue;
            }

            $page = $pages[0];
            $header = (array) $page->header();
            // eligibleGitePages() garantit déjà la présence d'une chaîne
            // non vide pour 'proprietaire'.
            $username = (string) $header['proprietaire'];
            $email = self::validatedAccountAddress($username, $page);
            if ($email === null) {
                continue; // déjà journalisé par validatedAccountAddress()
            }

            $table[$id] = [
                'label' => (string) $page->title(),
                'type' => 'gite',
                'page' => $page,
                'account' => $username,
                'email' => $email,
            ];
        }

        return $table;
    }

    /**
     * Pages réellement contactables : enfants DIRECTS (aucune profondeur
     * arbitraire — decision explicite, pas de notion de « membre autorisé »
     * hors du sous-arbre à ce stade) du sous-arbre configuré
     * (plugins.contact.gites_root), routables — `PageInterface::routable()`
     * combine déjà par ET son propre état et `published()` (voir le code
     * de Grav Core : « The page must be routable and published ») : une
     * page non publiée n'est donc jamais routable, un seul contrôle
     * suffit — du template métier attendu, dotées d'un identifiant public
     * valide (voir isValidGiteSlug()) distinct de `general`, et d'un
     * `proprietaire` renseigné (chaîne non vide).
     *
     * `visible` n'intervient JAMAIS dans ce filtre : cet attribut ne
     * contrôle que la présence dans le sommaire (déjà établi dans ce
     * projet, voir docs/architecture.md de grav-platform-docs pour la
     * même règle), pas l'accessibilité ni la validité métier d'une fiche.
     * Décision explicite : une fiche publiée, routable, mais retirée du
     * sommaire par choix éditorial reste contactable — un visiteur ayant
     * le lien direct (ou l'ayant précédemment consultée) doit pouvoir
     * continuer à la contacter.
     *
     * @return PageInterface[]
     */
    private static function eligibleGitePages(): array
    {
        $grav = Grav::instance();
        $config = $grav['config'];
        $root = rtrim((string) $config->get('plugins.contact.gites_root', '/gites'), '/');
        $template = (string) $config->get('plugins.contact.gite_template', 'gite-item');

        $rootPage = $grav['pages']->find($root);
        if (!$rootPage) {
            return [];
        }

        $eligible = [];
        foreach ($rootPage->children() as $page) {
            if (!$page->routable()) {
                continue;
            }
            if ($page->template() !== $template) {
                continue;
            }

            $slug = $page->slug();
            if ($slug === self::GENERAL_ID) {
                self::logConfigWarning(sprintf(
                    "page de gîte exclue : '%s' utilise le slug réservé '%s'",
                    $page->route(),
                    self::GENERAL_ID
                ));
                continue;
            }
            if (!self::isValidGiteSlug($slug)) {
                self::logConfigWarning(sprintf(
                    "page de gîte exclue : identifiant '%s' (page %s) hors du format accepté",
                    $slug,
                    $page->route()
                ));
                continue;
            }

            $header = (array) $page->header();
            $username = $header['proprietaire'] ?? null;
            if (!is_string($username) || $username === '') {
                continue;
            }

            $eligible[] = $page;
        }

        return $eligible;
    }

    private static function isValidGiteSlug(string $slug): bool
    {
        return $slug !== ''
            && strlen($slug) <= self::SLUG_MAX_LENGTH
            && preg_match(self::SLUG_PATTERN, $slug) === 1;
    }

    /**
     * Relit le compte pour ce nom d'utilisateur (déjà su présent et non
     * vide par eligibleGitePages()) et valide syntaxiquement son adresse
     * (filter_var FILTER_VALIDATE_EMAIL — déjà disponible en PHP, aucune
     * dépendance ajoutée). Ne journalise jamais l'adresse elle-même,
     * uniquement la page et la nature de l'anomalie : le journal Grav
     * (grav['log']) reste un journal serveur, jamais transmis au
     * visiteur, mais ce plugin y reste sobre par prudence.
     */
    private static function validatedAccountAddress(string $username, PageInterface $page): ?string
    {
        $user = Grav::instance()['accounts']->load($username);
        if (!$user->exists()) {
            self::logConfigWarning(sprintf(
                "gîte exclu : compte '%s' introuvable (page %s)",
                $username,
                $page->route()
            ));

            return null;
        }

        $email = $user['email'] ?? null;
        if (!is_string($email) || $email === '') {
            self::logConfigWarning(sprintf(
                "gîte exclu : compte '%s' sans adresse (page %s)",
                $username,
                $page->route()
            ));

            return null;
        }

        if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            self::logConfigWarning(sprintf(
                "gîte exclu : adresse du compte '%s' syntaxiquement invalide (page %s)",
                $username,
                $page->route()
            ));

            return null;
        }

        return $email;
    }

    private static function validatedGeneralAddress(): ?string
    {
        $address = Grav::instance()['config']->get('plugins.email.to');
        if (!is_string($address) || $address === '') {
            return null;
        }

        if (filter_var($address, FILTER_VALIDATE_EMAIL) === false) {
            self::logConfigWarning('contact général désactivé : plugins.email.to syntaxiquement invalide');

            return null;
        }

        return $address;
    }

    /**
     * Journal serveur (grav['log'], même mécanisme que le cœur Grav et le
     * plugin Form — voir user/plugins/form/form.php). Jamais une adresse
     * en clair, jamais un secret ; un nom de compte y apparaît comme un
     * simple identifiant de configuration, jamais transmis au visiteur.
     */
    private static function logConfigWarning(string $message): void
    {
        Grav::instance()['log']->warning('[contact] ' . $message);
    }
}
