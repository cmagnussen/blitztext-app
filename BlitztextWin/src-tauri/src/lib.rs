// Secret storage backed by the OS credential store
// (macOS Keychain via apple-native, Windows Credential Manager via windows-native).
const KEYRING_SERVICE: &str = "app.blitztext.win";
const LITELLM_KEY_ACCOUNT: &str = "liteLLMApiKey";

#[tauri::command]
fn secret_set(account: String, value: String) -> Result<(), String> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, &account).map_err(|e| e.to_string())?;
    entry.set_password(&value).map_err(|e| e.to_string())
}

#[tauri::command]
fn secret_get(account: String) -> Result<Option<String>, String> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, &account).map_err(|e| e.to_string())?;
    match entry.get_password() {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
fn secret_has(account: String) -> Result<bool, String> {
    Ok(secret_get(account)?.is_some())
}

// --- Gateway client ---------------------------------------------------------

fn litellm_key() -> Result<String, String> {
    secret_get(LITELLM_KEY_ACCOUNT.to_string())?
        .ok_or_else(|| "Kein API-Key gespeichert.".to_string())
}

/// Normalizes a user-entered gateway URL to the bare base, so we can append the
/// API paths ourselves. Strips a trailing slash and any trailing `/v1` or `/ui`
/// segments (in any order) — people often paste the LiteLLM web UI URL
/// (".../ui") or an OpenAI-style ".../v1" base.
fn normalize_base(base: &str) -> String {
    let mut value = base.trim().trim_end_matches('/').to_string();
    loop {
        let lower = value.to_lowercase();
        if lower.ends_with("/v1") || lower.ends_with("/ui") {
            value.truncate(value.len() - 3);
            value = value.trim_end_matches('/').to_string();
        } else {
            break;
        }
    }
    value
}

/// Lists the models the gateway exposes. Used by the "test connection" button
/// to confirm the URL, key and reachability in one shot.
#[tauri::command]
async fn gateway_test(base_url: String) -> Result<Vec<String>, String> {
    let key = litellm_key()?;
    let url = format!("{}/v1/models", normalize_base(&base_url));

    let response = reqwest::Client::new()
        .get(&url)
        .bearer_auth(key)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    let status = response.status();
    let body = response.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        return Err(format!("HTTP {}: {}", status.as_u16(), body));
    }

    let parsed: serde_json::Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
    let ids = parsed["data"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|m| m["id"].as_str().map(|s| s.to_string()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Ok(ids)
}

/// Transcribes recorded audio via the gateway. Audio is passed from the webview
/// as base64. The gateway may return JSON even for response_format=text, so we
/// parse defensively (prefer a top-level `text` field, fall back to raw body).
#[tauri::command]
async fn transcribe(
    base_url: String,
    model: String,
    language: Option<String>,
    audio_base64: String,
    filename: Option<String>,
    content_type: Option<String>,
) -> Result<String, String> {
    use base64::Engine as _;

    let key = litellm_key()?;
    let url = format!("{}/v1/audio/transcriptions", normalize_base(&base_url));
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(audio_base64.as_bytes())
        .map_err(|e| e.to_string())?;

    let mime = content_type.unwrap_or_else(|| "application/octet-stream".to_string());
    let part = reqwest::multipart::Part::bytes(bytes)
        .file_name(filename.unwrap_or_else(|| "audio.webm".to_string()))
        .mime_str(&mime)
        .map_err(|e| e.to_string())?;
    let mut form = reqwest::multipart::Form::new()
        .part("file", part)
        .text("model", model)
        .text("response_format", "text");
    if let Some(lang) = language {
        let lang = lang.trim().to_string();
        if !lang.is_empty() {
            form = form.text("language", lang);
        }
    }

    let response = reqwest::Client::new()
        .post(&url)
        .bearer_auth(key)
        .multipart(form)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = response.status();
    let body = response.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        return Err(format!("HTTP {}: {}", status.as_u16(), body));
    }

    let transcript = serde_json::from_str::<serde_json::Value>(&body)
        .ok()
        .and_then(|v| v["text"].as_str().map(|s| s.to_string()))
        .unwrap_or(body);
    Ok(transcript.trim().to_string())
}

/// Runs a chat completion for the rewrite workflows (improve / Dampf ablassen /
/// emoji). Temperature is intentionally omitted: the gateway's GPT-5 class
/// models reject any non-default value with HTTP 400.
#[tauri::command]
async fn chat_complete(
    base_url: String,
    model: String,
    system: String,
    user: String,
) -> Result<String, String> {
    let key = litellm_key()?;
    let url = format!("{}/v1/chat/completions", normalize_base(&base_url));
    let body = serde_json::json!({
        "model": model,
        "messages": [
            { "role": "system", "content": system },
            { "role": "user", "content": user },
        ],
    });

    let response = reqwest::Client::new()
        .post(&url)
        .bearer_auth(key)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = response.status();
    let text = response.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        return Err(format!("HTTP {}: {}", status.as_u16(), text));
    }

    let parsed: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let content = parsed["choices"][0]["message"]["content"]
        .as_str()
        .ok_or_else(|| "Antwort ohne content-Feld.".to_string())?;
    Ok(content.trim().to_string())
}

