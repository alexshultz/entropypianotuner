# Entropy Piano Tuner

Read this file before you change the project. It is the operating manual for a session that has never seen the code.

When this file and the Swift disagree, trust the Swift and update this file in the same change. The machine section is about Alex's Mac and phone on 2026-10-08. It is not part of the algorithm.

## What this is

A native SwiftUI port of Entropy Piano Tuner by Haye Hinrichsen and Christoph Wick (University of Würzburg). The app records each of the 88 keys, minimizes the Shannon entropy of the summed log-frequency spectra, and then shows how many cents each string is off the resulting tuning.

The port uses Swift, SwiftUI, AVFoundation, Accelerate, SwiftData, and CloudKit. It stays GPL-3. Upstream is <https://gitlab.com/tp3/Entropy-Piano-Tuner>. The GitHub mirror is <https://github.com/levush/Entropy-Piano-Tuner>. The modules that were ported are `modules/algorithms/entropyminimizer/entropyminimizer.cpp` (about 791 lines) and `auditorypreprocessing.cpp` (about 447 lines). FFTW, Qt, libuv, qwt, and tp3log stay out. Output is not claimed to be bit-identical to the Qt app. Accelerate's FFT and the Hann window are the likely sources of a numerical difference.

Local checkout on Alex's Mac: `/Users/alex/Projects/EntropyPianoTuner`. Open `EntropyPianoTuner.xcodeproj`. There is no separate `.xcworkspace`. That folder is its own git repository and it has no remote. The files match GitHub `main` at <https://github.com/alexshultz/entropypianotuner>. The commit history does not. Do not force-push the local root over `main`.

## Rules

These override convenience, a green build, and a guess about what the original app did.

1. Keep `LICENSE`, `COPYRIGHT`, and the Hinrichsen/Wick credit. The port stays GPL-3.
2. Do not add Qt, FFTW, libuv, qwt, tp3log, CocoaPods, or Swift packages. `packageProductDependencies` stays empty.
3. Deployment floors stay iOS 17.0, macOS 14.0, visionOS 1.0, and watchOS 10.0. Call a newer API only behind `#available` or an `#if` that still compiles for those floors.
4. One application target covers iPhone, iPad, Mac, Vision Pro, and Apple Watch. Apple TV stays out. `SUPPORTS_MACCATALYST`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, and `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` stay `NO`. `TARGETED_DEVICE_FAMILY` stays `1,2,4,7`.
5. Do not set `CODE_SIGNING_ALLOWED = NO`. An unsigned install fails with "The executable is not codesigned", `MIInstallerErrorDomain` 13, `0xe800801c`.
6. Signing stays automatic on team `N8D3Z8U4Y9`. `CODE_SIGN_ENTITLEMENTS` stays `EntropyPianoTuner.entitlements` on Debug and Release. There is no second team id.
7. Do not put an Info.plist, a property list, or an entitlements file inside `EntropyPianoTuner/`. That folder is a `PBXFileSystemSynchronizedRootGroup`. Xcode copies those files and also processes them, and the build fails. Entitlements stay at the project root. The background-mode plist stays in `Supporting/`.
8. Do not add a Mac, watch, or vision slot to `AppIcon.appiconset`. Do not add an empty Dark or Tinted well. Those empty wells were the "unassigned child" warning.
9. Do not delete the Resources build phase, id `A1000000000000000000000F`. Its `files` list is empty because the synchronized group fills it. Without the phase, builds succeed and the asset catalog is never compiled.
10. Do not set `INFOPLIST_KEY_UIBackgroundModes`. Generated plists ignored it. Background mode lives in `Supporting/BackgroundModes.plist`.
11. Key 0 is A0. A4 is key 48. C8 is key 87. Names run A, A♯, B, C, … Do not renumber the keyboard so that C is 0.
12. A spectrum is one `KeySpectrumRecord` per key, with `@Attribute(.externalStorage)` on the Float32 blob. Do not fold 88 spectra into the piano record. A CloudKit record holds about 1 MB. One key is about 43 KB. All 88 keys are about 3.8 MB.
13. SwiftData models have no `@Attribute(.unique)`, no relationships, and no stored Swift enums. Every stored property has a default or is optional. Add a new field the same way or existing CloudKit records fail to sync.
14. `mainContext.autosaveEnabled` stays false. Persist with `PianoStore.save` or `PianoStore.delete`. On save, rewrite a key row only when its measurement or its spectrum `Data` changed, and only then set that row's `modifiedAt`.
15. Selected key, page, microphone, accuracy, seed, the pitch-raise toggle, and auto-capture stay in process memory. Do not put them in CloudKit or in `NSUbiquitousKeyValueStore`.
16. Do not add `aps-environment` to `EntropyPianoTuner.entitlements`. One file signs Debug and Release on every platform. A hardcoded `development` value breaks Release.
17. `WindowGroup` has no `.modelContainer`. `PianoStore` owns the one container. Do not attach a second one.
18. `TunerSession.createPiano` builds the piano with `let` and assigns `self.piano`. The local value is not mutated. Leave that unless you are actually mutating it.
19. Do not reinstall Xcode and do not run `mas`. The installed Xcode is 27.0. iPhone Duo full-bleed, hinge, and vertical-bar layout need Xcode 27.1, which is not installed. Layout for that phone is size classes plus `safeAreaBar` on OS 26 and later.
20. EatWatch (`/Users/alex/Projects/EatWatch`), the Seldon vault, and Grok memory files are outside this repo. Do not edit them as part of tuner work.

