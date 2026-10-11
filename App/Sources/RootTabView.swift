import SwiftUI
import QDesign

enum AppTab: String, CaseIterable, Identifiable {
    case learn
    case library
    case review
    case leagues
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .learn: return "Learn"
        case .library: return "Library"
        case .review: return "Review"
        case .leagues: return "Leagues"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .learn: return "map"
        case .library: return "books.vertical"
        case .review: return "arrow.triangle.2.circlepath"
        case .leagues: return "trophy"
        case .profile: return "person"
        }
    }
}

/// An intentionally empty tab body; real screens arrive in later milestones.
struct EmptyTabView: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            Color(argb: AppPalette.light.bg)
                .padding(Spacing.standard.s3)
                .navigationTitle(tab.title)
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            ForEach(AppTab.allCases) { tab in
                EmptyTabView(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
            }
        }
    }
}
