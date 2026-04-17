//
//  ClientAvatarCache.swift
//  OPS
//
//  Disk cache for client and user avatar images. Mirrors ImageFileManager's
//  SHA256-hashed filename pattern but lives in a separate directory so lifecycle
//  (e.g. Spotlight backfill) can target avatars independently.
//

import UIKit
import Foundation
import CryptoKit

final class ClientAvatarCache {
    static let shared = ClientAvatarCache()

    private init() {
        createDirectoryIfNeeded()
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var avatarsDirectory: URL {
        documentsDirectory.appendingPathComponent("ClientAvatars", isDirectory: true)
    }

    private func createDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: avatarsDirectory.path) {
            try? fm.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
        }
    }

    private func hashedFilename(for url: String) -> String {
        let normalized = url.hasPrefix("//") ? "https:" + url : url
        let data = normalized.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return "avatar_\(hex.prefix(32))"
    }

    func fileURL(for remoteURL: String) -> URL {
        avatarsDirectory.appendingPathComponent(hashedFilename(for: remoteURL))
    }

    func exists(remoteURL: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: remoteURL).path)
    }

    func save(_ data: Data, for remoteURL: String) {
        let url = fileURL(for: remoteURL)
        try? data.write(to: url, options: .atomic)
    }

    func loadImage(for remoteURL: String) -> UIImage? {
        let url = fileURL(for: remoteURL)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func loadData(for remoteURL: String) -> Data? {
        let url = fileURL(for: remoteURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Download + cache. Returns cached data if already present.
    func ensureCached(remoteURL: String) async -> Data? {
        if let existing = loadData(for: remoteURL) { return existing }
        let normalized = remoteURL.hasPrefix("//") ? "https:" + remoteURL : remoteURL
        guard let url = URL(string: normalized) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            save(data, for: remoteURL)
            return data
        } catch {
            return nil
        }
    }

    /// Delete all cached avatars — used on logout.
    func clearAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: avatarsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }
}
