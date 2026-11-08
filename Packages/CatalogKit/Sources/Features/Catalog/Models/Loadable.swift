/// A value that arrives later. `failed` carries the words the screen shows.
enum Loadable<Value: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }
}
