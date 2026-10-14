import Foundation
import Combine
import QModel
import QNetwork

/// Strings for the course switcher (Android ShellViewModel).
public enum CourseSwitcherRules {
    public static let switchFallback = "Couldn't switch courses."
    public static let addFallback = "Couldn't add that course."
}

/// One enrolled course in the switcher.
public struct EnrolledCourse: Equatable, Sendable {
    public let code: String
    public let name: String
    public let isActive: Bool
}

/// Switch between enrolled courses or add another (Android ShellViewModel.switchTo / addCourse,
/// web CourseSwitcher). Names come from the catalog; a course missing from it shows its
/// upper-cased code. Every bootstrap the server returns goes to `onBootstrap`.
///
/// `isBusy` is set synchronously before the first await, so a second call while one is in
/// flight is a no-op. A failed catalog load is silent, as on Android (names fall back to codes).
@MainActor
public final class CourseSwitcherModel: ObservableObject {
    @Published public private(set) var bootstrap: BootstrapResponse
    @Published public private(set) var catalog: [CourseCatalogEntry] = []
    @Published public private(set) var isBusy = false
    @Published public private(set) var error: String?

    private let service: OnboardingService
    private let onBootstrap: @MainActor (BootstrapResponse) -> Void

    public init(
        service: OnboardingService,
        bootstrap: BootstrapResponse,
        onBootstrap: @escaping @MainActor (BootstrapResponse) -> Void = { _ in }
    ) {
        self.service = service
        self.bootstrap = bootstrap
        self.onBootstrap = onBootstrap
    }

    public var activeCode: String? { bootstrap.course?.code }

    public var enrolled: [EnrolledCourse] {
        bootstrap.enrolledCourseCodes.map {
            EnrolledCourse(code: $0, name: name(of: $0), isActive: $0 == activeCode)
        }
    }

    /// The catalog minus what is already enrolled.
    public var addable: [CourseCatalogEntry] {
        let have = Set(bootstrap.enrolledCourseCodes)
        return catalog.filter { !have.contains($0.code) }
    }

    public func name(of code: String) -> String {
        catalog.first { $0.code == code }?.latinName ?? code.uppercased()
    }

    public func loadCatalog() async {
        do {
            catalog = try await service.catalog()
        } catch {
            // Silent: names fall back to course codes and the add list stays empty.
        }
    }

    public func dismissError() { error = nil }

    /// Makes `code` the active course; the already-active course is a no-op.
    public func switchTo(_ code: String) async {
        guard !isBusy, code != activeCode else { return }
        await run(fallback: CourseSwitcherRules.switchFallback) {
            self.apply(try await self.service.switchActive(courseCode: code))
        }
    }

    /// Enrolls in `code`, then makes it active (Android addCourse). Already enrolled is a no-op.
    public func addCourse(_ code: String) async {
        guard !isBusy, !bootstrap.enrolledCourseCodes.contains(code) else { return }
        await run(fallback: CourseSwitcherRules.addFallback) {
            self.apply(try await self.service.enroll(courseCode: code))
            self.apply(try await self.service.switchActive(courseCode: code))
        }
    }

    private func apply(_ next: BootstrapResponse) {
        bootstrap = next
        onBootstrap(next)
    }

    private func run(fallback: String, _ action: () async throws -> Void) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await action()
        } catch is CancellationError {
            // No message.
        } catch {
            self.error = AuthRules.message(for: error, fallback: fallback)
        }
    }
}
