import XCTest

final class SwissSpellingTests: XCTestCase {
    private let apostrophe = "\u{2019}"

    private func assertUnchanged(_ sentences: [String], file: StaticString = #filePath, line: UInt = #line) {
        for sentence in sentences {
            XCTAssertEqual(SwissSpelling.apply(sentence), sentence, file: file, line: line)
        }
    }

    // MARK: - Rules

    func testSharpS() {
        XCTAssertEqual(SwissSpelling.apply("Die Straße ist groß."), "Die Strasse ist gross.")
        XCTAssertEqual(SwissSpelling.apply("STRAẞE"), "STRASSE")
    }

    func testNumbersFromFiveDigitsGetAnApostrophe() {
        XCTAssertEqual(SwissSpelling.apply("von 12.500 Leuten"), "von 12\(apostrophe)500 Leuten")
        XCTAssertEqual(SwissSpelling.apply("Das kostet 1.250.000 Franken."), "Das kostet 1\(apostrophe)250\(apostrophe)000 Franken.")
        XCTAssertEqual(SwissSpelling.apply("12\u{202F}500 Stück"), "12\(apostrophe)500 Stück")
        XCTAssertEqual(SwissSpelling.apply("Budget von 12'500 Franken"), "Budget von 12\(apostrophe)500 Franken")
    }

    func testFourDigitNumbersStayTogether() {
        XCTAssertEqual(SwissSpelling.apply("1000 und 1.000 Leute"), "1000 und 1000 Leute")
        XCTAssertEqual(SwissSpelling.apply("CHF 1200"), "CHF 1200")
    }

    func testAmountsWithoutSeparators() {
        XCTAssertEqual(SwissSpelling.apply("CHF 12500"), "CHF 12\(apostrophe)500")
        XCTAssertEqual(SwissSpelling.apply("12500 Franken"), "12\(apostrophe)500 Franken")
        XCTAssertEqual(SwissSpelling.apply("Euro 50000 nach Europa 50000"), "Euro 50\(apostrophe)000 nach Europa 50000")
        // Models group with plain spaces; next to a currency that is an amount.
        XCTAssertEqual(SwissSpelling.apply("für 1 250 000 Euro"), "für 1\(apostrophe)250\(apostrophe)000 Euro")
        XCTAssertEqual(SwissSpelling.apply("CHF 12 500"), "CHF 12\(apostrophe)500")
        XCTAssertEqual(SwissSpelling.apply("1 250,50 Franken"), "1250.50 Franken")
        assertUnchanged(["Wir waren 12 500 Meter weit", "PLZ 8001 und 3 Franken"])
    }

    func testAmountsGetADecimalPointInAnyCurrency() {
        let amounts = [
            ("CHF 23,50", "CHF 23.50"),
            ("Fr. 23,50", "Fr. 23.50"),
            ("€ 23,40", "€ 23.40"),
            ("$ 23,50", "$ 23.50"),
            ("23,50 Franken", "23.50 Franken"),
            ("23,40 Euro", "23.40 Euro"),
            ("23,50 USD", "23.50 USD"),
            ("Fr. 20,–", "Fr. 20.–"),
            ("CHF 12500,50", "CHF 12\(apostrophe)500.50"),
            ("12.500,50 Franken", "12\(apostrophe)500.50 Franken"),
            ("1.250,50 Franken", "1250.50 Franken"),
        ]
        for (input, expected) in amounts {
            XCTAssertEqual(SwissSpelling.apply(input), expected)
        }
    }

    /// Federal Chancellery, Schreibweisungen Rz. 514, 541, 544: these keep the comma.
    func testDecimalCommaStaysOutsideAmounts() {
        assertUnchanged([
            "3,5 Prozent und 88,5 m",
            "4,16 Millionen Franken",
            "4,16 Mio. CHF",
            "CHF 4,16 Mio.",
            "0,13 Rappen",
            "22,5 Rp.",
            "12,5 Cent",
            "20,– Franken",
        ])
    }

