const { invoke } = window.__TAURI__.core;

const WORKFLOW_CONFIGS = {
    transcription: {
        name: "Blitztext",
        model: null,
        temperature: null,
        systemPrompt: null,
    },
    textImprover: {
        name: "Blitztext+",
        model: "gpt-4o-mini",
        temperature: 0.3,
        defaultPrompt:
            "Du bist ein Lektor und Schreibassistent. Du erhaeltst ein Transkript gesprochener Sprache. " +
            "Deine Aufgabe: Korrigiere Rechtschreibung und Grammatik. Verbessere die Formulierung, damit der Text " +
            "klar und gut lesbar ist. Behalte die urspruengliche Bedeutung und den Inhalt bei. " +
            "Gib nur den verbesserten Text zurueck, ohne Erklaerungen.",
    },
    dampfAblassen: {
        name: "Blitztext $%&!",
        model: "gpt-4o",
        temperature: 0.4,
        defaultPrompt:
            "Du erhaeltst ein emotional gesprochenes Transkript. Die Person ist aufgebracht oder frustriert. " +
            "Deine Aufgabe: Erkenne das eigentliche Ziel und die Frustration. Entferne Beleidigungen, Drohungen und Sarkasmus. " +
            "Behalte die Fakten. Bewahre die Dringlichkeit. Formuliere eine ruhige, respektvolle Nachricht. " +
            "Gib nur die umformulierte Nachricht zurueck.",
    },
    emojiText: {
        name: "Blitztext :)",
        model: "gpt-4o-mini",
        temperature: 0.3,
    },
};

const EMOJI_DENSITY_PROMPTS = {
    wenig:
        "Du erhaeltst ein Transkript. Fuege passende Emojis ein, maximal 1-2 pro Absatz. " +
        "Gib nur den Text mit Emojis zurueck.",
    mittel:
        "Du erhaeltst ein Transkript. Fuege passende Emojis ein, etwa 1-2 alle 1-2 Saetze. " +
        "Gib nur den Text mit Emojis zurueck.",
    viel:
        "Du erhaeltst ein Transkript. Fuege reichlich passende Emojis ein, mehrere pro Satz. " +
        "Gib nur den Text mit Emojis zurueck.",
};

const TONE_ADDITIONS = {
    formal: " Verwende einen formellen, professionellen Ton.",
    neutral: "",
    casual: " Verwende einen lockeren, freundlichen Ton.",
};

let state = {
    currentPage: null,
    settings: null,
    activeWorkflow: null,
    waveformInterval: null,
    audioLevelInterval: null,
};

// ---- Page Navigation ----

function showPage(pageId) {
    document.querySelectorAll(".page").forEach((p) => p.classList.add("hidden"));
    document.getElementById(`page-${pageId}`).classList.remove("hidden");
    state.currentPage = pageId;
}

// ---- Initialization ----

async function init() {
    try {
        state.settings = await invoke("load_settings");
    } catch {
        state.settings = defaultSettings();
    }

    const hasKey = await invoke("has_api_key");

    if (!hasKey && !state.settings.app.hasSeenOnboarding) {
        showPage("onboarding");
    } else {
        showPage("main");
    }

    applySettings();
    setupEventListeners();
    setupGlobalShortcuts();
}

function defaultSettings() {
    return {
        app: { hotkeyMode: "toggle", hasSeenOnboarding: false },
        transcription: { language: "de", customTerms: [] },
        textImprovement: { systemPrompt: "", context: "", tone: "neutral", customName: "" },
        dampfAblassen: { systemPrompt: "", customName: "" },
        emojiText: { emojiDensity: "mittel", customName: "" },
    };
}

// ---- Event Listeners ----

function setupEventListeners() {
    document.getElementById("btn-save-key").addEventListener("click", onSaveOnboardingKey);

    document.querySelectorAll(".workflow-btn").forEach((btn) => {
        btn.addEventListener("click", () => startWorkflow(btn.dataset.workflow));
    });

    document.getElementById("btn-settings").addEventListener("click", () => showPage("settings"));
    document.getElementById("btn-back-settings").addEventListener("click", () => {
        saveCurrentSettings();
        showPage("main");
    });
    document.getElementById("btn-quit").addEventListener("click", async () => {
        const { exit } = window.__TAURI__.process;
        await exit(0);
    });

    document.getElementById("btn-stop").addEventListener("click", stopWorkflow);
    document.getElementById("btn-back").addEventListener("click", () => showPage("main"));
    document.getElementById("btn-retry").addEventListener("click", () => {
        if (state.activeWorkflow) startWorkflow(state.activeWorkflow);
    });

    document.querySelectorAll(".tab").forEach((tab) => {
        tab.addEventListener("click", () => switchTab(tab.dataset.tab));
    });

    document.getElementById("btn-update-key").addEventListener("click", onUpdateApiKey);
    document.getElementById("btn-add-term").addEventListener("click", addTerm);
    document.getElementById("new-term").addEventListener("keydown", (e) => {
        if (e.key === "Enter") addTerm();
    });
}

