import CryptoKit
import Foundation

/// A bundled browser-variant grader build: Resources/grader/{language}/v{N}/ (see scripts/fetch-grader.mjs).
public struct GraderBundle: Sendable {
    public let language: String
    public let version: Int
    public let root: URL

    private struct Manifest: Decodable {
        struct File: Decodable {
            let path: String
            let sha256: String
            let size: Int
        }
        let files: [File]
    }

    public init(language: String, version: Int, root: URL) {
        self.language = language
        self.version = version
        self.root = root
    }

    /// The highest bundled version for `language`.
    public static func bundled(language: String = "fa") throws -> GraderBundle {
        guard let base = Bundle.module.url(forResource: "grader", withExtension: nil) else {
            throw GraderError.bundleMissing("grader resources not in bundle")
        }
        let langDir = base.appendingPathComponent(language)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: langDir.path)) ?? []
        var best = -1
        for name in names where name.hasPrefix("v") {
            if let n = Int(name.dropFirst()), n > best { best = n }
        }
        guard best >= 0 else { throw GraderError.bundleMissing("no bundled grader for \(language)") }
        return GraderBundle(language: language, version: best, root: langDir.appendingPathComponent("v\(best)"))
    }

    /// The Android grader-host.js shim (Resources/grader-host.js).
    public static func hostScript() throws -> String {
        guard let url = Bundle.module.url(forResource: "grader-host", withExtension: "js") else {
            throw GraderError.bundleMissing("grader-host.js not in bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func fileURL(_ path: String) throws -> URL {
        if path.contains("..") || path.hasPrefix("/") { throw GraderError.bundleMissing("unsafe path \(path)") }
        return root.appendingPathComponent(path)
    }

    public func readData(_ path: String) throws -> Data {
        let url = try fileURL(path)
        guard let data = try? Data(contentsOf: url) else { throw GraderError.bundleMissing(path) }
        return data
    }

    public func readText(_ path: String) throws -> String {
        guard let s = String(data: try readData(path), encoding: .utf8) else {
            throw GraderError.bundleMissing("\(path) is not UTF-8")
        }
        return s
    }

    /// Checks every file against the manifest's sha256 and size. Returns the sha256 of manifest.json itself.
    @discardableResult
    public func verify() throws -> String {
        let manifestData = try readData("manifest.json")
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else {
            throw GraderError.integrity("manifest.json unreadable")
        }
        for file in manifest.files {
            let data = try readData(file.path)
            if data.count != file.size || Self.hex(SHA256.hash(data: data)) != file.sha256.lowercased() {
                throw GraderError.integrity(file.path)
            }
        }
        return Self.hex(SHA256.hash(data: manifestData))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
