// swift-tools-version:5.9
//
//  Package.swift
//
//  A SwiftPM manifest so Reef can be built with only the Xcode Command Line Tools.
//  The .xcodeproj is left in place and still works if full Xcode is installed; this is
//  an alternative front door, not a replacement.
//
//  Build with ./build.sh, which compiles this and then assembles the .app bundle
//  (SwiftPM produces a bare executable; it has no notion of an application bundle).
//

import PackageDescription

let package = Package(
    name: "Reef",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        // Vendored so the #Preview blocks in Recorder.swift can be removed — that macro
        // is implemented by a plugin that ships only inside Xcode.app. See
        // Vendor/KeyboardShortcuts/VENDORED.md.
        .target(
            name: "KeyboardShortcuts",
            path: "Vendor/KeyboardShortcuts",
            exclude: ["LICENSE", "VENDORED.md"],
            resources: [.process("Localization")]
        ),

        .executableTarget(
            name: "Reef",
            dependencies: ["KeyboardShortcuts"],
            path: "Reef",
            exclude: [
                // Bundle metadata, applied by build.sh rather than compiled.
                "Info.plist",
                "Reef.entitlements",
                // Asset catalogs need `actool`, which is Xcode-only. build.sh copies the
                // one image Reef actually uses straight into Resources instead.
                "Assets.xcassets",
                "reef_placeholder.icon",
                "Preview Content",
            ]
        ),
    ]
)
