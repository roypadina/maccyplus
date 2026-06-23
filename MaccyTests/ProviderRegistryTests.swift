import XCTest
@testable import Maccy

// MARK: - Stubs

private final class StubConditionBuiltin: ConditionProvider {
    let descriptor: ProviderDescriptor
    init() {
        descriptor = ProviderDescriptor(
            id: "stub.condition.builtin", name: "Stub Condition Builtin",
            description: "A stub builtin condition for tests", longHelp: nil,
            kind: .condition, engine: .native, params: [], capabilities: [], source: .builtin
        )
    }
    func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool { return true }
}

private final class StubConditionLocal: ConditionProvider {
    let descriptor: ProviderDescriptor
    init() {
        descriptor = ProviderDescriptor(
            id: "stub.condition.local", name: "Stub Condition Local",
            description: "A stub local condition for tests", longHelp: nil,
            kind: .condition, engine: .native, params: [], capabilities: [],
            source: .local("/tmp/stub-plugin")
        )
    }
    func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool { return false }
}

private final class StubActionBuiltin: ActionProvider {
    let descriptor: ProviderDescriptor
    init() {
        descriptor = ProviderDescriptor(
            id: "stub.action.builtin", name: "Stub Action Builtin",
            description: "A stub builtin action for tests", longHelp: nil,
            kind: .action, engine: .native, params: [], capabilities: [], source: .builtin
        )
    }
    func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome { return .none }
}

// MARK: - Tests

@MainActor
final class ProviderRegistryTests: XCTestCase {
    private var registry: ProviderRegistry!

    override func setUp() {
        super.setUp()
        registry = ProviderRegistry()
        registry.reset()
    }

    override func tearDown() {
        registry.reset()
        registry = nil
        super.tearDown()
    }

    func testRegisterAndLookupCondition() {
        registry.register(condition: StubConditionBuiltin())
        let found = registry.condition("stub.condition.builtin")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.descriptor.id, "stub.condition.builtin")
    }

    func testRegisterAndLookupAction() {
        registry.register(action: StubActionBuiltin())
        let found = registry.action("stub.action.builtin")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.descriptor.id, "stub.action.builtin")
    }

    func testUnknownConditionIdReturnsNil() {
        XCTAssertNil(registry.condition("nonexistent.id"))
    }

    func testUnknownActionIdReturnsNil() {
        XCTAssertNil(registry.action("nonexistent.id"))
    }

    func testDescriptorsKindConditionReturnsOnlyConditions() {
        registry.register(condition: StubConditionBuiltin())
        registry.register(action: StubActionBuiltin())
        let result = registry.descriptors(kind: .condition)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "stub.condition.builtin")
    }

    func testDescriptorsNilKindReturnsBothSortedByName() {
        registry.register(condition: StubConditionBuiltin())
        registry.register(action: StubActionBuiltin())
        let result = registry.descriptors(kind: nil)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Stub Action Builtin")
        XCTAssertEqual(result[1].name, "Stub Condition Builtin")
    }

    func testRemoveAllDropsLocalSourceButKeepsBuiltin() {
        registry.register(condition: StubConditionBuiltin())
        registry.register(condition: StubConditionLocal())
        registry.removeAll(where: { source in
            if case .local = source { return true } else { return false }
        })
        XCTAssertNotNil(registry.condition("stub.condition.builtin"))
        XCTAssertNil(registry.condition("stub.condition.local"))
    }

    func testResetEmptiesAllProviders() {
        registry.register(condition: StubConditionBuiltin())
        registry.register(action: StubActionBuiltin())
        registry.reset()
        XCTAssertNil(registry.condition("stub.condition.builtin"))
        XCTAssertNil(registry.action("stub.action.builtin"))
        XCTAssertTrue(registry.descriptors().isEmpty)
    }

    func testSharedSingletonExists() {
        XCTAssertNotNil(ProviderRegistry.shared)
    }
}
