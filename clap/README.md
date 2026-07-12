# Clap 🎬

Clone local de Screen Studio pour macOS : tu enregistres ton écran (ou une
fenêtre), et Clap fabrique une vidéo « propre », zooms fluides sur les
clics, curseur redessiné et lissé, webcam en overlay, fond dégradé, marges,
coins arrondis, ombre portée, avec un **éditeur** pour ajuster le résultat
avant l'export. 100 % natif, 100 % local, aucun abonnement.

## Comment ça marche

Clap n'embellit pas la vidéo en direct : il enregistre **plusieurs pistes
séparément**, puis compose la vidéo finale en post-traitement.

```
Pendant l'enregistrement                 Dans l'éditeur, puis à l'export
─────────────────────────                ──────────────────────────────
écran (sans curseur)  ──► raw.mov   ──►  caméra virtuelle (zooms édités)
souris + clics 60 Hz  ──► session.json   curseur synthétique lissé
touches clavier (opt) ──► session.json   pilule de raccourcis incrustée
webcam (opt)          ──► webcam.mov     vignette cercle/rectangle
micro (opt)           ──► mic.m4a        fond, marges, coins, ombre
                                         ──► MP4 final
```

L'aperçu de l'éditeur et l'export passent par **le même compositeur**
(FrameComposer) : ce que tu vois est exactement ce qui sera exporté.

## Fonctionnalités

- **Enregistrement** : écran principal ou fenêtre seule (suivie si elle
  bouge), compte à rebours 3-2-1, chrono dans la barre de menus, micro,
  webcam et touches clavier activables dans le menu.
- **Éditeur** (s'ouvre à l'arrêt de l'enregistrement) :
  - aperçu WYSIWYG avec lecture et scrub à la souris sur la timeline ;
    raccourcis : **espace** = lecture/pause, **←/→** = image par image
    (**⇧←/⇧→** = par seconde) ;
  - **zooms modifiables** : détectés automatiquement sur les clics, puis
    sélectionnables dans la timeline pour les désactiver, les supprimer,
    en ajouter un à la tête de lecture, **étirer les bords à la souris**, régler
    l'intensité globale ;
  - **rognage** début/fin ;
  - les réglages d'habillage sont **mémorisés** d'un enregistrement à
    l'autre ;
  - habillage : 5 fonds dégradés, couleur unie ou image personnalisée,
    marge, coins arrondis, taille du curseur ;
  - **webcam** : position (4 coins), forme (cercle ou rectangle), taille ;
  - pilule des **touches tapées** (raccourcis type ⌘⇧P) ;
  - les éditions sont sauvegardées dans la session (ré-export possible).
- **Export** : MP4 H.264 en 1080p/1440p/4K/vertical, micro mixé et aligné,
  progression et annulation.

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
| **Accessibilité** | détecter les clics et les touches |
| **Microphone** | la voix off (optionnel) |
| **Caméra** | la vignette webcam (optionnel) |

Après avoir accordé Accessibilité et Enregistrement de l'écran, quitte et
relance l'app.

## Utilisation

1. Menu 🎬 → active si besoin **Micro**, **Webcam**, **Touches**, puis
   « Enregistrer l'écran » ou « Enregistrer une fenêtre ».
2. Compte à rebours (Échap pour annuler), puis fais ta démo, clique là où
   tu veux attirer l'attention, c'est là que la caméra zoomera.
3. Menu 🎬 → « Arrêter et ouvrir l'éditeur » : ajuste zooms, rognage et
   habillage en voyant le résultat, puis « Exporter la vidéo… ».

Les sessions brutes restent dans `~/Movies/Clap/` ; « Rouvrir le dernier
enregistrement » permet de rééditer/ré-exporter sans réenregistrer.

> ⚠️ Si tu actives l'enregistrement des touches, celles-ci sont stockées en
> clair dans `session.json`, ne tape pas de mot de passe pendant une
> capture avec cette option.

## Limites connues

- L'export est calculé sur CPU : compter environ la durée de la vidéo pour
  un export 1080p30 sur Apple Silicon.
- L'aperçu de l'éditeur est fluide mais à ~15 i/s en lecture (le rendu
  exact reste celui de l'export).
- Un seul écran ; l'audio système (sons de l'app) n'est pas capturé, la
  brique existe côté Murmure si on veut l'ajouter.
- Webcam et micro alignés à ±1 image près.

## Pistes d'évolution

- Poignées de redimensionnement des zooms directement dans la timeline.
- Vitesse variable (accélération automatique des temps morts).
- Rendu Metal/Core Image pour des exports beaucoup plus rapides.
- Audio système (réutiliser SystemAudioRecorder de Murmure).
- GIF/WebM, préréglages d'export mémorisés.
