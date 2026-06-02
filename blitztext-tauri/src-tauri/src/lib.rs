mod audio;
mod credentials;
mod openai;
mod settings;
mod workflows;

use std::sync::Mutex;
use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::TrayIconBuilder,
    Manager,
};

pub struct AppStateWrapper(pub Mutex<settings::AppSettings>);

#[tauri::command]
async fn start_recording(state: tauri::State<'_, audio::RecorderState>) -> Result<(), String> {
    audio::start_recording(&state).map_err(|e| e.to_string())
}

#[tauri::command]
async fn stop_recording(state: tauri::State<'_, audio::RecorderState>) -> Result<String, String> {
    audio::stop_recording(&state).map_err(|e| e.to_string())
}

#[tauri::command]
async fn transcribe(audio_path: String, api_key: String, language: String, custom_terms: Vec<String>) -> Result<String, String> {
    openai::transcribe(&audio_path, &api_key, &language, &custom_terms)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn chat_completion(api_key: String, system_prompt: String, user_text: String, model: String, temperature: f64) -> Result<String, String> {
    openai::chat_completion(&api_key, &system_prompt, &user_text, &model, temperature)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn save_api_key(key: String) -> Result<(), String> {
    credentials::save_api_key(&key).map_err(|e| e.to_string())
}

#[tauri::command]
fn load_api_key() -> Result<String, String> {
    credentials::load_api_key().map_err(|e| e.to_string())
}

#[tauri::command]
fn delete_api_key() -> Result<(), String> {
    credentials::delete_api_key().map_err(|e| e.to_string())
}

#[tauri::command]
fn has_api_key() -> bool {
    credentials::has_api_key()
}

#[tauri::command]
fn load_settings() -> Result<settings::SettingsContainer, String> {
    settings::load_settings().map_err(|e| e.to_string())
}

#[tauri::command]
fn save_settings(s: settings::SettingsContainer) -> Result<(), String> {
    settings::save_settings(&s).map_err(|e| e.to_string())
}

#[tauri::command]
async fn simulate_paste() -> Result<(), String> {
    workflows::simulate_paste().map_err(|e| e.to_string())
}

#[tauri::command]
fn get_audio_level(state: tauri::State<'_, audio::RecorderState>) -> f32 {
    audio::get_audio_level(&state)
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .manage(audio::RecorderState::default())
        .manage(AppStateWrapper(Mutex::new(settings::AppSettings::default())))
        .setup(|app| {
            let quit = MenuItemBuilder::with_id("quit", "Beenden").build(app)?;
            let show = MenuItemBuilder::with_id("show", "Blitztext öffnen").build(app)?;
            let menu = MenuBuilder::new(app).items(&[&show, &quit]).build()?;

            let _tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("Blitztext")
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "quit" => {
                        app.exit(0);
                    }
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let tauri::tray::TrayIconEvent::Click {
                        button: tauri::tray::MouseButton::Left,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            start_recording,
            stop_recording,
            transcribe,
            chat_completion,
            save_api_key,
            load_api_key,
            delete_api_key,
            has_api_key,
            load_settings,
            save_settings,
            simulate_paste,
            get_audio_level,
        ])
        .run(tauri::generate_context!())
        .expect("Fehler beim Starten von Blitztext");
}