## Where to change things

| Change | File |
| --- | --- |
| Entropy search, seed, accuracy steps | `EntropyPianoTuner/Tuning/EntropyMinimizer.swift` |
| Spectrum cleanup before the search | `EntropyPianoTuner/Tuning/AuditoryPreprocessing.swift` |
| Pitch, inharmonicity, live cents | `EntropyPianoTuner/Tuning/NoteAnalysis.swift` |
| Log-bin count and frequency map | `EntropyPianoTuner/Tuning/LogBin.swift` |
| Coarse-grain and entropy math | `EntropyPianoTuner/Tuning/MathTools.swift` |
| Pitch-raise curve | `EntropyPianoTuner/Tuning/PitchRaise.swift` |
| Microphone and live meter | `EntropyPianoTuner/Audio/ToneEngine.swift` |
| In-memory piano and the record/calculate/tune flow | `EntropyPianoTuner/Model/TunerSession.swift`, `Piano.swift` |
| CloudKit store, legacy import, reconcile | `EntropyPianoTuner/Model/PianoSync.swift` |
| iPhone, iPad, Mac, Vision screens | `EntropyPianoTuner/UI/WorkspaceView.swift`, `KeyboardView.swift`, `Theme.swift` |
| Watch screen | `EntropyPianoTuner/UI/WatchWorkspace.swift` |
| Floors, signing, icon names, bundle id, background-mode plist wiring | `EntropyPianoTuner.xcodeproj/project.pbxproj` |
| iCloud capability | `EntropyPianoTuner.entitlements` |
| Silent-push background mode | `Supporting/BackgroundModes.plist` |
| Direction check for the algorithm | `AlgorithmCheck/main.swift` (not a member of the app target) |

A new `.swift` file dropped into `EntropyPianoTuner/` is compiled by the synchronized group. You do not add it to `project.pbxproj`. A file that must not be compiled or copied, including plists and entitlements, stays outside that folder.

## Build

Scheme `EntropyPianoTuner` is shared. Launch and Test use Debug. Profile and Archive use Release. `SDKROOT` is `auto`. `SWIFT_VERSION` is 5.0. Marketing version 1.0, build 1.

From the repo root, a signed iOS build that does not install:

```sh
xcodebuild -project EntropyPianoTuner.xcodeproj -scheme EntropyPianoTuner \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath /tmp/ept-build -allowProvisioningUpdates build
```

Use another `-destination` for the platform you touched: `generic/platform=macOS`, `generic/platform=watchOS`, `generic/platform=visionOS`, or a simulator name. A generic iOS destination builds. It does not install. Installing needs the real device as the run destination, or `devicectl` after the app is signed. Command-line device builds need `-allowProvisioningUpdates`. The first time a Mac must be registered, also pass `-allowProvisioningDeviceRegistration`.

In Xcode, Run is the toolbar triangle (Command-R). The destination popup is beside the scheme. Pick the phone by its name. A Simulator row is not the phone. Replace an installed copy by running from Xcode onto that phone.

`.gitignore` ignores `.DS_Store`, `build/`, `DerivedData/`, `*.xcuserstate`, and `xcuserdata/`. Leave user-specific Xcode state out of commits.

