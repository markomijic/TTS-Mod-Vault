# Prise en main

TTS Mod Vault lit les dossiers `Mods` et `Saves` de Tabletop Simulator, affiche chaque mod, partie enregistrée et objet enregistré avec l'état de ses fichiers de ressources, et vous permet de télécharger les fichiers manquants, de créer des sauvegardes `.ttsmod` et de les restaurer.

- Définissez les dossiers dans Paramètres → Dossiers. Un dossier de sauvegarde est facultatif, mais nécessaire pour que l'état des sauvegardes soit conservé d'un lancement à l'autre.
- La bibliothèque est indexée au démarrage ; cliquez sur Actualiser dans la barre latérale après avoir modifié des fichiers en dehors de l'application. "Vider le cache de Vault" relit tous les fichiers JSON.
- Mods, Parties enregistrées, Objets enregistrés et Sauvegardes sont des onglets au-dessus de la liste. Les objets enregistrés apparaissent quand ils sont activés dans Paramètres → Fonctionnalités, et les sauvegardes dès qu'un dossier de sauvegarde est défini.

# Bibliothèque

- Clic gauche sur un mod pour voir ses ressources et ses actions
- Clic droit sur un mod pour plus d'actions (télécharger, sauvegarder, ouvrir le dossier, renommer, supprimer, ...)
- Ctrl+clic (Cmd+clic sous macOS) pour sélectionner plusieurs mods et lancer des actions groupées
- Survolez l'icône de sauvegarde d'un mod pour voir la date de sauvegarde et le nombre de ressources
- Survolez le sélecteur de type pour voir combien il y a de mods, de parties enregistrées et d'objets enregistrés
- Recherchez, triez et filtrez depuis la barre d'outils ; les actions groupées tiennent compte du texte recherché et des filtres
- Clavier : Ctrl+F place le curseur dans la recherche, F5 actualise, Échap efface la sélection, Suppr supprime le mod sélectionné après confirmation

# Mod sélectionné

Le panneau de droite liste les ressources du mod sélectionné, regroupées par type. Couleurs des URL :

- Rouge : le fichier de ressource est manquant
- Vert : le fichier de ressource est téléchargé
- Orange : une vérification d'URL a marqué l'URL comme invalide
- En surbrillance : la dernière URL sur laquelle vous avez cliqué

Actions :

- Clic gauche ou droit sur une URL pour voir les options (ouvrir, copier, télécharger, remplacer, supprimer le fichier)
- Double-clic sur une miniature PDF pour ouvrir le fichier
- Tout télécharger : télécharge tous les fichiers de ressources manquants. Les fichiers encore manquants ensuite sont vérifiés : la boîte de dialogue "Résultats de la vérification du téléchargement" liste les domaines inaccessibles et les URL qui ne fonctionnent plus. Vous pouvez désactiver cela dans Paramètres → Réseau → Vérifier les fichiers manquants après les téléchargements
- "3 manquantes, 2 invalides" sur une carte : 3 fichiers sont manquants, et une vérification d'URL a trouvé que 2 de leurs URL ne fonctionnent plus, ils ne peuvent donc pas être téléchargés
- Sauvegarder : crée une sauvegarde à partir des fichiers de ressources téléchargés
- Les ressources audio peuvent être exclues globalement dans Paramètres → Fonctionnalités, et ce réglage peut être modifié pour un mod depuis son menu contextuel

# Sauvegardes

- Les sauvegardes sont des archives `.ttsmod` contenant le JSON du mod, son image et tous les fichiers de ressources téléchargés.
- L'état de la sauvegarde compare la sauvegarde au mod : à jour, obsolète (le JSON a changé après la sauvegarde) ou nombre de ressources différent.
- Importer des sauvegardes, dans la barre latérale, restaure des archives dans le dossier Mods. Importer un JSON ajoute un mod à partir d'un fichier JSON.
- Les sauvegardes groupées proposent Ignorer, Remplacer et Remplacer si obsolète, et peuvent supprimer ensuite les fichiers du mod si vous le souhaitez.

# Mettre à jour les URL

La fonction Mettre à jour les URL remplace le début des URL, voire des URL entières, de l'"Ancien préfixe" par le "Nouveau préfixe".

Vous pouvez saisir plusieurs anciens préfixes en les séparant par le symbole `|` (barre verticale). Dans Paramètres → Préréglages de mise à jour des URL, vous pouvez créer des préréglages qui seront ensuite proposés dans la boîte de dialogue Mettre à jour les URL.

Avec un seul ancien préfixe :

- Ancien préfixe : `http://pastebin.com/raw.php?i=`
- Nouveau préfixe : `https://pastebin.com/raw/`

Si votre mod contient `http://pastebin.com/raw.php?i=1234` et `http://pastebin.com/raw.php?i=example`, elles deviendront `https://pastebin.com/raw/1234` et `https://pastebin.com/raw/example`.

Avec plusieurs anciens préfixes :

- Anciens préfixes : `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Nouveau préfixe : `https://pastebin.com/raw/`

Si votre mod contient `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` et `http://pastebin.com/example2`, elles deviendront `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` et `https://pastebin.com/raw/example2`.

# Workshop

- Téléchargez des mods du Workshop depuis la barre latérale avec leur ID ou leur URL du Workshop Steam ; vous pouvez saisir plusieurs ID à la fois.
- Mettre à jour depuis le Workshop télécharge à nouveau le JSON d'un mod déjà présent. L'option Forcer la mise à jour écrase aussi un fichier local plus récent.

# Dépannage

- Le panneau Journal sous la liste enregistre chaque opération et ses échecs ; dépliez-le pour filtrer par niveau et par source, rechercher, copier des entrées ou le vider. Cliquez sur une entrée pour sélectionner son mod.
- Le fichier journal `vault.log` se trouve à côté de la base de données. Ouvrez-le depuis l'en-tête du panneau Journal ou depuis l'onglet À propos ; joignez-le à vos rapports de bug.
- Rien n'apparaît après un changement de dossier ? Cliquez sur Actualiser. Toujours rien ? Vérifiez les chemins des dossiers dans Paramètres → Dossiers et les sous-dossiers exclus.
- Des URL qui fonctionnent échouent quand beaucoup de téléchargements tournent en même temps ? Baissez le nombre de téléchargements simultanés dans Paramètres → Réseau.
- Les vérifications d'URL et la vérification après téléchargement testent d'abord si chaque domaine est accessible. Les URL d'un domaine inaccessible (hors ligne ou bloqué sur votre réseau) ne sont pas marquées comme invalides, et une vérification d'URL qui inclut un tel domaine n'est pas enregistrée. Paramètres → Réseau → Vérifier tous les domaines des mods et parties enregistrées teste chaque domaine utilisé par vos mods et parties enregistrées.
