import SwiftUI
import QModel
import QDesign

/// The Friends screen (web FriendsPage, Android FriendsScreen): search and add, answer incoming
/// requests, and the friends list. Reached from Profile, which supplies the back button.
public struct FriendsView: View {
    @ObservedObject private var model: FriendsModel

    public init(model: FriendsModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            FriendsContent(model: model).padding(16)
        }
        .navigationTitle("Friends")
        .task { await model.load() }
    }
}

/// The screen body without the scroll view, so snapshots can lay it out at full height.
struct FriendsContent: View {
    @ObservedObject var model: FriendsModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search by display name\u{2026}", text: Binding(get: { model.query }, set: { model.onQueryChange($0) }))
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .fieldTraits(.words)
                .frame(minHeight: 44)
            if let error = model.searchError { errorText(error, p) }
            ForEach(model.results, id: \.userId) { hit in
                hitRow(hit, p)
            }
            if let error = model.actionError { errorText(error, p) }

            section("Pending requests", model.requests, loading: "Loading requests\u{2026}",
                    empty: "No pending requests.", p) { request in
                let busy = model.busy.contains(request.userId)
                let name = request.displayName ?? friendsUnnamed
                PersonRow(name: name, p: p) {
                    Button("Accept") { Task { await model.accept(request.userId) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                        .accessibilityLabel("Accept \(name)")
                    Button("Decline") { Task { await model.decline(request.userId) } }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                        .accessibilityLabel("Decline \(name)")
                }
            }

            section("Your friends", model.friends, loading: "Loading friends\u{2026}",
                    empty: "No friends yet \u{2014} search above.", p) { friend in
                PersonRow(name: friend.displayName ?? friendsUnnamed, p: p) { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hitRow(_ hit: UserSearchResultResponse, _ p: AppPalette) -> some View {
        PersonRow(name: hit.displayName, p: p) {
            switch hitAction(userId: hit.userId, sent: model.sent, friendIds: model.friendIds) {
            case .friends:
                muted("Friends", p)
            case .requestSent:
                muted("Request sent", p)
            case .nothing:
                EmptyView()
            case .add:
                Button("Add") { Task { await model.add(hit.userId) } }
                    .buttonStyle(.bordered)
                    .disabled(model.busy.contains(hit.userId))
                    .accessibilityLabel("Add \(hit.displayName)")
            }
        }
    }

    @ViewBuilder
    private func section<Row: View>(
        _ title: String, _ list: FriendsList, loading: String, empty: String, _ p: AppPalette,
        @ViewBuilder row: @escaping (FriendRefResponse) -> Row
    ) -> some View {
        Text(title).font(.title3.weight(.semibold)).foregroundColor(Color(argb: p.text))
            .padding(.top, 16)
            .accessibilityAddTraits(.isHeader)
        if list.loading {
            HStack(spacing: 8) {
                ProgressView()
                Text(loading).font(.callout)
            }
        }
        if let error = list.error { errorText(error, p) }
        if let items = list.items {
            if items.isEmpty { muted(empty, p) }
            ForEach(items, id: \.userId) { item in row(item) }
        }
    }

    private func errorText(_ text: String, _ p: AppPalette) -> some View {
        Text(text).font(.callout).foregroundColor(Color(argb: p.danger))
    }

    private func muted(_ text: String, _ p: AppPalette) -> some View {
        Text(text).font(.callout).foregroundColor(Color(argb: p.textMuted))
    }
}

/// Web `.row`: the name, then actions beside it, or below it at accessibility text sizes.
private struct PersonRow<Actions: View>: View {
    let name: String
    let p: AppPalette
    let actions: Actions

    @Environment(\.dynamicTypeSize) private var typeSize

    init(name: String, p: AppPalette, @ViewBuilder actions: () -> Actions) {
        self.name = name
        self.p = p
        self.actions = actions()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { label; actions }
            } else {
                HStack(spacing: 8) { label; Spacer(minLength: 8); actions }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(argb: p.surface))
        .overlay(RoundedRectangle(cornerRadius: Radii.standard.sm).stroke(Color(argb: p.border), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radii.standard.sm))
    }

    private var label: some View {
        Text(name).font(.body.weight(.semibold)).foregroundColor(Color(argb: p.text))
    }
}

/// Fixed-content Friends for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct FriendsShowcase: View {
    private let large: Bool
    @StateObject private var model: FriendsModel
    @Environment(\.colorScheme) private var colorScheme

    public init(large: Bool = false) {
        self.large = large
        let since = Date(timeIntervalSince1970: 1_760_000_000)
        let hits = [
            UserSearchResultResponse(userId: "u1", displayName: "Ali Rezaei"),
            UserSearchResultResponse(userId: "u2", displayName: "Alice"),
            UserSearchResultResponse(userId: "u3", displayName: "Alina"),
            UserSearchResultResponse(userId: "u4", displayName: "Alireza"),
        ]
        let requests = FriendsList(items: [
            FriendRefResponse(userId: "r1", displayName: "Maryam", since: since),
            FriendRefResponse(userId: "r2", displayName: nil, since: since),
        ])
        let friends = FriendsList(items: [
            FriendRefResponse(userId: "u4", displayName: "Alireza", since: since),
            FriendRefResponse(userId: "f2", displayName: "Dariush", since: since),
        ], error: "Couldn't load friends.")
        _model = StateObject(wrappedValue: FriendsModel.preview(
            query: "ali", results: hits, requests: requests, friends: friends,
            sent: ["u2": .pending], busy: ["r2"], actionError: "Couldn't send that request."))
    }

    public var body: some View {
        FriendsContent(model: model)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(argb: (colorScheme == .dark ? AppPalette.dark : AppPalette.light).bg))
            .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}
