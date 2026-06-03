using System.ComponentModel;
using System.IO;
using System.Net.Http;
using System.Windows;
using BlitztextWin.App.Services;
using BlitztextWin.Core;
using Forms = System.Windows.Forms;
using WpfComboBox = System.Windows.Controls.ComboBox;
using WpfComboBoxItem = System.Windows.Controls.ComboBoxItem;

namespace BlitztextWin.App;

public partial class MainWindow : Window
{
    private readonly HttpClient httpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(90),
    };

    private readonly SettingsStore settingsStore = new();
    private readonly WavAudioRecorder recorder = new();
    private readonly GlobalHotkeyService hotkeyService = new();
    private readonly OpenAiClient openAiClient;

    private Forms.NotifyIcon? notifyIcon;
    private BlitztextSettings settings = new();
    private WorkflowType? activeWorkflow;
    private bool activeWorkflowFromHotkey;

    public MainWindow()
    {
        InitializeComponent();
        openAiClient = new OpenAiClient(httpClient);
        Loaded += MainWindow_Loaded;
        Closing += MainWindow_Closing;
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        settings = settingsStore.Load();
        ApplySettingsToUi();
        ApiKeyBox.Password = CredentialStore.ReadOpenAiApiKey() ?? string.Empty;
        ConfigureTrayIcon();
        hotkeyService.Initialize(this);
        hotkeyService.HotkeyPressed += StartWorkflowFromHotkey;
        hotkeyService.RegisterDefaults();
    }

    private void MainWindow_Closing(object? sender, CancelEventArgs e)
    {
        hotkeyService.Dispose();
        notifyIcon?.Dispose();
        recorder.Dispose();
        httpClient.Dispose();
    }

    private void ConfigureTrayIcon()
    {
        notifyIcon = new Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = "Blitztext",
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip(),
        };
        notifyIcon.ContextMenuStrip.Items.Add("Oeffnen", null, (_, _) => ShowFromTray());
        notifyIcon.ContextMenuStrip.Items.Add("Beenden", null, (_, _) => Close());
        notifyIcon.DoubleClick += (_, _) => ShowFromTray();
    }

    private void ShowFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void ApplySettingsToUi()
    {
        LanguageBox.Text = settings.Language;
        CustomTermsBox.Text = string.Join(Environment.NewLine, settings.TextImprovement.CustomTerms);
        ContextBox.Text = settings.TextImprovement.Context;
        AutoPasteBox.IsChecked = settings.AutoPaste;
        SelectComboByTag(ToneBox, settings.TextImprovement.Tone.ToString());
        SelectComboByTag(EmojiDensityBox, settings.EmojiDensity.ToString());
    }

    private void SaveSettingsFromUi()
    {
        settings.Language = string.IsNullOrWhiteSpace(LanguageBox.Text) ? "de" : LanguageBox.Text.Trim();
        settings.AutoPaste = AutoPasteBox.IsChecked == true;
        settings.TextImprovement.Context = ContextBox.Text.Trim();
        settings.TextImprovement.CustomTerms = ParseCustomTerms(CustomTermsBox.Text);
        settings.TextImprovement.Tone = ParseComboTag(ToneBox, TextTone.Neutral);
        settings.EmojiDensity = ParseComboTag(EmojiDensityBox, EmojiDensity.Mittel);
        settingsStore.Save(settings);
    }

    private static void SelectComboByTag(WpfComboBox comboBox, string tag)
    {
        foreach (WpfComboBoxItem item in comboBox.Items)
        {
            if (string.Equals(item.Tag?.ToString(), tag, StringComparison.Ordinal))
            {
                comboBox.SelectedItem = item;
                return;
            }
        }
    }

    private static T ParseComboTag<T>(WpfComboBox comboBox, T fallback)
        where T : struct
    {
        var tag = (comboBox.SelectedItem as WpfComboBoxItem)?.Tag?.ToString();
        return Enum.TryParse<T>(tag, out var value) ? value : fallback;
    }

    private static List<string> ParseCustomTerms(string value)
    {
        return value.Split([',', ';', '\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private void SaveApiKeyButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(ApiKeyBox.Password))
        {
            CredentialStore.DeleteOpenAiApiKey();
            SetStatus("API Key entfernt.");
            return;
        }

        CredentialStore.SaveOpenAiApiKey(ApiKeyBox.Password.Trim());
        SetStatus("API Key im Windows Credential Manager gespeichert.");
    }

    private void SaveSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        SaveSettingsFromUi();
        SetStatus("Einstellungen gespeichert.");
    }

    private async void WorkflowButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not string tag || !Enum.TryParse<WorkflowType>(tag, out var workflow))
        {
            return;
        }

        await ToggleWorkflowAsync(workflow, fromHotkey: false);
    }

    private async void StartWorkflowFromHotkey(WorkflowType workflow)
    {
        await Dispatcher.InvokeAsync(async () =>
        {
            Hide();
            await ToggleWorkflowAsync(workflow, fromHotkey: true);
        });
    }

    private async Task ToggleWorkflowAsync(WorkflowType workflow, bool fromHotkey)
    {
        if (activeWorkflow is not null)
        {
            await StopAndProcessAsync();
            return;
        }

        SaveSettingsFromUi();
        if (string.IsNullOrWhiteSpace(CredentialStore.ReadOpenAiApiKey()))
        {
            ShowFromTray();
            SetStatus("OpenAI API Key fehlt.");
            return;
        }

        try
        {
            var path = recorder.Start();
            activeWorkflow = workflow;
            activeWorkflowFromHotkey = fromHotkey;
            SetWorkflowButtonsEnabled(false);
            SetStatus($"{workflow.DisplayName()}: Aufnahme laeuft. Hotkey oder Button erneut druecken zum Stoppen.");
            ResultBox.Text = $"Aufnahme laeuft...\n{path}";
        }
        catch (Exception ex)
        {
            activeWorkflow = null;
            activeWorkflowFromHotkey = false;
            SetWorkflowButtonsEnabled(true);
            ShowFromTray();
            SetStatus("Aufnahme konnte nicht gestartet werden: " + ex.Message);
        }
    }

    private async Task StopAndProcessAsync()
    {
        if (activeWorkflow is null)
        {
            return;
        }

        var workflow = activeWorkflow.Value;
        var shouldAutoPaste = activeWorkflowFromHotkey && settings.AutoPaste;
        activeWorkflow = null;
        activeWorkflowFromHotkey = false;
        SetWorkflowButtonsEnabled(false);

        var recording = recorder.Stop();
        if (TranscriptionQualityService.ShouldRejectRecording(recording.Duration))
        {
            SetWorkflowButtonsEnabled(true);
            ShowFromTray();
            SetStatus("Keine Aufnahme erkannt.");
            return;
        }

        try
        {
            SetStatus("Wird transkribiert...");
            var apiKey = CredentialStore.ReadOpenAiApiKey();
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                throw new InvalidOperationException("OpenAI API Key fehlt.");
            }

            var rawText = await openAiClient.TranscribeAsync(
                apiKey,
                recording.FilePath,
                settings.TextImprovement.CustomTerms,
                settings.Language,
                CancellationToken.None);
            var cleanedRawText = TranscriptionQualityService.CleanedTranscript(rawText);
            if (TranscriptionQualityService.IsLikelyArtifact(cleanedRawText, recording.Duration))
            {
                throw new InvalidOperationException("Keine Aufnahme erkannt.");
            }

            var result = await RunSecondPhaseIfNeededAsync(apiKey, workflow, cleanedRawText);
            result = TranscriptionQualityService.CleanedTranscript(result);
            ResultBox.Text = result;
            System.Windows.Clipboard.SetText(result);

            if (shouldAutoPaste)
            {
                PasteService.SendCtrlV();
                SetStatus($"{workflow.DisplayName()}: Ergebnis eingefuegt.");
            }
            else
            {
                ShowFromTray();
                SetStatus($"{workflow.DisplayName()}: Ergebnis in Zwischenablage kopiert.");
            }
        }
        catch (Exception ex)
        {
            ShowFromTray();
            SetStatus(ex.Message);
        }
        finally
        {
            TryDelete(recording.FilePath);
            SetWorkflowButtonsEnabled(true);
        }
    }

    private Task<string> RunSecondPhaseIfNeededAsync(string apiKey, WorkflowType workflow, string cleanedRawText)
    {
        return workflow switch
        {
            WorkflowType.TextImprover => openAiClient.ImproveAsync(apiKey, cleanedRawText, settings.TextImprovement, CancellationToken.None),
            WorkflowType.DampfAblassen => openAiClient.DampfAblassenAsync(apiKey, cleanedRawText, settings.DampfAblassen, CancellationToken.None),
            WorkflowType.EmojiText => openAiClient.AddEmojisAsync(apiKey, cleanedRawText, settings.EmojiDensity, CancellationToken.None),
            _ => Task.FromResult(cleanedRawText),
        };
    }

    private void SetWorkflowButtonsEnabled(bool enabled)
    {
        TranscriptionButton.IsEnabled = enabled || activeWorkflow == WorkflowType.Transcription;
        ImproveButton.IsEnabled = enabled || activeWorkflow == WorkflowType.TextImprover;
        DampfButton.IsEnabled = enabled || activeWorkflow == WorkflowType.DampfAblassen;
        EmojiButton.IsEnabled = enabled || activeWorkflow == WorkflowType.EmojiText;
    }

    private void SetStatus(string text)
    {
        StatusText.Text = text;
        notifyIcon?.ShowBalloonTip(2000, "Blitztext", text, Forms.ToolTipIcon.Info);
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(ResultBox.Text))
        {
            System.Windows.Clipboard.SetText(ResultBox.Text);
            SetStatus("Ergebnis kopiert.");
        }
    }

    private void HideButton_Click(object sender, RoutedEventArgs e)
    {
        Hide();
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
