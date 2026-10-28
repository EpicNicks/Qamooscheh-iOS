import Foundation

/// Where a recording's take lives in the content store. A take's path is relative to its course version's root
/// ("../../../audio/<sha256>.mp3"), the same way the downloader resolves it, so the key is that path joined onto
/// "course/<code>/v<version>/" with the dot segments folded away.
public enum RecordingKeys {
    /// nil when the path climbs out of the store or is empty.
    public static func storeKey(courseCode: String, version: Int, path: String) -> String? {
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") { return nil }
        var parts: [String] = ["course", courseCode, "v\(version)"]
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if parts.isEmpty { return nil }
                parts.removeLast()
                continue
            }
            parts.append(String(part))
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: "/")
    }
}
