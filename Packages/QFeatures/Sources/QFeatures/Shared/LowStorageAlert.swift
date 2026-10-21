import SwiftUI
import QNetwork

/// Shows the one plain low-storage alert on whatever screen is up, dismissed with OK.
private struct LowStorageAlertModifier: ViewModifier {
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                StorageNotice.shared.setHandler { Task { @MainActor in showing = true } }
            }
            .alert(StorageNotice.message, isPresented: $showing) {
                Button("OK", role: .cancel) {}
            }
    }
}

extension View {
    /// Attach once at the app's root.
    public func lowStorageAlert() -> some View {
        modifier(LowStorageAlertModifier())
    }
}
