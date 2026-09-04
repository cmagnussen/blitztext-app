# Blitztext App

Blitztext App is an experimental open-source app for turning speech into text. The repository holds two apps:

- **macOS** — a native SwiftUI/AppKit menubar app (`BlitztextMac/`). The rest of this README is mostly about it.
- **Windows** — a cross-platform Tauri (Rust + TypeScript) companion app (`BlitztextWin/`), preview/work-in-progress. See [BlitztextWin/README.md](BlitztextWin/README.md).

The two apps don't share a codebase (native Swift vs. the Windows stack); only a small logic layer is shared in [`shared/`](shared/) (prompts, gateway contract, config schema).

It is intentionally small and unfinished. The goal is to make a real workflow visible and hackable: press a hotkey, speak, get text back, optionally rewrite it, and paste it into the app you were using.

This is a learning and experimentation project, not a polished product.

> Preview status: bring your own OpenAI API key, no hosted backend, no warranty, no support guarantee.

## What It Does

- **Blitztext**: record speech and transcribe it.
- **Blitztext+**: record speech, transcribe it, then turn the rough draft into cleaner writing.
- **Blitztext $%&!**: turn frustrated speech into a calmer message.
- **Blitztext :)**: add fitting emojis to dictated text.
- **Blitztext Notiz**: record a short thought and append it to a dated Markdown file in a folder you choose, instead of pasting at the cursor. Optional Second-Brain-style frontmatter.

## Important Preview Notes

- The macOS app (below) is the more complete one; the Windows app is an earlier preview — see [BlitztextWin/README.md](BlitztextWin/README.md).
- **Blitztext Notiz** needs a target folder in Settings before it becomes available. Files are named `YYYY-MM-DD-diktat.md`, and the day rolls over at 04:00 local time.
- Bring your own OpenAI API key (macOS) or LiteLLM gateway URL + key (Windows).
- No hosted Blitztext backend is included or provided.
- In online mode, audio and text are sent directly from the app to the OpenAI API.
- Optional local transcription via WhisperKit/CoreML if you install a compatible model locally.
- `./build.sh` creates a locally ad-hoc-signed development app. No notarized release binary is provided.
- Not production ready.
- No warranty and no support guarantee.

You are welcome to use, fork, adapt, and share this project under the license terms.

The intent is not to ship a one-click finished app. The intent is to make a real AI workflow understandable: clone it, build it, read the code, change it, break it, fix it, and suggest improvements. If you only want to download something and never look inside, this preview will probably feel rough. If you want to learn how a small native macOS AI app is put together, you are in the right place.

## Screenshots

<table>
  <tr>
    <td><img src="docs/screenshots/online-mode.png" alt="Blitztext online transcription mode" width="420"></td>
    <td><img src="docs/screenshots/local-mode.png" alt="Blitztext secure local transcription mode" width="420"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/local-model-picker.png" alt="Blitztext local model picker" width="420"></td>
    <td><img src="docs/screenshots/settings-customize.png" alt="Blitztext settings and customization view" width="420"></td>
  </tr>
</table>

## Requirements

- macOS 14 or newer
- Xcode 16 or newer (Swift 5.10), with Command Line Tools installed and selected for `xcodebuild`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project
- For online transcription and rewriting: an OpenAI API key with access to:
  - `whisper-1` for transcription
  - `gpt-4o-mini` and optionally `gpt-4o` for rewriting
- For local-only transcription: a WhisperKit CoreML model in:
  `~/Library/Application Support/Blitztext/models/whisperkit/`

The build also pulls one Swift Package dependency automatically:

- [`argmax-oss-swift`](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) — used for local on-device transcription.

Install XcodeGen if needed:

```bash
brew install xcodegen
```

## Build And Run

```bash
git clone https://github.com/cmagnussen/blitztext-app.git
cd blitztext-app
./build.sh --run
```

For a local install into `/Applications`:

```bash
./build.sh --install --run
```

The generated `.app` is ad-hoc signed for local development only. Do not treat it as a trusted redistributable binary. A public binary release would need Developer ID signing and notarization.

On first launch, either paste your own OpenAI API key for online workflows or install a WhisperKit CoreML model for local transcription. Rewriting workflows still require OpenAI.

For fully local transcription, install a WhisperKit CoreML model and enable **Sicherer Lokaler Modus** in the app.

For a slower, more explicit walkthrough, see [docs/setup.md](docs/setup.md).

