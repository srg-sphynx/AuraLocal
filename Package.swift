// swift-tools-version: 5.9
//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//
import PackageDescription

let package = Package(
    name: "AuraLocal",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // HTML → structured text (pure Swift, jsoup port).
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        // Zip container reader for DOCX / EPUB (both are zip archives).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        // Over-the-air auto-updates (appcast + EdDSA-signed archives).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .executableTarget(
            name: "AuraLocal",
            dependencies: [
                "CSQLite",
                "SwiftSoup",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/AuraLocal",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                // Sparkle.framework is copied into `Contents/Frameworks` by the
                // packaging script; teach the executable to look there at runtime.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
