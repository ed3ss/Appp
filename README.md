# Trajets 3.0 — Bilan, relecture et sauvegarde

App native SwiftUI, iOS 17 minimum. Compteur GPS, carte, enregistrement écran verrouillé et historique local.

## Nouveautés 3.0

- **Pause automatique**, activable dans Réglages > Enregistrement (désactivée par défaut). Sous 0,5 m/s pendant 15 secondes : pause ; à partir de 1,2 m/s pendant 3 secondes : reprise. Les positions doivent être récentes, précises à 25 m et ordonnées ; une interruption GPS réinitialise la détection. Le GPS continue pendant une pause automatique, tandis qu’une pause manuelle reste manuelle. Désactiver l’option reprend une pause automatique en cours.
- **Bilan détaillé** : vitesse moyenne/maximale, temps estimé en mouvement, arrêts hors pause, moyenne en mouvement et graphique de vitesse sélectionnable. Le mouvement est estimé au-dessus de 0,8 m/s entre fixes espacés d’au plus 10 s ; les anciens trajets utilisent leurs points conservés. Les pertes de GPS rendent ces estimations moins précises.
- **Relecture** : curseur, position sur la carte, vitesse/heure à cet endroit et lecture accélérée. Les pauses et trous GPS sont sautés ; aucune position n’est inventée entre deux portions.
- **Historique** : favoris, catégories voiture/vélo/marche/autre, filtres par catégorie, favoris, semaine/mois, statistiques des 8 dernières semaines ou 6 derniers mois. Catégorie par défaut dans Réglages ; modification individuelle dans le détail d’un trajet.
- **Partage PNG** : aperçu d’une fiche avec tracé vectoriel, nom, date, distance et durée, calculée hors ligne sans fond cartographique. Le fichier contient le tracé : vérifier l’aperçu avant de partager.
- **Sauvegardes JSON restaurables** : export de l’ensemble des trajets et métadonnées ; aperçu du nombre de nouveaux trajets avant import ; fusion par identifiant sans suppression ni remplacement. Une copie locale `avant-import-<UUID>.json` est créée avant toute restauration. Un trajet en cours est exporté comme un instantané terminé. Les préférences d’affichage ne sont pas incluses. Import limité à 30 Mo, 10 000 trajets et 500 000 points ; validation des dates, coordonnées, valeurs et identifiants avant écriture. Import des anciennes archives brutes V1/V2 également accepté. L’import GPX n’est pas inclus ; l’export GPX reste disponible.
- **Affichage personnalisable** : information principale et deux cartes du compteur (vitesse, distance, durée, moyenne), ainsi que valeur principale de la Dynamic Island et de l’écran verrouillé. Choix dans Réglages > Personnaliser les compteurs.