// ---- Global Shortcuts ----

async function setupGlobalShortcuts() {
    try {
        const { register } = window.__TAURI_PLUGIN_GLOBAL_SHORTCUT__;
        if (!register) return;

        await register("CmdOrCtrl+Shift+1", () => startWorkflow("transcription"));
        await register("CmdOrCtrl+Shift+2", () => startWorkflow("textImprover"));
        await register("CmdOrCtrl+Shift+3", () => startWorkflow("dampfAblassen"));
        await register("CmdOrCtrl+Shift+4", () => startWorkflow("emojiText"));
    } catch (e) {
        console.warn("Globale Shortcuts konnten nicht registriert werden:", e);
    }
}

// ---- Onboarding ----

async function onSaveOnboardingKey() {
    const input = document.getElementById("onboarding-api-key");
    const key = input.value.trim();

    if (!key || !key.startsWith("sk-")) {
        input.style.borderColor = "var(--error)";
        return;
    }

    try {
        await invoke("save_api_key", { key });
        state.settings.app.hasSeenOnboarding = true;
        await saveCurrentSettings();
        showPage("main");
    } catch (e) {
        console.error("Fehler beim Speichern:", e);
    }
}

// ---- Workflows ----

async function startWorkflow(type) {
    state.activeWorkflow = type;
    const config = WORKFLOW_CONFIGS[type];

    showPage("workflow");
    showWorkflowPhase("recording");
    document.getElementById("workflow-active-title").textContent = config.name;

    startWaveform();

    try {
        await invoke("start_recording");
    } catch (e) {
        showError("Mikrofon-Fehler: " + e);
    }
}

async function stopWorkflow() {
    stopWaveform();

    const type = state.activeWorkflow;
    const config = WORKFLOW_CONFIGS[type];

    showWorkflowPhase("processing");

    try {
        const audioPath = await invoke("stop_recording");

        document.getElementById("processing-detail").textContent = "Transkribiere...";

        const apiKey = await invoke("load_api_key");
        const language = state.settings.transcription.language || "de";
        const customTerms = state.settings.transcription.customTerms || [];

        let transcription = await invoke("transcribe", {
            audioPath,
            apiKey,
            language,
            customTerms,
        });

        transcription = transcription.trim();
        if (!transcription) {
            showError("Kein Text erkannt. Bitte sprich deutlicher oder laenger.");
            return;
        }

        let finalText = transcription;

        if (config.model) {
            document.getElementById("processing-detail").textContent = "Verbessere Text...";

            const systemPrompt = buildSystemPrompt(type);
            finalText = await invoke("chat_completion", {
                apiKey,
                systemPrompt,
                userText: transcription,
                model: config.model,
                temperature: config.temperature,
            });
        }

        finalText = finalText.trim();

        try {
            const { writeText } = window.__TAURI_PLUGIN_CLIPBOARD_MANAGER__;
            if (writeText) {
                await writeText(finalText);
                await invoke("simulate_paste");
            }
        } catch (e) {
            console.warn("Einfuegen fehlgeschlagen, Text in Zwischenablage:", e);
        }

        showSuccess(finalText);
    } catch (e) {
        showError(String(e));
    }
}

function buildSystemPrompt(type) {
    const s = state.settings;

    switch (type) {
        case "textImprover": {
            let prompt = s.textImprovement.systemPrompt || WORKFLOW_CONFIGS.textImprover.defaultPrompt;
            prompt += TONE_ADDITIONS[s.textImprovement.tone] || "";
            if (s.textImprovement.context) {
                prompt += ` Kontext: ${s.textImprovement.context}.`;
            }
            if (s.transcription.customTerms.length > 0) {
                prompt += ` Behalte diese Begriffe bei: ${s.transcription.customTerms.join(", ")}.`;
            }
            return prompt;
        }
        case "dampfAblassen":
            return s.dampfAblassen.systemPrompt || WORKFLOW_CONFIGS.dampfAblassen.defaultPrompt;
        case "emojiText":
            return EMOJI_DENSITY_PROMPTS[s.emojiText.emojiDensity] || EMOJI_DENSITY_PROMPTS.mittel;
        default:
            return "";
    }
}

// ---- Waveform ----

function startWaveform() {
    const container = document.getElementById("waveform");
    container.innerHTML = "";

    const barCount = 40;
    for (let i = 0; i < barCount; i++) {
        const bar = document.createElement("div");
        bar.className = "bar";
        bar.style.height = "4px";
        container.appendChild(bar);
    }

    const bars = container.querySelectorAll(".bar");

    state.audioLevelInterval = setInterval(async () => {
        try {
            const level = await invoke("get_audio_level");
            updateWaveformBars(bars, level);
        } catch {
            updateWaveformBars(bars, 0);
        }
    }, 50);
}

