use anyhow::{Context, Result};
use reqwest::multipart;
use serde::{Deserialize, Serialize};
use std::time::Duration;

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMessage>,
    temperature: f64,
}

#[derive(Serialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Deserialize)]
struct ChatChoice {
    message: ChatResponseMessage,
}

#[derive(Deserialize)]
struct ChatResponseMessage {
    content: Option<String>,
}

pub async fn transcribe(
    audio_path: &str,
    api_key: &str,
    language: &str,
    custom_terms: &[String],
) -> Result<String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(60))
        .build()?;

    let file_bytes = tokio::fs::read(audio_path).await?;
    let file_part = multipart::Part::bytes(file_bytes)
        .file_name("recording.wav")
        .mime_str("audio/wav")?;

    let mut form = multipart::Form::new()
        .part("file", file_part)
        .text("model", "whisper-1")
        .text("response_format", "text");

    if !language.is_empty() {
        form = form.text("language", language.to_string());
    }

    if !custom_terms.is_empty() {
        let prompt = format!("Eigennamen und Begriffe: {}", custom_terms.join(", "));
        form = form.text("prompt", prompt);
    }

    let response = client
        .post("https://api.openai.com/v1/audio/transcriptions")
        .header("Authorization", format!("Bearer {api_key}"))
        .multipart(form)
        .send()
        .await
        .context("Netzwerkfehler bei der Transkription")?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        anyhow::bail!("OpenAI API Fehler ({status}): {body}");
    }

    let text = response.text().await?;
    Ok(text.trim().to_string())
}

pub async fn chat_completion(
    api_key: &str,
    system_prompt: &str,
    user_text: &str,
    model: &str,
    temperature: f64,
) -> Result<String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(45))
        .build()?;

    let request = ChatRequest {
        model: model.to_string(),
        messages: vec![
            ChatMessage {
                role: "system".to_string(),
                content: system_prompt.to_string(),
            },
            ChatMessage {
                role: "user".to_string(),
                content: user_text.to_string(),
            },
        ],
        temperature,
    };

    let response = client
        .post("https://api.openai.com/v1/chat/completions")
        .header("Authorization", format!("Bearer {api_key}"))
        .header("Content-Type", "application/json")
        .json(&request)
        .send()
        .await
        .context("Netzwerkfehler bei der Chat-Anfrage")?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        anyhow::bail!("OpenAI API Fehler ({status}): {body}");
    }

    let chat_response: ChatResponse = response.json().await?;

    chat_response
        .choices
        .first()
        .and_then(|c| c.message.content.clone())
        .context("Keine Antwort von OpenAI erhalten")
}