`AlgorithmCheck/main.swift` is a command-line check, not an XCTest target. There is no test target. The check builds a 440 Hz sine, checks that a one-bin spectrum has entropy 0, runs the preprocessor and a low-accuracy search on synthetic inharmonic spectra with seed 1, and checks that A4 stays at 0 cents, that the treble sits sharper than the bass, and that pitch-raise also leaves A4 at 0. It does not link the app, the store, or the UI. From the repo root:

```sh
swiftc -framework Accelerate \
  AlgorithmCheck/main.swift \
  EntropyPianoTuner/Model/Piano.swift \
  EntropyPianoTuner/Tuning/*.swift \
  -o /tmp/ept-algorithm-check
/tmp/ept-algorithm-check
```

The last line it prints is `OK`. The low-accuracy search takes a couple of minutes.

## Layout and the platforms that reject APIs

`RootView` is a `NavigationSplitView` on iPhone, iPad, Mac, and visionOS. On watchOS it is a `NavigationStack` that swaps `LibraryView` and `WatchWorkspace`. `WorkspaceView` still compiles for watchOS, so a watch-unavailable call there breaks the watch build even though the watch never shows that view.

`LibraryView` lists pianos. New piano creates one and Delete removes it. An open piano has three pages, `WorkspacePage.record`, `.calculate`, and `.tune`. Record offers Capture, Clear, and Auto capture. Calculate offers Entropy or Pitch raise, a seed, the bass break, and Calculate tuning. Tune offers −1¢, In tune, and +1¢.

| API | Where it is allowed |
| --- | --- |
| `AVAudioSession` | Everywhere except macOS. The Mac engine uses `AVAudioEngine.inputNode` as it is. |
| `setPreferredSampleRate(48_000)` | iOS and visionOS. watchOS cannot call it. |
| Session options `.defaultToSpeaker` and `.allowBluetoothA2DP` | iOS and visionOS. watchOS uses `.allowBluetoothA2DP` only. Category is `.playAndRecord`, mode `.measurement`. |
| `listRowSeparator` | Everywhere except watchOS. |
| Segmented picker | Everywhere except watchOS, which uses `.navigationLink`. |
| `keyboardType` | iOS and visionOS only. |
| `navigationBarTitleDisplayMode` | Everywhere except macOS. |
| `digitalCrownRotation` | watchOS, in `WatchWorkspace`. |
| `safeAreaBar` | OS 26 and later, inside `Theme.dockedKeyboard`. Older OS versions get a `VStack` with the keyboard under the page. |

The watch has no 88-key keyboard. The crown selects the key. Capture, calculate, nudge, and "in tune" are buttons.

`PianoKeyboard` keys are buttons with `accessibilityLabel(PianoLayout.label)` and `.isSelected` on the active key. The cents meter exposes the cents reading and the level. The color scheme is dark. The tint is `Theme.amber`.

Mac window default size is 1100×780, minimum 880×680. visionOS default size is 1280×800. The microphone starts when a workspace appears and stops when it disappears. The usage string is the target's `INFOPLIST_KEY_NSMicrophoneUsageDescription`.

`Theme.dockedKeyboard` is the keyboard inset. On OS 26 and later, `safeAreaBar(edge: .bottom)` is what moves the keyboard off the iPhone Duo vertical bar. Do not raise the deployment target to call it unconditionally.

## Tuning pipeline

Constants live in `LogBin` and `PianoLayout`. Bin 0 is 20.601722 Hz. There are 10,800 bins, 1,200 per octave, nine octaves. `indexToFrequency` is `fmin * 2^(m/1200)`.

`PianoLayout.frequency(key:cents:concertPitch:)` is equal temperament around A4 plus a cents offset. Default concert pitch is 440, clamped to 415...466 by `setConcertPitch`. Default bass break is key 27. The calculate stepper offers 8...40. `setBassBreak` clamps to 1...87.

### Record

`ToneEngine` keeps a ring of recent samples. A capture takes the last 65,536. The live meter analyzes the last 32,768 when at least 16,384 are present. `SpectrumFFT` takes the largest power-of-two length of at least 4,096, applies a Hann window (`vDSP_HANN_NORM`), and returns the positive half of an Accelerate complex FFT as magnitudes.

`NoteAnalysis.analyze` maps that linear spectrum onto the log grid with `MathTools.coarseGrainSpectrum` at exponent 0.25, finds the fundamental (octave-folded for the low bass), fits inharmonicity B, and returns frequency, B, a quality number, and the 10,800-bin spectrum. The partial law is `f1 * n * sqrt((1 + B n²) / (1 + B))`. The expected B, used when a measured value is rejected, is `exp(-15.45 + 1.354 * log(f))` above 100 Hz and `0.000099575` at or below 100 Hz.

