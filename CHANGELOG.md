# Changelog

All notable changes to Wired Client are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
## [Unreleased]

### Features
- Show mandatory password-change sheet on first login for accounts migrated from Wired 2.5; the sheet cannot be dismissed until a new password is set ([`71989be`](https://github.com/martinmarsian/Wired-macOS/commit/71989be79eebb4c7bed7cc539e75dce3e72a3eef))

## [3.0-beta.22+42] — 2026-04-20

### Bug Fixes
- Fix Finder drag and drop state in FilesView ([`bc31644`](https://github.com/nark/Wired-macOS/commit/bc316443564b8cb678e0f89f6abcac49b02ee6b6))

- Fix tracker reload background execution ([`bef7e95`](https://github.com/nark/Wired-macOS/commit/bef7e959de361bad7b406ecb86688f920052bfc9))


### Other
- Seed default tracker on first launch ([`3e47203`](https://github.com/nark/Wired-macOS/commit/3e4720331ab89328262492de66165f7851b405f7))

## [3.0-beta.21+38] — 2026-04-13

### Bug Fixes
- Fix remote file drag and drop move/link behavior ([`326ec0c`](https://github.com/nark/Wired-macOS/commit/326ec0cb66e6aac7a79833f8f8d7e3c40daabe2d))

- Handle folder overwrite prompt correctly on drag-and-drop ([`6936447`](https://github.com/nark/Wired-macOS/commit/693644709b958ffedcbb16f4895267d41527ad51))

- Skip false overwrite prompt when dragging folders from server ([`00724f0`](https://github.com/nark/Wired-macOS/commit/00724f0b893c0f3c2c32a1709d38b6a5fc27adf5))


### Features
- Add interactive files breadcrumb and server stats ([`cf1d7e2`](https://github.com/nark/Wired-macOS/commit/cf1d7e23f9aeec18222e96f8e445d49fd0c3cf00))

- Sync Wired file labels with macOS Finder color tags ([`600740d`](https://github.com/nark/Wired-macOS/commit/600740d9b05bdcdedaf5676c195c8569d4f6f6b3))


### Other
- Preserve executable metadata in file browser and uploads ([`c5a4876`](https://github.com/nark/Wired-macOS/commit/c5a4876ed298771f7e72addd3687d73c9d35b343))

- Add icons to context menus ([`193035f`](https://github.com/nark/Wired-macOS/commit/193035fecca90af2768028e7f2f3ee7ad3bb601b))

- Add icons to context menus ([`0696638`](https://github.com/nark/Wired-macOS/commit/069663844852e9614717a30c9a41401b3ac4632e))

- Write modern Finder color tags on downloads ([`c6b9068`](https://github.com/nark/Wired-macOS/commit/c6b90689c39c1937c99948a1b948b5562897d466))

## [3.0-beta.20+37] — 2026-04-11

### Bug Fixes
- Fix swiftlint line length error in ChatAttachment ([`3ef725e`](https://github.com/nark/Wired-macOS/commit/3ef725e88558693bda8758fe9e98f945de50583f))

- Fix board post lint issues ([`667dadf`](https://github.com/nark/Wired-macOS/commit/667dadf85396c1f6729d3d17e91862dd0381c6f6))

- Fix easter egg overlay glyph bytes ([`f835adc`](https://github.com/nark/Wired-macOS/commit/f835adce63853d3ac5c15336e8e9b030357c30b6))

- Fix file preview selection in column view ([`32fa956`](https://github.com/nark/Wired-macOS/commit/32fa956e83668fa8e8c1b25121f14d3f90b4f7d1))


### Features
- Add label picker to file context menus and fix column view UI ([`d5dff97`](https://github.com/nark/Wired-macOS/commit/d5dff977561d63a8c50db3b486980b06213fc211))

- Add board attachment composition and preview UX ([`a9ac70e`](https://github.com/nark/Wired-macOS/commit/a9ac70e9fd2908d0087bb78cfdabaadbc8a8b308))

- Add Quick Look for message images ([`c744b09`](https://github.com/nark/Wired-macOS/commit/c744b099211805655f26d19ed45e69ad3c1822bd))

- Add attachment support to chats and private messages ([`9396453`](https://github.com/nark/Wired-macOS/commit/93964534d54035aa5d36acdc75452fe0423b1f77))

- Add Connection menu and Window toolbar shortcuts ([`b12e12d`](https://github.com/nark/Wired-macOS/commit/b12e12ddb1ff54ab0709f23618a7c310b4f2e6a7))

- Show directory counts in tree size column ([`faf794a`](https://github.com/nark/Wired-macOS/commit/faf794a9ef6d02e88e564932432d19c4b5f49860))


### Other
- Enrich FilePreviewColumn with label and sync pair info ([`1b61eee`](https://github.com/nark/Wired-macOS/commit/1b61eee2c59e7b07dd730c732c3204f6968e05b5))

- Tint Finder folder icons with file label color ([`a86cb48`](https://github.com/nark/Wired-macOS/commit/a86cb482749621f6bace39160a9a52c58acce606))

- Persist private message attachment metadata ([`f5edc29`](https://github.com/nark/Wired-macOS/commit/f5edc294b42dcbf86eed7840e88f08c6fcb8a377))

- Restore private message avatar padding ([`bd5362c`](https://github.com/nark/Wired-macOS/commit/bd5362c6513b17f0654570d8fee9c0f19212932b))

- Work around tree header overlap on first row ([`6fcf1ad`](https://github.com/nark/Wired-macOS/commit/6fcf1ad5fd8608ac81691d3944d32a367076f90e))

- Persist tree view sort preferences ([`3722f9d`](https://github.com/nark/Wired-macOS/commit/3722f9d71d196c9b58e0b5ac669a932c4992f3e8))

- Persist preferred files view mode ([`23a0207`](https://github.com/nark/Wired-macOS/commit/23a0207b074db6e9326f3bdb2fbd5ff42d9777cb))

- Relax SwiftLint CI severity ([`7e4ed9d`](https://github.com/nark/Wired-macOS/commit/7e4ed9ddb3367d868501420ce5ce1d7e6d9aed86))


### Performance
- Optimize private message conversation rendering ([`b06b856`](https://github.com/nark/Wired-macOS/commit/b06b8561ec0f7ee813026307adff6163f7d934ed))


### Refactoring
- Split BoardsView files ([`33e6e7a`](https://github.com/nark/Wired-macOS/commit/33e6e7a26998a1f3abf517b541b5cfffa14301bb))

## [3.0-beta.19+36] — 2026-04-08

### Bug Fixes
- Make bookmark queries Xcode 16.2 compatible ([`f780864`](https://github.com/nark/Wired-macOS/commit/f7808643f3b2bccaa9811ec9ffb8101bc93f9a5e))

- Remove unsupported toolbar background helper call ([`b66120e`](https://github.com/nark/Wired-macOS/commit/b66120e56fe50746be7120138445c69ffa9bde85))

- Fix public chat deletion sending wrong chat ID ([`420b1ba`](https://github.com/nark/Wired-macOS/commit/420b1ba23409d30a185d413b556b2b9779ed6bcf))


### CI
- Use dedicated scheme for app unit tests ([`b403796`](https://github.com/nark/Wired-macOS/commit/b403796455e85ce2962403f32d0ddcc3b47f4efc))

- Select latest Xcode in GitHub Actions ([`5150e61`](https://github.com/nark/Wired-macOS/commit/5150e613f5636d09e4329ed856a63910285d18dd))


### Documentation
- Rewrite README for Wired Client ([`a5f4dd0`](https://github.com/nark/Wired-macOS/commit/a5f4dd0f8d3e7b408e327170db9732eada51a37e))


### Features
- Add README screenshots ([`5ebdef0`](https://github.com/nark/Wired-macOS/commit/5ebdef074b96c4f6282c9f8a161ae199e148c719))

- Add community docs and changelog tooling ([`5663ff3`](https://github.com/nark/Wired-macOS/commit/5663ff31f2e38230b8a96b07f6c79cd82e5332da))

- Add Quick Look previews for remote files ([`3b5e71e`](https://github.com/nark/Wired-macOS/commit/3b5e71ed68351447a44a418ab95abb3ed0da7bee))

- Focus searchable fields with Command-F ([`4353f6a`](https://github.com/nark/Wired-macOS/commit/4353f6a11e727e12eb3b40b696322f0c49d5869d))

- Add sortable columns to files tree view ([`620e47e`](https://github.com/nark/Wired-macOS/commit/620e47e9f7cd3a02905d4b5c8ee09b11e0b86f61))

- Add GitHub Actions coverage for app unit tests ([`fbb6bad`](https://github.com/nark/Wired-macOS/commit/fbb6bad6b8d7710397d0b88c03ad12148b42d16b))

- Add wiredsyncd and app unit test coverage ([`2a11c16`](https://github.com/nark/Wired-macOS/commit/2a11c169184954d2856fafcaf4b7f048f0a7cbcf))

- Add SwiftLint CI workflow ([`836c19d`](https://github.com/nark/Wired-macOS/commit/836c19dccbc5f93f1b12db096496c1ada089ffcf))

- Show bookmark name in Chat History connection list when available ([`d86c63b`](https://github.com/nark/Wired-macOS/commit/d86c63b24008af0f5fec33d0fa9042108a8038b1))

- Add chat history archiving, browsing window, and live chat integration ([`9049b4a`](https://github.com/nark/Wired-macOS/commit/9049b4affe237b46c935842478aa85fa0d352161))

- Add hidden /generate debug command to inject 100 fake messages ([`e5e5987`](https://github.com/nark/Wired-macOS/commit/e5e5987998520ea16d5f5b4c30ab0b9ca3c1f794))

- Add windowed message display with async load-more ([`51b634d`](https://github.com/nark/Wired-macOS/commit/51b634db9fb1d6914d0a035c9e052e15c98fbe1d))


### Other
- Update README wording ([`6d322a8`](https://github.com/nark/Wired-macOS/commit/6d322a8e889c8bed9c95ce217b0193cd9512a420))

- Restore toolbar glass helper and fix Xcode 16.2 parse error ([`3a9f791`](https://github.com/nark/Wired-macOS/commit/3a9f79156405a1bd61f9ff4795627145b29c45c1))

- Disable structural lint rules for legacy connection controller ([`02e7943`](https://github.com/nark/Wired-macOS/commit/02e7943428b78684021c184264d34743f01393ec))

- Align test deployment targets with macOS app ([`59ce251`](https://github.com/nark/Wired-macOS/commit/59ce25188a73f77e284e0b17531718a778e4d24d))

- Relax SwiftLint structural limits for legacy files ([`692faa3`](https://github.com/nark/Wired-macOS/commit/692faa389e14379736e1e021db14306a559be671))

- Rename @main app file ([`77659f7`](https://github.com/nark/Wired-macOS/commit/77659f73d3904365097376ef66870c3a8204f499))

- Apply low-risk SwiftLint fixes ([`ca5ad75`](https://github.com/nark/Wired-macOS/commit/ca5ad75148ed951793f6821f5bfda395b313f5bf))

- Remove unused Carthage artifacts ([`dc02665`](https://github.com/nark/Wired-macOS/commit/dc02665ec8101d66e08c5b2c28db825a11dd911c))


### Performance
- Optimize chat message rendering with pre-calculated grouping flags ([`4f2f0f3`](https://github.com/nark/Wired-macOS/commit/4f2f0f30ef66f9cd6470c6d942435d81ce2fd7be))

- Optimize chat rendering performance for large message counts ([`92fdbb4`](https://github.com/nark/Wired-macOS/commit/92fdbb42239ef2a00d1c429f3a178b32f9b48d66))


### Refactoring
- Split wiredsyncd daemon into multiple files ([`b455fe4`](https://github.com/nark/Wired-macOS/commit/b455fe4e96bf377077cfdaccb4c43c35c32def65))

- Refactor feature folders and split FilesView ([`a4a0228`](https://github.com/nark/Wired-macOS/commit/a4a02282d143290f4ab4ecec95ee78ca117acbf8))

## [3.0-beta.18+35] — 2026-04-06

### Bug Fixes
- Avoid sidebar deadlock on disconnect ([`2db0a51`](https://github.com/nark/Wired-macOS/commit/2db0a51606514e497f32edcf2d59cd3a8349b44e))

- Fix command autocomplete for no-arg commands ([`b2ca53c`](https://github.com/nark/Wired-macOS/commit/b2ca53cfa2f9e62233e67c20447ce62acbce7507))


### Features
- Add tracker browsing UI ([`bbb2257`](https://github.com/nark/Wired-macOS/commit/bbb22579c4a0772f147cca7de2109d4cb700e4fc))

- Add server monitor UI ([`dcdaf96`](https://github.com/nark/Wired-macOS/commit/dcdaf966e767aa738d31caae9f22350f9039c6f7))

- Show active transfer progress in user info ([`40f1aca`](https://github.com/nark/Wired-macOS/commit/40f1aca60aae24a59fcf7059b6d71103acf7a3e9))

- Implement /clear chat command ([`d7f2320`](https://github.com/nark/Wired-macOS/commit/d7f23202275f03c5bcaf43a410cf82b750603a02))

- Implement /afk chat command ([`cb329b0`](https://github.com/nark/Wired-macOS/commit/cb329b0939f5c12a11b1fc56d36384656861f102))


### Other
- Anchor tracker info popover to sidebar rows ([`5d5fc59`](https://github.com/nark/Wired-macOS/commit/5d5fc59e0434abde0534b68bd5f432bb859a7f59))

- Refine tracker sidebar navigation ([`1b662bb`](https://github.com/nark/Wired-macOS/commit/1b662bbe1c4d649c9491dc3464f9608d01f3189b))

- Align tracker settings UI with tracker URLs ([`aa238c1`](https://github.com/nark/Wired-macOS/commit/aa238c1fbb56d5a9e4b420157f9ff3baed498717))

- Remove client-side idle timer ([`dae54e5`](https://github.com/nark/Wired-macOS/commit/dae54e54e3cb97f958630d94683f51640bc63edd))

- Handle /broadcast in chat commands ([`e3908ed`](https://github.com/nark/Wired-macOS/commit/e3908eded4db458b6ef1ee8811536ba8e2cea632))


### Refactoring
- Improve bookmark and tracker form state handling ([`413206b`](https://github.com/nark/Wired-macOS/commit/413206b741b433be093194fdc42a67a2150d4bda))

## [3.0-beta.17+33] — 2026-04-02

### Bug Fixes
- Sign wiredsyncd with hardened runtime ([`4467632`](https://github.com/nark/Wired-macOS/commit/44676323ea733ab6e959edd534e17854b040f0e6))

- Make wiredsyncd paths test-configurable ([`cbf60e8`](https://github.com/nark/Wired-macOS/commit/cbf60e84bfddac9a33ffb728a7b3e87c99b1a31d))

- Stabilize wiredsyncd sqlite store ([`905c5d4`](https://github.com/nark/Wired-macOS/commit/905c5d4e44f0a0358a1b5b257c042d68015496cd))

- Secure wiredsyncd credentials in keychain ([`952a649`](https://github.com/nark/Wired-macOS/commit/952a649ebe8ce72aff43b749933018987c78a7fe))

- Sync wired.xml in Wired-macOS bundle with quota fields (7031/7032/7033) ([`04f490c`](https://github.com/nark/Wired-macOS/commit/04f490cd889d164bc4fa8db54b67e822722d883b))

- Fix bidirectional sync loop, missed syncs, and deletions (daemon v11) ([`b717a5b`](https://github.com/nark/Wired-macOS/commit/b717a5b7ae868afabcd1b2f8d567baa33ed988ee))

- Log daemon version update outcome instead of silently swallowing errors ([`57d249a`](https://github.com/nark/Wired-macOS/commit/57d249a59c1f4aef8cd6e1bb67b31a84e4503970))

- Fix daemon startup timeout on sync folder rename ([`6b93107`](https://github.com/nark/Wired-macOS/commit/6b9310715a408bd116a918fc0099da25efa80ad8))

- Fix rename errors for sync folders ([`3ccce97`](https://github.com/nark/Wired-macOS/commit/3ccce97a2107a13b25b5e20317cfc2d80bac6a60))

- Make WiredSyncPairDescriptor internal to match WiredSyncDaemonIPC visibility ([`18134d5`](https://github.com/nark/Wired-macOS/commit/18134d5d3937535f019bf3ef6458a249d58d1430))

- Stabilize sync pair policy and daemon reconciliation ([`1921148`](https://github.com/nark/Wired-macOS/commit/192114820c3ed080fc19d276df553ba58f41b94a))

- Fix GIF cropping by disabling NSImageView intrinsic content size ([`30db536`](https://github.com/nark/Wired-macOS/commit/30db53646326c7991265bc6223896b11a87e4a98))


### CI
- Point wiredsyncd CI at WiredSwift main ([`6fd4c1f`](https://github.com/nark/Wired-macOS/commit/6fd4c1f56baf6a0a7d5bf3b8d001d1390272d489))


### Features
- Add wiredsyncd GitHub Actions workflow ([`d6fb4d7`](https://github.com/nark/Wired-macOS/commit/d6fb4d79d4beeb376aad101b6d61da56232d6a80))

- Implement persistent wiredsyncd pair sessions ([`d548c2f`](https://github.com/nark/Wired-macOS/commit/d548c2f5d4ecf8a86c453e5e1c13ac2ed4eb0634))

- Rename packaged app to Wired Client ([`3587baa`](https://github.com/nark/Wired-macOS/commit/3587baaeb6ea5b1d74734eabf365cb82040e5b79))

- Implement quota fields — max_file_size_bytes, max_tree_size_bytes, exclude_patterns (daemon v12) ([`ad926fd`](https://github.com/nark/Wired-macOS/commit/ad926fd06e7f18bba09c56656b338958c2ab01a1))

- Add folder rename in FileInfoSheet with sync pair update ([`173d0fa`](https://github.com/nark/Wired-macOS/commit/173d0fa34bc84ef6ad4c2604c48a795872a3390e))

- Add wiredsyncd integration and sync pair reconciliation ([`08b9a0f`](https://github.com/nark/Wired-macOS/commit/08b9a0ff10e55bc2e03f099e0ce156376e9b55dc))

- Add client sync folder support and standalone wiredsyncd daemon ([`43c8596`](https://github.com/nark/Wired-macOS/commit/43c859660d76d38f494d00ce7b3aed3eb5f987f5))

- Display large emoji for short emoji-only messages ([`3179506`](https://github.com/nark/Wired-macOS/commit/3179506326ea42a566894433f4a51ee6b009ee92))

- Animate GIF images in ChatRemoteImageBubbleView on macOS ([`b2d8119`](https://github.com/nark/Wired-macOS/commit/b2d8119721fe24ea44124987731f772da2403b40))


### Other
- Pin WiredSwift sync branch in wiredsyncd CI ([`3eea842`](https://github.com/nark/Wired-macOS/commit/3eea84204bc917c4077d5366b019730cf009e1c8))

- Set wiredsyncd nick explicitly ([`789becd`](https://github.com/nark/Wired-macOS/commit/789becdb042af8a4035ae9a5f4d265dc87793f8a))

- Modernize FileInfoSheet with card-based layout ([`160a6c5`](https://github.com/nark/Wired-macOS/commit/160a6c563734dc021aacd0a42ee7b403f6774087))


### Refactoring
- Consume shared wired protocol spec ([`976d150`](https://github.com/nark/Wired-macOS/commit/976d150eedf56d2c554ac5520b053e64bebf13f6))

## [3.0-beta.15+28] — 2026-03-26

### Bug Fixes
- Fix toolbar layout on macOS Sonoma by scoping .searchable() to boardsList column ([`3ec0624`](https://github.com/nark/Wired-macOS/commit/3ec0624b1878bdcdb1cae88818de61e954b05b3b))

- Fix stale binding in ChatInputField coordinator causing text to appear in wrong chat ([`0c120f9`](https://github.com/nark/Wired-macOS/commit/0c120f9a7752cd73c62bbfdf9fb8d890d7c28e3c))

- Replace delete-all/reinsert with upsert to fix SwiftData crash on Sonoma ([`e4bf24f`](https://github.com/nark/Wired-macOS/commit/e4bf24f3d41d8f7a543551fb038e47eaa8af7632))

## [3.0-beta.14+27] — 2026-03-25

### Bug Fixes
- Fix deferred shake animation never playing on thread open ([`5ab1baa`](https://github.com/nark/Wired-macOS/commit/5ab1baa93fbf332d987f85f0ae9473976f9d962c))

- Hide scrollbar in emoji picker for cleaner look ([`97bab86`](https://github.com/nark/Wired-macOS/commit/97bab861542039da1057adca88364e0c1d096973))

- Delay hover popover by 500 ms to avoid blocking clicks ([`29d2744`](https://github.com/nark/Wired-macOS/commit/29d274477d8d844f3251bc5d6d6ccd40fe24c7e8))

- Implement real summary popover + clean up dead code ([`7493d3d`](https://github.com/nark/Wired-macOS/commit/7493d3d18b09f0efbbfd72faf526ccdafe94668d))

- Update topReactionEmojis before reactionsLoaded guard ([`d122a0b`](https://github.com/nark/Wired-macOS/commit/d122a0bb3d1a517b08bde33d09689a85b199a8fd))

- Refresh after toggle without breaking broadcast update ([`6c7310d`](https://github.com/nark/Wired-macOS/commit/6c7310d2d4b3db5bd3cd257ee67535a9ef6e5a20))

- Show reaction bar immediately without waiting for async load ([`d71ecf4`](https://github.com/nark/Wired-macOS/commit/d71ecf499b8849514780695b650e6091915fa54b))

- Update bundled protocol spec with reaction additions ([`2933766`](https://github.com/nark/Wired-macOS/commit/293376698aecf7f370763e7bf7ca5ff35ce855d4))

- Sync protocol spec with reaction additions ([`a91e493`](https://github.com/nark/Wired-macOS/commit/a91e4934cdd1279f3e5913ec274afa2c7efd1857))


### Features
- Emoji reaction system for board threads and posts ([`c17eb36`](https://github.com/nark/Wired-macOS/commit/c17eb3672be5d54a875f9bc6db4d485239ac700b))

- Deferred shake animation on thread open ([`48bc7b6`](https://github.com/nark/Wired-macOS/commit/48bc7b6bc333b91b06553443f50ba9d0892501d8))

- Unread badges + shake animation for incoming reactions ([`c7f6d5c`](https://github.com/nark/Wired-macOS/commit/c7f6d5c029a96311b320aa2fe847219b9f66c09e))

- Add Board Reaction Received event with sound, dock and notification ([`1bea72c`](https://github.com/nark/Wired-macOS/commit/1bea72c87734d5ed9cef0a3ff571eea65554e9ba))

- Add reaction.emojis and reaction.nicks fields (6029, 6030) ([`4f7f702`](https://github.com/nark/Wired-macOS/commit/4f7f702f57e3c20a90899f23174a1e2f03bf051d))

- Add search field to emoji picker ([`8d3a5ab`](https://github.com/nark/Wired-macOS/commit/8d3a5aba5b38ce4dca27c64d8cb4607c52afb67c))

- Full categorised emoji picker with sticky section headers ([`e1729d4`](https://github.com/nark/Wired-macOS/commit/e1729d4895c60e3868a6a7c666141f4d12bfd8f6))

- Replace summary button with hover popover on chips ([`cebd011`](https://github.com/nark/Wired-macOS/commit/cebd01182d6bd2ee45d0e5c9e188b00af5b2afbd))

- Display reactor nicks in summary popover ([`8a8332b`](https://github.com/nark/Wired-macOS/commit/8a8332b6fd629c63530a9c6ee4e8e9adb15d332e))

- Parse thread emoji summary from thread_list, keep in sync with broadcasts ([`718d4ba`](https://github.com/nark/Wired-macOS/commit/718d4baff58180f69641f7bb824e0c914620089e))

- Improved UI — inline controls, emoji picker, thread list preview ([`f325441`](https://github.com/nark/Wired-macOS/commit/f325441d6c3347d45ab0a66a6a173279d07fafd8))

- Implement emoji reaction system for board posts ([`743d1f7`](https://github.com/nark/Wired-macOS/commit/743d1f71cc2415484c53f6c218db2656f15187e6))


### Other
- Minor fixes to thread/post editor ([`9e61537`](https://github.com/nark/Wired-macOS/commit/9e615370ee7418f1625ad6f729960adf2c60f40e))

- Package resolved update ([`e1f5cb8`](https://github.com/nark/Wired-macOS/commit/e1f5cb8c04671e16e79d1bbd761967981adb820c))

- Remove .scrollIndicators(.hidden) from emoji picker scroll views ([`5409fad`](https://github.com/nark/Wired-macOS/commit/5409fadf5c1af5a87e003804a2ef0abf5520a888))

## [3.0-beta.13+25] — 2026-03-24

### Bug Fixes
- Auto-focus ChatInputField when isEnabled transitions false→true ([`956a274`](https://github.com/nark/Wired-macOS/commit/956a274b56844fc1b04707f2a5e788d55591c86e))

- Sync NSTextView editability with isEnabled and fix composer placeholder ([`4d54095`](https://github.com/nark/Wired-macOS/commit/4d540958d378e1da9ec1c84de2ca036b13a5cb9c))

- Route join/leave/nick events to the correct chat instead of public chat ([`22e3ca4`](https://github.com/nark/Wired-macOS/commit/22e3ca470c9d7e0bf2d7f89a1650221c75306070))

- Retry up to 3 times on transient connect errors (EHOSTUNREACH) ([`31645de`](https://github.com/nark/Wired-macOS/commit/31645de1187ec66dde3342a23b11533ed6093f1e))


### Features
- Implement wired.log.* client runtime and ServerLog settings view ([`1c34c74`](https://github.com/nark/Wired-macOS/commit/1c34c74106cb2899fbb9e763986025af330aa27a))

- Persist scroll position in FilesView tree and column views ([`39e8a6c`](https://github.com/nark/Wired-macOS/commit/39e8a6c3240fc537891f93ef3ae40744d07ad21e))

- Persist selected ServerSettingsCategory across tab switches ([`e03180e`](https://github.com/nark/Wired-macOS/commit/e03180e1adef01cca1e9eb23a54838814df84036))

- Persist smart board selection across tab switches ([`2f025e6`](https://github.com/nark/Wired-macOS/commit/2f025e6c0e1e887055ca23801695b630ba8f12d8))

- Preserve board and thread selection across tab switches ([`497441d`](https://github.com/nark/Wired-macOS/commit/497441daa28d6dfd3bf64a3065ca4689e50a5a2c))

- Preserve private message composer draft across tab switches ([`6f81bb2`](https://github.com/nark/Wired-macOS/commit/6f81bb27ea3a8ea8f996a527379409fac0c7b134))

- Preserve chat composer draft across tab switches ([`c3703f0`](https://github.com/nark/Wired-macOS/commit/c3703f0a61ae5d4998ba4e35e57777cc7264d3c3))

- Add content marging to chat scroll indicators ([`1c7cad8`](https://github.com/nark/Wired-macOS/commit/1c7cad827c37c8d6b2cd1e6fbf879644cb24de3e))


### Other
- Update issue templates ([`4df6be7`](https://github.com/nark/Wired-macOS/commit/4df6be7b16ec01c590bd32b80c075ccbcdf6d640))

- Update issue templates ([`2cb3a60`](https://github.com/nark/Wired-macOS/commit/2cb3a605c85cda7d5bd452067b40e33c0c0674ec))

## [3.0-beta.12+24] — 2026-03-23

### Bug Fixes
- Fix command suggestions panel appearing below the window ([`0b33349`](https://github.com/nark/Wired-macOS/commit/0b333493cbde9d575fb598ff7598f42192e09c5a))

- Fix image bubble layout, polish typing-to-image morph animation ([`1a23d0f`](https://github.com/nark/Wired-macOS/commit/1a23d0fd95412847846c493f9ac2f05b51b6e788))

- Fix delayed loading of server events ([`bbddfc0`](https://github.com/nark/Wired-macOS/commit/bbddfc049c25c16554488af3559d52a9cea2c2b4))


### Features
- Add keyboard navigation to slash-command autocomplete ([`ced20ca`](https://github.com/nark/Wired-macOS/commit/ced20ca30ee9928853d5fe63766757062e585e93))

- Add ChatCommand enum and slash-command autocomplete in composer ([`86c0225`](https://github.com/nark/Wired-macOS/commit/86c0225916e5fd92f799487e817896fefdb1d398))

- Add delay to chat topic mouse hover ([`8f819a2`](https://github.com/nark/Wired-macOS/commit/8f819a27d86f3653a43b3840c78a02bb8c079396))

- Add action to create/delete user and group accounts ([`0073aa9`](https://github.com/nark/Wired-macOS/commit/0073aa9aa8cc682d928ac3c3ee940ddbc6fcae70))

- Add chat typing indicator UI and client handling ([`6af559f`](https://github.com/nark/Wired-macOS/commit/6af559fbf2372aadee066337673ce9e78134208b))


### Other
- Display image bubbles in private message conversations ([`5ba4cd2`](https://github.com/nark/Wired-macOS/commit/5ba4cd2839ea2748f6b2728ec12668f651322bfd))

- Join public chat with double-clic ([`6f6ef09`](https://github.com/nark/Wired-macOS/commit/6f6ef096e27fc913fa6f5a2e96c70833274b0198))

- Handle Enter key to apply command autocomplete suggestion ([`51c5768`](https://github.com/nark/Wired-macOS/commit/51c5768d842f2e926d03a90aae44843e1253cad9))

- Move chat row context menu to list-level selection context menu ([`b727b7c`](https://github.com/nark/Wired-macOS/commit/b727b7cf91220b19d100d80d9ff5305d81fb5594))

- Refine chat typing transcript behavior ([`5e8b3e2`](https://github.com/nark/Wired-macOS/commit/5e8b3e27b5a5fc42b4981898b30be5cf100aed11))

- Polish chat typing indicator bubble ([`826a751`](https://github.com/nark/Wired-macOS/commit/826a751e582b620842a16d84b5bde7dacca1a653))

- Checkpoint typing handoff polish ([`8f5bff0`](https://github.com/nark/Wired-macOS/commit/8f5bff04b07798338413feeb31482ca2524a2f08))

- Checkpoint typing bubble morphing ([`1a41fdb`](https://github.com/nark/Wired-macOS/commit/1a41fdb26cbeab6d990a2ac8165b2edf320a97ca))

- WIP typing indicator transcript integration ([`f9d7501`](https://github.com/nark/Wired-macOS/commit/f9d7501e1ee09248c9b18b0794b8064953838975))

- Refine chat typing indicator bubble UI ([`2751bc6`](https://github.com/nark/Wired-macOS/commit/2751bc639994b3e0917474d21468a7347dc8664c))

## [3.0-beta.11+23] — 2026-03-20

### Features
- Implement client events view and live event support ([`9296e4a`](https://github.com/nark/Wired-macOS/commit/9296e4a94736cc738fb98fef9c9b983a2fa05607))

- Add moderation UI and ban management ([`37586c1`](https://github.com/nark/Wired-macOS/commit/37586c1a15118f79b13268919e16da980bc9bf5a))

- Add file navigation progress indicator ([`815e9ec`](https://github.com/nark/Wired-macOS/commit/815e9ec496f3697649a05aaedf03328ab24e50ad))

- Add transient chat search progress indicator ([`93b5182`](https://github.com/nark/Wired-macOS/commit/93b5182ac028c0e975a73d3386fb5b6dfa61b416))

- Add board search UI and client integration ([`b4c17a0`](https://github.com/nark/Wired-macOS/commit/b4c17a0ab825c65718ba96a8836b3a108b7865e0))

- Add chat search and fix empty detail layout ([`ac908a2`](https://github.com/nark/Wired-macOS/commit/ac908a279cc4392b880dcdb5ac6e3b6640247c80))

- Add message conversation search and filtering ([`b521bd3`](https://github.com/nark/Wired-macOS/commit/b521bd33cc56f9d82392f26c283e4c33d2a45f1d))


### Other
- Refine board and message search progress indicators ([`0ff4413`](https://github.com/nark/Wired-macOS/commit/0ff44138487d5bd96980715503d0f62b62d492db))

- Minor layout adjustment on boards list bottom bar ([`101438c`](https://github.com/nark/Wired-macOS/commit/101438c4d3d8b39aa727f2beb4954c7c5d57e32f))

- Move selected file view type into files view model ([`19ba6f8`](https://github.com/nark/Wired-macOS/commit/19ba6f86cec9adac60e7b7cd94bca5b4c4df014e))

- Add searchable toolbar for chats, messages, boards and files ([`172d4ac`](https://github.com/nark/Wired-macOS/commit/172d4ac41cb8cdfbf2d02853e39f27174d075a8b))

## [3.0-beta.10+22] — 2026-03-19

### Bug Fixes
- Fix Sonoma main window toolbar crash ([`b0a695f`](https://github.com/nark/Wired-macOS/commit/b0a695fa063ef06813bd9216524ca0ffca230471))


### Features
- Add hover popovers to message timestamps ([`d5f3683`](https://github.com/nark/Wired-macOS/commit/d5f3683acc3f5ad47b17ff75144aaf5fe2a890fb))

- Add timestamps to private messages ([`630ded0`](https://github.com/nark/Wired-macOS/commit/630ded0f039fff5e439c93a046830121b4f260e4))

- Add inline chat timestamps ([`b9e053e`](https://github.com/nark/Wired-macOS/commit/b9e053ec98fac2af560c1d68a478abcf87541960))

- Add board unread actions ([`7a2111c`](https://github.com/nark/Wired-macOS/commit/7a2111c1e87c342bfb01046cd20673147eb67e98))


### Other
- Minor change ([`3678156`](https://github.com/nark/Wired-macOS/commit/36781561d16839e533501e315174f1c988ca1aa8))

- Refine join chat view ([`fffdaff`](https://github.com/nark/Wired-macOS/commit/fffdaff86eecbc673028fdb4bbde1e6bfa2cb00a))

- Hide private chats section when empty ([`3da80ef`](https://github.com/nark/Wired-macOS/commit/3da80ef0f4370381eb10162de076f9f88ed13b21))

- Refine ChatTopicView layout ([`7c58578`](https://github.com/nark/Wired-macOS/commit/7c58578727444dd87ce78065670a6ccf53c3449f))

- Surface chat operation failures in the client ([`871639b`](https://github.com/nark/Wired-macOS/commit/871639b3537b160c67be30a173bf1b5b807cfa18))

- Timestamp chat messages ([`6544ce9`](https://github.com/nark/Wired-macOS/commit/6544ce99fb7a6ae5bda5d2cddee2e1e2279719c6))


### Refactoring
- Refactor SettingsView: replace custom components with native SwiftUI Form ([`af118b1`](https://github.com/nark/Wired-macOS/commit/af118b14cd65e3c99c315723babeea3c9167a270))

## [3.0-beta.9+21] — 2026-03-18

### Bug Fixes
- Fix 46 compilation warnings, SwiftUI runtime warnings, and public chat sheet ([`dad04b5`](https://github.com/nark/Wired-macOS/commit/dad04b50f17c9f0c950d9d13dbf254a118d80326))

- Fix private messages sent to self instead of recipient ([`b9aabb0`](https://github.com/nark/Wired-macOS/commit/b9aabb0bec8d269e7fef79b4d981507e26064ddf))

- Fix transfers toggle button color in DM ([`7b6ce09`](https://github.com/nark/Wired-macOS/commit/7b6ce09319e5f85eeb7189988004d8ec625638a3))

- Fix password issue ([`a184434`](https://github.com/nark/Wired-macOS/commit/a184434a385b3c36cafc8779051989d8ac46693f))

- Clear stale keychain password on auth failure ([`88a5916`](https://github.com/nark/Wired-macOS/commit/88a591645d338e9763674387b73b0e225d30810b))

- Don't send password on permissions-only edits ([`56df6e1`](https://github.com/nark/Wired-macOS/commit/56df6e1cbd658414c46438198d597c9f675eddf6))


### Features
- Add user confirmation dialog on server identity change ([`944887d`](https://github.com/nark/Wired-macOS/commit/944887d2bb2f8536264b47c1b5ac197d72cf1e4b))

- Implement change password UI (wired.account.change_password) ([`e173adf`](https://github.com/nark/Wired-macOS/commit/e173adf25b36b21bf742d1df55591b2a2c995b61))

- Add clear button on password field ([`d12d479`](https://github.com/nark/Wired-macOS/commit/d12d479ddff0026bfea235be02dec272ea420690))


### Other
- Refine layout of MessagesView ([`bec615c`](https://github.com/nark/Wired-macOS/commit/bec615cdab3c4449f5478582ae9c27a195f3f381))

- Refine unread badges in chat lists ([`90eef4c`](https://github.com/nark/Wired-macOS/commit/90eef4c3a0e23dc4e5579c6638531219c8616ac6))

- Match private message layout to chat view ([`027f67f`](https://github.com/nark/Wired-macOS/commit/027f67f7a2402305af6ec2b705c4593c3b12fa23))

- Refine chat topic header layout ([`e0db04d`](https://github.com/nark/Wired-macOS/commit/e0db04d00ecf6f0e8b7d259643eb4d5e908ed221))

- Align edge fade with container background ([`fd2c90f`](https://github.com/nark/Wired-macOS/commit/fd2c90f3ca634513d03d4505d4410163643caff3))

- Refine chat edge fade and scroll indicator inset ([`8f95251`](https://github.com/nark/Wired-macOS/commit/8f95251b733fc6b8ec1420757f0500472025619e))

- Remove automatic keychain clearing on auth failure ([`c0f5092`](https://github.com/nark/Wired-macOS/commit/c0f50926f161fb61eac2863ff1a7d9acecf5378e))

- Remove passwordExplicitlySet workaround ([`c518132`](https://github.com/nark/Wired-macOS/commit/c518132b5bab4d0c5bb934f115cbc3d1d30e9892))

- Some liquid UI experiments ([`450f1fa`](https://github.com/nark/Wired-macOS/commit/450f1fa7b45bfef50d6d9eca25e9fb18f4b1df54))


### Refactoring
- Improve boards bootstrap, auto-read threads, and chat/board UI refinements ([`821c2bb`](https://github.com/nark/Wired-macOS/commit/821c2bb3575f813a563bba628d751af10e1a5d92))

## [3.0-beta.8+18] — 2026-03-17

### Bug Fixes
- Constrain ServerInfoView width, center content, add top padding ([`9e5f324`](https://github.com/nark/Wired-macOS/commit/9e5f3246d3bab22fe1d85edb12ad971434cfa1a9))

- Improve ServerInfoView layout — breathing room, two-column grid alignment ([`7838328`](https://github.com/nark/Wired-macOS/commit/78383283c1a9bce1e68ac9b10f3ff4d901bf762b))

- Fix duplicate Error Log/Settings menu entries ([`b889d54`](https://github.com/nark/Wired-macOS/commit/b889d54c6ce09e1a858f75ba80dfb1e5085bda73))


### Features
- Add missing file ([`dc54048`](https://github.com/nark/Wired-macOS/commit/dc54048b116cfbd0c0f3d2d57026c76d0234dfe4))

- Show P7 and Wired protocol versions in ServerInfoView and UserInfosView ([`92d3cec`](https://github.com/nark/Wired-macOS/commit/92d3cec2efb8fc37660e98cf9b7ebe83b1eff968))

- Add server identity badge to ServerInfoView (TOFU) ([`abd7a2f`](https://github.com/nark/Wired-macOS/commit/abd7a2fed883b26d3f61327eb3fed0bc4e889341))

- Implement client-side TOFU for server identity (A_009) ([`cd4b087`](https://github.com/nark/Wired-macOS/commit/cd4b08726b0594bc3bdf0748651886896d68f78b))


### Other
- Some experiments around liquid glass design ([`13db977`](https://github.com/nark/Wired-macOS/commit/13db977ecf9b4776e8bb102a11da30d3fbacc5bf))

- Minor layout fix ([`2d01f2e`](https://github.com/nark/Wired-macOS/commit/2d01f2e4318d2a30d0f20bcd540d2d95d4e86caf))

- Minor layout fix ([`10cfef7`](https://github.com/nark/Wired-macOS/commit/10cfef7640d4dd336a5b6911dc97a084c4634313))

- Refine chat topic UI, permissions, and iPad/iPhone navigation behavior ([`eaae99c`](https://github.com/nark/Wired-macOS/commit/eaae99cd7cd7b1426c7d825a95f036d61d8d5708))

- IOS cross-platform fixes (layout, boards, navigation) ([`254da3d`](https://github.com/nark/Wired-macOS/commit/254da3d888718193cf82d783cbf76517025845ff))


### Refactoring
- Refactor app shell and settings for iOS cross-platform support ([`f2166d7`](https://github.com/nark/Wired-macOS/commit/f2166d7159afc3d1fa0778361457635f3ad9e5e3))

## [3.0-beta.7+15] — 2026-03-13

### Bug Fixes
- Clear search mode when navigating history ([`b89e029`](https://github.com/nark/Wired-macOS/commit/b89e029cc2ec93ad63a5fd65f4355a7f6c1df976))

- Preserve search results when switching between column and tree views ([`0e5172e`](https://github.com/nark/Wired-macOS/commit/0e5172e236608c962d5dffba7913d099363970f6))

- Fix column view not refreshing after permission grant ([`63dc65b`](https://github.com/nark/Wired-macOS/commit/63dc65b3535edbff46aaa8966a401176d81acdc2))


### Features
- Add file search with wired.file.search protocol ([`6e10bdf`](https://github.com/nark/Wired-macOS/commit/6e10bdf7a169d0933c27badd2129d6080bdc8993))


### Other
- Adjust toolbar red badges vertical position by 2px ([`3ddee5f`](https://github.com/nark/Wired-macOS/commit/3ddee5f4fd325556eaec05cb1c665485870d0ca3))

- Harden ServerInfo loading for slow links and reconnect ([`e97eecc`](https://github.com/nark/Wired-macOS/commit/e97eecc89f90037f0c04fd2ca91805b3d335ac39))

## [3.0-beta.6+14] — 2026-03-13

### Bug Fixes
- Fix download queue failure on zero-byte files ([`df79662`](https://github.com/nark/Wired-macOS/commit/df79662e3aa460b0078b83c22b74b1066f9a8b29))

- Fix ServerInfo refresh when server metadata changes ([`46bbf11`](https://github.com/nark/Wired-macOS/commit/46bbf11a0c0dc31a93205322f8b7c099bf1c4c34))

- Fix chat unread badge when active chat tab is foreground ([`1d28825`](https://github.com/nark/Wired-macOS/commit/1d2882538d204e6e32a996f98bc40fd1ab8e0825))


### Other
- Update live identity sync and refine sidebar Connect behavior ([`9f62c4a`](https://github.com/nark/Wired-macOS/commit/9f62c4a0407b435f75dce39d3b69ee282ebc3382))


### Refactoring
- Improve server settings autosave UX while typing ([`42dfcd5`](https://github.com/nark/Wired-macOS/commit/42dfcd5bc9b9dbbe97501ed4c8123032e988b08a))

## [3.0-beta.4+12] — 2026-03-13

### Bug Fixes
- Fix server info UI refresh on wired.server_info ([`e93776e`](https://github.com/nark/Wired-macOS/commit/e93776e10c1792cf44653605506d7c3b8e8ef599))


### Features
- Implement message conversation deletion with confirmation ([`d8d6d48`](https://github.com/nark/Wired-macOS/commit/d8d6d4814950d09bee26b09b7ca581056cbbffa3))

## [3.0-beta.2+10] — 2026-03-12

### Bug Fixes
- Fix boards layout with HSplitView ([`7fc28cf`](https://github.com/nark/Wired-macOS/commit/7fc28cfca8f799937379a7a0c8961be499e82f5c))

- Fix compilation error: move lineWidth into StrokeStyle ([`f58a455`](https://github.com/nark/Wired-macOS/commit/f58a455c233f1aa55957fe588d1b4b55961710c4))

- Fix blue stroke appearing on non-future messages ([`2e56e27`](https://github.com/nark/Wired-macOS/commit/2e56e2724e8adce16de08bd64866cc9329e6143d))

- Fix crash when selecting text in chat bubbles ([`e3b4047`](https://github.com/nark/Wired-macOS/commit/e3b40472316ef5faf0a3afd63d780688b52040d1))

- Fix duplicate public chats on connection ([`0791346`](https://github.com/nark/Wired-macOS/commit/0791346a6586db3e780ce830e4e885e3407fdd46))


### Features
- Add chat highlights settings and bubble color previews ([`fbb21fa`](https://github.com/nark/Wired-macOS/commit/fbb21fab24a4e05790c25f4b5bb11fc9d8896486))


### Other
- Splited view layout fix in v26 ([`e322f42`](https://github.com/nark/Wired-macOS/commit/e322f4241e955274f3b8cc13485c8b185bb8d764))

- Update bundle ID and fix keychain issue ([`1e3a136`](https://github.com/nark/Wired-macOS/commit/1e3a13655e49210a3636f11102f19aea1d6fc721))

- Remove tracked .DS_Store files and keep them ignored ([`2db1129`](https://github.com/nark/Wired-macOS/commit/2db1129b782c48391f121cbd72ec6faa95f4250f))

- Refine grouped message spacing in chat and PM lists ([`51d64db`](https://github.com/nark/Wired-macOS/commit/51d64db4eba1ceb685518fa7ed201bbbc8c513a2))

- Group consecutive messages by sender in chat and PM views ([`c73caaf`](https://github.com/nark/Wired-macOS/commit/c73caafa869146a9dbe4728ffe4176609cdea406))


### Refactoring
- Improve chat/message bubbles, unread handling, and new message animations ([`85defeb`](https://github.com/nark/Wired-macOS/commit/85defebc839bc0b5a5a5ef80d99d871baee4e3ec))

## [3.0+5] — 2026-03-06

### Bug Fixes
- Fix version ([`565f637`](https://github.com/nark/Wired-macOS/commit/565f6370a15122d2aa4b935716fa35dbd648855a))

## [3.0+4] — 2026-03-05

### Bug Fixes
- Fix private messages conversation madness ([`47c826a`](https://github.com/nark/Wired-macOS/commit/47c826af3bca81f84178fe46225570177c38cc2c))

- Fix boardPostAdded event not firing on replies for unloaded threads ([`3406524`](https://github.com/nark/Wired-macOS/commit/340652483f47275ab7319386b43c4a97be6f0e01))

- Stabilize new-connection sheet routing and close confirmations ([`9d632d1`](https://github.com/nark/Wired-macOS/commit/9d632d169d9708035283e015e5bb3dc4d4c27070))

- Fix SwiftData store location and legacy migration ([`fa0eaa8`](https://github.com/nark/Wired-macOS/commit/fa0eaa8d7ba2ef7ad36ef9b86dd453704f2a900b))

- Fix SwiftData store path for non-sandbox macOS builds ([`9d161ae`](https://github.com/nark/Wired-macOS/commit/9d161aed7c06d8ad256664b969ab30078404a5db))

- Fix chat history navigation with Cmd+Up/Cmd+Down ([`20bf18e`](https://github.com/nark/Wired-macOS/commit/20bf18ea1819613e19c7fd2c5c8b0a7b7eccf33e))

- Fix stale connection error alert state ([`c4be982`](https://github.com/nark/Wired-macOS/commit/c4be98260364abd285179ae80b69407c16f65812))

- Fix optional user status handling and settings notifications ([`c4fd2c4`](https://github.com/nark/Wired-macOS/commit/c4fd2c445de5b894b270d5030661bffb49fb883c))

- Fix Files tab initial load race in SwiftUI ([`c441414`](https://github.com/nark/Wired-macOS/commit/c441414642f197515d9d50151145e64c81536e82))

- Fix download conflict policy and transfer resume UX ([`68f1687`](https://github.com/nark/Wired-macOS/commit/68f1687407c77ff6cc875715297f65d004a9e7e7))

- Stabilize AppKit file browser tree/columns and Finder drag-drop ([`521b965`](https://github.com/nark/Wired-macOS/commit/521b965edf8c60b46e64b63c7fdf091997ed8280))

- Fix file double-click download gesture in tree and columns ([`19213d7`](https://github.com/nark/Wired-macOS/commit/19213d75bdde63b1a2c03d71126ab92318e5b237))

- Fix clear transfers persistence in SwiftData ([`6341c5f`](https://github.com/nark/Wired-macOS/commit/6341c5f02cee28eba775c4cb7613dac13804e7dd))

- Fix tree/columns sync to avoid file_not_found on file selection ([`5a62ade`](https://github.com/nark/Wired-macOS/commit/5a62ade3ee5474c29cd408b96b884d104138cb1a))


### Features
- Add Events settings panel and configurable event actions ([`b0f4cda`](https://github.com/nark/Wired-macOS/commit/b0f4cdaa117b1af95a6e3300d7c376973bc47442))

- Add support for boards/threads drag and drop WIP ([`f0795d2`](https://github.com/nark/Wired-macOS/commit/f0795d297aff13a60102d21fa1c349e59058729f))

- Add board support ([`76559e0`](https://github.com/nark/Wired-macOS/commit/76559e0da552b21da07ed3a1af20c96766e25918))

- Add per-bookmark nick/status overrides and tighten close/quit prompts ([`e13273d`](https://github.com/nark/Wired-macOS/commit/e13273db484c40b75e4b4a885dc55596a7de36ed))

- Add unread badges to chats and messages toolbar items ([`735d123`](https://github.com/nark/Wired-macOS/commit/735d123ceb4d6ff75e1184de64df9da51093e66e))

- Implement persisted private messages/broadcasts and messages UI refactor ([`05f9241`](https://github.com/nark/Wired-macOS/commit/05f924187db329322e0d4922408de7a70497d52d))

- Add wired color picker and colorize user nicknames ([`620244e`](https://github.com/nark/Wired-macOS/commit/620244e11e63cf88f9c92706a351afa88e91c7ca))

- Show account color permission even when spec omits it ([`38bb7db`](https://github.com/nark/Wired-macOS/commit/38bb7db750bcb29add1f297ae84baaf53fa1dd60))

- Add private chat UX flow with invitations, accept/decline, and cleanup on leave ([`d533d8b`](https://github.com/nark/Wired-macOS/commit/d533d8b357195072f958c57ed37ebc9b1e640d17))

- Add server settings accounts UI and transfer error surfacing ([`bf71e61`](https://github.com/nark/Wired-macOS/commit/bf71e61605e09aabb3cca0f6dd9bdf085f21a79e))

- Add transient retry for early network connect failures ([`4124b19`](https://github.com/nark/Wired-macOS/commit/4124b195662e8e55c76e3afae290ac7a49ac328b))

- Add quit confirmation when transfers are active ([`835f298`](https://github.com/nark/Wired-macOS/commit/835f29870a5ba38213de901c4924b3e1ca9e82d3))

- Add icons and help text to transfers buttons ([`789c63e`](https://github.com/nark/Wired-macOS/commit/789c63e33bfa52679c3f724fa43172ef2f5d7697))

- Add animated transfers badge and auto-open drawer on activity ([`d18b9a7`](https://github.com/nark/Wired-macOS/commit/d18b9a75d8a8dc29479ca862c07e1036e03b99d4))

- Add transfer reveal actions and context menu support ([`924e96d`](https://github.com/nark/Wired-macOS/commit/924e96d348b1b2d39df764fc0101e7d4d8e68522))


### Other
- Update gitignore ([`d07481e`](https://github.com/nark/Wired-macOS/commit/d07481e5c278d6e038e0813e3241351d1800780a))

- Update Info.plist ([`00ebcb4`](https://github.com/nark/Wired-macOS/commit/00ebcb4c4811584a8e382d147c3bc8fad3aabbe0))

- Migrate settings to dedicated preferences window ([`252da7e`](https://github.com/nark/Wired-macOS/commit/252da7e103617f9c56ebc228767742ac0f8a88b0))

- Refine Events settings table layout and dynamic pane sizing ([`be00e11`](https://github.com/nark/Wired-macOS/commit/be00e11065069686488f403eef9ee58a61dfcbc4))

- Board/thread drag-drop transferable refactor ([`bddcf81`](https://github.com/nark/Wired-macOS/commit/bddcf81b37c943ce6244d7f34abba251a58514e6))

- Restore MessagesView changes from saved boards stash ([`f0085fb`](https://github.com/nark/Wired-macOS/commit/f0085fb3ad87aebb9df3cd2515d247a3fe3cd2f9))

- Boards UX and drag-drop refinements ([`3a23a98`](https://github.com/nark/Wired-macOS/commit/3a23a983ff75882c534db0a47ced6821e3d03395))

- Stabilize tabs/sidebar behavior and window chrome experiments ([`a58e45f`](https://github.com/nark/Wired-macOS/commit/a58e45fac77ed4724fe885bfce9e06c49370187f))

- Right-align permission toggles in settings list ([`789eefc`](https://github.com/nark/Wired-macOS/commit/789eefcd718c80c68567b808ee78825eeb7aac53))

- Remove searchable from server accounts settings to avoid toolbar crash ([`990786d`](https://github.com/nark/Wired-macOS/commit/990786df37a7ee234d8c79a3e2ee74d800375630))

- Group account permissions by category in settings ([`8bcf2e4`](https://github.com/nark/Wired-macOS/commit/8bcf2e418ef1705788128d860debd3105815bc75))

- Colorize account list rows from wired.account.color ([`7a36f4a`](https://github.com/nark/Wired-macOS/commit/7a36f4aaba1ed13e465578ca9e13cc6cfc419231))

- Parse account color enum in permissions and user updates ([`e0bb6cc`](https://github.com/nark/Wired-macOS/commit/e0bb6ccf77fa406a202f5a08eab03a5cc2316b27))

- Ensure public chat 1 is selected when chat view appears ([`392d71a`](https://github.com/nark/Wired-macOS/commit/392d71aec65ebda623dfcbd382c2e3032d06c1e3))

- Enable text selection in chat messages ([`0b37100`](https://github.com/nark/Wired-macOS/commit/0b37100f6f3ff7e360a285042f73a3b9802dc054))

- Handle internal wired3 links and make chat URLs clickable ([`864efbf`](https://github.com/nark/Wired-macOS/commit/864efbfb44cda9d5d3ff64da6105e4d6a922b893))

- Wired 3: support remote folder creation from UI ([`ae1315b`](https://github.com/nark/Wired-macOS/commit/ae1315b5df02ad635df2d3f3451aeda0a661fc4a))

- Wired 3: improve files navigation and multi-selection delete ([`bb2ab09`](https://github.com/nark/Wired-macOS/commit/bb2ab09dac21362395e14a1340aea039fc82ed5d))

- Handle account change broadcasts in Wired 3 settings ([`254aab2`](https://github.com/nark/Wired-macOS/commit/254aab2435b28b44a1e069b8152435983d7693aa))

- Wired 3: add remote folder history and dynamic tree root ([`24202b4`](https://github.com/nark/Wired-macOS/commit/24202b41698fb59e9a45b9e376e4f32b456006fb))

- Wired 3: checkpoint permissions fichiers et UI settings/comptes ([`648c27a`](https://github.com/nark/Wired-macOS/commit/648c27a9371257836f3aada009b3e0ca019b4640))

- Persist main window frame across launches ([`7a207d5`](https://github.com/nark/Wired-macOS/commit/7a207d5ff4779951409cf0a0a35159d5c969f073))

- Update default compression algo to LZ4 ([`9b8a05f`](https://github.com/nark/Wired-macOS/commit/9b8a05fa0cacc724cae958252e1d76b6246e5d0b))

- Use server name and confirm before remove ([`0accb89`](https://github.com/nark/Wired-macOS/commit/0accb896fbc25b1bc80ec9c3f3c57f6761ef1841))

- Enable folder download actions and Finder drag export ([`9e4ff19`](https://github.com/nark/Wired-macOS/commit/9e4ff1966bad27f7bc4db6bb150b7de464f1c4a5))

- Harden transfer worker for directory upload retries and ping handling ([`4ee2888`](https://github.com/nark/Wired-macOS/commit/4ee2888e10393ff2e256c8060040788893d4c9aa))

- Update bookmark transfer security defaults ([`40e15c8`](https://github.com/nark/Wired-macOS/commit/40e15c88b0bcf0ff7fa46342ad1c0be11837ddce))

- Use bookmark security settings in TransferWorker ([`ea7cdb7`](https://github.com/nark/Wired-macOS/commit/ea7cdb79a721948602370c46b9e202e27bfed425))

- Handle directory subscription events and ignore stale file_not_found on delete ([`e81e9af`](https://github.com/nark/Wired-macOS/commit/e81e9afee0d1249d963ef631342973329e44ea16))

- Better preview layout ([`ed5079b`](https://github.com/nark/Wired-macOS/commit/ed5079bc0331822ccf4a8869381a48b52b5d7ef3))

- Polish files browser selection and drag export behavior ([`33b4a57`](https://github.com/nark/Wired-macOS/commit/33b4a57351738262122a1acb96056bc035abff93))

- Rework remote file browser with tree mode, resizable columns, and Finder-style preview ([`4e2ec47`](https://github.com/nark/Wired-macOS/commit/4e2ec479ab6c78511810dd2de3c6b46c7dcd756a))

- Before transfers queue ([`cd010b9`](https://github.com/nark/Wired-macOS/commit/cd010b91223af28b5869bf8f6b2fc19c80c55b57))

- Wired 3 client ([`bb33557`](https://github.com/nark/Wired-macOS/commit/bb33557489282a44ab5f0261199c7a82a1240000))

- Conform to ClientInfoDelegate and returns right client infos ([`8eab40d`](https://github.com/nark/Wired-macOS/commit/8eab40d87925bdb9317fff7fbc212f26c2b58a5f))

- Separated from original repo nark/WiredSwift ([`87f4d88`](https://github.com/nark/Wired-macOS/commit/87f4d8893d9dbb3f55a6ca384680b2982e99c2d6))


### Refactoring
- Refactor settings window UI ([`ea485c6`](https://github.com/nark/Wired-macOS/commit/ea485c666acf1f3185bc0061b6a2c7de690c529f))

- Improve chat input with multiline autoresize, history, and wrapping ([`ecb4ebb`](https://github.com/nark/Wired-macOS/commit/ecb4ebbf9cca8e21ff8922ce048c85fd6a9417e2))

- Refactor connections to support temporary sessions and wired3 URLs ([`00a2c7e`](https://github.com/nark/Wired-macOS/commit/00a2c7e5794ad3d29fb49f5d182ea65e5cdfcdca))

- Improve files selection responsiveness in tree and columns ([`c774076`](https://github.com/nark/Wired-macOS/commit/c774076af8eed9c6377b5e0b7631d67c064f5e0c))

- Refactor transfer engine and persistence lifecycle ([`3c43b37`](https://github.com/nark/Wired-macOS/commit/3c43b373838a3d34e860fd6b4f26c6f941cb51a3))


