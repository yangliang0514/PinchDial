import XCTest
@testable import PinchDialCore

final class ShortcutTests: XCTestCase {
    func testPersistenceRoundTripAndInvalidSettingsFallback() throws {
        let custom = ZoomShortcuts(zoomIn: Shortcut(keyCode: 122), zoomOut: Shortcut(keyCode: 123))
        XCTAssertEqual(ZoomShortcuts.restored(from: try JSONEncoder().encode(custom)), custom)
        XCTAssertEqual(ZoomShortcuts.restored(from: nil), ZoomShortcuts())
        XCTAssertEqual(ZoomShortcuts.restored(from: Data("nonsense".utf8)), ZoomShortcuts())
        for invalid in [
            ZoomShortcuts(zoomIn: Shortcut(keyCode: 80)),
            ZoomShortcuts(zoomIn: Shortcut(keyCode: 999)),
            ZoomShortcuts(zoomIn: Shortcut(keyCode: 55)),
            ZoomShortcuts(zoomIn: Shortcut(keyCode: 79, modifiers: .command))
        ] {
            XCTAssertFalse(invalid.isValid)
            XCTAssertEqual(ZoomShortcuts.restored(from: try JSONEncoder().encode(invalid)), ZoomShortcuts())
        }
    }

    func testCatalogHasUniqueCodesAndSearchableUnavailableKeys() {
        XCTAssertEqual(Set(KeyCatalog.all.map(\.id)).count, KeyCatalog.all.count)
        XCTAssertEqual(KeyCatalog.all.filter { $0.matches(" f19 ") }.map(\.id), [80])
        XCTAssertEqual(KeyCatalog.all.filter { $0.matches("ESC") }.map(\.id), [53])
        XCTAssertTrue(KeyCatalog.all.filter { $0.matches("F999") }.isEmpty)
        XCTAssertNil(KeyCatalog.key(55))
        XCTAssertEqual(KeyCatalog.key(79)?.name, "F18")
        XCTAssertEqual(KeyCatalog.key(90)?.name, "F20")
    }

    func testCustomKeysReplaceDefaultsAndModifiersPassThrough() {
        var bridge = KeyBridge()
        let custom = ZoomShortcuts(zoomIn: Shortcut(keyCode: 0), zoomOut: Shortcut(keyCode: 1))
        XCTAssertEqual(bridge.handle(key: 79, down: true, repeated: false, enabled: true, shortcuts: custom), .init(consume: false))
        for modifier: ShortcutModifiers in [.command, .shift, .control, .option, [.command, .shift]] {
            XCTAssertEqual(bridge.handle(key: 0, down: true, repeated: false, enabled: true, shortcuts: custom, modifiers: modifier), .init(consume: false))
            XCTAssertEqual(bridge.handle(key: 0, down: false, repeated: false, enabled: true, shortcuts: custom), .init(consume: false))
        }
        XCTAssertEqual(bridge.handle(key: 0, down: true, repeated: false, enabled: true, shortcuts: custom), .init(consume: true, direction: 1))
        XCTAssertEqual(bridge.handle(key: 1, down: true, repeated: false, enabled: true, shortcuts: custom), .init(consume: true, direction: -1))
    }

    func testReassignmentWhileHeldKeepsOwnershipUntilRelease() {
        var bridge = KeyBridge()
        _ = bridge.handle(key: 79, down: true, repeated: false, enabled: true)
        let changed = ZoomShortcuts(zoomIn: Shortcut(keyCode: 122))
        XCTAssertEqual(bridge.handle(key: 79, down: true, repeated: true, enabled: true, shortcuts: changed, modifiers: .command), .init(consume: true))
        XCTAssertEqual(bridge.handle(key: 79, down: false, repeated: false, enabled: false, shortcuts: changed, modifiers: .command), .init(consume: true))
        XCTAssertEqual(bridge.handle(key: 79, down: true, repeated: false, enabled: true, shortcuts: changed), .init(consume: false))
        XCTAssertEqual(bridge.handle(key: 122, down: true, repeated: true, enabled: true, shortcuts: changed), .init(consume: false))
        XCTAssertEqual(bridge.handle(key: 122, down: true, repeated: false, enabled: true, shortcuts: changed), .init(consume: true, direction: 1))
    }

    func testModifierNormalizationAllowsFunctionArrowAndCapsLockFlags() {
        XCTAssertEqual(ShortcutModifiers.fromEventFlags((1 << 16) | (1 << 21) | (1 << 23)), [])
        XCTAssertEqual(ShortcutModifiers.fromEventFlags((1 << 20) | (1 << 17) | (1 << 23)), [.command, .shift])
    }

    func testDisabledAndInvalidConfigurationNeverStartZoom() {
        var bridge = KeyBridge()
        XCTAssertEqual(bridge.handle(key: 79, down: true, repeated: false, enabled: false), .init(consume: false))
        XCTAssertEqual(bridge.handle(key: 79, down: true, repeated: false, enabled: true,
                                     shortcuts: ZoomShortcuts(zoomOut: Shortcut(keyCode: 79))), .init(consume: false))
        XCTAssertEqual(bridge.handle(key: 79, down: true, repeated: false, enabled: true), .init(consume: true, direction: 1))
        bridge.reset()
        XCTAssertEqual(bridge.handle(key: 79, down: false, repeated: false, enabled: true), .init(consume: false))
    }
}
