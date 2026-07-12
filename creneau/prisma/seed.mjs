// Seed : réglages par défaut + compte admin + exemple de type de RDV.
// Idempotent : ne recrée rien si les données existent déjà.
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

function slugify(text) {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

async function main() {
  await prisma.settings.upsert({
    where: { id: 'main' },
    update: {},
    create: { id: 'main' },
  });

  const adminEmail = process.env.ADMIN_EMAIL || 'admin@example.com';
  const adminPassword = process.env.ADMIN_PASSWORD || 'admin123';
  const adminName = process.env.ADMIN_NAME || 'Admin';

  const existing = await prisma.user.findUnique({ where: { email: adminEmail } });
  if (existing) {
    console.log(`Admin déjà présent : ${adminEmail}`);
    return;
  }

  const user = await prisma.user.create({
    data: {
      email: adminEmail,
      name: adminName,
      slug: slugify(adminName),
      passwordHash: bcrypt.hashSync(adminPassword, 12),
      isAdmin: true,
      availability: {
        create: [1, 2, 3, 4, 5].flatMap((weekday) => [
          { weekday, startMinute: 9 * 60, endMinute: 12 * 60 },
          { weekday, startMinute: 14 * 60, endMinute: 18 * 60 },
        ]),
      },
      eventTypes: {
        create: [
          {
            name: 'Démo (30 min)',
            slug: 'demo-30',
            description:
              'Une démonstration personnalisée de 30 minutes, en visio.',
            durationMin: 30,
            bufferAfterMin: 10,
            questions: JSON.stringify([
              {
                id: 'societe',
                label: 'Votre société',
                type: 'text',
                required: true,
              },
              {
                id: 'contexte',
                label: 'Dites-nous en deux mots votre besoin',
                type: 'textarea',
                required: false,
              },
            ]),
          },
        ],
      },
    },
  });

  console.log(`Admin créé : ${user.email} (page publique : /${user.slug})`);
  if (!process.env.ADMIN_PASSWORD) {
    console.log('⚠️  Mot de passe par défaut "admin123", change-le vite !');
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
