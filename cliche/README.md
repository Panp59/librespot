# Cliché

Clone local de CleanShot X pour macOS. Capture d'écran, annotation, OCR, épinglage : tout se passe sur le Mac, rien ne part dans le cloud.

## Fonctionnalités

- **Capture de zone** (⇧⌘7) : sélection au lasso, comme l'outil natif mais en mieux rangé.
- **Capture de fenêtre** (⇧⌘8) : survolez une fenêtre et cliquez. Ombre incluse (désactivable).
- **Capture d'écran entier** (⇧⌘9).
- **Carte d'actions rapides** : après chaque capture, une carte apparaît en bas à droite avec l'aperçu et les actions : Annoter, Copier, Texte (OCR), Épingler, Finder, corbeille. Un clic sur l'aperçu ouvre directement l'éditeur.
- **Éditeur d'annotations** : flèche, cadre, ellipse, trait, surligneur, texte, pixelisation (pour masquer une info sensible), badges numérotés, recadrage. Annuler (⌘Z) et rétablir (⌘⇧Z), couleur et épaisseur réglables, changement d'outil avec les touches 1 à 9. Les dimensions de l'image s'affichent dans le titre de la fenêtre.
- **Joli fond** : une case à cocher ajoute marge, dégradé, coins arrondis et ombre portée, avec aperçu fidèle dans l'éditeur. Parfait pour une doc ou un post.
- **Épinglage** : la capture flotte au-dessus de toutes les fenêtres. Glisser pour déplacer, molette pour redimensionner, double-clic pour fermer, clic droit pour copier, revenir à la taille réelle ou fermer.
- **Extraction de texte (OCR)** : reconnaissance locale via Vision (français et anglais), résultat direct dans le presse-papiers.
- **Copie automatique** : chaque capture part aussi dans le presse-papiers (désactivable).
- Les captures sont enregistrées dans `~/Images/Cliché` (dossier configurable).

## Installation

```bash
cd cliche/mac
./make_app.sh
cp -r build/Cliche.app /Applications/
open /Applications/Cliche.app
```

L'app vit dans la barre de menus (icône viseur d'appareil photo). Pas d'icône dans le Dock, c'est normal.

## Autorisations

À la première capture, macOS demande l'autorisation **Enregistrement de l'écran** :

1. Réglages Système > Confidentialité et sécurité > Enregistrement de l'écran
2. Activer Cliché
3. Relancer l'app (obligatoire, macOS ne recharge pas cette autorisation à chaud)

Important : après chaque recompilation (`make_app.sh`), la signature de l'app change. Si les captures ne marchent plus, retirez Cliché de la liste Enregistrement de l'écran (bouton moins) puis réajoutez-le.

## Réglages

Tout est dans le menu de la barre de menus, sous Réglages :

- Copier automatiquement dans le presse-papiers
- Carte d'actions rapides après capture
- Son de capture
- Ombre des fenêtres capturées
- Lancement au démarrage du Mac
- Dossier de sauvegarde

## Raccourcis

| Raccourci | Action |
|---|---|
| ⇧⌘7 | Capturer une zone |
| ⇧⌘8 | Capturer une fenêtre |
| ⇧⌘9 | Capturer l'écran |
| Échap | Annuler la capture en cours |

Dans l'éditeur : ⌘Z annuler, ⌘⇧Z rétablir, ⌘C copier, ⌘S enregistrer, ⌘W ou Échap fermer, Entrée enregistrer, touches 1 à 9 pour changer d'outil.

## Hors périmètre (v1)

- Capture défilante (scrolling capture)
- Enregistrement vidéo et GIF : c'est le travail de Clap
- Upload cloud : volontairement absent, tout reste local

## Dépannage

- **Rien ne se passe au raccourci** : vérifiez qu'une autre app n'utilise pas déjà ⇧⌘7/8/9 (les raccourcis natifs de macOS utilisent 3/4/5, pas de conflit par défaut).
- **Capture noire ou vide** : autorisation Enregistrement de l'écran manquante, voir plus haut.
- **La carte d'actions ne s'affiche pas** : réactivez-la dans Réglages > Carte d'actions rapides.
