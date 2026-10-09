# Entropy Piano Tuner

Native SwiftUI port of [Entropy Piano Tuner](https://gitlab.com/tp3/Entropy-Piano-Tuner) by Haye Hinrichsen and Christoph Wick. One Xcode target runs on iPhone, iPad, Mac, Apple Watch, and Vision Pro. The tuner records each key and minimizes the entropy of the summed spectra.

Coding agents: read [AGENTS.md](AGENTS.md) before changing the project. That file is the operating manual. A session that read the Apple OS 27 design guidelines first still starts there: the chrome pass is finished, and that page leaves the icons, Apple TV, the algorithm, and the custom keyboard, meter, and curve as this repo already has them. When AGENTS.md and the Swift disagree, trust the Swift.

Open `EntropyPianoTuner.xcodeproj` in Xcode 27 and run the `EntropyPianoTuner` scheme. The deployment floors are iOS 27, macOS 27, visionOS 27, and watchOS 27. Apple TV is not a target.

This program is free software under the GNU General Public License, version 3. See `LICENSE` and `COPYRIGHT`.
