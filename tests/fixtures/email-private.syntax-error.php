<?php
// Fixture de test — erreur de syntaxe PHP volontaire. Documente un risque
// connu (voir docs/secrets-and-config.md) : `require` sur ce fichier
// déclenche une ParseError non interceptée par contact.php, qui peut faire
// échouer TOUTES les pages du site (onPluginsInitialized s'exécute à
// chaque requête), pas seulement l'envoi d'e-mail.
return [
    'password' => 'unterminated string
