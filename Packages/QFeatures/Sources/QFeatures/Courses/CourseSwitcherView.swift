import SwiftUI
import QModel
import QDesign

/// The course switcher as a sheet body (Android CourseSwitcher dropdown plus the add-a-language
/// list): enrolled courses with a checkmark on the active one, then the courses still to add.
/// Tapping an enrolled course switches to it; tapping an addable one enrolls and switches.
public struct CourseSwitcherView: View {
    @ObservedObject private var model: CourseSwitcherModel
    @Environment(\.colorScheme) private var colorScheme

    public init(model: CourseSwitcherModel) {
        self.model = model
    }

    private var palette: AppPalette { colorScheme == .dark ? .dark : .light }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.standard.s2) {
                Text("Your languages")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Color(argb: palette.text))
                    .accessibilityAddTraits(.isHeader)
                if let message = model.error {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(Color(argb: palette.danger))
                        .accessibilityLabel("Error: \(message)")
                }
                ForEach(model.enrolled, id: \.code) { course in
                    enrolledRow(course)
                }
                Text("Add a language")
                    .font(.headline)
                    .foregroundColor(Color(argb: palette.text))
                    .padding(.top, Spacing.standard.s2)
                    .accessibilityAddTraits(.isHeader)
                if model.addable.isEmpty {
                    Text("There are no more languages to add.")
                        .font(.subheadline)
                        .foregroundColor(Color(argb: palette.textMuted))
                }
                ForEach(model.addable, id: \.code) { course in
                    addRow(course)
                }
            }
            .padding(Spacing.standard.s4)
        }
        .background(Color(argb: palette.bg).ignoresSafeArea())
        .task { await model.loadCatalog() }
    }

    private func enrolledRow(_ course: EnrolledCourse) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        return Button {
            Task { await model.switchTo(course.code) }
        } label: {
            HStack(spacing: Spacing.standard.s3) {
                Text(course.name)
                    .font(.headline)
                    .foregroundColor(Color(argb: course.isActive ? palette.primary : palette.text))
                Spacer()
                if course.isActive {
                    Image(systemName: "checkmark")
                        .foregroundColor(Color(argb: palette.primary))
                }
            }
            .padding(Spacing.standard.s3)
            .background(shape.fill(Color(argb: course.isActive ? palette.successBg : palette.bg)))
            .overlay(shape.stroke(Color(argb: course.isActive ? palette.primary : palette.border), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(course.name)
        .accessibilityValue(course.isActive ? "Current language" : "")
        .accessibilityAddTraits(course.isActive ? [.isButton, .isSelected] : [.isButton])
    }

    private func addRow(_ course: CourseCatalogEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radii.standard.md)
        return Button {
            Task { await model.addCourse(course.code) }
        } label: {
            HStack(spacing: Spacing.standard.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.latinName)
                        .font(.headline)
                        .foregroundColor(Color(argb: palette.text))
                    Text(course.nativeName)
                        .font(.body)
                        .foregroundColor(Color(argb: palette.textMuted))
                }
                Spacer()
                Image(systemName: "plus")
                    .foregroundColor(Color(argb: palette.primary))
            }
            .padding(Spacing.standard.s3)
            .background(shape.fill(Color(argb: palette.bg)))
            .overlay(shape.stroke(Color(argb: palette.border), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add \(course.latinName), \(course.nativeName)")
        .accessibilityAddTraits(.isButton)
    }
}
