import Foundation

@MainActor enum CameraEvents {
    struct Event: Codable { let date: Date; let state: String }
    private(set) static var events: [Event] = []
    static func record(_ state: CameraController.State) {
        guard events.last?.state != state.rawValue else { return }
        events.append(Event(date: Date(), state: state.rawValue))
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }
}
