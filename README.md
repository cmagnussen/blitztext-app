# Blitztext

**Speak. Text. Done.** A macOS menu bar app that turns speech into text, fully on your Mac.

Hold a shortcut, speak, let go. Blitztext transcribes locally and pastes the text where your cursor is. The writing modes rewrite it with Apple Intelligence on your Mac. No account, no Blitztext server, no audio leaving the device.

**[Download the latest version](https://github.com/cmagnussen/blitztext-app/releases/latest)** (signed and notarized by Apple) · [Build it yourself](#build-it-yourself) · [blitztext.de](https://blitztext.de)

> Experimental open-source project by Blackboat, provided as-is under the MIT License, without warranty or support guarantee.

<p align="center">
  <img src="docs/screenshots/menu-bar.png" width="380" alt="Blitztext in the menu bar: four modes, each with its own shortcut, everything local">
  <img src="docs/screenshots/settings-modes.png" width="380" alt="Settings, Modi: Blitztext+ and the other modes, plus a mode per app or website such as Gmail">
</p>

## What It Does

| Mode | Shortcut | What happens |
|---|---|---|
| **Blitztext** | `fn + Shift` | Speech to exact text |
| **Blitztext+** | `fn + Control` | Speech to clean written text |
| **Blitztext $%&!** | `fn + Option` | Frustrated speech to a calm, effective message |
| **Blitztext :)** | `fn + Cmd` | Text with fitting emojis |

- **Local speech recognition:** NVIDIA Parakeet v3 (fast, 25 European languages) or OpenAI Whisper via WhisperKit (about 100 languages). Both detect the spoken language.
- **Local writing modes:** Blitztext+, $%&! and :) run with Apple Intelligence on your Mac (macOS 26 with Apple Intelligence). Optionally you can bring your own model provider (OpenAI, Anthropic, Google Gemini, Mistral, OpenRouter, Ollama or LM Studio) with your own API key.
- **Fits where you type:** spaces and capitals follow the text around your cursor, also mid-sentence. Password fields are never read.
- **Mode per app or website:** e.g. Mail or Gmail always Blitztext+, Slack word for word.
- **Sound off while recording:** a podcast or music is muted while you speak and back right after.
- **Voice memos and WhatsApp voice messages:** drop an audio file on Blitztext and get the text, optionally with paragraphs.
- **Own shortcuts** for keyboards without `fn`, **dictionary** with names, terms and fixed replacements ("n acht n" becomes "n8n").
- **History** of recent results, encrypted and stored only on your Mac.
- **Updates** inside the app: Blitztext offers new versions from this repository's releases.

## Install

1. [Download the ZIP](https://github.com/cmagnussen/blitztext-app/releases/latest), unpack it and move **Blitztext.app** to **Applications**.
2. Open Blitztext. It lives in the menu bar.
3. Allow **Microphone** and **Accessibility** (needed to paste into other apps).
4. In the settings (**Modelle**), load a local speech model once (Parakeet v3 is recommended on Apple silicon, about 500 MB).
5. Hold `fn + Shift`, speak, let go.

Requirements: macOS 14 or newer. Parakeet needs Apple silicon. The writing modes on device need macOS 26 with Apple Intelligence turned on; without it, add your own model provider or use plain dictation only.

## Data Flow

```text
Speech recognition:  your Mac (Parakeet or Whisper, Core ML / Neural Engine)
Writing modes:       your Mac (Apple Intelligence)
                     or, if you add one, your own model provider with your own API key
Model download:      Hugging Face, once per model
Update check:        GitHub releases of this repository (can be turned off)
```

Blitztext has no backend and collects no data. See [docs/privacy.md](docs/privacy.md).

## Build It Yourself

You need Xcode 26 or newer (for the Apple Intelligence APIs) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/cmagnussen/blitztext-app.git
cd blitztext-app
./build.sh --install --run
```

`build.sh` creates an ad-hoc signed app for your own Mac. If you publish a fork, use your own bundle identifier, name and icon (see [TRADEMARKS.md](TRADEMARKS.md)) and sign it with your own Developer ID.

More in [docs/setup.md](docs/setup.md) and [docs/local-models.md](docs/local-models.md).

## Project Structure

```text
BlitztextMac/        macOS menu bar app (SwiftUI, AppKit)
  App/               app state and lifecycle
  Features/          workflows, menu bar, settings, audio files, release notes
  Services/          recording, hotkeys, local transcription, paste, history
  Views/             shared UI pieces
  Tests/             unit tests: post-processing, cursor fit, paragraphs, filters
BlitztextShared/     code shared with the (not yet public) iOS app
  AI/                model providers, Apple Intelligence rewriting, mode prompts
  Audio/             audio file conversion
  Transcription/     Whisper call and filter for invented text
  Design/            design tokens, Public Sans
  Licenses/          bundled third-party licenses
build.sh             local build script
```

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md). Ideas and direction: [ROADMAP.md](ROADMAP.md).

Thanks to everyone whose pull requests shaped this version, among them automatic paragraphs (#21), build fixes (#5, #16) and a cancellation fix (#10).

## From the Community

Independent projects built on the Blitztext idea. They are not maintained or reviewed by Blackboat.

- Linux (KDE/Wayland): [TimInTech/blitztext-linux](https://github.com/TimInTech/blitztext-linux)
- Windows with voice notes: [danielstefanmueller/Blitznotiz](https://github.com/danielstefanmueller/Blitznotiz)
- Windows (.NET 8): [echobrain-de/blitztext](https://github.com/echobrain-de/blitztext)
- Fork with history, meetings and a team server: [mschnitzler-creator/blitztext-app-v2](https://github.com/mschnitzler-creator/blitztext-app-v2)

## License

Code: MIT License, see [LICENSE](LICENSE). Third-party code and models: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); the full license texts ship inside the app (Settings > Allgemein > Über Blitztext > "Lizenzen und Hinweise"). Names, logos and icons are not licensed for reuse, see [TRADEMARKS.md](TRADEMARKS.md).

## Legal / Impressum & Datenschutz

The signed release builds and the website blitztext.de are published by Blackboat Internet GmbH.

- Impressum: https://www.blackboat.com/impressum
- Datenschutz / Privacy: https://www.blackboat.com/datenschutz
