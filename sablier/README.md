# Sablier

Clone local de Timing (96 euros par an) : suivi du temps automatique sur Mac, sans aucune saisie et sans cloud. Sablier échantillonne l'app au premier plan toutes les 5 secondes, détecte les absences, et reconstruit la journée, aussi fragmentée soit-elle.

## Le principe

Pas de chronomètre à lancer ni de projet à déclarer : c'est justement fait pour les journées où on jongle entre démos, mails, dev et devis. La fragmentation devient une donnée mesurée (nombre de changements de contexte, plus longue période de concentration) au lieu d'un problème de saisie.

- **Capteur** : app au premier plan + titre de la fenêtre (optionnel), toutes les 5 secondes. Au-delà de 3 minutes sans clavier ni souris, le temps ne compte plus, et la session s'arrête rétroactivement au dernier geste.
- **Multi-écrans** : macOS fait défiler la fenêtre sous la souris sans lui donner le focus. Quand le dernier geste est un défilement au-dessus d'une autre app que celle qui a le focus clavier, Sablier attribue le temps à l'app réellement lue, celle sous le pointeur.
- **Catégories par règles** : un simple fichier texte, une règle par ligne (`motif => Catégorie`). Le motif est cherché dans l'app, le **domaine du site** (navigateurs) et le titre de fenêtre. Les règles sont rétroactives : vous les affinez, tout l'historique se reclasse.
- **Distinction des apps web** : quand tout tourne dans le navigateur, Sablier lit le domaine de l'onglet actif (Safari, Chrome, Brave, Edge, Vivaldi, Arc) pour séparer par exemple le mail de Prospex, là où le seul nom « Brave Browser » ne le permettait pas. Seul le domaine est retenu, jamais l'URL complète.
- **Rapport** : frise chronologique colorée de la journée (survolez pour le détail), totaux par catégorie, top des applications, statistiques de fragmentation, vue semaine, export CSV.
- **Bilan IA optionnel** : un bouton envoie les totaux du jour au LLM local (Ollama) qui rédige un court bilan en français. Jamais bloquant, jamais dans le cloud.
- **Barre de menus** : le temps actif du jour, visible en permanence, et le bilan du jour en tête de menu (« Aujourd'hui : 4 h 12, surtout Dev »).
- **Pauses** : suspendre le suivi jusqu'à nouvel ordre, pendant 1 heure, ou jusqu'à demain (pour ce qui ne regarde que vous). L'historique complet s'efface en un clic, sur confirmation.

Dans le rapport : flèches gauche/droite pour changer de jour, clic sur une colonne de la vue semaine pour ouvrir ce jour, la vue « aujourd'hui » se rafraîchit toute seule pendant qu'elle est ouverte.

## Installation

```bash
cd sablier/mac
./make_app.sh
cp -r build/Sablier.app /Applications/
open /Applications/Sablier.app
```

L'app vit dans la barre de menus (icône sablier). Le suivi démarre immédiatement. Pensez à activer « Lancer au démarrage » dans le menu.

## Autorisations

Sablier fonctionne **sans aucune autorisation** : app au premier plan et temps d'inactivité sont accessibles librement.

En option, l'autorisation **Accessibilité** ajoute les titres de fenêtres : le rapport distingue alors « devis Dupont.pdf » de « notice OPTIMa.pdf » au lieu d'un simple « Preview ». Menu > Activer les titres de fenêtres, puis ajoutez Sablier dans Réglages Système > Confidentialité et sécurité > Accessibilité.

En option également, l'autorisation **Automatisation** laisse Sablier lire le domaine de l'onglet actif du navigateur (pour séparer les sites web entre eux). macOS la demande automatiquement au premier passage sur chaque navigateur ; acceptez, et le navigateur apparaît dans Réglages Système > Confidentialité et sécurité > Automatisation. Refusée, Sablier retombe simplement sur le titre de fenêtre. Seul le domaine est lu, jamais l'URL, et rien n'est enregistré d'autre.

Après chaque recompilation (`make_app.sh`), la signature ad hoc change : retirez puis réajoutez Sablier dans la liste Accessibilité si les titres disparaissent.

## Les règles de catégories

Menu > Modifier les règles de catégories, ou éditez directement :

```
~/Library/Application Support/Sablier/regles.txt
```

Format, une règle par ligne, la première qui correspond gagne :

```
prospex => Prospex
mail.google.com => Mails
gmao => OPTIMa
teams => Réunions
xcode => Dev
safari => Web
```

Mettez les motifs les plus précis (domaines de sites, titres de documents) en haut, les plus généraux (noms d'apps comme `safari`, `brave`) en bas — sinon `brave => Web` attraperait tout le web avant vos règles par domaine. Enregistrez puis rouvrez le rapport : tout l'historique est reclassé.

## Bilan IA (optionnel)

Nécessite [Ollama](https://ollama.com) avec un modèle tiré (`ollama pull qwen3:14b`). Modèle configurable via la variable d'environnement `SABLIER_OLLAMA_MODEL`. Sans Ollama, le bouton affiche simplement un message, rien ne casse.

## Vos données

Tout est dans `~/Library/Application Support/Sablier/` : une base SQLite (`sablier.db`) et le fichier de règles. Rien ne quitte le Mac, aucune télémétrie, et l'export CSV vous rend les données brutes quand vous voulez.

## Dépannage

- **Pas de temps affiché dans la barre de menus** : normal tant que la journée n'a pas d'activité enregistrée, ou si le suivi est en pause.
- **Tout finit dans « Autre »** : ajoutez des règles, c'est le signe qu'il en manque.
- **Les titres de fenêtres restent vides** : autorisation Accessibilité absente ou à renouveler après recompilation, voir plus haut.
