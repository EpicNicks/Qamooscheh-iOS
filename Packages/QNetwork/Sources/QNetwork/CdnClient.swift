import CryptoKit
import Foundation
import QModel

/// The fetched manifest bytes did not hash to the expected SHA-256.
public struct ManifestHashMismatchError: Error, Equatable, LocalizedError, Sendable {
    public let expected: String
    public let actual: String

    public init(expected: String, actual: String) {
        self.expected = expected
        self.actual = actual
    }

    public var errorDescription: String? {
        "Manifest hash mismatch: expected \(expected), got \(actual)"
    }
}

/// A CDN fetch returned a non-2xx status.
public struct CdnFetchError: Error, Equatable, Sendable {
    public let url: String
    public let status: Int

    public init(url: String, status: Int) {
        self.url = url
        self.status = status
    }
}

public enum Sha256 {
    /// Lowercase hex SHA-256 of `data`.
    public static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads course artifacts straight from the CDN, never through ApiClient.
/// Only the root manifest is hash-verified; children are reached through the
/// trusted manifest's relative paths.
public struct CdnClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func courseRoot(courseCode: String, version: Int) -> String {
        baseURL.absoluteString + "/course/\(courseCode)/v\(version)"
    }

    /// Fetches and SHA-256 verifies manifest.json against the bootstrap hash.
    public func courseManifest(courseCode: String, version: Int, manifestSha256: String) async throws -> CourseManifest {
        let url = courseRoot(courseCode: courseCode, version: version) + "/manifest.json"
        let data = try await fetch(url)
        let actual = Sha256.hex(data)
        guard actual.lowercased() == manifestSha256.lowercased() else {
            throw ManifestHashMismatchError(expected: manifestSha256, actual: actual)
        }
        return try QJSON.makeDecoder().decode(CourseManifest.self, from: data)
    }

    /// Fetches an unverified child artifact at a path relative to the version root.
    public func artifact<T: Decodable>(
        courseCode: String, version: Int, path: String, as type: T.Type = T.self
    ) async throws -> T {
        let data = try await fetch(courseRoot(courseCode: courseCode, version: version) + "/" + path)
        return try QJSON.makeDecoder().decode(T.self, from: data)
    }

    /// Absolute URL for a recording path, which may climb out of the version root.
    public func contentURL(courseCode: String, version: Int, relativePath: String) -> URL? {
        guard let root = URL(string: courseRoot(courseCode: courseCode, version: version) + "/") else { return nil }
        return URL(string: relativePath, relativeTo: root)?.absoluteURL
    }

    private func fetch(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw InvalidResponseError() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw InvalidResponseError() }
        guard (200..<300).contains(http.statusCode) else {
            throw CdnFetchError(url: urlString, status: http.statusCode)
        }
        return data
    }
}
