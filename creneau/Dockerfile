# --- Étape 1 : dépendances + build ---
FROM node:22-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY prisma ./prisma
RUN npx prisma generate

COPY . .
# Next a besoin d'une DATABASE_URL au build (aucune requête réelle).
ENV DATABASE_URL="file:/tmp/build.db"
RUN npx prisma db push --skip-generate && npm run build

# --- Étape 2 : image d'exécution minimale ---
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV DATABASE_URL="file:/data/creneau.db"

# Sortie standalone de Next + assets + CLI Prisma pour la migration au boot.
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/prisma ./node_modules/prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /app/node_modules/.bin ./node_modules/.bin
COPY --from=builder /app/node_modules/bcryptjs ./node_modules/bcryptjs
COPY docker-entrypoint.sh ./

RUN mkdir -p /data && chown node:node /data
VOLUME /data
USER node
EXPOSE 3000

CMD ["sh", "docker-entrypoint.sh"]
