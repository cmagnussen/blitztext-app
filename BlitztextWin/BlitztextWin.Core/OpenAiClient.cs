using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BlitztextWin.Core;

public sealed class OpenAiClient(HttpClient httpClient)
{
    private const string WhisperModel = "whisper-1";
    private const string FastEditModel = "gpt-4o-mini";
    private const string RageModel = "gpt-4o";

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public async Task<string> TranscribeAsync(
        string apiKey,
        string audioFilePath,
        IReadOnlyCollection<string> customTerms,
        string language,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/audio/transcriptions");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);

        using var content = new MultipartFormDataContent();
        await using var fileStream = File.OpenRead(audioFilePath);
        using var audioContent = new StreamContent(fileStream);
        audioContent.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
        content.Add(audioContent, "file", "audio.wav");
        content.Add(new StringContent(WhisperModel), "model");
        content.Add(new StringContent("text"), "response_format");

        if (customTerms.Count > 0)
        {
            content.Add(new StringContent("Eigennamen und Begriffe: " + string.Join(", ", customTerms)), "prompt");
        }

        if (!string.IsNullOrWhiteSpace(language))
        {
            content.Add(new StringContent(language.Trim()), "language");
        }

        request.Content = content;

        using var response = await httpClient.SendAsync(request, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException("OpenAI-Fehler: " + ReadOpenAiError(responseBody, response.StatusCode));
        }

        var text = responseBody.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            throw new InvalidOperationException("Transkription fehlgeschlagen.");
        }

        return text;
    }

    public Task<string> ImproveAsync(
        string apiKey,
        string text,
        TextImprovementSettings settings,
        CancellationToken cancellationToken)
    {
        return CompleteAsync(apiKey, text, PromptBuilder.BuildTextImprovementPrompt(settings), FastEditModel, 0.3, cancellationToken);
    }

    public Task<string> DampfAblassenAsync(
        string apiKey,
        string text,
        DampfAblassenSettings settings,
        CancellationToken cancellationToken)
    {
        return CompleteAsync(apiKey, text, settings.SystemPrompt, RageModel, 0.4, cancellationToken);
    }

    public Task<string> AddEmojisAsync(
        string apiKey,
        string text,
        EmojiDensity density,
        CancellationToken cancellationToken)
    {
        return CompleteAsync(apiKey, text, PromptBuilder.BuildEmojiPrompt(density), FastEditModel, 0.3, cancellationToken);
    }

    private async Task<string> CompleteAsync(
        string apiKey,
        string text,
        string systemPrompt,
        string model,
        double temperature,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/chat/completions");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = JsonContent.Create(
            new ChatRequest(
                model,
                [
                    new ChatMessage("system", systemPrompt),
                    new ChatMessage("user", text),
                ],
                temperature),
            options: JsonOptions);

        using var response = await httpClient.SendAsync(request, cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException("OpenAI-Fehler: " + ReadOpenAiError(responseBody, response.StatusCode));
        }

        var decoded = JsonSerializer.Deserialize<ChatResponse>(responseBody, JsonOptions);
        var result = decoded?.Choices?.FirstOrDefault()?.Message?.Content?.Trim();
        if (string.IsNullOrWhiteSpace(result))
        {
            throw new InvalidOperationException("Keine Antwort erhalten. Bitte nochmal versuchen.");
        }

        return result;
    }

    private static string ReadOpenAiError(string responseBody, System.Net.HttpStatusCode statusCode)
    {
        try
        {
            var error = JsonSerializer.Deserialize<OpenAiErrorResponse>(responseBody, JsonOptions);
            if (!string.IsNullOrWhiteSpace(error?.Error?.Message))
            {
                return error.Error.Message;
            }
        }
        catch (JsonException)
        {
            // Fall through to status code.
        }

        return "Status " + (int)statusCode;
    }

    private sealed record ChatRequest(string Model, IReadOnlyList<ChatMessage> Messages, double Temperature);

    private sealed record ChatMessage(string Role, string Content);

    private sealed record ChatResponse(IReadOnlyList<ChatChoice>? Choices);

    private sealed record ChatChoice(ChatResponseMessage? Message);

    private sealed record ChatResponseMessage(string? Content);

    private sealed record OpenAiErrorResponse(OpenAiError? Error);

    private sealed record OpenAiError(string? Message);
}
