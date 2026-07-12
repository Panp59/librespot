#!/bin/sh
# Applique le schéma à la base (création au premier démarrage), crée le
# compte admin si nécessaire, puis lance le serveur.
set -e
node_modules/.bin/prisma db push --skip-generate
node prisma/seed.mjs
exec node server.js
