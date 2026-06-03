namespace BlitztextWin.Core;

public static class TranscriptionQualityService
{
    private static readonly string[] KnownArtifacts =
    [
        "Untertitel der Amara.org-Community",
        "Untertitel im Auftrag des ZDF",
        "Vielen Dank fuer's Zuschauen",
        "Danke fuers Zuschauen",
        "Copyright WDR",
        "Music",
        "[Musik]",
    ];

    public static bool ShouldRejectRecording(TimeSpan duration) => duration < TimeSpan.FromMilliseconds(650);

    public static string CleanedTranscript(string text)
    {
        return string.Join(
            "\n",
            text.Replace("\r\n", "\n", StringComparison.Ordinal)
                .Split('\n')
                .Select(line => line.Trim())
                .Where(line => !string.IsNullOrWhiteSpace(line)))
            .Trim();
    }

    public static bool IsLikelyArtifact(string text, TimeSpan recordingDuration)
    {
        var cleaned = CleanedTranscript(text);
        if (string.IsNullOrWhiteSpace(cleaned))
        {
            return true;
        }

        if (recordingDuration < TimeSpan.FromMilliseconds(900) && cleaned.Length < 10)
        {
            return true;
        }

        return KnownArtifacts.Any(artifact => cleaned.Contains(artifact, StringComparison.OrdinalIgnoreCase));
    }
}
