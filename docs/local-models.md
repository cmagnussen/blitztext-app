# Local Models

All speech recognition in Blitztext runs on your Mac. The app does not bundle a model; it downloads the one you choose from Hugging Face into `~/Library/Application Support/Blitztext/models/`.

## Recommended Model

**NVIDIA Parakeet TDT 0.6B v3** via [FluidAudio](https://github.com/FluidInference/FluidAudio), on Apple silicon: very fast, 25 European languages, detects the language. Weights under CC BY 4.0 ([model page](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)).

## Whisper Models

WhisperKit Core ML models (about 100 languages, language detection), installed from the app or manually into `~/Library/Application Support/Blitztext/models/whisperkit/`:

- [openai_whisper-small_216MB](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small_216MB)

- [openai_whisper-large-v3-v20240930_626MB](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB)
- [openai_whisper-large-v3-v20240930_turbo_632MB](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo_632MB)

The app detects installed model folders that contain `AudioEncoder.mlmodelc`, `MelSpectrogram.mlmodelc`, and `TextDecoder.mlmodelc`.

## Install From The App

Open **Settings > Modelle > Spracherkennung**, choose a model and load it. The selected model is used by every mode; the writing modes then rewrite the text with Apple Intelligence or your own model provider.

## Optional Manual Install

If you prefer the CLI path, install the Hugging Face CLI so the `hf` command is available:

```bash
python3 -m pip install --upgrade "huggingface_hub[cli]"
```

Create the local model cache:

```bash
mkdir -p "$HOME/Library/Application Support/Blitztext/models/whisperkit"
```

Download the recommended first model:

```bash
hf download argmaxinc/whisperkit-coreml \
  --include 'openai_whisper-small_216MB/*' \
  --local-dir "$HOME/Library/Application Support/Blitztext/models/whisperkit" \
  --max-workers 4
```

Expected folder layout:

```text
~/Library/Application Support/Blitztext/models/whisperkit/
  openai_whisper-small_216MB/
    AudioEncoder.mlmodelc/
    MelSpectrogram.mlmodelc/
    TextDecoder.mlmodelc/
```

If the folder is nested differently, the app will not detect the model.

## Notes

- First use can be slower because the model has to load and prewarm. After a macOS update, macOS prepares the model for the Neural Engine again, which can take a few minutes once.
- Audio never leaves the Mac. The writing modes rewrite locally with Apple Intelligence, or with your own model provider if you add one.
- Models are downloaded on demand so the repository and app package stay small and auditable.
