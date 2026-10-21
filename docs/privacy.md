# Privacy

Blitztext has no backend. It does not collect, send or store any data on servers operated by Blitztext or Blackboat.

## What Stays On Your Mac

- **Audio:** recorded and transcribed on your Mac with a local model (Parakeet or Whisper). Temporary recordings are deleted after each workflow.
- **Writing modes with Apple Intelligence:** run on your Mac.
- **Settings, dictionary, prompts:** local app storage.
- **History (optional):** encrypted on your Mac, kept as long as you choose (off, 24 hours, 7 days).
- **API keys** for an optional model provider: in the macOS Keychain.
- **Text around the cursor:** when a dictation starts, Blitztext reads the focused text field through the Accessibility API to fit spaces and capitals. Password fields are never read. The text stays on your Mac, unless you turn on "KI-Modi sehen den Text am Cursor" (see below).
- **Meetings:** the microphone and, for online meetings, the sound your Mac plays are recorded and transcribed on your Mac; speaker detection runs there too. The audio is deleted after the evaluation; transcript and summary are stored encrypted on your Mac. Live notes and the summary use only the local language model or Apple Intelligence, never a model provider, whatever is set for the writing modes.
- **Browser address:** only if you added a website to "Modus je App", Blitztext reads the address of the frontmost browser tab when you press the Blitztext shortcut, to pick the mode. It stays on your Mac.

## When Data Leaves Your Mac

- **Model download:** loading a speech model, or the optional local language model for meetings, downloads it from Hugging Face (huggingface.co). Hugging Face sees the request, as with any download.
- **Optional model provider:** if you add your own provider and API key, the *recognized text* of the writing modes goes directly from your Mac to that provider. Audio never does. Your contract and their privacy terms apply.
- **Text around the cursor for the writing modes (off by default):** with "KI-Modi sehen den Text am Cursor" on, the text around your cursor goes along to the writing mode. With Apple Intelligence it stays on your Mac; with your own model provider it goes to that provider.
- **Update check:** Blitztext asks the GitHub releases of this repository for a new version (Sparkle). GitHub sees the request, as with any download. Turn it off in Settings > Allgemein > Über Blitztext. On Macs managed by Jamf, Blitztext does not check; updates come from the device management.

## Clipboard

To paste, Blitztext puts the text on the clipboard and restores your previous clipboard afterwards. Clipboard managers may still see the text while it is there.

## Sensitive Content

Transcription and the Apple Intelligence modes are local. If you configure an external model provider, check whether your content may be sent there.
