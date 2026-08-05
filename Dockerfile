# syntax=docker/dockerfile:1
#
# Image applicative "projet-gites", construite sur le runtime générique
# grav-runtime. Ne réimplémente jamais PHP, Nginx, Grav Core/Admin,
# l'entrypoint, le healthcheck ou le bootstrap admin : tout cela appartient
# exclusivement à grav-runtime (voir docs/runtime-contract.md).
#
# Version épinglée explicitement — jamais "latest" (voir
# docs/compatibility-policy.md pour la matrice de compatibilité certifiée).
FROM ghcr.io/sepp67/grav-runtime:1.0.4

# Code applicatif immuable : thème, plugins métier, configuration versionnée
# (voir docs/secrets-and-config.md pour la classification détaillée).
COPY --chown=www-data:www-data grav/user/themes/  /var/www/html/user/themes/
COPY --chown=www-data:www-data grav/user/plugins/ /var/www/html/user/plugins/
COPY --chown=www-data:www-data grav/user/config/  /var/www/html/user/config/

# Contenu initial : copié dans le volume persistant par le mécanisme de seed
# de grav-runtime (/opt/grav-seed/), uniquement si le volume est vide au
# premier démarrage — jamais écrasé ensuite (voir docs/seed-lifecycle.md).
COPY --chown=www-data:www-data grav/user/pages/ /opt/grav-seed/pages/
