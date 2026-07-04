#!/bin/bash
set -euo pipefail

# Startet einen lokalen, OpenAI-kompatiblen LLM-Server für die Blitztext-KI-Features
# (Blitztext+, $%&!, :)) – komplett offline.
#
# Verwendet das bereits von CoTypist installierte Gemma-Modell (kein Download nötig).
# Voraussetzung: brew install llama.cpp
#
# In Blitztext → Einstellungen → Zugang → "Lokales KI-Modell verwenden" aktivieren,
# Server-Adresse: http://localhost:8080/v1

MODEL="${BLITZTEXT_LLM_MODEL:-$HOME/Library/Application Support/app.cotypist.Cotypist/Models/Qwen3-8B.i1-Q4_K_M.gguf}"
PORT="${BLITZTEXT_LLM_PORT:-8080}"

if ! command -v llama-server >/dev/null 2>&1; then
    echo "❌ llama-server nicht gefunden. Installiere es mit: brew install llama.cpp"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "❌ Modell nicht gefunden: $MODEL"
    echo "   Setze BLITZTEXT_LLM_MODEL auf den Pfad einer .gguf-Datei."
    exit 1
fi

echo "🧠 Starte llama-server auf http://127.0.0.1:$PORT/v1"
echo "   Modell: $MODEL"
echo "   Beenden mit Ctrl+C."

# Qwen-3 ist auf den "Thinking"-Modus ausgelegt. Mit --reasoning on läuft das Modell
# nativ (stoppt zuverlässig), und llama-server filtert den <think>-Teil serverseitig
# in ein separates Feld -> das von Blitztext gelesene "content" bleibt sauber.
# (--reasoning off bringt dieses Modell zum Endlos-Generieren / Halluzinieren.)
EXTRA_ARGS=()
case "$(basename "$MODEL" | tr '[:upper:]' '[:lower:]')" in
    *qwen3*|*qwen-3*|*qwen_3*)
        echo "   Qwen erkannt → nativer Reasoning-Modus, Denk-Teil wird ausgefiltert."
        EXTRA_ARGS+=(--reasoning on)
        ;;
esac

# --jinja  : nutzt das im GGUF eingebettete Chat-Template (wichtig für korrektes Format)
# -ngl 99  : alle Layer auf die GPU (Metal) – schnelle Antworten
# -c 8192  : Kontextfenster
exec llama-server \
    -m "$MODEL" \
    --host 127.0.0.1 \
    --port "$PORT" \
    --jinja \
    -ngl 99 \
    -c 8192 \
    --parallel 1 \
    "${EXTRA_ARGS[@]}"
