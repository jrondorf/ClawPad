// Extensions.swift
// AgentApp
//
// Shared utility extensions used across the application.

import Foundation

// MARK: - String Extensions

extension String {
    /// Trims leading and trailing whitespace and newlines.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns true if the string contains only whitespace.
    var isBlank: Bool {
        trimmed.isEmpty
    }

    /// Truncates the string to a maximum length, appending an ellipsis if truncated.
    func truncated(to maxLength: Int, trailing: String = "…") -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength)) + trailing
    }

    /// Sanitizes the string for safe inclusion in tool arguments.
    /// Removes control characters and null bytes.
    var sanitized: String {
        unicodeScalars.filter { scalar in
            // Allow printable characters, newlines, and tabs
            scalar == "\n" || scalar == "\r" || scalar == "\t" ||
            (scalar.value >= 0x20 && scalar.value != 0x7F)
        }.map { String($0) }.joined()
    }
}

// MARK: - Date Extensions

extension Date {
    /// Returns a relative time string (e.g., "2 hours ago").
    var relativeString: String {
        #if canImport(UIKit) || canImport(AppKit)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
        #else
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
        #endif
    }

    /// Returns a short date/time string.
    var shortString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - UUID Extensions

extension UUID {
    /// Returns a shortened string representation (first 8 characters).
    var shortID: String {
        String(uuidString.prefix(8))
    }
}

// MARK: - Array Extensions

extension Array {
    /// Safely accesses an element at the given index.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - AsyncThrowingStream Helpers

extension AsyncThrowingStream where Failure == Error {
    /// Creates a stream from an async closure that yields values via a continuation.
    static func fromClosure(
        _ body: @escaping @Sendable (AsyncThrowingStream<Element, Error>.Continuation) async -> Void
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await body(continuation)
                continuation.finish()
            }
        }
    }
}
