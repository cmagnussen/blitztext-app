#!/usr/bin/env swift
// Erzeugt einmalig ein Ed25519-Schluesselpaar fuer die macOS-Update-Signatur.
// Nutzung: swift Scripts/generate-update-key.swift
//
// Der private Teil gehoert als Repo-Secret BLITZTEXT_UPDATE_PRIVATE_KEY
// hinterlegt und sonst nirgendwohin. Der oeffentliche Teil gehoert als
// BLZUpdatePublicKey in BlitztextMac/Resources/Info.plist.
import CryptoKit
import Foundation

let schluessel = Curve25519.Signing.PrivateKey()
print("Privat  (Secret BLITZTEXT_UPDATE_PRIVATE_KEY):")
print(schluessel.rawRepresentation.base64EncodedString())
print("")
print("Oeffentlich (Info.plist BLZUpdatePublicKey):")
print(schluessel.publicKey.rawRepresentation.base64EncodedString())
