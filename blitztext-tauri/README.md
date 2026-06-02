# Blitztext (Windows / Tauri)

Windows-Version der Blitztext-App, gebaut mit [Tauri 2](https://tauri.app/) (Rust + Web-UI).

## Features

- **Blitztext**: Sprache aufnehmen und transkribieren (OpenAI Whisper)
- **Blitztext+**: Transkribieren und Text verbessern (Whisper + GPT-4o-mini)
- **Blitztext $%&!**: Frust in sachliche Worte fassen (Whisper + GPT-4o)
- **Blitztext :)**: Text mit passenden Emojis versehen (Whisper + GPT-4o-mini)
- System-Tray-Integration
- Globale Tastenkuerzel (Ctrl+Shift+1/2/3/4)
- Automatisches Einfuegen in die aktive Anwendung
- API Key sicher im Windows Credential Store

## Voraussetzungen

- Windows 10/11
- [Rust](https://rustup.rs/) (stable)
- [Node.js](https://nodejs.org/) 18+
- [Microsoft C++ Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) (oder Visual Studio mit C++ Workload)
- OpenAI API Key

## Build & Run

```bash
cd blitztext-tauri
npm install
npm run dev
```

Fuer ein Release-Build (erstellt MSI + NSIS Installer):

```bash
npm run build
```

Der Installer liegt danach unter `src-tauri/target/release/bundle/`.

## Projekt-Struktur

```
blitztext-tauri/
  src/                  Frontend (HTML/CSS/JS)
    index.html          Haupt-UI
    styles.css          Styling
    main.js             App-Logik & Workflow-Steuerung
  src-tauri/            Rust Backend
    src/
      main.rs           Einstiegspunkt
      lib.rs            Tauri-Setup, Commands & Tray
      audio.rs          Mikrofon-Aufnahme (cpal + WAV)
      openai.rs         OpenAI API (Whisper + Chat)
      credentials.rs    API Key Speicherung (Windows Credential Store)
      settings.rs       Einstellungen (JSON)
      workflows.rs      Einfuegen-Simulation (Ctrl+V)
    Cargo.toml          Rust-Abhaengigkeiten
    tauri.conf.json     Tauri-Konfiguration
```

## Tastenkuerzel

| Kuerzel | Funktion |
|---------|----------|
| Ctrl+Shift+1 | Blitztext (Transkription) |
| Ctrl+Shift+2 | Blitztext+ (Transkription + Verbesserung) |
| Ctrl+Shift+3 | Blitztext $%&! (Dampf ablassen) |
| Ctrl+Shift+4 | Blitztext :) (Emojis einfuegen) |

## Unterschiede zur macOS-Version

- Kein lokaler Transkriptionsmodus (WhisperKit/CoreML ist Apple-exklusiv)
- Windows Credential Store statt macOS Keychain
- Ctrl statt fn-basierte Hotkeys
- MSI/NSIS Installer statt .app Bundle