    func testQuotationMarks() {
        XCTAssertEqual(SwissSpelling.apply("Er sagte „Hallo“ und ‚ja‘."), "Er sagte «Hallo» und ‹ja›.")
        XCTAssertEqual(SwissSpelling.apply("Er sagte \"Hallo zusammen\" laut."), "Er sagte «Hallo zusammen» laut.")
        XCTAssertEqual(SwissSpelling.apply("Das Modell schrieb “Test” hier."), "Das Modell schrieb «Test» hier.")
        assertUnchanged(["Ein 27\" Monitor"])
    }

    // MARK: - Exceptions

    func testYearsTimesAndDatesStay() {
        assertUnchanged(["Im Jahr 2026 um 12.30 Uhr am 01.11.2026 und am 1.11.2026"])
    }

    func testPostcodesStay() {
        assertUnchanged(["8001 Zürich und 80331 München", "PLZ 9490 Vaduz"])
    }

    func testPhoneNumbersStay() {
        assertUnchanged(["Tel. +41 44 668 18 00, 044 668 18 00, 044.668.18.00 oder 0441234567"])
    }

    func testVersionNumbersStay() {
        assertUnchanged(["Version 2.100.3 ist da", "0.250 Liter"])
    }

    func testAccountNumbersStay() {
        assertUnchanged([
            "IBAN CH93 0076 2011 6238 5295 7",
            "IBAN DE89 3704 0044 0532 0130 00",
            "AHV 756.1234.5678.97",
            "Konto 235.123.456",
            "Kontonummer: 235.123.456",
            "Konto-Nr. 235.123.456",
            "Kundennummer 100.200.300",
            "Postkonto 80-2-2",
        ])
    }

    func testEnglishKeepsNumbersAndQuotes() {
        assertUnchanged(["We sold 1.250 units and he said \"great\" to the whole team today."])
    }

    // MARK: - Germany and Austria stay exactly as they are

    func testGermanAndAustrianTextStaysExactly() {
        let text = "Die Straße kostet 1.250.000 Euro, CHF 23,50 und „heute“ sagt er ‚ja‘."
        let processor = TranscriptPostProcessor(correctCustomTerms: false, removeFillerWords: false)
        XCTAssertEqual(processor.process(text), text)

        for variant in [GermanVariant.automatic, .standard] {
            XCTAssertFalse(variant.isSwiss(systemIsSwiss: false))
        }
        XCTAssertFalse(GermanVariant.isSwiss(locale: Locale(identifier: "de_DE"), preferredLanguages: ["de-DE"]))
        XCTAssertFalse(GermanVariant.isSwiss(locale: Locale(identifier: "de_AT"), preferredLanguages: ["de-AT"]))
        XCTAssertEqual(SwissSpelling.addingRules(to: "Anweisung", isSwiss: false), "Anweisung")
    }

    func testPostProcessorEndsWithTheSwissStep() {
        var processor = TranscriptPostProcessor(correctCustomTerms: false, removeFillerWords: false)
        processor.swissSpelling = true
        XCTAssertEqual(processor.process("Die Straße ist groß."), "Die Strasse ist gross.")
    }

    func testWritingModesGetTheSwissRules() {
        XCTAssertTrue(SwissSpelling.addingRules(to: "Anweisung", isSwiss: true).hasSuffix(SwissSpelling.modelInstruction))
        let rules = SwissSpelling.modelInstruction
        XCTAssertTrue(rules.contains("Liechtenstein"))
        // A model once answered in Italian first: the spelling must not read as a language.
        XCTAssertTrue(rules.contains("Die Sprache bleibt"))
        // Amounts as pairs that keep their currency; examples all in Franken made "Euro" Franken.
        XCTAssertTrue(rules.contains("CHF 23,50 → CHF 23.50"))
        XCTAssertTrue(rules.contains("23,40 Euro → 23.40 Euro"))
        XCTAssertTrue(rules.contains("Euro bleibt Euro"))
        // Only quantities and amounts are grouped; `apply` cannot undo "80’331 München".
        XCTAssertTrue(rules.contains("Postleitzahlen"))
        XCTAssertTrue(rules.contains("(80331 München)"))
        // Swiss words stay; they are not asked for ("Fahrrad" stays "Fahrrad").
        XCTAssertTrue(rules.contains("Lass sie stehen"))
        XCTAssertFalse(rules.contains("wird Velo"))
    }

