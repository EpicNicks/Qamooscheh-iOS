import SwiftUI
import QDesign

/// The Library topics screen (web ThemesPage, Android LibraryScreen): a grid of Deep Dive topics
/// and a Remix button. Stories, conversations and songs are a follow-up.
public struct LibraryView: View {
    @ObservedObject private var model: LibraryModel
    private let onOpenTopic: (String) -> Void
    private let onRemix: ([String]) -> Void
    @StateObject private var picker = RemixPickerModel(allTopics: [])
    @State private var picking = false

    public init(model: LibraryModel, onOpenTopic: @escaping (String) -> Void, onRemix: @escaping ([String]) -> Void) {
        self.model = model
        self.onOpenTopic = onOpenTopic
        self.onRemix = onRemix
    }

    public var body: some View {
        ScrollView {
            LibraryContent(model: model, onOpenTopic: onOpenTopic, onRemixTapped: { picking = true })
                .padding(16)
        }
        .navigationTitle("Library")
        .task { await model.refresh() }
        .onReceive(model.$state) { state in
            if case .ready(let ready) = state { picker.update(allTopics: ready.allTopics) }
        }
        .sheet(isPresented: $picking) {
            RemixPickerView(model: picker, onStart: { ids in
                picking = false
                onRemix(ids)
            })
        }
    }
}

