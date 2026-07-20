# Démos automatiques : Claude tourne la vidéo tout seul

Cette recette permet à un CLI Claude (sur le Mac) de produire une vidéo de démo de bout en bout : il écrit le storyboard, pilote le navigateur, déclenche l'enregistrement Clap, puis génère la voix off avec Souffleur. Tu finis le montage dans Clap et tu exportes.

Trois briques déjà en place :

- **Clap** expose une petite API de contrôle locale (menu Clap > « Contrôle par le CLI »).
- **Souffleur** synthétise la voix off française en local.
- **Le MCP Chrome** que tu utilises déjà pilote le navigateur.

## Préparation (une fois)

1. Dans Clap, active « Contrôle par le CLI (démo auto) ». Une fenêtre confirme le port et l'emplacement du jeton.
2. Installe Souffleur : `cd souffleur && ./run.sh selftest`.
3. Rends le wrapper exécutable : `chmod +x clap/clap-ctl.sh`.

## Le déroulé, étape par étape (ce que fait Claude)

1. **Brief** : tu donnes une consigne courte, par exemple « démo de 3 minutes sur la planification de tournées, ton commercial ».

2. **Storyboard** : Claude rédige un storyboard et te le montre pour validation. Chaque étape a une action navigateur et le texte à dire :

   ```json
   {
     "etapes": [
       {"action": "goto", "url": "https://gmao.org/demo", "dire": "Voici OPTIMa, la GMAO d'ADTI."},
       {"action": "click", "selecteur": "#nouvelle-intervention", "dire": "Créons une intervention."},
       {"action": "fill", "selecteur": "#titre", "valeur": "Panne ligne 3", "dire": "On décrit la panne."},
       {"action": "click", "selecteur": "#planifier", "dire": "Et on la planifie sur la tournée du technicien."}
     ]
   }
   ```

3. **Tournage** : après ta validation, Claude
   - démarre l'enregistrement : `clap/clap-ctl.sh start window "OPTIMa"` (ou `start screen`). L'appel ne rend la main que lorsque la capture tourne vraiment : c'est le t=0 de la vidéo.
   - joue chaque étape via le MCP Chrome, en notant le temps écoulé depuis le t=0 au moment où il attaque chaque étape (c'est le `start` de la réplique).
   - laisse un court battement après la dernière action, puis arrête : `clap/clap-ctl.sh stop`. La réponse donne le dossier de la session.

4. **Voix off** : Claude construit le plan Souffleur à partir des temps relevés, puis assemble la narration directement dans le dossier de la session :

   ```bash
   souffleur/run.sh assemble --plan plan.json \
     --out "~/Movies/Clap/<session>/narration.wav"
   ```

   Le rapport indique si une réplique a été repoussée (texte trop long) ; le cas échéant Claude raccourcit et régénère.

5. **Finition** : Claude te dit d'ouvrir Clap et « Rouvrir le dernier enregistrement ». La case « Voix off (Souffleur) » est déjà cochée (Clap détecte le fichier narration.wav). Tu ajustes les zooms, le cadrage, le fond, puis tu exportes le MP4.

## L'API de contrôle Clap (pour référence)

Tout est en loopback (`127.0.0.1`), protégé par le jeton de `~/Library/Application Support/Clap/control.json`, à passer en en-tête `X-Clap-Token`.

| Requête | Effet |
|---|---|
| `GET /health` | Test de vie (sans jeton). |
| `GET /status` | `{recording, session, elapsed}`. |
| `POST /start` `{"target":"screen"}` ou `{"target":"window","match":"OPTIMa","webcam":false}` | Démarre sans compte à rebours, rend la main quand la capture tourne, renvoie le dossier de session. |
| `POST /stop` | Arrête, renvoie le dossier de session (n'ouvre pas l'éditeur). |

Le micro est coupé d'office pendant une démo pilotée par le CLI : la voix off Souffleur le remplace sur la piste finale.

## Notes

- La synchro voix/vidéo est à la seconde près (le `start` d'une réplique = le temps où Claude attaque l'action correspondante). Suffisant pour une narration ; si tu veux caler au poil, tu déplaces la voix dans un éditeur audio, la piste est un simple WAV.
- Rien ne sort du Mac : Clap, Souffleur et les modèles sont tous locaux.
- Si Piper n'est pas installé, Souffleur produit quand même la narration avec la voix macOS, tu passeras à Piper plus tard sans rien changer au reste.
