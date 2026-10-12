import SwiftUI
import QDesign

/// Shared chrome for the login and register screens (Android AuthLayout, Brand, Notice, FooterLink).
struct AuthLayout<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var palette: AppPalette { colorScheme == .dark ? .dark : .light }

    var body: some View {
        ZStack {
            Color(argb: palette.bg).ignoresSafeArea()
            ScrollView {
                VStack(spacing: Spacing.standard.s3) {
                    Text("ParsLing")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(Color(argb: palette.primary))
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
                .padding(Spacing.standard.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radii.standard.lg)
                        .fill(Color(argb: palette.surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.standard.lg)
                        .stroke(Color(argb: palette.border), lineWidth: 1)
                )
                .frame(maxWidth: 420)
                .padding(Spacing.standard.s3)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct AuthNotice: View {
    let message: String
    let background: UInt32
    let foreground: UInt32

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(Color(argb: foreground))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.standard.s3)
            .background(
                RoundedRectangle(cornerRadius: Radii.standard.sm).fill(Color(argb: background))
            )
            .accessibilityElement(children: .combine)
    }
}

struct AuthErrorBanner: View {
    let message: String
    let palette: AppPalette

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(Color(argb: palette.danger))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.standard.s3)
            .background(
                RoundedRectangle(cornerRadius: Radii.standard.sm).fill(Color(argb: palette.dangerBg))
            )
            .accessibilityLabel("Error: \(message)")
    }
}

struct AuthFieldBox<Field: View>: View {
    let label: String
    let palette: AppPalette
    private let field: Field

    init(label: String, palette: AppPalette, @ViewBuilder field: () -> Field) {
        self.label = label
        self.palette = palette
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard.s1) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(argb: palette.textMuted))
            field
                .foregroundColor(Color(argb: palette.text))
                .padding(Spacing.standard.s2 + Spacing.standard.s1)
                .background(
                    RoundedRectangle(cornerRadius: Radii.standard.sm).fill(Color(argb: palette.bg))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.standard.sm)
                        .stroke(Color(argb: palette.border), lineWidth: 1)
                )
        }
    }
}

struct AuthPrimaryButton: View {
    let title: String
    let palette: AppPalette
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(Color(argb: palette.primaryContrast))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.standard.s3 - Spacing.standard.s1)
                .background(
                    RoundedRectangle(cornerRadius: Radii.standard.md).fill(Color(argb: palette.primary))
                )
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct AuthFooterLink: View {
    let prompt: String
    let action: String
    let palette: AppPalette
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: Spacing.standard.s1) {
            Text(prompt)
                .font(.subheadline)
                .foregroundColor(Color(argb: palette.textMuted))
            Button(action: onTap) {
                Text(action)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color(argb: palette.current))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Which AutoFill role a field has. iOS-only modifiers live here so `swift test` on macOS still compiles.
enum AuthFieldRole {
    case email
    case password
    case newPassword
}

struct AuthFieldTraits: ViewModifier {
    let role: AuthFieldRole

    func body(content: Content) -> some View {
        #if os(iOS)
        switch role {
        case .email:
            content
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        case .password:
            content.textContentType(.password)
        case .newPassword:
            content.textContentType(.newPassword)
        }
        #else
        content
        #endif
    }
}

extension View {
    func authField(_ role: AuthFieldRole) -> some View {
        modifier(AuthFieldTraits(role: role))
    }
}
