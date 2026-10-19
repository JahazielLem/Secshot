// swift-tools-version:5.9
// SecShot — security evidence capture tool for macOS.
// Copyright (C) 2026 JahazielLem
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Made by AI

import PackageDescription

let package = Package(
    name: "SecShot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SecShot",
            path: "Sources/SecShot",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
