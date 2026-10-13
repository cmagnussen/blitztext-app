# Security Policy

Blitztext is free and open source software.

It is provided as-is under the MIT License, without warranty or support guarantees.

## Supported Versions

Only the current `main` branch is considered for security fixes.

## Reporting A Vulnerability

Please do not open a public issue with sensitive security details.

Use GitHub private vulnerability reporting for this repository. Maintainers should enable it before making the repository public.

If private vulnerability reporting is not available yet, open a minimal public issue titled `Security contact request` without technical details.

Do not include API keys, access tokens, private recordings, or confidential transcripts in a report.

Include:

- what you found
- how to reproduce it
- what data or system access could be affected
- your suggested fix, if you have one

## Security Notes

- Speech recognition and the Apple Intelligence writing modes run on the Mac. Audio is never sent anywhere.
- If a user adds their own model provider, the recognized text of the writing modes is sent directly to that provider. Its API key is stored in the macOS Keychain.
- Speech models are downloaded from Hugging Face over HTTPS.
- Temporary audio files may exist briefly during processing.
- Accessibility permission allows the app to paste text into the current app.
- The app currently runs **without** the macOS App Sandbox. This is a deliberate trade-off: the menubar workflow needs Accessibility-based paste into arbitrary frontmost apps, system-wide hotkeys, and Application Support paths for local WhisperKit models, all of which are awkward or impossible inside a strict sandbox. Hardened Runtime is enabled, and the entitlements are limited to microphone input and outbound network access. Reintroducing the sandbox is on the roadmap once these flows are reworked.

Do not use Blitztext for confidential or regulated data without your own review.
