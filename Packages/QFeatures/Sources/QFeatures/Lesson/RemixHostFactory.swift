import Foundation
import QDomain

public extension SignedInShell {
    /// The model behind a topics Repack's contents step: its fill-in-the-blank round is played, submitted and saved the same
    /// way the flashcards start screen's is.
    func makeRemixHost(route: LessonRoute, environment: LessonEnvironment) -> RemixHostModel {
        let store = vocabulary
        let submitter = app?.flashcards
        let unauthorized = unauthorizedHandler
        let services = app.map { ClozeServices.live(app: $0) }
            ?? ClozeServices(practice: nil, sentences: nil)
        return RemixHostModel(route: route, environment: environment, store: store, makeRound: { deck, hardcore in
            ClozeRoundModel(
                store: store, services: services, submitter: submitter, hardcore: hardcore, handed: deck,
                onUnauthorized: unauthorized)
        }, settings: services.settings)
    }
}
