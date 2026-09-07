#!/usr/bin/env swift
// Signiert eine Datei mit dem Ed25519-Schluessel aus der Umgebung.
// Nutzung: swift Scripts/sign-update.swift <eingabe> <ausgabe.sig>
//
// Der private Schluessel kommt base64-kodiert aus der Umgebungsvariablen
// BLITZTEXT_UPDATE_PRIVATE_KEY. Geschrieben wird die Signatur als Base64-Text.
import CryptoKit
import Foundation

func abbrechen(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

let argumente = CommandLine.arguments
guard argumente.count == 3 else {
    abbrechen("Nutzung: swift Scripts/sign-update.swift <eingabe> <ausgabe.sig>")
}

guard let rohSchluessel = ProcessInfo.processInfo.environment["BLITZTEXT_UPDATE_PRIVATE_KEY"],
      let schluesselDaten = Data(base64Encoded: rohSchluessel.trimmingCharacters(in: .whitespacesAndNewlines))
else {
    abbrechen("BLITZTEXT_UPDATE_PRIVATE_KEY fehlt oder ist kein Base64.")
}

do {
    let schluessel = try Curve25519.Signing.PrivateKey(rawRepresentation: schluesselDaten)
    let inhalt = try Data(contentsOf: URL(fileURLWithPath: argumente[1]))
    let signatur = try schluessel.signature(for: inhalt)
    try Data(signatur.base64EncodedString().utf8)
        .write(to: URL(fileURLWithPath: argumente[2]))
    print("Signatur geschrieben: \(argumente[2])")
} catch {
    abbrechen("Signieren fehlgeschlagen: \(error.localizedDescription)")
}