function updateWaveformBars(bars, level) {
    const time = Date.now() / 1000;
    bars.forEach((bar, i) => {
        const phase = (i / bars.length) * Math.PI * 2;
        const breathe = Math.sin(time * 3 + phase) * 0.3 + 0.5;
        const jitter = (Math.random() - 0.5) * 0.15;
        const height = Math.max(4, (level * breathe + jitter) * 60 + 4);
        bar.style.height = `${height}px`;
        bar.style.opacity = 0.5 + level * 0.5;
    });
}

function stopWaveform() {
    if (state.audioLevelInterval) {
        clearInterval(state.audioLevelInterval);
        state.audioLevelInterval = null;
    }
}

// ---- UI Helpers ----

function showWorkflowPhase(phase) {
    document.getElementById("workflow-recording").classList.add("hidden");
    document.getElementById("workflow-processing").classList.add("hidden");
    document.getElementById("workflow-result").classList.add("hidden");

    document.getElementById(`workflow-${phase}`).classList.remove("hidden");
}

function showSuccess(text) {
    showWorkflowPhase("result");
    document.getElementById("result-success").classList.remove("hidden");
    document.getElementById("result-error").classList.add("hidden");
    document.getElementById("result-text").textContent = text;
}

function showError(message) {
    stopWaveform();
    showWorkflowPhase("result");
    document.getElementById("result-success").classList.add("hidden");
    document.getElementById("result-error").classList.remove("hidden");
    document.getElementById("error-message").textContent = message;
}

// ---- Settings ----

function switchTab(tabName) {
    document.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
    document.querySelector(`.tab[data-tab="${tabName}"]`).classList.add("active");

    document.querySelectorAll(".tab-content").forEach((c) => c.classList.add("hidden"));
    document.getElementById(`tab-${tabName}`).classList.remove("hidden");
}

function applySettings() {
    const s = state.settings;

    document.getElementById("setting-hotkey-mode").value = s.app.hotkeyMode;
    document.getElementById("setting-language").value = s.transcription.language;
    document.getElementById("setting-tone").value = s.textImprovement.tone;
    document.getElementById("setting-improvement-prompt").value = s.textImprovement.systemPrompt;
    document.getElementById("setting-context").value = s.textImprovement.context;
    document.getElementById("setting-dampf-prompt").value = s.dampfAblassen.systemPrompt;
    document.getElementById("setting-emoji-density").value = s.emojiText.emojiDensity;

    renderTerms();
}

function renderTerms() {
    const container = document.getElementById("terms-list");
    container.innerHTML = "";

    (state.settings.transcription.customTerms || []).forEach((term, i) => {
        const chip = document.createElement("span");
        chip.className = "term-chip";
        chip.innerHTML = `${escapeHtml(term)} <button data-index="${i}">&times;</button>`;
        chip.querySelector("button").addEventListener("click", () => removeTerm(i));
        container.appendChild(chip);
    });
}

function addTerm() {
    const input = document.getElementById("new-term");
    const term = input.value.trim();
    if (!term) return;

    if (!state.settings.transcription.customTerms) {
        state.settings.transcription.customTerms = [];
    }

    state.settings.transcription.customTerms.push(term);
    input.value = "";
    renderTerms();
    saveCurrentSettings();
}

function removeTerm(index) {
    state.settings.transcription.customTerms.splice(index, 1);
    renderTerms();
    saveCurrentSettings();
}

async function onUpdateApiKey() {
    const input = document.getElementById("setting-api-key");
    const key = input.value.trim();
    if (!key) return;

    try {
        await invoke("save_api_key", { key });
        input.value = "";
        input.placeholder = "Gespeichert!";
        setTimeout(() => {
            input.placeholder = "sk-...";
        }, 2000);
    } catch (e) {
        console.error("Fehler:", e);
    }
}

async function saveCurrentSettings() {
    state.settings.app.hotkeyMode = document.getElementById("setting-hotkey-mode").value;
    state.settings.transcription.language = document.getElementById("setting-language").value;
    state.settings.textImprovement.tone = document.getElementById("setting-tone").value;
    state.settings.textImprovement.systemPrompt = document.getElementById("setting-improvement-prompt").value;
    state.settings.textImprovement.context = document.getElementById("setting-context").value;
    state.settings.dampfAblassen.systemPrompt = document.getElementById("setting-dampf-prompt").value;
    state.settings.emojiText.emojiDensity = document.getElementById("setting-emoji-density").value;

    try {
        await invoke("save_settings", { s: state.settings });
    } catch (e) {
        console.error("Einstellungen konnten nicht gespeichert werden:", e);
    }
}

function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
}

// ---- Start ----

document.addEventListener("DOMContentLoaded", init);
