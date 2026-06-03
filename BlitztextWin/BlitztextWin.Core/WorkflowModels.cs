namespace BlitztextWin.Core;

public enum WorkflowType
{
    Transcription,
    TextImprover,
    DampfAblassen,
    EmojiText,
}

public static class WorkflowTypeExtensions
{
    public static string DisplayName(this WorkflowType type) => type switch
    {
        WorkflowType.Transcription => "Blitztext",
        WorkflowType.TextImprover => "Blitztext+",
        WorkflowType.DampfAblassen => "Blitztext $%&!",
        WorkflowType.EmojiText => "Blitztext :)",
        _ => type.ToString(),
    };

    public static string Subtitle(this WorkflowType type) => type switch
    {
        WorkflowType.Transcription => "Sprache rein. Text raus.",
        WorkflowType.TextImprover => "Geschrieben sprechen.",
        WorkflowType.DampfAblassen => "Frust rein. Entspannt raus.",
        WorkflowType.EmojiText => "Text rein. Emojis dazu.",
        _ => string.Empty,
    };

    public static string HotkeyLabel(this WorkflowType type) => type switch
    {
        WorkflowType.Transcription => "Ctrl + Shift + Space",
        WorkflowType.TextImprover => "Ctrl + Alt + Space",
        WorkflowType.DampfAblassen => "Ctrl + Alt + R",
        WorkflowType.EmojiText => "Ctrl + Alt + E",
        _ => string.Empty,
    };
}

public enum TextTone
{
    Formal,
    Neutral,
    Casual,
}

public enum EmojiDensity
{
    Wenig,
    Mittel,
    Viel,
}

public sealed class TextImprovementSettings
{
    public string SystemPrompt { get; set; } = string.Empty;

    public List<string> CustomTerms { get; set; } = [];

    public string Context { get; set; } = string.Empty;

    public TextTone Tone { get; set; } = TextTone.Neutral;
}

public sealed class DampfAblassenSettings
{
    public string SystemPrompt { get; set; } =
        "Du erhaeltst ein emotional gesprochenes Transkript. Erkenne zuerst das eigentliche Ziel, Anliegen und den wahren Frust der Person. Formuliere daraus eine klare, respektvolle und wirksame Nachricht, mit der die Person ihr Ziel eher erreicht. Bewahre relevante Fakten, konkrete Probleme, Grenzen, Erwartungen und die noetige Dringlichkeit. Entferne Beleidigungen, Drohungen, Sarkasmus, Unterstellungen und unnoetige Eskalation. Wenn mehrere Vorwuerfe genannt werden, verdichte sie auf die entscheidenden Kernpunkte. Der Ton soll ruhig, menschlich, bestimmt und loesungsorientiert sein. Gib NUR die fertige Nachricht zurueck.";
}

public sealed class BlitztextSettings
{
    public string Language { get; set; } = "de";

    public bool AutoPaste { get; set; } = true;

    public TextImprovementSettings TextImprovement { get; set; } = new();

    public DampfAblassenSettings DampfAblassen { get; set; } = new();

    public EmojiDensity EmojiDensity { get; set; } = EmojiDensity.Mittel;
}
