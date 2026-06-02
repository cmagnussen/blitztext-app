use anyhow::{Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

pub struct RecorderState {
    inner: Mutex<RecorderInner>,
}

impl Default for RecorderState {
    fn default() -> Self {
        Self {
            inner: Mutex::new(RecorderInner {
                is_recording: false,
                audio_level: 0.0,
                samples: Vec::new(),
                sample_rate: 16000,
                stream: None,
                output_path: None,
            }),
        }
    }
}

struct RecorderInner {
    is_recording: bool,
    audio_level: f32,
    samples: Vec<f32>,
    sample_rate: u32,
    stream: Option<cpal::Stream>,
    output_path: Option<String>,
}

// cpal::Stream is not Send, but we only access it from the main thread context
unsafe impl Send for RecorderInner {}

pub fn start_recording(state: &RecorderState) -> Result<()> {
    let mut inner = state.inner.lock().unwrap();

    if inner.is_recording {
        anyhow::bail!("Aufnahme läuft bereits");
    }

    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .context("Kein Mikrofon gefunden")?;

    let config = cpal::StreamConfig {
        channels: 1,
        sample_rate: cpal::SampleRate(16000),
        buffer_size: cpal::BufferSize::Default,
    };

    inner.samples.clear();
    inner.sample_rate = 16000;
    inner.is_recording = true;
    inner.audio_level = 0.0;

    let samples_ref = Arc::new(Mutex::new(Vec::<f32>::new()));
    let level_ref = Arc::new(Mutex::new(0.0f32));
    let samples_clone = samples_ref.clone();
    let level_clone = level_ref.clone();

    let stream = device.build_input_stream(
        &config,
        move |data: &[f32], _: &cpal::InputCallbackInfo| {
            let mut samples = samples_clone.lock().unwrap();
            samples.extend_from_slice(data);

            if !data.is_empty() {
                let rms = (data.iter().map(|s| s * s).sum::<f32>() / data.len() as f32).sqrt();
                let db = 20.0 * rms.max(1e-10).log10();
                let normalized = ((db + 50.0) / 50.0).clamp(0.0, 1.0);
                *level_clone.lock().unwrap() = normalized;
            }
        },
        |err| {
            eprintln!("Audio-Fehler: {err}");
        },
        None,
    )?;

    stream.play()?;

    inner.stream = Some(stream);

    // Store references for later retrieval
    let temp_dir = std::env::temp_dir();
    let file_name = format!("blitztext-{}.wav", Uuid::new_v4());
    let output_path = temp_dir.join(file_name);
    inner.output_path = Some(output_path.to_string_lossy().to_string());

    // Swap in the shared buffers — we'll read from them on stop
    // Store Arc refs in a static-like way by leaking into inner
    // Actually, we need to store the Arc refs so stop_recording can access them
    // Use a simpler approach: store samples directly via the Arc
    // We'll swap the Arc's contents into inner.samples on stop
    drop(inner);

    // Store the Arcs in thread-local or a side channel
    // For simplicity, we'll re-lock and store the Arc pointers
    // Store shared buffers for retrieval on stop
    SHARED_SAMPLES
        .lock()
        .unwrap()
        .replace(samples_ref);
    SHARED_LEVEL.lock().unwrap().replace(level_ref);

    Ok(())
}

use std::sync::LazyLock;

static SHARED_SAMPLES: LazyLock<Mutex<Option<Arc<Mutex<Vec<f32>>>>>> =
    LazyLock::new(|| Mutex::new(None));
static SHARED_LEVEL: LazyLock<Mutex<Option<Arc<Mutex<f32>>>>> =
    LazyLock::new(|| Mutex::new(None));

pub fn stop_recording(state: &RecorderState) -> Result<String> {
    let mut inner = state.inner.lock().unwrap();

    if !inner.is_recording {
        anyhow::bail!("Keine aktive Aufnahme");
    }

    inner.is_recording = false;
    inner.stream = None; // drops the stream, stopping recording

    // Retrieve samples from shared buffer
    let samples = if let Some(arc) = SHARED_SAMPLES.lock().unwrap().take() {
        arc.lock().unwrap().clone()
    } else {
        Vec::new()
    };

    SHARED_LEVEL.lock().unwrap().take();

    let output_path = inner
        .output_path
        .take()
        .context("Kein Ausgabepfad gesetzt")?;

    let sample_rate = inner.sample_rate;
    drop(inner);

    // Write WAV file
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = hound::WavWriter::create(&output_path, spec)?;
    for sample in &samples {
        let amplitude = (sample * 32767.0).clamp(-32768.0, 32767.0) as i16;
        writer.write_sample(amplitude)?;
    }
    writer.finalize()?;

    Ok(output_path)
}

pub fn get_audio_level(_state: &RecorderState) -> f32 {
    if let Some(arc) = SHARED_LEVEL.lock().unwrap().as_ref() {
        *arc.lock().unwrap()
    } else {
        0.0
    }
}
