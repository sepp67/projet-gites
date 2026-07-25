<?php
// Fixture de test — PHP syntaxiquement valide mais ne retourne pas un
// tableau : contact.php::loadEmailPrivateConfig() doit ignorer ce fichier
// silencieusement (is_array() échoue), sans planter (voir docs/secrets-and-config.md).
return null;
