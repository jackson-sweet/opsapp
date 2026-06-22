//
//  ShareFontRegistrar.swift
//  OPSShareExtension
//
//  Belt-and-suspenders font registration. The bundled brand fonts are declared
//  in the extension's Info.plist (UIAppFonts), which is sufficient on current
//  iOS, but UIAppFonts has historically been flaky inside app extensions across
//  OS versions. Registering the same files programmatically at launch guarantees
//  the picker renders in the OPS type system. Already-registered fonts return a
//  harmless error which we ignore.
//

import Foundation
import CoreText

enum ShareFontRegistrar {
    private static var registered = false

    private static let fontNames = [
        "CakeMono-Light",
        "JetBrainsMono-Regular",
        "JetBrainsMono-Medium",
        "Mohave-Regular",
        "Mohave-Medium",
        "Mohave-Light"
    ]

    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        for name in fontNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
