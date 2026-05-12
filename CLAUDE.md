# CLAUDE.md — Wired Client (macOS)

Notes pour Claude (et autres assistants IA) qui travaillent sur ce dépôt.

## Ce que ce repo contient

| Chemin | Rôle |
|---|---|
| `Wired 3/` | App macOS — UI native (chats, boards, fichiers, bookmarks, admin) |
| `Wired 3Tests/` | Tests unitaires de l'app |
| `Wired 3UITests/` | Tests UI |
| `wiredsyncd/` | Daemon de synchronisation des dossiers, en arrière-plan |
| `Wired-macOS.xcodeproj` | Projet Xcode |

**Dépendance locale** : `Wired-macOS` consomme `WiredSwift` via le paquet local
`../WiredSwift`. Les deux repos sont supposés clonés côte à côte.

## Documentation déjà existante — lis-la avant d'agir

| Fichier | Quand le consulter |
|---|---|
| [CONTRIBUTING.md](CONTRIBUTING.md) | Setup, style, tests, workflow PR |
| [SECURITY.md](SECURITY.md) | Politique de signalement de vulnérabilité |
| [README.md](README.md) | Vue d'ensemble, build, run |
| [CHANGELOG.md](CHANGELOG.md) | Historique des changements |
| `../WiredSwift/COMPATIBILITY.md` | **À lire dès que la PR change la façon dont l'app parle au serveur** |

## Règles non négociables

1. **Nom du produit** : conserver « Wired Client » dans les textes visibles
   par l'utilisateur, sauf raison forte.
2. **Compat protocole** : si la PR introduit de nouveaux champs / messages /
   comportements gatés sur la version du pair, les règles de
   `../WiredSwift/COMPATIBILITY.md` s'appliquent des deux côtés du fil.
3. **Sécurité** : credentials/keychain, entitlements, sandbox macOS, chemins
   de fichiers (`wiredsyncd` surtout). Pas de force-unwrap sur des entrées
   réseau ou disque.
4. **SwiftLint** : `swiftlint lint` doit passer. Les fichiers anciens ont des
   règles intentionnellement relâchées — pas de croisade de refactor non
   demandée.
5. **Conventional Commits** : `feat(scope): …`. Scopes courants : `chat`,
   `boards`, `files`, `messages`, `sync`, `ui`, `ci`, `docs`.
6. **PR focalisée** : pas de cleanup non lié au changement.

## Commandes utiles

```bash
# Lint
swiftlint lint
scripts/run-swiftlint-ci.sh all
scripts/run-swiftlint-ci.sh changed <base-sha> <head-sha>

# Tests app
xcodebuild test \
  -project "Wired-macOS.xcodeproj" \
  -scheme "Wired 3 Unit Tests" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# Tests wiredsyncd
cd wiredsyncd && swift test
```

## Review automatique

Les PR sont relues automatiquement par Claude (Sonnet 4.6) via
[.github/workflows/claude-review.yml](.github/workflows/claude-review.yml).
La review est indicative — elle ne bloque pas le merge. Le focus est :
sécurité (credentials, sandbox, chemins), conventions du projet, qualité.
