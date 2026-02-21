// swift-tools-version: 5.9
// Package.swift
//
// Swift Package Manager manifest for the AgentApp.
// This enables compilation verification on CI and local development.
// The actual iPad app target is managed by the Xcode project.

import PackageDescription

let package = Package(
    name: "AgentApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AgentApp",
            targets: ["AgentApp"]
        )
    ],
    targets: [
        .target(
            name: "AgentApp",
            path: "AgentApp"
        ),
        .testTarget(
            name: "AgentAppTests",
            dependencies: ["AgentApp"],
            path: "Tests"
        )
    ]
)
