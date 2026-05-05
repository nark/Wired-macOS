# Contributing to Wired Client

Thank you for your interest in contributing to Wired Client.
This document covers local setup, project conventions, and the pull request workflow for the macOS client and its bundled sync daemon.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Code Style](#code-style)
- [Testing](#testing)
- [Commit Conventions](#commit-conventions)
- [Pull Request Workflow](#pull-request-workflow)
- [Project Overview](#project-overview)

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| macOS | 14.6+ | App Store / Apple Developer |
| Xcode | Recent version with macOS 14.6 SDK support | App Store / Apple Developer |
| SwiftLint | 0.63+ recommended | `brew install swiftlint` |
| Git | any | system |

CI currently runs on `macos-14`.

## Getting Started

`Wired-macOS` depends on `WiredSwift` as a local package using the relative path `../WiredSwift`.
Clone both repositories side by side:

```bash
mkdir Wired3
cd Wired3
git clone https://github.com/nark/WiredSwift.git
git clone https://github.com/nark/Wired-macOS.git
```

Expected layout:

```text
Wired3/
├── Wired-macOS/
└── WiredSwift/
```

Open the app project:

```bash
cd Wired-macOS
open Wired-macOS.xcodeproj
```

Use the `Wired 3` scheme to run the app locally.

## Code Style

This project uses **SwiftLint** to keep the Swift codebase consistent.
The configuration lives in [`.swiftlint.yml`](.swiftlint.yml).

### Quick reference

| Convention | Rule |
|-----------|------|
| Indentation | 4 spaces |
| Line length | follow the existing SwiftLint configuration |
| Naming | `camelCase` for Swift APIs and local values |
| Comments | keep them short and useful |
| Legacy files | some structural rules are intentionally relaxed in older files |

### Running the linter

Lint the whole repository:

```bash
swiftlint lint
```

Or use the repo script to lint all or only changed Swift files:

```bash
scripts/run-swiftlint-ci.sh all
```

```bash
scripts/run-swiftlint-ci.sh changed <base-sha> <head-sha>
```

Prefer small, focused refactors when touching older files with pre-existing complexity.

## Testing

Before opening a PR, run the tests that match your change.

### App unit tests

```bash
xcodebuild test \
  -project "Wired-macOS.xcodeproj" \
  -scheme "Wired 3 Unit Tests" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

### `wiredsyncd` package tests

```bash
cd wiredsyncd
swift test
```

If your change affects both the app and sync, run both test suites.

## Commit Conventions

This repository follows [Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>(<scope>): <short summary>
```

Common types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`.

Example scopes for this repository:

- `chat`
- `boards`
- `files`
- `messages`
- `sync`
- `ui`
- `ci`
- `docs`

Examples:

```text
feat(files): add Quick Look previews for remote files
fix(chat): send correct public chat id on deletion
test(sync): expand wiredsyncd package coverage
docs(readme): rewrite project overview for Wired Client
```

## Pull Request Workflow

1. Fork the repository and create a branch from `main`
2. Make your changes in focused commits
3. Run relevant lint and test commands locally
4. Open a pull request against `main`
5. Address review feedback and keep the branch up to date

Please avoid unrelated cleanup in feature PRs unless it is directly needed for the change.

## Project Overview

| Path / Target | Role |
|---------------|------|
| `Wired 3/` | Main macOS client app source |
| `Wired 3Tests/` | App unit tests |
| `Wired 3UITests/` | UI tests |
| `wiredsyncd/` | Background synchronization daemon |
| `Wired-macOS.xcodeproj` | Xcode project for the app |

At a high level:

- the app provides the native macOS UI for chats, boards, files, bookmarks, and administration
- `wiredsyncd` handles folder synchronization in the background
- `WiredSwift` provides the underlying protocol and connection layer

If your change touches the Wired protocol itself (new fields, new messages,
new behaviour gated on the peer's version), follow the rules documented in
[`WiredSwift/COMPATIBILITY.md`](../WiredSwift/COMPATIBILITY.md) — the same
policy applies on both sides of the wire.

If you are changing behavior in the client UI, please keep the public product name as **Wired Client** in user-facing text unless there is a strong reason not to.