`TunerSession.store` writes that key, clears `tuningCents`, `entropy`, and `tuningConcertPitch`, and saves. One new recording invalidates the previous tuning. Auto-capture on the record page fires when the level is above 0.08, the live cents are inside ±40, and that holds for more than 8 readings and 0.7 seconds. It then advances one key.

Live cents on the tune page compare the sounding partial to the target partial. The partial is 4 when A4 is more than 36 keys above the note, 2 when the distance is greater than 24, and 1 otherwise.

### Calculate

`AuditoryPreprocessing.prepare` requires all 88 keys. A key counts as recorded when its spectrum has 10,800 bins and its frequency is positive. The order is fixed: normalize, multiply by a cosine comb of the inharmonic index (`clean`), zero bins below five sixths of the fundamental index (`cutLow`), apply the SPL(A)-style weight, extrapolate inharmonicity upward from eight keys below A4, reinforce partials 2...6 from A4 upward, then mollify with a frequency-dependent Gaussian. The extrapolated B values are written back onto the piano when the search finishes.

`EntropyMinimizer.compute` is a zero-temperature Monte Carlo search. A candidate is kept only when the Shannon entropy of the normalized sum of the shifted spectra goes down. A4 is never the moved key. Two kinds of move:

- One key, by a binomial draw of width 20 centered on its current cents. The draw is rejected when the key was inside its tolerance band around the initial curve and the proposal would leave that band.
- A block: every key from the bottom through the chosen key, or from the chosen key through the top, shifted by one cent. The same sign applies to the whole block.

`methodRatio` starts at 1. A random draw above `methodRatio` is a single-key move. Any other draw is a block move. At 1, every draw is a block move. A kept block move multiplies `methodRatio` by 0.995, so single-key moves start only after block moves have succeeded. The initial curve is rounded to integer cents. It is a partial-matching stretch, and it is not the same function as `PitchRaise.compute`. The minimizer's A5 seed uses partial 2 of A4. Its bass walk mixes partials 3 against 6 and 5 against 10. Pitch-raise uses a two-section fit of measured B around the bass break, seeds A5 from a mix of partials 2 and 3, and walks the bass with partials 4 against 2 and 10 against 5. Do not collapse the two into one helper unless you have compared both with upstream.

`.low`, `.standard`, and `.high` supply 50, 100, and 150 as the scale of the progress annealer ported from upstream. The loop does not stop at that many attempts. Each attempt feeds a velocity, and the search ends when the derived progress passes 1. `.infinite` skips that end condition and runs until cancel. Do not replace the annealer with a plain attempt counter. `stopCalculation` sets the cancel flag and replaces the calc token, so the partial cent vector is discarded. Seed text `"0"` becomes a random `MT19937` seed. Any other decimal `UInt64` is the seed. The generator is in `EntropyMinimizer.swift` so a seed does not depend on a C library.

Pitch-raise is the other calculate path. It returns nil unless A4 has more than 13 keys on each side and each side of the bass break has at least two inharmonicities above `1e-10`. Its result is stored with entropy 0, and the status line says the pitch-raise curve is ready. The library shows "Tuned" when `tuningCents != nil` and `tuningConcertPitch == concertPitch`. Changing the concert pitch does not recompute cents, so the row becomes "Stale". Nudging a tuned note clamps that note to ±80 cents and clears its tuned flag.

## Library and iCloud

The shared library is a SwiftData store at Application Support `EntropyPianoTuner/EntropyPianoTuner.store`. The configuration name is `EntropyPianoTuner`. The container id is `iCloud.com.alex.entropypianotuner`, which is `iCloud.` plus bundle id `com.alex.entropypianotuner`. EatWatch uses a different bundle id and a different container. Do not copy that id here.

`PianoStore.prepare` tries `cloudKitDatabase: .private(containerIdentifier)` and, if that throws, opens the same file with `.none`. If the local open also throws, it calls `fatalError`. `PianoStore.syncsWithICloud` records which open succeeded. The flag is not shown in the UI. A "pianos did not sync" bug starts by checking that flag and checking that both devices ran a Debug build.