Version 3.0 / build 4 ; même identifiant d’app, même icône, conservation des données V1/V2. **34 tests réussis, 0 échec**, compilation iPhone réussie et IPA vérifié (version 3.0, build 4, icône et extension présentes). [Exécution vérifiée](https://github.com/ed3ss/Appp/actions/runs/39400063935). Fichier local : `Trajets-v3.ipa`. Captures du compteur, de l’historique, du détail, de la relecture et de la fiche partageable contrôlées. La capture facultative a atteint sa limite de 4 minutes avant les écrans statistiques, sauvegarde et personnalisation ; ces trois écrans ont été compilés mais pas contrôlés visuellement. La pause automatique, les échanges de fichiers et l’activité en direct en arrière-plan restent à essayer sur un iPhone réel.

Références techniques : [Swift Charts](https://developer.apple.com/documentation/charts) · [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer).

## Nouveautés 2.1

- Liquid Glass natif sous iOS 26 sur les commandes et contrôles de carte, avec l’apparence système des onglets. Fond dégradé et cartes de statistiques translucides.
- Sur iOS 17/18 : matériaux translucides compatibles. Le réglage d’accessibilité Réduire la transparence remplace le verre personnalisé par un fond opaque.
- Extension WidgetKit intégrée : vitesse compacte dans la Dynamic Island, distance/durée/état en vue agrandie, résumé sur l’écran verrouillé.
- Démarrage automatique de l’activité avec le trajet ; pause/reprise et changements d’unités actualisent le contenu ; Terminer retire l’activité. Après relancement, les activités orphelines sont fermées.
- Toucher l’activité ouvre l’onglet Trajet pour Pause/Reprendre/Terminer. Ces commandes ne sont pas exécutées directement dans l’îlot.
- Option Activités en direct dans Réglages. Un refus du système n’empêche jamais l’enregistrement GPS.
- Actualisations demandées au plus toutes les 5 secondes en déplacement, avec état périmé après 15 secondes sans mise à jour. iOS peut limiter la fréquence ; cet affichage ne remplace pas un compteur instantané. La vitesse n’est pas affichée si la position est trop ancienne, pendant une pause ou après l’arrêt.
- Aucun serveur de notifications push, App Group ou compte supplémentaire. L’extension doit être conservée lors de la signature AltStore (si AltStore demande de retirer les extensions, choisir de les garder).

Liquid Glass requiert iOS 26. La Dynamic Island nécessite un iPhone doté de cet écran ; le résumé verrouillé reste prévu sur les autres iPhone compatibles. iOS limite la durée de vie d’une activité en direct ; l’enregistrement dans l’app est indépendant.

Compilation avec Xcode 26.3, cible minimale iOS 17, version 2.1 / build 3. L’IPA vérifie la présence de l’extension et la cohérence des versions. Les tests ajoutés couvrent les valeurs périmées, la durée active, les pauses et la taille/sérialisation du contenu d’activité.

Validation 2.1 terminée le 20 octobre 2026 : **17 tests réussis, 0 échec**, compilation iPhone et capture du tableau de bord réussies. Le fichier `Trajets-v2.1.ipa` a été contrôlé : archive intacte, version 2.1 / build 3 et extension WidgetKit présente. [Exécution vérifiée](https://github.com/ed3ss/Appp/actions/runs/39341541444). Le fonctionnement de la Dynamic Island sur un appareil réel reste à confirmer. À vérifier sur iPhone : démarrer puis revenir à l’accueil, agrandir l’îlot, verrouiller, pause/reprise, terminer, refuser les activités en direct et activer Réduire la transparence. Les états de l’activité ne contiennent pas les coordonnées GPS.

Références : [Live Activities Apple](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) · [Liquid Glass Apple](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

## Nouveautés V2

- Icône originale : route en forme de T et repère GPS, menthe sur fond sombre.
- Démarrer / Pause / Reprendre / Terminer restent accessibles au bas de l’écran.
- Pause manuelle : durée active et distance excluent les pauses. Aucun trait ne relie les portions avant et après une pause.
- Précision GPS affichée et vitesse mise à jour même à l’arrêt.
- Carte avec suivi de position, vue satellite, vue d’ensemble et plein écran.
- Historique : recherche, filtre de la semaine, distance cumulée et durée active cumulée.
- Renommage des trajets, export GPX 1.1 via la feuille de partage iOS.
- Réglages : kilomètres/miles et maintien optionnel de l’écran allumé pendant l’enregistrement.
- Lecture des archives V1, sauvegarde préalable du fichier existant et récupération d’un trajet interrompu.
- Message persistant et bouton Réessayer si une sauvegarde échoue.

## Installation et mise à jour

Le dépôt privé est [ed3ss/Appp](https://github.com/ed3ss/Appp).
Dans [Actions](https://github.com/ed3ss/Appp/actions), ouvrir la dernière exécution réussie de **Build iOS**, télécharger l’artefact **Trajets-unsigned-ipa**, puis extraire `Trajets.ipa`.

Dans AltStore Classic sur l’iPhone : **My Apps > +**, sélectionner l’IPA. Pour mettre à jour, utiliser le même compte Apple et conserver l’app installée ; **ne pas supprimer Trajets**. Le bundle reste `com.prive.trajets` pour permettre la mise à jour. Exporter les parcours importants en GPX est conseillé avant toute réinstallation.

L’IPA n’est pas signé ; AltStore le signe. Avec un compte Apple gratuit, renouveler avant expiration (7 jours). [Guide Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) · [Renouvellement](https://faq.altstore.io/altstore-classic/your-altstore).

## Utilisation

Démarrer au premier plan et autoriser la localisation pendant l’utilisation avec Position exacte. Attendre le GPS à l’extérieur, puis verrouiller l’écran si souhaité. Pause suspend l’enregistrement ; Reprendre démarre une nouvelle portion du tracé. Terminer sauvegarde le trajet dans Historique. Ouvrir un trajet pour le renommer ou exporter le GPX.

La moyenne inclut les arrêts sans pause, mais exclut les pauses manuelles. Les positions anciennes, imprécises ou incohérentes sont rejetées. Une perte de GPS d’au moins 30 secondes crée une nouvelle portion sans ajouter de distance inconnue. La distance peut donc être sous-estimée en mauvaise réception.

Le GPS peut continuer écran verrouillé grâce au mode iOS de localisation en arrière-plan. Une fermeture forcée, un redémarrage ou une interruption iOS peut arrêter le suivi. Au lancement suivant, le trajet est récupéré jusqu’au dernier point de sauvegarde ; le suivi ne redémarre pas seul. Les tests écran verrouillé et de batterie restent à réaliser sur l’iPhone cible.

## Données

Les trajets sont dans Application Support/trajets.json. Lors de la première ouverture d’un fichier existant en V2, une copie `trajets-avant-v2.json` est conservée sans être remplacée. Les champs V2 sont optionnels pour relire les archives V1. Écritures atomiques à chaque point de déplacement accepté ; points de contrôle à l’arrêt toutes les 5 secondes environ quand le GPS fournit des positions.

Aucun serveur de collecte ni outil d’analyse. Apple Maps peut nécessiter Internet ; les sauvegardes système de l’iPhone peuvent inclure les données. Les exports GPX contiennent les positions et horaires : ils sont partagés seulement sur action de l’utilisateur. Les exports intermédiaires restent dans le dossier temporaire iOS.

## Compilation et vérification

Le workflow macOS génère le projet via XcodeGen, exécute les tests, compile et publie l’IPA iPhone, puis capture le tableau de bord du simulateur. La capture est facultative et ne bloque pas la livraison du paquet. Les minutes GitHub Actions sont prises sur le quota du compte.

Sur Mac : `brew install xcodegen`, `xcodegen generate`, puis ouvrir `Trajets.xcodeproj`. `project.yml` est la source du projet.

Les tests couvrent : distance, doublons, positions erronées, pertes GPS, ancien format V1, pauses multiples, arrêt pendant une pause, reprise sans ajout de distance, récupération après interruption, format/échappement XML du GPX et conversions d’unités.

À vérifier sur l’iPhone : installation par-dessus la V1 et conservation des trajets ; pause/reprise à pied ; 5 minutes écran verrouillé ; export dans Fichiers et ouverture GPX ; suivi/plein écran ; réglage de veille ; localisation refusée ; affichage avec texte agrandi.

V2 validée le 20 octobre 2026 : **13 tests réussis, 0 échec**, compilation iPhone réussie et capture du tableau de bord contrôlée sur un simulateur iPhone SE. Le paquet a été vérifié : version 2.0, build 2, icône présente, identifiant conservé. [Exécution vérifiée](https://github.com/ed3ss/Appp/actions/runs/39338558095). Fichier local : `Trajets-v2.ipa`.

Les avertissements d’isolation du délégué Core Location observés en V2 ont été corrigés en 2.1. Le projet utilise Swift 5. Les interactions sur l’iPhone réel (GPS, verrouillage, partage et mise à jour AltStore) restent à vérifier.

## Logo

Créé avec l’outil intégré de génération d’images. Original dans `Design/logo-original.png`, prompt dans `Design/README.md`, icône opaque 1024 px dans `Trajets/Assets.xcassets/AppIcon.appiconset`.

Références : [Apple : localisation en arrière-plan](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates) · [GPX 1.1](https://www.topografix.com/gpx/1/1/).
