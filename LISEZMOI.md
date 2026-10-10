# CLEAN — nettoyeur pour macOS (Apple Silicon)

Projet complet : application SwiftUI, moteur de nettoyage, tests, script de build et workflow GitHub Actions.
**Rien n'a encore été compilé.** Le fichier `.dmg` n'existe qu'après la réussite du workflow (coche verte ✅).

## Obtenir le .dmg (environ 15 minutes, sans Terminal)

1. **Compte GitHub** (gratuit) : https://github.com → « Sign up ».
2. **Nouveau dépôt** : bouton **+** en haut à droite → **New repository** → nom `clean-mac` → laissez tout le reste → **Create repository**.
   Choisissez **Public** (compilation gratuite). En privé, les minutes macOS sont comptées ×10 sur le quota gratuit.
3. **Décompressez** `CLEAN-projet.zip` (double-clic). Ouvrez le dossier `CLEAN`.
4. **Affichez les fichiers cachés** dans le Finder : ⌘ + ⇧ + `.` (point). Le dossier `.github` apparaît.
5. Dans le dossier `CLEAN`, **⌘ + A** (tout sélectionner) puis **glissez le contenu** dans la page GitHub du dépôt (lien « uploading an existing file »).
   Glissez le *contenu* du dossier, pas le dossier lui-même. Cliquez **Commit changes**.
6. Si `.github` n'a pas été envoyé : **Add file → Create new file**, nom `.github/workflows/build.yml`, collez le contenu de `workflow-build.yml`, **Commit changes**.
7. Onglet **Actions**. Si GitHub le demande, cliquez « I understand my workflows, go ahead and enable them ».
   Le build démarre seul. Sinon : **Build CLEAN** (à gauche) → **Run workflow** → **Run workflow**.
8. Attendez 5 à 15 minutes. **Coche verte ✅** : cliquez sur l'exécution, descendez à **Artifacts**, téléchargez **CLEAN-macOS-arm64**, décompressez : le `.dmg` est dedans.
   **Croix rouge ❌** : ne l'installez pas. Téléchargez l'artefact **logs** (ou copiez les lignes rouges) et envoyez-moi le contenu.

**Lien stable (facultatif)** : *Releases → Create a new release* → tag `v1.0.0` (Create new tag) → **Publish release**. Le workflow joint alors le `.dmg` à la release (téléchargeable sans connexion si le dépôt est public).

## Installer

1. Double-clic sur le `.dmg`, glissez **CLEAN** sur **Applications**.
2. Ouvrez CLEAN. L'application est signée « ad hoc » mais **non notarisée** : macOS affiche un avertissement.
   Cliquez **Terminé**, puis **Réglages Système → Confidentialité et sécurité**, descendez, cliquez **Ouvrir quand même**, validez. Ce n'est à faire qu'une fois.
   Gatekeeper n'est jamais désactivé.

## Premier test conseillé

1. Ouvrez les **Réglages** de CLEAN (⌘ ,) et activez **Mode simulation**.
2. Cliquez **Nettoyer mon Mac**, regardez **Voir les détails**, lancez la simulation, consultez le rapport.
3. Désactivez la simulation pour un vrai nettoyage.

## Ce que fait / ne fait pas CLEAN

- Nettoie : caches d'applications (hors Apple et applications ouvertes), journaux et rapports de plantage de plus de 30 jours, fichiers temporaires de plus de 3 jours, caches Xcode/Swift, npm, pnpm, Homebrew (seulement s'ils existent).
- « À vérifier » (décoché par défaut, confirmation requise) : résidus d'applications désinstallées.
- Corbeille : action séparée avec confirmation distincte.
- Jamais supprimés : documents, photos, iCloud, trousseaux, cookies, sauvegardes, simulateurs et archives Xcode, téléchargements. Les gros fichiers sont seulement signalés.
- Seuls des dossiers enfants directs de zones autorisées sont supprimés ; liens symboliques jamais suivis ; chaque élément est revalidé juste avant suppression.
- Journal local : `~/Library/Application Support/CLEAN/operations.log`. Aucune télémétrie. Les fichiers supprimés ne sont pas restaurables par CLEAN.

## Organisation

```
CLEAN/
├── Package.swift
├── LISEZMOI.md
├── workflow-build.yml        (copie visible du workflow)
├── .github/workflows/build.yml
├── resources/Info.plist
├── scripts/build_app.sh, make_icon.swift
├── Sources/CleanCore/        (moteur : analyse, sécurité, suppression)
├── Sources/Clean/            (interface SwiftUI)
└── Tests/CleanCoreTests/     (tests unitaires)
```
