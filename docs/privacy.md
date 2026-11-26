# Privacy

Blitztext has no backend. It does not collect, send or store any data on servers operated by Blitztext or Blackboat.

This page covers the Mac app and, further down, the [iPhone app](#iphone-app). Blitztext is a Blackboat project; the [imprint](https://www.blackboat.com/impressum) names the responsible company, and [Blackboat's privacy policy](https://www.blackboat.com/datenschutz) explains your rights. Questions: blitztext@blackboat.com.

## What Stays On Your Mac

- **Audio:** recorded and transcribed on your Mac with a local model (Parakeet or Whisper). Temporary recordings are deleted after each workflow. A dictation whose transcription failed stays on your Mac for up to 24 hours, encrypted with a key kept in the macOS Keychain, so it can be transcribed again from the menu; then it is deleted.
- **Writing modes with Apple Intelligence:** run on your Mac.
- **Settings, dictionary, prompts:** local app storage.
- **History (optional):** encrypted on your Mac with a key kept in the macOS Keychain, kept as long as you choose (off, 24 hours, 7 days).
- **API keys** for an optional model provider: in the macOS Keychain.
- **Text around the cursor:** when a dictation starts, Blitztext reads the focused text field through the Accessibility API to fit spaces and capitals. Password fields are never read. The text stays on your Mac, unless you turn on "KI-Modi sehen den Text am Cursor" (see below).
- **Meetings:** the microphone and, for online meetings, the sound your Mac plays are recorded and transcribed on your Mac; speaker detection runs there too. The audio is deleted after the evaluation; a meeting that was never evaluated keeps its audio for 30 days, then it is deleted too. The recordings are excluded from Time Machine. Transcript and summary are stored encrypted on your Mac and stay in your backups, so a restored Mac keeps its meetings. Live notes and the summary use only the local language model, Apple Intelligence or a model server running on this Mac ("Eigene Adresse" pointing at localhost), never a provider on the internet, whatever is set for the writing modes. Note that an address on localhost can also be a tunnel to another computer (an SSH port forward, for example); then the text goes where you set that tunnel up to go.
- **Browser address:** only if you added a website to "Modus je App", Blitztext reads the address of the frontmost browser tab when you press the Blitztext shortcut, to pick the mode. It stays on your Mac.

## When Data Leaves Your Mac

- **Model download:** loading a speech model, or the optional local language model for meetings, downloads it from Hugging Face (huggingface.co). Hugging Face sees the request, as with any download. Blitztext does not sign in to Hugging Face, also not with a token you set up for other tools.
- **Optional model provider:** if you add your own provider and API key, the *recognized text* of the writing modes goes directly from your Mac to that provider. Audio never does. Your contract and their privacy terms apply.
- **Text around the cursor for the writing modes (off by default):** with "KI-Modi sehen den Text am Cursor" on, the text around your cursor goes along to the writing mode. With Apple Intelligence it stays on your Mac; with your own model provider it goes to that provider.
- **Update check:** Blitztext asks the GitHub releases of this repository for a new version (Sparkle). GitHub sees the request, as with any download. Turn it off in Settings > Allgemein > Über Blitztext. On Macs where Blackboat's Jamf installed Blitztext, it does not check; updates come from Jamf.

## Clipboard

To paste, Blitztext puts the text on the clipboard and restores your previous clipboard afterwards. Clipboard managers may still see the text while it is there.

## Sensitive Content

Transcription and the Apple Intelligence modes are local. If you configure an external model provider, check whether your content may be sent there.

## iPhone App

The iPhone app needs no account and talks to no Blitztext or Blackboat server. It contains no analytics, no advertising and no tracking.

### What Stays On Your iPhone

- **Audio:** recorded and transcribed on your iPhone with a local model (Parakeet, Whisper or the speech recognition built into iOS). The recording is deleted as soon as its text is done.
- **Imported audio:** voice memos and voice messages you share with Blitztext are converted and transcribed on your iPhone; the copies are deleted afterwards.
- **Writing modes with Apple Intelligence:** run on your iPhone.
- **History (optional):** stored on your iPhone, protected by iOS data protection and shared only between the app and its keyboard, kept as long as you choose (off, 24 hours, 7 days or 30 days; 7 days by default). It is not included in iCloud or computer backups.
- **Meetings:** recorded, transcribed and split by speaker on your iPhone. The audio is deleted after the evaluation; a meeting that was never evaluated keeps its audio for 30 days, then it is deleted too. Transcript and summary stay on your iPhone until you delete them and are not included in iCloud or computer backups. With Apple Intelligence the summary is written on your iPhone; otherwise only through your own model provider, if you allowed it (see below).
- **Settings, dictionary and your own modes:** local app storage.
- **API keys** for an optional model provider: in the iOS Keychain, on this device only.
- **Clipboard:** every result is also copied to the clipboard. iOS may offer it on your other devices (Universal Clipboard).

### Keyboard

By default the Blitztext app records and the keyboard only sends start and stop and inserts the result. For this exchange it needs Full Access. It does not record what you type. It reads the text around the cursor in two cases:

- to insert the result into the field where you started; it keeps that text on your iPhone only for the running dictation.
- when you turn on "Kontext": then the text around the cursor goes along to the writing mode. With Apple Intelligence it stays on your iPhone; with your own model provider it goes to that provider.

Without a running dictation session, a tap on "Blitztext öffnen" in the keyboard opens the Blitztext app, which then records. "Tastatur jetzt starten" in the app's options gets the keyboard ready without that step.

**Dictation inside the keyboard (Beta, off by default).** If you turn on "Direkt in der Tastatur diktieren" under Optionen > Tastatur, the Blitztext keyboard records itself after you tap "Diktat starten" and turns the speech into text on your iPhone. iOS asks for microphone access for this. The recording never leaves your iPhone and is deleted as soon as the text exists; if a dictation is interrupted, the keyboard or the app deletes the file at the next start. Only while this option is on, Blitztext puts your dictionary and replacements into the storage shared by the app and its keyboard, and removes them when you turn it off. The text goes into the field where you dictated and into the history if the history is on; with the history off, the keyboard stores nothing. Music that is playing pauses during a dictation in the keyboard. For troubleshooting, Blitztext keeps steps and timings without any text; they are only sent if you choose "Feedback senden".

### When Data Leaves Your iPhone

- **Model download:** speech models come from Hugging Face (huggingface.co), which sees the request, as with any download. The speech recognition of iOS loads its language data from Apple.
- **Optional model provider:** only if you add your own provider (OpenAI, Anthropic, Google Gemini, Mistral, OpenRouter or an address of your own) and allow it in the app; Blitztext asks before any text goes there. Then, whenever Apple Intelligence does not take over or you chose "Immer Modell-Anbieter", the *text* goes directly from your iPhone to that provider: dictations in the writing modes, meeting transcripts for the summary, the terms in your dictionary and, with "Kontext", the text around the cursor. Audio never does. Your contract and the provider's privacy terms apply. You can withdraw the permission at any time under Optionen > KI-Modi.
- **Update check:** at most once a day the app asks Apple's App Store whether a newer version exists, to show a notice on the start screen. The request names the app and your region's store, nothing about you or your device beyond what every request carries, such as your IP address.
- **Feedback:** "Feedback senden" prepares an email to blitztext@blackboat.com with the app version, iOS version, device model and speech model details. You see and can change everything before you send it; the app sends nothing by itself.
