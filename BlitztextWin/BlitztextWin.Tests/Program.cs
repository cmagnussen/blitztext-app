using BlitztextWin.Core;

var tests = new (string Name, Action Body)[]
{
    ("Text improvement prompt preserves custom terms and context", () =>
    {
        var settings = new TextImprovementSettings
        {
            Tone = TextTone.Formal,
            Context = "Antwort an einen Kunden",
            CustomTerms = ["Blitztext", "Blackboat"],
        };

        var prompt = PromptBuilder.BuildTextImprovementPrompt(settings);

        AssertContains(prompt, "formellen");
        AssertContains(prompt, "Blitztext, Blackboat");
        AssertContains(prompt, "Antwort an einen Kunden");
    }),
    ("Emoji prompt changes density instruction", () =>
    {
        var prompt = PromptBuilder.BuildEmojiPrompt(EmojiDensity.Viel);

        AssertContains(prompt, "grosszuegig");
        AssertContains(prompt, "Gib NUR den Text mit Emojis zurueck");
    }),
    ("Short recordings and known Whisper artifacts are rejected", () =>
    {
        AssertTrue(TranscriptionQualityService.ShouldRejectRecording(TimeSpan.FromMilliseconds(300)));
        AssertTrue(TranscriptionQualityService.IsLikelyArtifact("Untertitel der Amara.org-Community", TimeSpan.FromSeconds(1.2)));
        AssertFalse(TranscriptionQualityService.IsLikelyArtifact("Bitte den Termin auf morgen verschieben.", TimeSpan.FromSeconds(2)));
    }),
};

var failed = 0;
foreach (var test in tests)
{
    try
    {
        test.Body();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failed++;
        Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}");
    }
}

return failed == 0 ? 0 : 1;

static void AssertContains(string value, string expected)
{
    if (!value.Contains(expected, StringComparison.Ordinal))
    {
        throw new InvalidOperationException($"Expected '{expected}' in '{value}'.");
    }
}

static void AssertTrue(bool value)
{
    if (!value)
    {
        throw new InvalidOperationException("Expected true.");
    }
}

static void AssertFalse(bool value)
{
    if (value)
    {
        throw new InvalidOperationException("Expected false.");
    }
}
