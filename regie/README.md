# Régie

Le poste de commande du Mac, dans la barre de menus. Régie remplace Bartender (rangement des icônes) et One Switch (interrupteurs système), et ajoute le bouton qui manquait : le **mode Démo**.

## Le mode Démo

Un seul geste avant un partage d'écran (Ctrl+Option+D ou le menu) :

- icônes secondaires de la barre de menus masquées
- fichiers du bureau masqués
- Ne pas déranger activé (plus de notifications qui surgissent devant le client)
- mise en veille bloquée

Le même geste après la démo, et tout revient exactement comme avant : chaque composant mémorise son état antérieur. Ce que le mode Démo active est configurable dans le menu (Le mode Démo active).

## Les interrupteurs

- **Masquer les icônes secondaires** : Régie pose un trait et un chevron dans la barre de menus. Maintenez Cmd et glissez les icônes à ranger à GAUCHE du trait, puis cliquez le chevron pour replier ou déplier. Les icônes masquées continuent de tourner, elles sont juste hors de vue.
- **Bureau propre** : masque tous les fichiers du bureau (Finder ne les dessine plus, rien n'est déplacé).
- **Ne pas déranger** : voir configuration ci-dessous.
- **Garder le Mac éveillé** : bloque la mise en veille et l'extinction de l'écran (caffeinate).
- **Apparence sombre** : bascule sombre/clair de tout le système.

## Installation

```bash
cd regie/mac
./make_app.sh
cp -r build/Regie.app /Applications/
open /Applications/Regie.app
```

L'app vit dans la barre de menus (icône interrupteurs). Activez « Lancer au démarrage » dans le menu.

## Configurer Ne pas déranger (une fois)

macOS n'offre aucune API publique pour la concentration : la seule voie officielle passe par l'app Raccourcis. À faire une seule fois :

1. Ouvrez l'app **Raccourcis**
2. Nouveau raccourci, action « Définir le mode de concentration », choisissez **Activer** Ne pas déranger, et nommez-le exactement `Régie Concentration On`
3. Recommencez avec **Désactiver**, nommé `Régie Concentration Off`

Le menu Régie > Configurer Ne pas déranger... affiche ces instructions et ouvre Raccourcis. Au premier déclenchement, macOS demandera l'autorisation d'exécuter le raccourci.

## Autorisations

- **Automatisation (System Events)** : demandée au premier changement d'apparence sombre/claire.
- **Raccourcis** : demandée au premier déclenchement de Ne pas déranger.
- Rien d'autre : pas d'Accessibilité, pas d'enregistrement d'écran.

Après recompilation (`make_app.sh`), la signature ad hoc change : si l'apparence ne bascule plus, retirez puis réautorisez Régie dans Réglages Système > Confidentialité et sécurité > Automatisation.

## Dépannage

- **Le trait et le chevron n'apparaissent pas** : la barre de menus est pleine. Fermez une app de barre de menus, ils reviendront.
- **Une icône refuse d'être masquée** : certaines apps (horloge système...) ne se déplacent pas ; tout ce qui se Cmd-glisse à gauche du trait se masque.
- **Ne pas déranger affiche « non configurée »** : les deux raccourcis n'existent pas encore ou leurs noms diffèrent, voir plus haut.