// --- Native audio recording (cpal -> WAV) ----------------------------------
//
// Recording happens in the Rust core instead of the webview's MediaRecorder so
// the audio quality is deterministic and matches the macOS app (16-bit PCM mono
// WAV). cpal's Stream is !Send, so it is created and kept alive on a dedicated
// thread; the input callback pushes mono i16 samples into a shared buffer.

#[derive(Default)]
struct AudioRecorder {
    inner: std::sync::Mutex<Option<RecorderHandle>>,
}

struct RecorderHandle {
    stop: std::sync::Arc<std::sync::atomic::AtomicBool>,
    join: std::thread::JoinHandle<()>,
    samples: std::sync::Arc<std::sync::Mutex<Vec<i16>>>,
    sample_rate: std::sync::Arc<std::sync::atomic::AtomicU32>,
}

/// Starts capturing from the default input device. Returns once the stream is
/// running (or with the device/stream error).
#[tauri::command]
fn record_start(state: tauri::State<'_, AudioRecorder>) -> Result<(), String> {
    use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
    use std::sync::{mpsc, Arc, Mutex};

    let mut guard = state.inner.lock().map_err(|e| e.to_string())?;
    if guard.is_some() {
        return Ok(()); // already recording
    }

    let samples = Arc::new(Mutex::new(Vec::<i16>::new()));
    let sample_rate = Arc::new(AtomicU32::new(0));
    let stop = Arc::new(AtomicBool::new(false));
    let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();

    let t_samples = samples.clone();
    let t_sr = sample_rate.clone();
    let t_stop = stop.clone();

    let join = std::thread::spawn(move || {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

        let host = cpal::default_host();
        let Some(device) = host.default_input_device() else {
            let _ = ready_tx.send(Err("Kein Mikrofon gefunden.".into()));
            return;
        };
        let supported = match device.default_input_config() {
            Ok(c) => c,
            Err(e) => {
                let _ = ready_tx.send(Err(format!("Audio-Konfiguration: {e}")));
                return;
            }
        };
        let channels = supported.channels() as usize;
        t_sr.store(supported.sample_rate().0, Ordering::SeqCst);
        let config: cpal::StreamConfig = supported.config();
        let err_fn = |err| eprintln!("Audio-Stream-Fehler: {err}");

        // Downmix interleaved frames to one mono i16 sample.
        let build = || -> Result<cpal::Stream, cpal::BuildStreamError> {
            match supported.sample_format() {
                cpal::SampleFormat::F32 => {
                    let buf = t_samples.clone();
                    device.build_input_stream(
                        &config,
                        move |data: &[f32], _: &_| {
                            let mut b = buf.lock().unwrap();
                            for frame in data.chunks(channels) {
                                let avg = frame.iter().copied().sum::<f32>() / channels as f32;
                                b.push((avg.clamp(-1.0, 1.0) * i16::MAX as f32) as i16);
                            }
                        },
                        err_fn,
                        None,
                    )
                }
                cpal::SampleFormat::I16 => {
                    let buf = t_samples.clone();
                    device.build_input_stream(
                        &config,
                        move |data: &[i16], _: &_| {
                            let mut b = buf.lock().unwrap();
                            for frame in data.chunks(channels) {
                                let avg = frame.iter().map(|&s| s as i32).sum::<i32>()
                                    / channels as i32;
                                b.push(avg as i16);
                            }
                        },
                        err_fn,
                        None,
                    )
                }
                cpal::SampleFormat::U16 => {
                    let buf = t_samples.clone();
                    device.build_input_stream(
                        &config,
                        move |data: &[u16], _: &_| {
                            let mut b = buf.lock().unwrap();
                            for frame in data.chunks(channels) {
                                let avg = frame.iter().map(|&s| s as i32 - 32768).sum::<i32>()
                                    / channels as i32;
                                b.push(avg as i16);
                            }
                        },
                        err_fn,
                        None,
                    )
                }
                other => {
                    eprintln!("Nicht unterstuetztes Sample-Format: {other:?}");
                    Err(cpal::BuildStreamError::StreamConfigNotSupported)
                }
            }
        };

        let stream = match build() {
            Ok(s) => s,
            Err(e) => {
                let _ = ready_tx.send(Err(format!("Audio-Stream: {e}")));
                return;
            }
        };
        if let Err(e) = stream.play() {
            let _ = ready_tx.send(Err(format!("Audio-Start: {e}")));
            return;
        }
        let _ = ready_tx.send(Ok(()));

        // Keep the stream (and thus capture) alive until stop is requested.
        while !t_stop.load(Ordering::SeqCst) {
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        drop(stream);
    });

    match ready_rx.recv() {
        Ok(Ok(())) => {}
        Ok(Err(e)) => {
            let _ = join.join();
            return Err(e);
        }
        Err(_) => return Err("Audio-Thread unerwartet beendet.".into()),
    }

    *guard = Some(RecorderHandle {
        stop,
        join,
        samples,
        sample_rate,
    });
    Ok(())
}

/// Stops the recording and returns the captured audio as a base64-encoded WAV
/// (16-bit PCM mono), ready to hand to `transcribe` with content type audio/wav.
#[tauri::command]
fn record_stop(state: tauri::State<'_, AudioRecorder>) -> Result<String, String> {
    use base64::Engine as _;
    use std::sync::atomic::Ordering;

    let handle = state
        .inner
        .lock()
        .map_err(|e| e.to_string())?
        .take()
        .ok_or_else(|| "Keine laufende Aufnahme.".to_string())?;

    handle.stop.store(true, Ordering::SeqCst);
    let _ = handle.join.join();

    let samples = handle.samples.lock().map_err(|e| e.to_string())?.clone();
    let sample_rate = handle.sample_rate.load(Ordering::SeqCst).max(16000);

    let spec = hound::WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut cursor = std::io::Cursor::new(Vec::<u8>::new());
    {
        let mut writer = hound::WavWriter::new(&mut cursor, spec).map_err(|e| e.to_string())?;
        for sample in samples {
            writer.write_sample(sample).map_err(|e| e.to_string())?;
        }
        writer.finalize().map_err(|e| e.to_string())?;
    }
    Ok(base64::engine::general_purpose::STANDARD.encode(cursor.into_inner()))
}

// --- Autostart (launch on login) -------------------------------------------

#[tauri::command]
fn set_autostart(app: tauri::AppHandle, enabled: bool) -> Result<(), String> {
    use tauri_plugin_autostart::ManagerExt;
    let manager = app.autolaunch();
    if enabled {
        manager.enable()
    } else {
        manager.disable()
    }
    .map_err(|e| e.to_string())
}

#[tauri::command]
fn get_autostart(app: tauri::AppHandle) -> Result<bool, String> {
    use tauri_plugin_autostart::ManagerExt;
    app.autolaunch().is_enabled().map_err(|e| e.to_string())
}

// --- Paste into the active app ---------------------------------------------

/// Puts `text` on the clipboard and simulates the paste shortcut so it lands in
/// whatever app currently has focus (our window stays hidden in the tray).
/// macOS needs Accessibility permission for the synthetic keystroke; Windows
/// needs no prompt.
#[tauri::command]
fn paste_text(text: String) -> Result<(), String> {
    use enigo::{Direction, Enigo, Key, Keyboard, Settings};

    if text.is_empty() {
        return Ok(());
    }

    arboard::Clipboard::new()
        .and_then(|mut cb| cb.set_text(text))
        .map_err(|e| format!("Zwischenablage: {e}"))?;

    // Let the clipboard write settle before pasting.
    std::thread::sleep(std::time::Duration::from_millis(80));

    let mut enigo = Enigo::new(&Settings::default())
        .map_err(|e| format!("Eingabe-Simulation nicht verfuegbar: {e}"))?;
    #[cfg(target_os = "macos")]
    let modifier = Key::Meta;
    #[cfg(not(target_os = "macos"))]
    let modifier = Key::Control;

    let paste = |enigo: &mut Enigo| -> Result<(), enigo::InputError> {
        enigo.key(modifier, Direction::Press)?;
        enigo.key(Key::Unicode('v'), Direction::Click)?;
        enigo.key(modifier, Direction::Release)?;
        Ok(())
    };
    paste(&mut enigo).map_err(|e| format!("Einfuegen fehlgeschlagen: {e}"))?;
    Ok(())
}

// --- Push-to-talk global hotkeys -------------------------------------------

/// Maps each currently registered global shortcut to its workflow id, so the
/// shared handler knows which workflow to emit and so hotkeys can be rebound at
/// runtime. The Windows/Super key plays the role `fn` plays on the macOS app.
#[derive(Default)]
struct HotkeyMap(std::sync::Mutex<std::collections::HashMap<tauri_plugin_global_shortcut::Shortcut, String>>);

/// Rebinds the global hotkey for a workflow. Accepts an accelerator string
/// (e.g. "Super+Shift+KeyD"); a real key is required because modifier-only
/// combos cannot be registered as global shortcuts on Windows. Frees both the
/// workflow's previous combo and any combo another workflow already holds, so
/// bindings can never collide or leak.
#[tauri::command]
fn set_hotkey(
    app: tauri::AppHandle,
    state: tauri::State<'_, HotkeyMap>,
    workflow: String,
    accelerator: String,
) -> Result<(), String> {
    use std::str::FromStr;
    use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};

    let shortcut =
        Shortcut::from_str(accelerator.trim()).map_err(|e| format!("Ungueltiger Hotkey: {e}"))?;
    let gs = app.global_shortcut();
    let mut map = state.0.lock().map_err(|e| e.to_string())?;

    // Release the workflow's old combo and any combo another workflow held.
    let stale: Vec<Shortcut> = map
        .iter()
        .filter(|(s, w)| **w == workflow || **s == shortcut)
        .map(|(s, _)| *s)
        .collect();
    for s in stale {
        let _ = gs.unregister(s);
        map.remove(&s);
    }

    gs.register(shortcut)
        .map_err(|e| format!("Hotkey konnte nicht registriert werden: {e}"))?;
    map.insert(shortcut, workflow);
    Ok(())
}

