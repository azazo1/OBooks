import Combine
import Foundation

@MainActor
final class ReaderController: ObservableObject {
    @Published private(set) var command: ReaderCommand?

    func send(_ action: ReaderAction) {
        command = ReaderCommand(action: action)
    }
}
