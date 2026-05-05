# Wired Client

[![CI](https://github.com/nark/Wired-macOS/actions/workflows/wiredsyncd-tests.yml/badge.svg)](https://github.com/nark/Wired-macOS/actions/workflows/wiredsyncd-tests.yml)
[![Swift](https://img.shields.io/badge/swift-5.0%2B-orange.svg)](https://www.swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)](https://github.com/nark/Wired-macOS)
[![Version](https://img.shields.io/github/v/tag/nark/Wired-macOS?sort=semver)](https://github.com/nark/Wired-macOS/tags)
[![License](https://img.shields.io/badge/license-BSD-blue.svg)](https://github.com/nark/Wired-macOS/blob/main/LICENSE)

**Wired Client** is a modern macOS client for the **Wired 3.0** protocol.

The project is currently in **beta**. It is already usable, but it is still evolving quickly. If you want the latest macOS version, always download the newest beta build from the project's [GitHub Releases](https://github.com/nark/Wired-macOS/releases).

## Table of Contents

- [What is Wired?](#what-is-wired)
- [Why Wired Client?](#why-wired-client)
- [Screenshots](#screenshots)
- [Download](#download)
- [Main Features](#main-features)
- [About the Wired Server](#about-the-wired-server)
- [Building from Source](#building-from-source)
- [wiredsyncd](#wiredsyncd)
- [Contributing](#contributing)
- [License](#license)

## What is Wired?

**Wired** is a long-running community platform originally created as a modern alternative to Hotline. A Wired server lets you host a private space where users can:

- chat in public rooms
- exchange private messages
- post on discussion boards
- share files
- manage a community with fine-grained permissions

In the Wired 3.0 ecosystem, communication between client and server is encrypted, and the server identity can also be verified on the client side.

## Why Wired Client?

Wired Client aims to provide a native macOS experience that feels approachable while staying true to the spirit of Wired:

- an interface built around conversations, files, and boards
- support for public chats, private messages, and broadcasts
- file transfers and folder synchronization
- saved server bookmarks for quick access
- server information and identity verification
- built-in administration tools when your account has the required privileges

The repository is named `Wired-macOS`, but the main application target and product name are **Wired Client**. This may change later.

## Screenshots

### Conversations

<p align="center">
  <img src="screenshots/1-public-chat.png" alt="Public chat" width="48%">
  <img src="screenshots/2-private-messages.png" alt="Private messages" width="48%">
</p>

### Boards and files

<p align="center">
  <img src="screenshots/3-boards.png" alt="Boards" width="48%">
  <img src="screenshots/4-files.png" alt="Files" width="48%">
</p>

### Server information and administration

<p align="center">
  <img src="screenshots/5-server-infos.png" alt="Server information" width="32%">
  <img src="screenshots/6-server-settings.png" alt="Server settings" width="32%">
  <img src="screenshots/7-server-events.png" alt="Server events" width="32%">
</p>

<p align="center">
  <img src="screenshots/8-server-logs.png" alt="Server logs" width="48%">
  <img src="screenshots/9-account-permissions.png" alt="Account permissions" width="48%">
</p>

## Download

Wired Client is distributed through the project's **GitHub Releases**:

1. Open the releases page: [github.com/nark/Wired-macOS/releases](https://github.com/nark/Wired-macOS/releases)
2. Download the **latest beta** build of `Wired Client`
3. Unzip the archive if needed
4. Move the app to `/Applications`
5. Launch **Wired Client**

### Requirements

- macOS **14.6** or newer

## Main Features

### Public chats

Wired Client lets you join a Wired server's public chat rooms, follow conversations live, see connected users, and participate in a native macOS interface.

In the Wired 3.0 ecosystem, multiple public chats can coexist, making it easier to organize discussions by topic or community.

### Private messages and broadcasts

The client supports direct private conversations between users, as well as broadcast messages. This makes it easy to keep personal conversations separate from public chat rooms.

### Discussion boards

Boards provide a more durable space for discussions than chat. Wired Client includes a dedicated boards interface for browsing topics, reading threads, replying, and keeping track of longer-lived conversations.

Wired 3.0 also brings more modern capabilities here, including reactions and server-side board search.

### File sharing

Wired Client includes a file browser for exploring shared server folders, uploading files, downloading content, and tracking transfers.

For many users, this is one of the core parts of the app: conversations on one side, shared files on the other.

### Folder synchronization

On macOS, Wired Client can pair a local folder with a remote folder to keep content in sync. This feature is powered by a separate component, `wiredsyncd`, documented later in this README.

### Bookmarks and quick access

The client can save connection bookmarks so you can reopen your usual servers quickly. That makes day-to-day access to a Wired community much more convenient.

### Server info and trust

Wired Client can display the main information exposed by a server:

- name and description
- banner image
- server version
- system information
- file count and size

The client can also remember a server identity fingerprint to help detect unexpected key changes when reconnecting.

### Administration tools

If your account has the required privileges, Wired Client also gives you access to several administration views directly inside the app:

- server settings
- connected user monitoring
- events
- logs
- accounts and groups
- permissions
- bans

This part is mainly intended for administrators and moderators, but it is integrated into the same client.

## About the Wired Server

Wired Client is designed to work with the **Wired 3.0** ecosystem built around **WiredSwift**.

The [WiredSwift](https://github.com/nark/WiredSwift) repository includes:

- **WiredSwift**: the Swift library used to build Wired clients
- **wired3**: the server daemon
- **WiredServerApp**: the macOS GUI app for local server administration

Wired Client interoperates with any Wired 3 server sharing the same protocol *major* version. Minor-version differences are negotiated transparently — see [`WiredSwift/COMPATIBILITY.md`](https://github.com/nark/WiredSwift/blob/master/COMPATIBILITY.md) for the policy.

In practice, a Wired server can host a private community with:

- multiple public chats
- private messages
- boards
- file sharing
- server-side search
- accounts, groups, and fine-grained permissions

If you want to install or administer a Wired server, the `WiredSwift` README is the right place to start for the server side.

## Building from Source

This section is for developers who want to build **Wired Client** locally.

### Requirements

- macOS
- Xcode with a macOS 14.6 compatible SDK
- Git

### Important: clone WiredSwift next to this repository

The Xcode project references **WiredSwift** as a **local package** using the path `../WiredSwift`.

To make the project open and build without changing the package reference, you should clone both repositories **side by side**:

```bash
mkdir Wired3
cd Wired3
git clone https://github.com/nark/WiredSwift.git
git clone https://github.com/nark/Wired-macOS.git
```

Your folder layout should look like this:

```text
Wired3/
├── Wired-macOS/
└── WiredSwift/
```

### Open and run the project

1. Open `Wired-macOS/Wired-macOS.xcodeproj`
2. Select the `Wired 3` scheme
3. Build and run from Xcode

The generated app product is **Wired Client**.

### Good to know

- the main app depends on the local `../WiredSwift` package
- `wiredsyncd` is included in this repository as part of the overall client stack
- the app build automatically embeds `wiredsyncd` inside the macOS app bundle

## wiredsyncd

`wiredsyncd` is the background synchronization daemon used by Wired Client for folder sync. It is intentionally separate from the GUI so sync pairs can continue running in the background.

In normal use, **Wired Client installs and manages the daemon for you automatically**, so you usually do not need to interact with it directly.

### What `wiredsyncd` does

At a high level, the daemon:

- stores sync pair configuration
- keeps local synchronization state
- stores passwords in the macOS Keychain
- communicates locally with Wired Client over a Unix socket
- runs background synchronization passes
- talks directly to the Wired server for file operations

### How it fits with Wired Client

The responsibilities are straightforward:

- **Wired Client** manages the interface, configuration, and lifecycle
- **`wiredsyncd`** performs the background sync work
- **Wired Server** remains the remote source and destination

### Running `wiredsyncd` manually

If you are working on sync support or troubleshooting a sync issue, you can also launch the daemon manually:

```bash
cd wiredsyncd
swift build
```

Then:

```bash
WIRED_SYNCD_RESOURCE_ROOT="$(pwd)/../WiredSwift/Sources/WiredSwift/Resources" \
./.build/debug/wiredsyncd
```

If you built a release binary, replace `debug` with `release`.

### Where the daemon is installed for app-managed use

When the app manages it, `wiredsyncd` is installed under:

```text
~/Library/Application Support/WiredSync/daemon/wiredsyncd
```

and loaded through a per-user LaunchAgent:

```text
~/Library/LaunchAgents/fr.read-write.wiredsyncd.plist
```

### Quick troubleshooting

If sync stops working, the first things worth checking are:

- whether the local socket exists
- the daemon logs
- the user LaunchAgent
- whether `wired.xml` is available when running the daemon manually

Useful commands:

```bash
ls -l "$HOME/Library/Application Support/WiredSync/run"
```

```bash
tail -n 200 "$HOME/Library/Logs/WiredSync/wiredsyncd.out.log"
```

```bash
tail -n 200 "$HOME/Library/Logs/WiredSync/wiredsyncd.err.log"
```

If you need the most direct debugging setup, it is often easiest to stop the launchd-managed version first and then run `wiredsyncd` in the foreground.

## Contributing

Issues and pull requests are welcome.

If you contribute to the macOS client, good areas to test include:

- connections to a Wired 3.0 server
- public chats and private messages
- boards
- file transfers
- sync through `wiredsyncd`
- administration views with different permission levels

## License

This project is distributed under the BSD license. See [LICENSE](LICENSE).
