# Trajets — app iPhone privée

Première version native SwiftUI, iOS 17 minimum. Vitesse GPS en km/h, distance en km, durée, carte du parcours, historique et suppression avec confirmation. Interface française avec thème sombre.

## État

Les sources et le workflow sont préparés sous Windows. La compilation et les tests Swift nécessitent Xcode sur Mac ; ils ne sont pas encore exécutés. Aucun dépôt distant n’a été créé et aucun fichier IPA n’a encore été produit.

## Compiler depuis Windows avec GitHub Actions

1. Créer un dépôt GitHub **privé**, puis y envoyer le contenu de ce dossier, y compris `.github/workflows/ios.yml`, sur la branche `main`.
2. Dans GitHub, ouvrir **Actions > Build iOS > Run workflow** si le workflow ne démarre pas automatiquement.
3. Le Mac hébergé génère le projet Xcode avec XcodeGen, lance les tests puis compile pour iPhone.
4. Télécharger l’artefact **Trajets-unsigned-ipa**, puis extraire `Trajets.ipa` du ZIP.
5. Installer AltServer et AltStore Classic en suivant le [guide officiel Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows).
6. Transférer le fichier IPA sur l’iPhone, ouvrir AltStore Classic > My Apps > + et le sélectionner. AltStore doit le signer avec votre compte Apple ; l’IPA produit ici n’est pas signé.
7. Suivre les demandes d’iOS et d’AltStore pour approuver l’installation et activer le mode développeur si demandé.

Avec la signature gratuite, les apps expirent après 7 jours : voir le [guide AltStore](https://faq.altstore.io/altstore-classic/your-altstore). Garder AltServer accessible pour les renouvellements. La compilation GitHub utilise le quota de minutes du compte ; vérifier le quota avant exécution.

## Utiliser

- Appuyer sur **Démarrer le trajet** et autoriser la localisation pendant l’utilisation, avec la position précise.
- Attendre le signal GPS à l’extérieur. Verrouiller ensuite l’écran si souhaité.
- Appuyer sur **Terminer le trajet**, puis confirmer pour retrouver le parcours dans **Historique**.
- Glisser une ligne de l’historique pour supprimer un trajet.

Le suivi démarre au premier plan et utilise le mode iOS de localisation en arrière-plan, avec indicateur système. L’autorisation « Toujours » n’est pas demandée. Le fonctionnement écran verrouillé reste à valider sur l’iPhone cible. Une fermeture forcée, un redémarrage ou une interruption par iOS peut arrêter le suivi. Au lancement suivant, le dernier trajet interrompu est récupéré jusqu’au dernier point sauvegardé ; le suivi ne redémarre pas automatiquement.

## Données et précision

Les trajets sont enregistrés dans Application Support/trajets.json, par écritures atomiques après chaque point accepté. La protection du fichier permet de continuer à écrire après verrouillage, une fois l’iPhone déverrouillé depuis son démarrage. Aucun serveur de collecte, compte applicatif ou outil d’analyse n’est intégré. Les fonds de carte utilisent Apple Maps et peuvent nécessiter Internet ; les sauvegardes système de l’iPhone peuvent inclure les données de l’app.

Les positions trop anciennes, imprécises ou incohérentes sont rejetées. Les interruptions GPS de 30 secondes ou plus ne sont pas reliées sur la carte et n’ajoutent pas de distance inconnue. La distance peut donc être sous-estimée en cas de mauvaise réception. La vitesse moyenne inclut les arrêts. Pas de mode pause dans cette version.

## Validation à effectuer

- Exécuter le workflow : tests unitaires puis compilation iPhone.
- Installer l’IPA sur un iPhone iOS 17 ou ultérieur.
- Tester l’autorisation acceptée, refusée, puis modifiée dans Réglages.
- Enregistrer un trajet de 10 minutes, dont 5 écran verrouillé ; vérifier distance, durée et tracé.
- Terminer puis relancer l’app : vérifier la conservation de l’historique.
- Forcer la fermeture pendant un trajet de test puis relancer : vérifier la récupération.
- Tester une perte de GPS, la suppression annulée/confirmée et le renouvellement AltStore.

Les tests inclus vérifient la distance, le rejet des doublons et des mauvaises positions, les interruptions GPS, ainsi que la sérialisation de l’historique. Ils ne remplacent pas le test sur appareil réel.

Sur Mac : `brew install xcodegen`, `xcodegen generate`, puis ouvrir `Trajets.xcodeproj`. Le fichier `project.yml` est la source du projet.

Référence Apple : [suivi en arrière-plan](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates).