`Piano` and `KeyMeasurement` stay structs. The stored types are `PianoRecord` and `KeySpectrumRecord`, joined in code by `pianoID`. Logical ids are the piano UUID string and `"\(pianoID)-\(keyIndex)"`. `SpectrumCodec` writes a spectrum as 10,800 host-endian `Float` values, or empty `Data` when the row is the wrong length or its energy is 0. Tuning cents are 88 raw `Double`s, or empty `Data` for nil. Apple platforms are little-endian, and the bytes are copied with no swap.

CloudKit will deliver two rows for one logical id. `reconcile` groups by `pianoID` or `keyID`, keeps the newer `modifiedAt`, breaks a tie with `String(describing: persistentModelID)` compared as a string (the greater string wins), deletes the losers, and saves so the delete syncs.

`refreshFromStore` calls `processPendingChanges`, reconciles, and replaces the open piano only when the stored `updated` date is newer than the in-memory one. An equal or older store copy leaves the in-memory piano alone. If the open piano is gone, the session clears it. The watchers are:

- `NSPersistentStoreRemoteChange` on every OS this app supports.
- `ModelContext.didSave`, object set to this context, from iOS 18, macOS 15, watchOS 11, and visionOS 2.
- `ResultsObserver` plus `withContinuousObservation(options: .didSet)` on iOS 27, macOS 27, watchOS 27, and visionOS 27. The token is `~Copyable` and stays inside `@MainActor PianoCloudWatch`. `PianoCloudWatchBox` holds that object as `Any` so `TunerSession` does not require OS 27. Construct the box on the main actor.

`RootView` also calls `refreshFromStore` when `scenePhase` becomes `.active`.

Debug builds share the CloudKit Development database. Release and TestFlight use Production until that schema is deployed in the CloudKit console. Sync is eventual. A second device sees the same Development pianos only if it too is a Debug build from Xcode.

`importLegacyLibrary` runs once per device. The flag is `PianoCloud.legacyImportedKey`, and the UserDefaults string is `EntropyPianoTuner.legacyLibraryImported`. It reads sibling folders of the store directory that contain `piano.json`, skips ids already in the store, stamps `modifiedAt` from the file's modification date or `.distantPast`, and reads `spectra.bin` as 88 concatenated Float32 spectra. A later cloud edit wins because its `modifiedAt` is newer. The flag is per device, not in CloudKit. Do not clear it unless a reimport is the task.

`Supporting/BackgroundModes.plist` contains only `UIBackgroundModes` = `remote-notification`. `INFOPLIST_FILE` points at it for `iphoneos*`, `iphonesimulator*`, `watchos*`, and `watchsimulator*` only. `GENERATE_INFOPLIST_FILE` stays YES, so the microphone string, orientations, display name, and scene manifest still come from the `INFOPLIST_KEY_*` build settings. Mac and visionOS do not use that plist.

Deleting a piano deletes its piano rows and its key rows and saves, so the delete can sync.

## Icons

`EntropyPianoTuner/Assets.xcassets` holds four icon sets. Each platform's `actool` run must see only its own assigned children.

| Set | Used when | Contents |
| --- | --- | --- |
| `AppIcon.appiconset` | default, which is iOS | one 1024×1024 image, idiom `universal`, platform `ios` |
| `MacAppIcon.appiconset` | `sdk=macosx*` | mac idiom, 512 pt at 2x |
| `WatchAppIcon.appiconset` | `sdk=watchos*` and `sdk=watchsimulator*` | 1024×1024, idiom `universal`, platform `watchos` |
| `VisionAppIcon.solidimagestack` | `sdk=xros*` and `sdk=xrsimulator*` | Front, Middle, and Back layers |

The vision stack used to be named `AppIcon.solidimagestack`. The rename is what keeps it from being a second unassigned AppIcon. Empty Dark and Tinted wells were removed on 2026-10-08. After that, `actool` compiles were clean for iphoneos, macosx, watchos, and xros. If Xcode still shows the unassigned-child warning, clean the build folder before adding slots back.

## Changes that break a working setup

