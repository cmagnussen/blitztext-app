import XCTest

final class GemmaChatFormatTests: XCTestCase {
    func testPromptWithSystemTurnAndClosedThinking() {
        XCTAssertEqual(
            GemmaChatFormat.prompt(system: "Fasse zusammen.", user: "Wir verschieben den Launch.", closesThinking: true),
            "<bos><|turn>system\nFasse zusammen.<turn|>\n<|turn>user\nWir verschieben den Launch.<turn|>\n<|turn>model\n<|channel>thought\n<channel|>"
        )
    }

    func testPromptForOlderTemplateEndsAtModelTurn() {
        XCTAssertEqual(
            GemmaChatFormat.prompt(system: "Fasse zusammen.", user: "Text", closesThinking: false),
            "<bos><|turn>system\nFasse zusammen.<turn|>\n<|turn>user\nText<turn|>\n<|turn>model\n"
        )
    }

    func testPromptWithoutSystemTurn() {
        XCTAssertEqual(
            GemmaChatFormat.prompt(system: "  ", user: "Hallo", closesThinking: false),
            "<bos><|turn>user\nHallo<turn|>\n<|turn>model\n"
        )
    }

    func testPromptTrimsLikeTheTemplate() {
        let prompt = GemmaChatFormat.prompt(system: "\n Anweisung \n", user: "\n\nText\n", closesThinking: false)
        XCTAssertTrue(prompt.contains("system\nAnweisung<turn|>"))
        XCTAssertTrue(prompt.contains("user\nText<turn|>"))
    }

    func testDetectsTemplateThatClosesThinking() {
        let newer = "{%- if not enable_thinking | default(false) -%}\n    {{- '<|channel>thought\\n<channel|>' -}}\n{%- endif -%}"
        let older = "{{- '<|channel>thought\\n' + thinking_text + '\\n<channel|>' -}}"
        XCTAssertTrue(GemmaChatFormat.closesThinking(template: newer))
        XCTAssertFalse(GemmaChatFormat.closesThinking(template: older))
    }

    func testRecognizesGemma4ModelTypes() {
        XCTAssertTrue(GemmaChatFormat.isGemma4(modelType: "gemma4"))
        XCTAssertTrue(GemmaChatFormat.isGemma4(modelType: "gemma4_unified"))
        XCTAssertFalse(GemmaChatFormat.isGemma4(modelType: "gemma3"))
    }

    func testCleanedKeepsPlainAnswer() {
        XCTAssertEqual(GemmaChatFormat.cleaned("Der Launch verschiebt sich.\n"), "Der Launch verschiebt sich.")
    }

    func testCleanedRemovesThinking() {
        let output = "<|channel>thought\nDer Nutzer will zwei Sätze.<channel|>Der Launch verschiebt sich um eine Woche."
        XCTAssertEqual(GemmaChatFormat.cleaned(output), "Der Launch verschiebt sich um eine Woche.")
    }

    func testCleanedDropsThinkingCutOffByTheTokenLimit() {
        XCTAssertEqual(GemmaChatFormat.cleaned("<|channel>thought\nIch überlege noch"), "")
    }

    func testCleanedStopsAtEndOfTurn() {
        let output = "Kurzfassung.<turn|>\n<|turn>user\nNoch etwas"
        XCTAssertEqual(GemmaChatFormat.cleaned(output), "Kurzfassung.")
    }

    func testCleanedRemovesStrayControlTokens() {
        XCTAssertEqual(GemmaChatFormat.cleaned("<channel|>Antwort<eos>"), "Antwort")
    }
}
