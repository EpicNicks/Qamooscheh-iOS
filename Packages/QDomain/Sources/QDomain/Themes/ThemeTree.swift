import Foundation
import QModel

// Pure helpers over themes.json's flat theme list (ThemeEntry.parentId). Every
// ordering follows themes.json's own entry order among siblings. A parentId
// naming a missing theme makes that theme a root (never dropped); every walk
// is cycle-safe, though nodes only reachable through a cycle are omitted from
// buildThemeForest / dfsAllThemes.

/// A theme with its nested children.
public struct ThemeNode: Equatable, Sendable {
    public var theme: ThemeEntry
    public var children: [ThemeNode]

    public init(theme: ThemeEntry, children: [ThemeNode]) {
        self.theme = theme
        self.children = children
    }
}

/// A theme and its 1-based depth in the tree (a root is 1).
public struct ThemeAtDepth: Equatable, Sendable {
    public var theme: ThemeEntry
    public var depth: Int

    public init(theme: ThemeEntry, depth: Int) {
        self.theme = theme
        self.depth = depth
    }
}

/// id -> entry. Assumes ids are globally unique; a duplicate id resolves to the last entry.
public func indexThemesById(_ themes: [ThemeEntry]) -> [String: ThemeEntry] {
    var byId: [String: ThemeEntry] = [:]
    for theme in themes { byId[theme.id] = theme }
    return byId
}

/// nil for a root AND for an orphan whose parent is missing from byId.
private func effectiveParentId(_ theme: ThemeEntry, _ byId: [String: ThemeEntry]) -> String? {
    if let parent = theme.parentId, byId[parent] != nil { return parent }
    return nil
}

/// Direct children of parentId; nil lists the roots, orphans included.
public func childrenOf(_ themes: [ThemeEntry], parentId: String?) -> [ThemeEntry] {
    let byId = indexThemesById(themes)
    return themes.filter { effectiveParentId($0, byId) == parentId }
}

/// Splits themes into roots (incl. orphans) and a parent -> children map, both in themes order.
private func groupByEffectiveParent(_ themes: [ThemeEntry], _ byId: [String: ThemeEntry]) -> (roots: [ThemeEntry], byParent: [String: [ThemeEntry]]) {
    var roots: [ThemeEntry] = []
    var byParent: [String: [ThemeEntry]] = [:]
    for theme in themes {
        if let parent = effectiveParentId(theme, byId) {
            byParent[parent, default: []].append(theme)
        } else {
            roots.append(theme)
        }
    }
    return (roots, byParent)
}

/// The whole tree as nested nodes, roots first. Orphans become roots.
public func buildThemeForest(_ themes: [ThemeEntry]) -> [ThemeNode] {
    let byId = indexThemesById(themes)
    let grouped = groupByEffectiveParent(themes, byId)
    var visited = Set<String>()
    func build(_ theme: ThemeEntry) -> ThemeNode {
        visited.insert(theme.id)
        // Filter eagerly (before any child is built), as the web and Android ports do.
        let unvisited = (grouped.byParent[theme.id] ?? []).filter { !visited.contains($0.id) }
        return ThemeNode(theme: theme, children: unvisited.map { build($0) })
    }
    var forest: [ThemeNode] = []
    for root in grouped.roots { forest.append(build(root)) }
    return forest
}

/// The lesson's top-level tags only, although rollup puts it in every ancestor.
public func rootThemesForLesson(_ themeIndex: ThemeIndexArtifact?, lessonKey: String) -> [ThemeEntry] {
    guard let themeIndex = themeIndex else { return [] }
    let byId = indexThemesById(themeIndex.themes)
    return themesForLesson(themeIndex, lessonKey: lessonKey).filter { effectiveParentId($0, byId) == nil }
}

/// root...id inclusive, or [] when id isn't in the index. Stops at a missing parent or a cycle.
public func ancestorsOf(_ themeIndex: ThemeIndexArtifact?, id: String) -> [ThemeEntry] {
    guard let themeIndex = themeIndex else { return [] }
    let byId = indexThemesById(themeIndex.themes)
    var chain: [ThemeEntry] = []
    var seen = Set<String>()
    var current = byId[id]
    while let node = current, !seen.contains(node.id) {
        seen.insert(node.id)
        chain.append(node)
        if let parent = node.parentId { current = byId[parent] } else { current = nil }
    }
    return chain.reversed()
}

/// Every theme tagged with the lesson, in pre-order with its true 1-based depth.
/// A tagged theme whose parent isn't tagged starts its own subtree at its real depth.
public func dfsThemesForLesson(_ themeIndex: ThemeIndexArtifact?, lessonKey: String) -> [ThemeAtDepth] {
    let tagged = themesForLesson(themeIndex, lessonKey: lessonKey)
    guard let themeIndex = themeIndex, !tagged.isEmpty else { return [] }
    let taggedIds = Set(tagged.map { $0.id })
    var byParent: [String: [ThemeEntry]] = [:]
    var starts: [ThemeEntry] = []
    for theme in tagged {
        if let parent = theme.parentId, taggedIds.contains(parent), parent != theme.id {
            byParent[parent, default: []].append(theme)
        } else {
            starts.append(theme)
        }
    }
    var result: [ThemeAtDepth] = []
    var visited = Set<String>()
    func walk(_ theme: ThemeEntry, _ depth: Int) {
        if visited.contains(theme.id) { return }
        visited.insert(theme.id)
        result.append(ThemeAtDepth(theme: theme, depth: depth))
        for child in byParent[theme.id] ?? [] { walk(child, depth + 1) }
    }
    for start in starts {
        walk(start, max(ancestorsOf(themeIndex, id: start.id).count, 1))
    }
    return result
}

/// rootId plus every descendant, pre-order; [] for an unknown id. Cycle-safe.
public func subtreeIds(_ themes: [ThemeEntry], rootId: String) -> [String] {
    let byId = indexThemesById(themes)
    if byId[rootId] == nil { return [] }
    let byParent = groupByEffectiveParent(themes, byId).byParent
    var result: [String] = []
    var visited = Set<String>()
    func walk(_ id: String) {
        if visited.contains(id) { return }
        visited.insert(id)
        result.append(id)
        for child in byParent[id] ?? [] { walk(child.id) }
    }
    walk(rootId)
    return result
}

/// The whole tree in pre-order with 1-based depth (orphans count as roots).
public func dfsAllThemes(_ themes: [ThemeEntry]) -> [ThemeAtDepth] {
    var result: [ThemeAtDepth] = []
    func walk(_ node: ThemeNode, _ depth: Int) {
        result.append(ThemeAtDepth(theme: node.theme, depth: depth))
        for child in node.children { walk(child, depth + 1) }
    }
    for root in buildThemeForest(themes) { walk(root, 1) }
    return result
}