// --- Windows & recording state ---------------------------------------------

/// Tracks whether a dictation is currently recording, so a tray click can stop
/// it instead of toggling the popover.
#[derive(Default)]
struct RecordingFlag(std::sync::atomic::AtomicBool);

#[tauri::command]
fn set_recording(state: tauri::State<'_, RecordingFlag>, active: bool) {
    state
        .0
        .store(active, std::sync::atomic::Ordering::SeqCst);
}

/// While true the popover stays open on focus loss (set when the settings view
/// is showing, so editing fields doesn't dismiss the popover).
#[derive(Default)]
struct PopoverPinned(std::sync::atomic::AtomicBool);

/// The tray icon's last known screen rect, captured from tray events, so the
/// popover can be positioned right next to it (deterministic on the first open).
#[derive(Default)]
struct TrayRect(std::sync::Mutex<Option<tauri::Rect>>);

#[tauri::command]
fn set_popover_pinned(state: tauri::State<'_, PopoverPinned>, pinned: bool) {
    state
        .0
        .store(pinned, std::sync::atomic::Ordering::SeqCst);
}

/// Hides the popover (used after a click-to-record so focus returns to the
/// previously active app before pasting).
#[tauri::command]
fn hide_popover(app: tauri::AppHandle) {
    use tauri::Manager;
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
    }
}

