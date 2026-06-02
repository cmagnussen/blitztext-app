use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsContainer {
    #[serde(default)]
    pub app: AppSettings,
    #[serde(default)]
    pub transcription: TranscriptionSettings,
    #[serde(default)]
    pub text_improvement: TextImprovementSettings,
    #[serde(default)]
    pub dampf_ablassen: DampfAblassenSettings,
    #[serde(default)]
    pub emoji_text: EmojiTextSettings,
}

impl Default for SettingsContainer {
    fn default() -> Self {
        Self {
            app: AppSettings::default(),
            transcription: TranscriptionSettings::default(),
            text_improvement: TextImprovementSettings::default(),
            dampf_ablassen: DampfAblassenSettings::default(),
            emoji_text: EmojiTextSettings::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    #[serde(default = "default_hotkey_mode")]
    pub hotkey_mode: String,
    #[serde(default)]
    pub has_seen_onboarding: bool,
}

fn default_hotkey_mode() -> String {
    "toggle".to_string()
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            hotkey_mode: default_hotkey_mode(),
            has_seen_onboarding: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptionSettings {
    #[serde(default = "default_language")]
    pub language: String,
    #[serde(default)]
    pub custom_terms: Vec<String>,
}

fn default_language() -> String {
    "de".to_string()
}

impl Default for TranscriptionSettings {
    fn default() -> Self {
        Self {
            language: default_language(),
            custom_terms: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TextImprovementSettings {
    #[serde(default)]
    pub system_prompt: String,
    #[serde(default)]
    pub context: String,
    #[serde(default = "default_tone")]
    pub tone: String,
    #[serde(default)]
    pub custom_name: String,
}

fn default_tone() -> String {
    "neutral".to_string()
}

impl Default for TextImprovementSettings {
    fn default() -> Self {
        Self {
            system_prompt: String::new(),
            context: String::new(),
            tone: default_tone(),
            custom_name: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DampfAblassenSettings {
    #[serde(default)]
    pub system_prompt: String,
    #[serde(default)]
    pub custom_name: String,
}

impl Default for DampfAblassenSettings {
    fn default() -> Self {
        Self {
            system_prompt: String::new(),
            custom_name: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EmojiTextSettings {
    #[serde(default = "default_emoji_density")]
    pub emoji_density: String,
    #[serde(default)]
    pub custom_name: String,
}

fn default_emoji_density() -> String {
    "mittel".to_string()
}

impl Default for EmojiTextSettings {
    fn default() -> Self {
        Self {
            emoji_density: default_emoji_density(),
            custom_name: String::new(),
        }
    }
}

fn settings_path() -> PathBuf {
    let base = dirs::data_local_dir().unwrap_or_else(|| PathBuf::from("."));
    let dir = base.join("Blitztext");
    std::fs::create_dir_all(&dir).ok();
    dir.join("settings.json")
}

pub fn load_settings() -> Result<SettingsContainer> {
    let path = settings_path();
    if !path.exists() {
        return Ok(SettingsContainer::default());
    }
    let data = std::fs::read_to_string(&path)?;
    let settings: SettingsContainer = serde_json::from_str(&data)?;
    Ok(settings)
}

pub fn save_settings(settings: &SettingsContainer) -> Result<()> {
    let path = settings_path();
    let data = serde_json::to_string_pretty(settings)?;
    std::fs::write(&path, data)?;
    Ok(())
}
