namespace BlitztextWin.Core;

public static class PromptBuilder
{
    public static string BuildTextImprovementPrompt(TextImprovementSettings settings)
    {
        if (!string.IsNullOrWhiteSpace(settings.SystemPrompt))
        {
            var prompt = settings.SystemPrompt.Trim();
            if (settings.CustomTerms.Count > 0)
            {
                prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: "
                    + string.Join(", ", settings.CustomTerms);
            }

            return prompt;
        }

        var lines = new List<string>
        {
            "Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:",
            "- Korrigiere Rechtschreibung und Grammatik",
            "- Verbessere die Formulierung und den Lesefluss",
            "- Behalte die urspruengliche Bedeutung bei",
            "- Gib NUR den verbesserten Text zurueck, keine Erklaerungen",
        };

        lines.Add(settings.Tone switch
        {
            TextTone.Formal => "- Verwende einen formellen, professionellen Ton",
            TextTone.Casual => "- Verwende einen lockeren, natuerlichen Ton",
            _ => "- Verwende einen neutralen, klaren Ton",
        });

        if (settings.CustomTerms.Count > 0)
        {
            lines.Add(string.Empty);
            lines.Add("Wichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: "
                + string.Join(", ", settings.CustomTerms));
        }

        if (!string.IsNullOrWhiteSpace(settings.Context))
        {
            lines.Add(string.Empty);
            lines.Add("Kontext: " + settings.Context.Trim());
        }

        return string.Join('\n', lines);
    }

    public static string BuildEmojiPrompt(EmojiDensity density)
    {
        var densityInstruction = density switch
        {
            EmojiDensity.Wenig => "Setze nur vereinzelt Emojis ein, maximal 1-2 pro Absatz.",
            EmojiDensity.Viel => "Setze grosszuegig Emojis ein, gerne mehrere pro Satz.",
            _ => "Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze.",
        };

        return "Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, aber fuege passende Emojis ein. "
            + densityInstruction
            + " Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. Gib NUR den Text mit Emojis zurueck, keine Erklaerungen.";
    }
}