#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    use tauri::{Emitter, Manager};
    use tauri_plugin_global_shortcut::ShortcutState;

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(
            // Hold-to-talk: the plugin reports both Pressed and Released, so we
            // emit a down/up pair the webview turns into start/stop recording.
            // The workflow id is looked up from the runtime HotkeyMap.
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    let workflow = app
                        .state::<HotkeyMap>()
                        .0
                        .lock()
                        .ok()
                        .and_then(|map| map.get(shortcut).cloned());
                    if let Some(workflow) = workflow {
                        let _ = match event.state() {
                            ShortcutState::Pressed => app.emit("hotkey-down", workflow),
                            ShortcutState::Released => app.emit("hotkey-up", workflow),
                        };
                    }
                })
                .build(),
        )
        .manage(HotkeyMap::default())
        .manage(RecordingFlag::default())
        .manage(PopoverPinned::default())
        .manage(TrayRect::default())
        .manage(AudioRecorder::default())
        .invoke_handler(tauri::generate_handler![
            secret_set,
            secret_get,
            secret_has,
            gateway_test,
            transcribe,
            chat_complete,
            set_hotkey,
            paste_text,
            record_start,
            record_stop,
            set_autostart,
            get_autostart,
            set_recording,
            set_popover_pinned,
            hide_popover,
            quit_app
        ])
        .on_window_event(|window, event| match event {
            // Closing the window only hides it; the app keeps running in the
            // tray so the global hotkey stays alive. "Beenden" is the real quit.
            tauri::WindowEvent::CloseRequested { api, .. } => {
                let _ = window.hide();
                api.prevent_close();
            }
            // The popover is transient: hide it on focus loss like a native
            // menu-bar dropdown — unless pinned (settings view open).
            tauri::WindowEvent::Focused(false) if window.label() == "main" => {
                if !window
                    .app_handle()
                    .state::<PopoverPinned>()
                    .0
                    .load(std::sync::atomic::Ordering::SeqCst)
                {
                    let _ = window.hide();
                }
            }
            _ => {}
        })
        .setup(|app| {
            // Hotkeys themselves are registered by the frontend from saved
            // settings via `set_hotkey` once the webview loads.
            build_tray(app.handle())?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// Positions the popover right next to the tray icon and shows it. All math is
/// done in PHYSICAL pixels against the virtual desktop, and the target monitor
/// is picked from the tray point, so it lands on the correct screen even with
/// multiple monitors at different scale factors. Position is set BEFORE showing
/// so the first open is already correct.
fn show_popover(app: &tauri::AppHandle) {
    use tauri::{Manager, PhysicalPosition};

    let Some(window) = app.get_webview_window("main") else {
        return;
    };

    // The popover's logical size (kept in sync with tauri.conf.json).
    const WIN_W: f64 = 380.0;
    const WIN_H: f64 = 540.0;
    const GAP: f64 = 6.0;

    let win_scale = window.scale_factor().unwrap_or(1.0);
    if let Some(rect) = app.state::<TrayRect>().0.lock().ok().and_then(|r| *r) {
        // Tray rect in absolute physical coordinates (the value is already
        // physical on the platforms we target; to_physical is a safe no-op then).
        let pos = rect.position.to_physical::<f64>(win_scale);
        let size = rect.size.to_physical::<f64>(win_scale);
        let center_x = pos.x + size.width / 2.0;
        let center_y = pos.y + size.height / 2.0;

        // Find the monitor that contains the tray icon; fall back to the
        // primary monitor (then the first) so we can always clamp on-screen.
        let monitors = window.available_monitors().unwrap_or_default();
        let monitor: Option<tauri::Monitor> = monitors
            .iter()
            .find(|m| {
                let mp = m.position();
                let ms = m.size();
                center_x >= mp.x as f64
                    && center_x < mp.x as f64 + ms.width as f64
                    && center_y >= mp.y as f64
                    && center_y < mp.y as f64 + ms.height as f64
            })
            .cloned()
            .or_else(|| window.primary_monitor().ok().flatten())
            .or_else(|| monitors.first().cloned());
        let scale = monitor.as_ref().map(|m| m.scale_factor()).unwrap_or(win_scale);

        let win_w = WIN_W * scale;
        let win_h = WIN_H * scale;
        let gap = GAP * scale;

        let mut x = center_x - win_w / 2.0;
        // macOS tray sits at the top (drop below it); elsewhere at the bottom
        // (rise above it).
        #[cfg(target_os = "macos")]
        let mut y = pos.y + size.height + gap;
        #[cfg(not(target_os = "macos"))]
        let mut y = pos.y - win_h - gap;

        // Keep the popover fully inside the target monitor.
        if let Some(m) = monitor {
            let mp = m.position();
            let ms = m.size();
            let min_x = mp.x as f64;
            let max_x = (mp.x as f64 + ms.width as f64 - win_w).max(min_x);
            let min_y = mp.y as f64;
            let max_y = (mp.y as f64 + ms.height as f64 - win_h).max(min_y);
            x = x.clamp(min_x, max_x);
            y = y.clamp(min_y, max_y);
        }

        let _ = window.set_position(PhysicalPosition::new(x, y));
    }

    let _ = window.show();
    let _ = window.set_focus();
}

/// System-tray icon. Left-click toggles the popover near the tray (or stops an
/// active recording); right-click opens a small menu (settings / quit). Keeps
/// the app alive in the background so the global hotkey works.
fn build_tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    use std::sync::atomic::Ordering;
    use tauri::menu::{Menu, MenuItem};
    use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
    use tauri::{Emitter, Manager};

    let settings = MenuItem::with_id(app, "settings", "Einstellungen", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Beenden", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&settings, &quit])?;

    // The monochrome Blitztext glyph (template on macOS so the menu bar tints it).
    let tray_icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray.png"))?;

    TrayIconBuilder::new()
        .icon(tray_icon)
        .icon_as_template(true)
        .tooltip("Blitztext — Win+Shift+D halten zum Diktieren")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "settings" => {
                show_popover(app);
                let _ = app.emit("open-settings", ());
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            let app = tray.app_handle();
            // Remember the icon's screen rect so show_popover can place itself.
            let rect = match &event {
                TrayIconEvent::Click { rect, .. } => Some(rect.clone()),
                TrayIconEvent::Move { rect, .. } => Some(rect.clone()),
                TrayIconEvent::Enter { rect, .. } => Some(rect.clone()),
                _ => None,
            };
            if let Some(rect) = rect {
                if let Ok(mut slot) = app.state::<TrayRect>().0.lock() {
                    *slot = Some(rect);
                }
            }

            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                // While recording, a tray click stops the dictation instead of
                // toggling the popover.
                if app.state::<RecordingFlag>().0.load(Ordering::SeqCst) {
                    let _ = app.emit("popover-stop", ());
                    return;
                }
                if let Some(window) = app.get_webview_window("main") {
                    if window.is_visible().unwrap_or(false) {
                        let _ = window.hide();
                    } else {
                        show_popover(app);
                    }
                }
            }
        })
        .build(app)?;
    Ok(())
}