- Unsigned simulator builds are not the repair for `0xe800801c`. Put signing back.
- Stripping `CODE_SIGN_ENTITLEMENTS` was the workaround while team `N8D3Z8U4Y9` was a free Personal Team. The paid membership is on that same team. Leave the entitlements file attached.
- `INFOPLIST_FILE` inside `EntropyPianoTuner/` fails the build. The plist is already in `Supporting/`.
- A second `AppIcon` child for Mac, or an empty luminosity well, brings back the asset-catalog warning. Add a platform by adding a set and an `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=…]` line.
- Sharing one spectrum record for the whole piano blows the CloudKit size limit.
- `@Attribute(.unique)` on `pianoID` or `keyID` fights CloudKit. Duplicates are reconciled in code.
- Turning autosave on and also calling `save` double-writes.
- Resetting `PianoCloud.legacyImportedKey` (`EntropyPianoTuner.legacyLibraryImported`) reimports old folders over the cloud library.
- Replacing `EntropyMinimizer`'s initial curve with `PitchRaise.compute` changes the search. They are different partial mixes on purpose.
- Installing the SwiftUI Pro skill (twostraws/swiftui-agent-skill) does not help the tuner. It assumes an iOS 26 deployment target and does not cover this algorithm or the audio path. It is not installed.
- Reinstalling the configuration profiles Client-SecureQ and Secure-InterQ, and fully trusting them, can stall Verify App again. Leave the Atkinson Hyperlegible iFont profiles in place.

## This Mac and this phone (2026-10-08)

Xcode 27.0 (27A266a) is at `/Applications/Xcode.app`. `xcode-select` points there. The license is accepted. Do not reinstall it.

Apple ID `alex.shultz@mac.com`. Team name Alex Shultz. Team id `N8D3Z8U4Y9`, Individual, paid. Xcode records `isFreeProvisioningTeam = 0`. The codesigning identity on this Mac is `Apple Development: alex.shultz@mac.com (4TRS65CTUB)`. It is the valid identity. Do not create another.

Bundle id `com.alex.entropypianotuner`. App ID name `XC com alex entropypianotuner`. The embedded iOS development profile from the signed Debug build is `1c2a984e-d844-453d-ad7a-6f3b6c421e97`, "iOS Team Provisioning Profile: com.alex.entropypianotuner", created 2026-10-08, expires 2027-10-08, TimeToLive 365. It includes container `iCloud.com.alex.entropypianotuner` for Development and Production. The earlier 7-day profile `d8ace5c7-6e42-4de7-85a8-8c10ddfa9d82` is not embedded. Do not describe this app as expiring in 7 days. Apps that omit the iCloud entitlement still get the short free-team lifetime. This one does not omit it.

The connected phone is an iPhone 16 Pro Max, model iPhone17,2, iOS 27.0.1 (24A446), UDID `00008140-000C78E43A33001C`. Developer Mode is on. The developer certificate was trusted after a reboot. Verify App did nothing until two configuration profiles were removed and the phone was rebooted: Client-SecureQ (`6AA99C8F-2733-450B-A32E-23AF79B65E59`) and Secure-InterQ (`C0197272-85A9-4864-BA8C-10CF52872C86`). If Verify App does nothing again, remove those two, leave the font profiles, and reboot. The trust screen is Settings → General → VPN & Device Management. On that day the phone was on cellular, with no VPN, no iCloud Private Relay, and automatic date and time. `https://ppq.apple.com` answered from the Mac.

The watch uses this same target. It installs through the paired iPhone. Turn on Developer Mode on the watch if the install asks. No separate watch target exists.

The paid-signed generic iOS Debug build succeeded and its codesign entitlements included the CloudKit container. That build was not installed onto the phone from here. Alex runs it from Xcode. Before the entitlements file was attached, Debug builds succeeded for the iOS simulator, Mac, visionOS simulator, and watchOS simulator. watchOS was not rebuilt after `BackgroundModes.plist` was wired up. No iPad, Watch, or Vision Pro was connected for an install.

## Not verified

Do not report these as done.

- Two devices signed into the same iCloud account seeing the same piano.
- A legacy `piano.json` folder imported into a live store.
- A real CloudKit duplicate reconciled by `modifiedAt`.
- A watchOS build after the background-mode plist was added.
- The Production CloudKit schema. Until it is deployed, a Release or TestFlight build has an empty library even when Debug on another device has pianos.
- A bit-match against the Qt tuner.
- Launch of the paid-signed app on the phone, an iPad, a Watch, or Vision Pro from this session.
- Silent push while the app is backgrounded. `aps-environment` was left off on purpose. Foreground refresh uses `scenePhase` and the store notifications.

A later save on this device still overwrites a key whose measurement or spectrum changed, even if another device edited that same key in between. Unchanged keys are not rewritten.

## License

GNU General Public License version 3, in `LICENSE`. Copyright holders and the upstream URL are in `COPYRIGHT`.