## Continuous Builds And Releases

Each app has its own GitHub Actions workflow, and they only run when their own files change (`paths` filters):

- macOS: [.github/workflows/macos-release.yml](.github/workflows/macos-release.yml) — universal (Apple Silicon + Intel) `.app`.
- Windows: [.github/workflows/windows-release.yml](.github/workflows/windows-release.yml) — NSIS `.exe` + MSI installers built on a Windows runner.

The macOS workflow builds automatically:

- **Pull requests**: the app is built and verified, then uploaded as a downloadable artifact on the workflow run (Actions tab, open the run, see Artifacts). No release is published.
- **Merge / push to `main`**: a fresh build is published automatically as a **prerelease**, so there is always a current downloadable build under Releases.
- **Version tag `v*`**: the build is published as a full, official GitHub Release. Use this for deliberate versions:

```bash
git tag v1.0.0
git push origin v1.0.0
```

All builds are **ad-hoc signed**, not notarized. On first launch, right-click the app and choose Open, or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Blitztext.app
```

A notarized, Gatekeeper-friendly build would require Developer ID signing credentials stored as repository secrets.

The Windows workflow follows the same pattern: artifacts on pull requests, a prerelease on pushes to `main`, and installers attached to a `v*` release. Both apps' artifacts are published to the **same** GitHub Release for a given push or tag. Windows installers are currently unsigned (Windows SmartScreen may warn on first launch); Authenticode signing would likewise need credentials in repository secrets.

Editing files under `.github/workflows/` and pushing them requires a GitHub token with the `workflow` scope.

## Permissions

Blitztext asks for:

- **Microphone**: to record your voice.
- **Accessibility**: to paste the result back into the app you were using.

If you do not grant Accessibility permission, you can still copy results manually.

Full Disk Access is not required. If auto-paste does not work even though transcription succeeds, open **System Settings -> Privacy & Security -> Accessibility**, enable Blitztext there, restart Blitztext, and try again with the cursor focused in a text field. If macOS shows multiple Blitztext entries, remove or disable the old ones and grant the permission to the app you just built or installed.

## Data Flow

The preview has no custom backend.

```text
Online transcription: Your Mac -> OpenAI Audio Transcriptions API
Text rewriting:       Your Mac -> OpenAI Chat Completions API
Local transcription:  Your Mac -> WhisperKit/CoreML on device
```

The app stores your OpenAI API key in the user's macOS Keychain.

Read [docs/privacy.md](docs/privacy.md) before using the preview with sensitive content.

## Project Structure

```text
BlitztextMac/     Native macOS app (SwiftUI/AppKit)
  App/            App lifecycle and paste handling
  Features/       Workflows, menu bar UI, settings
  Services/       Recording, OpenAI calls, hotkeys, local storage
  Views/          Shared SwiftUI views
BlitztextWin/     Windows app (Tauri v2: Rust core + TypeScript UI)
shared/           Single source shared by both apps: prompts, gateway
                  contract, config schema
build.sh          Local macOS build script
docs/             Setup, privacy, roadmap, preflight, landing page notes
```

## Local Models

Local transcription is available as an experimental WhisperKit/CoreML path. The app does not bundle a model; choose one in the app, click install, and then switch on **Sicherer Lokaler Modus** from the menu bar or settings.

See [docs/local-models.md](docs/local-models.md).

## Contributing

Contributions are welcome, especially if they make the preview easier to build, understand, or fork.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## Support And Roadmap

This preview has no formal support promise. See [SUPPORT.md](SUPPORT.md) for how to ask for help without sharing secrets.

The current direction is documented in [ROADMAP.md](ROADMAP.md). Maintainer-facing release checks live in [docs/open-source-preflight.md](docs/open-source-preflight.md).

## License

Code is released under the MIT License. See [LICENSE](LICENSE).

Project names, logos, and app icons are not automatically granted as trademarks or brand assets. See [TRADEMARKS.md](TRADEMARKS.md).

## Legal / Impressum & Datenschutz

This is an experimental, non-commercial open-source project, provided as-is under the MIT License without warranty or support. Nothing is sold here and no installation or operation is performed on your behalf.

The companion website (blitztext.de) is operated by Blackboat Internet GmbH:

- Impressum: https://www.blackboat.com/impressum
- Datenschutz / Privacy: https://www.blackboat.com/datenschutz
