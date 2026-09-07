import { invoke } from "@tauri-apps/api/core";
import promptData from "../../shared/prompts.json";

export type ApiProvider = "openAI" | "liteLLM";

export type TextTone = "formal" | "neutral" | "casual";
export type EmojiDensity = "wenig" | "mittel" | "viel";
// "hold" = push-to-talk (record while held); "toggle" = press to start/stop.
export type HotkeyMode = "hold" | "toggle";

export interface Settings {
  apiProvider: ApiProvider;
  // Launch the app on login (Windows: registry Run key / macOS: LaunchAgent).
  autostart: boolean;
  hotkeyMode: HotkeyMode;
  // Automatische Update-Pruefung, hoechstens einmal pro Kalendertag.
  automaticUpdateChecks: boolean;
  // ISO-Zeitstempel der letzten Pruefung, null wenn noch nie geprueft.
  lastUpdateCheck: string | null;
  liteLLM: {
    baseURL: string;
    fastModel: string;
    strongModel: string;
    transcriptionModel: string;
  };
  // Global hotkeys per workflow, as accelerator strings (e.g. "Super+Shift+KeyD").
  // "Super" is the Windows key (= Cmd on the Mac dev machine). Key names follow
  // the W3C KeyboardEvent.code values, so the in-app recorder can store them 1:1.
  hotkeys: Record<WorkflowType, string>;
  // Per-workflow tuning, mirroring the macOS app's "Anpassen" tab.
  improve: {
    tone: TextTone;
    systemPrompt: string; // custom instruction; overrides the default base prompt
    context: string;
    customTerms: string[];
  };
  dampf: {
    systemPrompt: string; // custom instruction; overrides the default prompt
  };
  emoji: {
    density: EmojiDensity;
  };
}

// The four dictation workflows, mirroring the macOS app.
export type WorkflowType = "transcribe" | "improve" | "dampf" | "emoji";

// UI labels and the macOS "Blitztext…" product names per workflow.
export const workflowLabels: Record<WorkflowType, string> = {
  transcribe: "Diktat",
  improve: "Text verbessern",
  dampf: "Dampf ablassen",
  emoji: "Emojis",
};

export const workflowBrandNames: Record<WorkflowType, string> = {
  transcribe: "Blitztext",
  improve: "Blitztext+",
  dampf: "Blitztext $%&!",
  emoji: "Blitztext :)",
};

const SETTINGS_KEY = "blitztext.settings";
export const LITELLM_KEY_ACCOUNT = "liteLLMApiKey";

export const defaultSettings: Settings = {
  apiProvider: "liteLLM",
  autostart: false,
  hotkeyMode: "hold",
  automaticUpdateChecks: true,
  lastUpdateCheck: null,
  liteLLM: {
    baseURL: "",
    fastModel: "gpt-4o-mini",
    strongModel: "gpt-5.5",
    transcriptionModel: "gpt-4o-transcribe",
  },
  hotkeys: {
    transcribe: "Super+Shift+KeyD",
    improve: "Super+Shift+KeyI",
    dampf: "Super+Shift+KeyA",
    emoji: "Super+Shift+KeyE",
  },
  improve: {
    tone: "neutral",
    systemPrompt: "",
    context: "",
    customTerms: [],
  },
  dampf: {
    // Pre-filled with the default prompt (editable), exactly like the macOS app.
    systemPrompt: promptData.dampfAblassen.default,
  },
  emoji: {
    density: "mittel",
  },
};

export function loadSettings(): Settings {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return structuredClone(defaultSettings);
    const parsed = JSON.parse(raw);
    return {
      ...structuredClone(defaultSettings),
      ...parsed,
      liteLLM: { ...defaultSettings.liteLLM, ...(parsed.liteLLM ?? {}) },
      hotkeys: { ...defaultSettings.hotkeys, ...(parsed.hotkeys ?? {}) },
      improve: { ...defaultSettings.improve, ...(parsed.improve ?? {}) },
      // An empty stored dampf prompt falls back to the default text, so the
      // pre-filled instruction is always visible (and editable).
      dampf: {
        systemPrompt: parsed.dampf?.systemPrompt?.trim()
          ? parsed.dampf.systemPrompt
          : defaultSettings.dampf.systemPrompt,
      },
      emoji: { ...defaultSettings.emoji, ...(parsed.emoji ?? {}) },
    };
  } catch {
    return structuredClone(defaultSettings);
  }
}

export function saveSettings(settings: Settings): void {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
}

// Secret helpers backed by the Rust keyring commands.
export async function setSecret(account: string, value: string): Promise<void> {
  await invoke("secret_set", { account, value });
}

export async function getSecret(account: string): Promise<string | null> {
  return (await invoke<string | null>("secret_get", { account })) ?? null;
}

export async function hasSecret(account: string): Promise<boolean> {
  return await invoke<boolean>("secret_has", { account });
}
