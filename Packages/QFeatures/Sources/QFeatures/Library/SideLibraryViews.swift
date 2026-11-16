import SwiftUI
import QDomain
import QDesign

/// A story or listening library page: the lessons by unit, a unit's heading over its rows (web CategoryPage).
/// A lesson of a reached unit opens whatever its state on the road; one of a later unit is locked.
public struct SideLibraryView: View {
    @ObservedObject private var model: SideLibraryModel
    private let onOpen: (PathSkill) -> Void

    public init(model: SideLibraryModel, onOpen: @escaping (PathSkill) -> Void) {
        self.model = model
        self.onOpen = onOpen
    }

    public var body: some View {
        ScrollView {
            SideLibraryContent(model: model, onOpen: onOpen).padding(16)
        }
        .navigationTitle(model.kind.title)
        .task { await model.refresh() }
    }
}

struct SideLibraryContent: View {
    @ObservedObject var model: SideLibraryModel
    let onOpen: (PathSkill) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 8) {
            switch model.state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading\u{2026}").font(.callout)
                }
            case .unavailable(let message):
                Text(message).font(.callout).foregroundColor(Color(argb: p.danger))
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            case .ready(let units):
                if units.isEmpty {
                    Text(model.kind.emptyText).font(.callout).foregroundColor(Color(argb: p.textMuted))
                }
                ForEach(units, id: \.unitKey) { unit in
                    Text(unit.heading).font(.title3.weight(.bold)).foregroundColor(Color(argb: p.text))
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(unit.lessons, id: \.skillKey) { skill in
                        SideLibraryRow(skill: skill, icon: model.kind.icon, unitUnlocked: unit.unlocked, p: p, onOpen: { onOpen(skill) })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SideLibraryRow: View {
    let skill: PathSkill
    let icon: String
    let unitUnlocked: Bool
    let p: AppPalette
    let onOpen: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        let note = sideLibraryRowNote(skill, unitUnlocked: unitUnlocked)
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text(icon).accessibilityHidden(true)
                Text(skill.title).font(.body.weight(.semibold))
                    .foregroundColor(Color(argb: unitUnlocked ? p.text : p.textMuted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let note = note {
                    Text(note).font(.footnote).foregroundColor(Color(argb: skill.completed ? p.primary : p.textMuted))
                }
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(Color(argb: unitUnlocked ? p.surface : p.locked))
            .clipShape(shape)
            .overlay(shape.stroke(Color(argb: skill.completed ? p.primary : p.border), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!unitUnlocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.map { "\(skill.title), \($0)" } ?? skill.title)
        .accessibilityAddTraits(.isButton)
    }
}