    func testMeetingSummaryGetsTheSwissStep() {
        let summary = """
        Zusammenfassung
        Die Strasse vor dem Schulhaus wird für 12.500 Franken saniert, der Parkplatz kostet CHF 4,50.

        To-dos
        - Anna: Offerte für das „Velo-Projekt“ einholen (bis Freitag)
        """
        XCTAssertEqual(SwissSpelling.apply(summary.replacingOccurrences(of: "Strasse", with: "Straße")), """
        Zusammenfassung
        Die Strasse vor dem Schulhaus wird für 12\(apostrophe)500 Franken saniert, der Parkplatz kostet CHF 4.50.

        To-dos
        - Anna: Offerte für das «Velo-Projekt» einholen (bis Freitag)
        """)
        assertUnchanged(["Summary\nThe school road is renovated for 12.500 francs and we said \"fine\" to it.\n\nTo-dos\n- Anna: get the offer (by Friday)"])
    }

    // MARK: - Automatisch: region and language of macOS

    /// The AppleLocale values macOS stores, with the first preferred language.
    func testSetupsAutomatischCovers() {
        let setups: [(locale: String, languages: [String], swiss: Bool)] = [
            ("de_CH", ["de-CH"], true),            // Region Schweiz, Deutsch (Schweiz)
            ("de_CH", ["de"], true),               // Region Schweiz, Deutsch
            ("en_CH", ["en-CH"], true),            // Region Schweiz, English
            ("fr_CH", ["fr-CH"], true),            // Region Schweiz, Français
            ("de_DE@rg=chzzzz", ["de"], true),     // Region Schweiz, set apart from the language
            ("en_US@rg=chzzzz", ["en-US"], true),
            ("de_DE", ["de-CH", "en"], true),      // Region Deutschland, Deutsch (Schweiz) first
            ("de_LI", ["de"], true),               // Liechtenstein
            ("de_DE", ["de-LI"], true),
            ("de_DE", ["gsw"], true),
            ("de_DE", ["de-DE"], false),           // Deutschland
            ("de_AT", ["de-AT"], false),           // Österreich
            ("de_DE", ["de", "de-CH"], false),     // only the first language counts
            ("de_CH@rg=dezzzz", ["de"], false),    // region set to Deutschland
            ("de_DE", ["fr-CH"], false),           // French (Switzerland) on a German Mac
        ]
        for setup in setups {
            XCTAssertEqual(
                GermanVariant.isSwiss(locale: Locale(identifier: setup.locale), preferredLanguages: setup.languages),
                setup.swiss,
                "\(setup.locale) \(setup.languages)"
            )
        }
    }

    func testAutomaticFollowsTheSystem() {
        XCTAssertTrue(GermanVariant.automatic.isSwiss(systemIsSwiss: true))
        XCTAssertFalse(GermanVariant.automatic.isSwiss(systemIsSwiss: false))
        XCTAssertTrue(GermanVariant.swiss.isSwiss(systemIsSwiss: false))
        XCTAssertFalse(GermanVariant.standard.isSwiss(systemIsSwiss: true))
    }

    func testLabels() {
        XCTAssertEqual(GermanVariant.automatic.label(systemIsSwiss: true), "Automatisch (Schweiz)")
        XCTAssertEqual(GermanVariant.automatic.label(systemIsSwiss: false), "Automatisch (Deutsch)")
        XCTAssertEqual(GermanVariant.standard.label(systemIsSwiss: true), "Deutsch")
        XCTAssertEqual(GermanVariant.swiss.label(systemIsSwiss: false), "Deutsch (Schweiz)")
    }

    func testDefaultIsAutomatic() throws {
        XCTAssertEqual(GermanVariant.current, .automatic)
        let decoded = try JSONDecoder().decode([GermanVariant].self, from: Data(#"["automatic","standard","swiss"]"#.utf8))
        XCTAssertEqual(decoded, [.automatic, .standard, .swiss])
    }
}
