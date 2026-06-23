import Foundation

@MainActor final class ProviderRegistry {
    static let shared = ProviderRegistry()

    private var conditions: [String: ConditionProvider] = [:]
    private var actions: [String: ActionProvider] = [:]

    func register(condition: ConditionProvider) { conditions[condition.descriptor.id] = condition }
    func register(action: ActionProvider) { actions[action.descriptor.id] = action }
    func condition(_ id: String) -> ConditionProvider? { conditions[id] }
    func action(_ id: String) -> ActionProvider? { actions[id] }

    func descriptors(kind: ProviderKind? = nil) -> [ProviderDescriptor] {
        let all: [ProviderDescriptor]
        switch kind {
        case .condition: all = conditions.values.map(\.descriptor)
        case .action:    all = actions.values.map(\.descriptor)
        case nil:        all = conditions.values.map(\.descriptor) + actions.values.map(\.descriptor)
        }
        return all.sorted { $0.name < $1.name }
    }

    func removeAll(where predicate: (ProviderSource) -> Bool) {
        conditions = conditions.filter { !predicate($0.value.descriptor.source) }
        actions = actions.filter { !predicate($0.value.descriptor.source) }
    }

    func reset() {
        conditions.removeAll()
        actions.removeAll()
    }
}