struct LibraryContent: View {
    @ObservedObject var model: LibraryModel
    let onOpenTopic: (String) -> Void
    let onRemixTapped: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 12) {
            switch model.state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading the library\u{2026}").font(.callout)
                }
            case .unavailable(let message):
                Text(message).font(.callout).foregroundColor(Color(argb: p.danger))
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            case .ready(let ready):
                topics(ready, p)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func topics(_ ready: LibraryTopics, _ p: AppPalette) -> some View {
        Text("Topics").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
            .accessibilityAddTraits(.isHeader)
        if ready.topics.isEmpty {
            Text("No themed lessons yet for this course.").font(.callout).foregroundColor(Color(argb: p.textMuted))
        } else {
            HStack(alignment: .center, spacing: 8) {
                Text("Pick a topic to explore, or mix several together.")
                    .font(.callout).foregroundColor(Color(argb: p.textMuted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onRemixTapped) {
                    Text("Remix").font(.body.weight(.bold)).foregroundColor(Color(argb: p.primaryContrast))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Color(argb: p.deepDive)).clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                ForEach(ready.topics, id: \.id) { topic in
                    Button(action: { onOpenTopic(topic.id) }) { TopicCard(topic: topic, p: p) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TopicCard: View {
    let topic: TopicSummary
    let p: AppPalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        VStack(alignment: .leading, spacing: 2) {
            Text(topic.id).font(.body.weight(.bold)).foregroundColor(Color(argb: p.text))
            Text("\(topic.lessonCount) lessons").font(.footnote).foregroundColor(Color(argb: p.textMuted))
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(12)
        .background(Color(argb: p.surface))
        .clipShape(shape)
        .overlay(shape.stroke(Color(argb: p.border), lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(topic.id), \(topic.lessonCount) lessons")
        .accessibilityAddTraits(.isButton)
    }
}

/// A topic's Deep Dive lessons (web ThemeBrowsePage, Android TopicScreen).
public struct TopicView: View {
    @ObservedObject private var model: TopicModel
    private let onStartLesson: (String) -> Void

    public init(model: TopicModel, onStartLesson: @escaping (String) -> Void) {
        self.model = model
        self.onStartLesson = onStartLesson
    }

    public var body: some View {
        ScrollView {
            TopicContent(model: model, onStartLesson: onStartLesson).padding(16)
        }
        .navigationTitle(model.themeId)
        .task { await model.refresh() }
    }
}

struct TopicContent: View {
    @ObservedObject var model: TopicModel
    let onStartLesson: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 8) {
            switch model.state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading lessons\u{2026}").font(.callout)
                }
            case .unavailable(let message):
                Text(message).font(.callout).foregroundColor(Color(argb: p.danger))
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            case .ready:
                Text(model.themeId).font(.title.weight(.bold)).foregroundColor(Color(argb: p.text))
                    .accessibilityAddTraits(.isHeader)
                Picker("Order", selection: Binding(get: { model.order }, set: { model.setOrder($0) })) {
                    Text("Structured").tag(TopicOrder.structured)
                    Text("Random").tag(TopicOrder.random)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
                let lessons = model.visibleLessons
                if lessons.isEmpty {
                    Text("Nothing browsable in this topic right now.").font(.callout).foregroundColor(Color(argb: p.textMuted))
                }
                ForEach(lessons, id: \.id) { lesson in
                    Button(action: { onStartLesson(lesson.id) }) {
                        LessonRow(lesson: lesson, highlighted: lesson.id == model.highlighted, p: p)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LessonRow: View {
    let lesson: TopicLesson
    let highlighted: Bool
    let p: AppPalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        let tag: String? = lesson.commonUsageScore.map { commonnessLabel($0) }
        HStack(spacing: 8) {
            Text(lesson.title).font(.body.weight(.semibold)).foregroundColor(Color(argb: p.text))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = tag {
                Text(tag).font(.footnote).foregroundColor(Color(argb: p.textMuted))
            }
        }
        .padding(12)
        .frame(minHeight: 44)
        .background(Color(argb: p.surface))
        .clipShape(shape)
        .overlay(shape.stroke(highlighted ? Color(argb: p.current) : Color(argb: p.border), lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tag.map { "\(lesson.title), \($0)" } ?? lesson.title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Pick topics to blend (web ThemeRemixPage, Android RemixPicker).
public struct RemixPickerView: View {
    @ObservedObject private var model: RemixPickerModel
    private let onStart: ([String]) -> Void

    public init(model: RemixPickerModel, onStart: @escaping ([String]) -> Void) {
        self.model = model
        self.onStart = onStart
    }

    public var body: some View {
        RemixPickerContent(model: model, onStart: onStart)
    }
}

struct RemixPickerContent: View {
    @ObservedObject var model: RemixPickerModel
    let onStart: ([String]) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 8) {
            Text("Remix topics").font(.title2.weight(.bold)).foregroundColor(Color(argb: p.text))
                .accessibilityAddTraits(.isHeader)
            Text("Pick the topics to mix into one session.").font(.callout).foregroundColor(Color(argb: p.textMuted))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.topics, id: \.id) { topic in
                        Button(action: { model.toggle(topic.id) }) {
                            HStack(spacing: 8) {
                                Image(systemName: model.isSelected(topic.id) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(model.isSelected(topic.id) ? Color(argb: p.current) : Color(argb: p.textMuted))
                                    .accessibilityHidden(true)
                                Text(topic.id).foregroundColor(Color(argb: p.text))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(topic.lessonCount)").foregroundColor(Color(argb: p.textMuted))
                            }
                            .padding(.leading, CGFloat(max(topic.depth - 1, 0) * 20))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(topic.breadcrumb), \(topic.lessonCount) lessons")
                        .accessibilityValue(model.isSelected(topic.id) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
            Button(action: { if let ids = model.start() { onStart(ids) } }) {
                Text(model.startTitle).font(.body.weight(.bold))
                    .foregroundColor(Color(argb: p.primaryContrast))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(model.canStart ? Color(argb: p.deepDive) : Color(argb: p.locked))
                    .clipShape(RoundedRectangle(cornerRadius: Radii.standard.md))
            }
            .buttonStyle(.plain)
            .disabled(!model.canStart)
        }
        .padding(16)
    }
}

/// Fixed-content Library screens for snapshot tests. `large` renders at an accessibility Dynamic Type size.
public struct ThemesShowcase: View {
    private let large: Bool
    @StateObject private var library: LibraryModel
    @StateObject private var topic: TopicModel
    @StateObject private var picker: RemixPickerModel
    @Environment(\.colorScheme) private var colorScheme

    public init(large: Bool = false) {
        self.large = large
        let all: [TopicSummary] = [
            TopicSummary(id: "Food", lessonCount: 12, breadcrumb: "Food", depth: 1),
            TopicSummary(id: "Drinks", lessonCount: 5, breadcrumb: "Food \u{203A} Drinks", depth: 2),
            TopicSummary(id: "Travel", lessonCount: 9, breadcrumb: "Travel", depth: 1),
            TopicSummary(id: "Family", lessonCount: 7, breadcrumb: "Family", depth: 1),
            TopicSummary(id: "Work", lessonCount: 0, breadcrumb: "Work", depth: 1),
        ]
        let roots = all.filter { $0.depth == 1 }
        _library = StateObject(wrappedValue: LibraryModel.preview(.ready(LibraryTopics(topics: roots, allTopics: all))))
        _topic = StateObject(wrappedValue: TopicModel.preview(themeId: "Food", highlighted: "food-2", lessons: [
            TopicLesson(id: "food-1", title: "Ordering at a cafe", commonUsageScore: 85),
            TopicLesson(id: "food-2", title: "Cooking verbs", commonUsageScore: 55),
            TopicLesson(id: "food-3", title: "Regional dishes", commonUsageScore: 20),
            TopicLesson(id: "food-4", title: "Table manners", commonUsageScore: nil),
        ]))
        let pick = RemixPickerModel(allTopics: all)
        pick.toggle("Food")
        pick.toggle("Travel")
        _picker = StateObject(wrappedValue: pick)
    }

    public var body: some View {
        let p = colorScheme == .dark ? AppPalette.dark : AppPalette.light
        VStack(alignment: .leading, spacing: 24) {
            LibraryContent(model: library, onOpenTopic: { _ in }, onRemixTapped: {})
            Divider()
            TopicContent(model: topic, onStartLesson: { _ in })
            Divider()
            RemixPickerContent(model: picker, onStart: { _ in })
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: p.bg))
        .environment(\.dynamicTypeSize, large ? .accessibility2 : .large)
    }
}
