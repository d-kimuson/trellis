import XCTest

@testable import Trellis

final class BrowserEventMonitorTests: XCTestCase {

    // MARK: - Mouse handler lifecycle

    func testMouseMonitorInstalledOnFirstHandler() {
        let monitor = BrowserEventMonitor()
        let owner = NSObject()
        monitor.addMouseHandler(for: owner) { $0 }
        XCTAssertEqual(monitor.mouseHandlerCount, 1)
        XCTAssertTrue(monitor.hasMouseMonitor)
    }

    func testMouseMonitorRemovedWhenLastHandlerRemoved() {
        let monitor = BrowserEventMonitor()
        let owner = NSObject()
        monitor.addMouseHandler(for: owner) { $0 }
        monitor.removeMouseHandler(for: owner)
        XCTAssertEqual(monitor.mouseHandlerCount, 0)
        XCTAssertFalse(monitor.hasMouseMonitor)
    }

    func testMultipleMouseHandlersShareOneMonitor() {
        let monitor = BrowserEventMonitor()
        let owner1 = NSObject()
        let owner2 = NSObject()
        monitor.addMouseHandler(for: owner1) { $0 }
        monitor.addMouseHandler(for: owner2) { $0 }
        XCTAssertEqual(monitor.mouseHandlerCount, 2)
        XCTAssertTrue(monitor.hasMouseMonitor)
        monitor.removeMouseHandler(for: owner1)
        XCTAssertEqual(monitor.mouseHandlerCount, 1)
        XCTAssertTrue(monitor.hasMouseMonitor)
        monitor.removeMouseHandler(for: owner2)
        XCTAssertFalse(monitor.hasMouseMonitor)
    }

    // MARK: - Keyboard handler lifecycle

    func testKeyboardMonitorInstalledOnFirstHandler() {
        let monitor = BrowserEventMonitor()
        let owner = NSObject()
        monitor.addKeyboardHandler(for: owner) { $0 }
        XCTAssertEqual(monitor.keyboardHandlerCount, 1)
        XCTAssertTrue(monitor.hasKeyboardMonitor)
    }

    func testKeyboardMonitorRemovedWhenLastHandlerRemoved() {
        let monitor = BrowserEventMonitor()
        let owner = NSObject()
        monitor.addKeyboardHandler(for: owner) { $0 }
        monitor.removeKeyboardHandler(for: owner)
        XCTAssertEqual(monitor.keyboardHandlerCount, 0)
        XCTAssertFalse(monitor.hasKeyboardMonitor)
    }

    // MARK: - Duplicate and idempotency

    func testAddingSameOwnerTwiceReplacesHandler() {
        let monitor = BrowserEventMonitor()
        let owner = NSObject()
        monitor.addMouseHandler(for: owner) { $0 }
        monitor.addMouseHandler(for: owner) { $0 }
        XCTAssertEqual(monitor.mouseHandlerCount, 1)
    }

    func testRemovingNonexistentOwnerIsNoop() {
        let monitor = BrowserEventMonitor()
        let owner = NSObject()
        monitor.removeMouseHandler(for: owner)
        XCTAssertEqual(monitor.mouseHandlerCount, 0)
        XCTAssertFalse(monitor.hasMouseMonitor)
    }

    func testRemoveAllCleansUpBothMonitors() {
        let monitor = BrowserEventMonitor()
        let owner = NSObject()
        monitor.addMouseHandler(for: owner) { $0 }
        monitor.addKeyboardHandler(for: owner) { $0 }
        monitor.removeAll(for: owner)
        XCTAssertEqual(monitor.mouseHandlerCount, 0)
        XCTAssertEqual(monitor.keyboardHandlerCount, 0)
        XCTAssertFalse(monitor.hasMouseMonitor)
        XCTAssertFalse(monitor.hasKeyboardMonitor)
    }
}
