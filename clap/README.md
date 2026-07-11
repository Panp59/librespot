# Clap 🎬

Clone local de Screen Studio pour macOS : tu enregistres ton écran, et Clap
fabrique automatiquement une vidéo « propre » — zooms fluides sur les clics,
curseur redessiné et lissé, fond dégradé, marges, coins arrondis et ombre
portée. 100 % natif, 100 % local, aucun abonnement.

## Comment ça marche

Comme l'original, Clap n'embellit pas la vidéo en direct : il enregistre
**deux choses séparément**, puis compose la vidéo finale en post-traitement.

```
Pendant l'enregistrement                 À l'export
─────────────────────────                ──────────────────────────────
écran (sans curseur)  ──► raw.mov   ──►  caméra virtuelle (zoom clics)
souris + clics 60 Hz  ──► session.json   curseur synthétique lissé
micro (optionnel)     ──► mic.m4a        fond, marges, coins, ombre
                                         ──► MP4 final
```

- **Capture** : ScreenCaptureKit (écran principal, curseur masqué, 60 i/s),
  trajectoire souris échantillonnée à 60 Hz + horodatage des clics,
  micro en AAC.
- **Rendu** : caméra virtuelle qui zoome sur les clics avec des transitions
  douces (courbes *smoothstep*, centre lissé façon steadicam), curseur
  vectoriel redessiné avec ondes de clic, compositing Core Graphics,
  encodage H.264 via AVFoundation.

## Installation

Prérequis : macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

```bash
cd clap/mac
./make_app.sh
cp -r build/Clap.app /Applications/
open /Applications/Clap.app
```

Autorisations demandées au premier lancement :

| Autorisation | Sert à |
|---|---|
| **Enregistrement de l'écran** | capturer la vidéo |
| **Accessibilité** | détecter les clics (pour les zooms) |
| **Microphone** | la voix off (optionnel) |

Après avoir accordé Accessibilité et Enregistrement de l'écran, quitte et
relance l'app.

## Utilisation

1. Menu 🎬 → **« Démarrer l'enregistrement »** (le micro s'active/désactive
   dans le menu).
2. Fais ta démo normalement — clique là où tu veux attirer l'attention,
   c'est là que la caméra zoomera.
3. Menu 🎬 → **« Arrêter et préparer l'export »** : la fenêtre d'export
   s'ouvre. Choisis le format (1080p, 1440p, 4K, vertical), le fond, la
   marge, l'intensité du zoom… puis **« Exporter la vidéo… »**.
4. La vidéo finale s'affiche dans le Finder à la fin.

Les enregistrements bruts sont conservés dans `~/Movies/Clap/` :
« Exporter à nouveau le dernier enregistrement » permet de refaire un export
avec d'autres réglages sans réenregistrer.

## Limites de cette v1 (assumées)

- **Pas d'éditeur timeline** : les zooms sont entièrement automatiques
  (déclenchés par les clics). C'est le cœur de la valeur de Screen Studio et
  ça couvre le cas « démo produit rapide » ; l'éditeur viendra après si besoin.
- Écran principal uniquement (pas de sélection de fenêtre ni multi-écrans).
- L'export est calculé sur CPU : compter environ la durée de la vidéo pour
  un export 1080p30 sur Apple Silicon.
- L'audio micro est aligné sur la vidéo à ±0,1 s près.
- Le clavier n'est pas affiché (pas d'incrustation des touches tapées).

## Pistes d'évolution

- Éditeur : timeline avec zooms ajustables/supprimables, aperçu temps réel.
- Enregistrement d'une fenêtre seule ; multi-écrans.
- Webcam en overlay (coin arrondi), incrustation des raccourcis clavier.
- Rendu Metal/Core Image pour des exports beaucoup plus rapides.
- Fonds personnalisés (image, flou du fond d'écran).
