<?php
// Fixture de test — valeurs fictives, jamais un vrai secret. Structure
// attendue par contact.php::loadEmailPrivateConfig() : chaque clé est
// fusionnée dans plugins.email.mailer.smtp.* (voir docs/secrets-and-config.md).
return [
    'server'     => 'smtp.test.invalid',
    'port'       => '2525',
    'encryption' => 'tls',
    'user'       => 'test-user@test.invalid',
    'password'   => 'FIXTURE-SECRET-DO-NOT-REUSE-9f8e7d6c',
];
