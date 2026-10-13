# Third-Party Notices

## Handy

Parts of the macOS app are adapted from Handy (https://github.com/cjpais/handy):

- `BlitztextMac/Services/TranscriptPostProcessor.swift`: custom term correction and filler word removal, ported from `src-tauri/src/audio_toolkit/text.rs`
- `BlitztextMac/Services/ClipboardPasteService.swift`: receipt-based clipboard restore, adapted from `src-tauri/src/paste_tx`

```text
MIT License

Copyright (c) 2025 CJ Pais

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Amical

Parts of both apps follow Amical (https://github.com/amicalhq/amical):

- `BlitztextShared/Transcription/HallucinationFilter.swift`: the idea of a list of phrases Whisper invents (`pipeline/utils/segment-filter.ts`)
- `BlitztextMac/Services/FocusedFieldReader.swift`: reading the browser address through the Accessibility API with `AXManualAccessibility` (`swift-helper`)
- `BlitztextMac/Services/SystemAudioMuter.swift`: muting the sound output while recording, with volume 0 as fallback (`swift-helper`)
- The idea of fitting a dictation to the text around the cursor (`BlitztextMac/Services/InsertionFitter.swift`) and of telling the language model that the transcript is not a request (`BlitztextShared/AI/ModePrompts.swift`)

```text
MIT License

Copyright (c) 2025 Naomi Chopra, Haritabh Singh

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## FluidAudio

Local Parakeet transcription uses FluidAudio (https://github.com/FluidInference/FluidAudio), licensed under the Apache License 2.0.

## NVIDIA Parakeet TDT 0.6B v3

The local model "Parakeet v3" is NVIDIA Parakeet TDT 0.6B v3 (https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), converted to CoreML by FluidInference (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml). Both are licensed under Creative Commons Attribution 4.0 International (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). The weights are downloaded on demand and not modified by Blitztext.

## Octicons

The GitHub mark in the macOS settings (`BlitztextMac/Resources/Assets.xcassets/GitHubMark.imageset`) is `mark-github-24.svg` from Octicons (https://github.com/primer/octicons). It links to the Blitztext repository. GitHub and the GitHub logo are trademarks of GitHub, Inc.

```text
MIT License

Copyright (c) 2026 GitHub Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Public Sans

Headlines use Public Sans (https://github.com/uswds/public-sans), bundled from the Blackboat design system as TrueType files. Public Sans is licensed under the SIL Open Font License 1.1 (https://openfontlicense.org). The fonts were converted from WOFF2 to TTF without changing the glyphs.

## WhisperKit and Whisper

Local Whisper transcription (macOS, and optionally iOS) uses WhisperKit by Argmax (https://github.com/argmaxinc/argmax-oss-swift), licensed under the MIT License. The models are OpenAI Whisper (https://github.com/openai/whisper, MIT License), converted to Core ML by Argmax (https://huggingface.co/argmaxinc/whisperkit-coreml). The weights are downloaded on demand and not modified by Blitztext.
