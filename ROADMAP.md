# Roadmap

Ideas and direction, not a promise.

## Current Scope

- macOS menu bar app, signed and notarized release builds
- local speech recognition (Parakeet v3, Whisper via WhisperKit)
- writing modes with Apple Intelligence or an optional own model provider
- audio files, own shortcuts, mode per app or website, dictionary with replacements, local history
- text fitted to the cursor, sound muted while recording, optional automatic paragraphs
- meetings in the room and online (beta) with live notes, optional local language model (Gemma 4) for summaries
- in-app updates from the GitHub releases (Sparkle)
- no hosted backend, no accounts

## Next Useful Work

- DMG download in addition to the ZIP.
- Choose the microphone, with fallback to the system default (idea from #18).
- A small recording hint at the cursor position (idea from #8).
- Make the iOS app (dictation keyboard, Shortcuts action) public.
- Reduce the Accessibility blast radius, ideally with a smaller paste helper.
- Stronger supply-chain checks for downloaded speech models.

## Not In Scope Yet

- Production support.
- Accounts, sync, teams, or hosted infrastructure.
- App Store distribution.
