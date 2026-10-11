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

/// A content path from the CDN was absolute, escaping, or left the CDN origin.
public struct InvalidContentPathError: Error, Equatable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
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

    /// Path-segment character set: urlPathAllowed minus "/".
    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    private static func encodeSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }

    private static func encodePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { encodeSegment(String($0)) }
            .joined(separator: "/")
    }

    private var base: String {
        var text = baseURL.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    public func courseRoot(courseCode: String, version: Int) -> String {
        base + "/course/" + CdnClient.encodeSegment(courseCode) + "/v\(version)"
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
        let data = try await fetch(courseRoot(courseCode: courseCode, version: version) + "/" + CdnClient.encodePath(path))
        return try QJSON.makeDecoder().decode(T.self, from: data)
    }

    /// Absolute URL for a content path from unverified child JSON. Only plain
    /// relative paths are accepted; the result must stay on the CDN origin.
    public func contentURL(courseCode: String, version: Int, relativePath: String) throws -> URL {
        let invalid = InvalidContentPathError(path: relativePath)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\") else { throw invalid }
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if segments.contains("..") { throw invalid }
        // A colon in the first segment would parse as a URL scheme.
        if let first = segments.first, first.contains(":") { throw invalid }
        let text = courseRoot(courseCode: courseCode, version: version) + "/" + CdnClient.encodePath(relativePath)
        guard let url = URL(string: text),
              url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host?.lowercased() == baseURL.host?.lowercased(),
              url.port == baseURL.port
        else { throw invalid }
        return url
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
