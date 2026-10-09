//
//  GuitarTapUITests.swift
//  GuitarTapUITests
//
//  Export regression: drive the real app as a user does. Each case is imported through Saved
//  Measurements → Import, then exported as the spectrum image and the PDF report from both places the
//  app offers them: the main window, with the import loaded, and the row's menu in Saved Measurements.
//  Nothing is replaced — the open and save panels are the system's, given paths as a user types them
//  (⇧⌘G), which also grants the sandboxed app access to them. The app runs in a test sandbox of its
//  own (GT_TEST_SANDBOX), so its settings and library start empty and are never the user's.
//

import AppKit
import XCTest

final class GuitarTapUITests: XCTestCase {

    /// The fixtures are Swift's, since Swift's exports are the expected ones.
    static let cases: [(name: String, fixture: String)] = [
        ("guitar", "dws-2024-umik-1-swift-mac-1784225155"),
        ("multi-tap", "dws-2024-umik-1-3-tap-swift-mac-1785359425"),
        ("plate", "plate-umik-1-swift-mac-1785359486"),
        ("brace", "brace-umik-1-swift-mac-1785359411"),
        ("comparison", "5-guitar-comparison-1776708138"),
    ]

    /// Where the exports are written: `<case>/main` and `<case>/saved`. The runner is sandboxed, so this
    /// is its own temporary folder; the app reaches it through the save panel, as it would any folder a
    /// user picks. Each export is also attached to the test result, which is how the files leave the run.
    static let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("guitartap-uitest")

    /// The unit tests' fixtures, from the source tree.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("GuitarTapTests")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Each case: one launch and import, then both export paths — the main window with the import loaded,
    /// then the row's menu in Saved Measurements.
    @MainActor func testExports() throws {
        for c in Self.cases {
            try XCTContext.runActivity(named: c.name) { _ in
                let app = launch()
                try importCase(c.fixture, app: app)

                let main = try emptyFolder(c.name, "main")
                app.buttons["Export Spectrum"].firstMatch.click()
                try save(to: main, app: app, expecting: "png")
                app.buttons["Export PDF"].firstMatch.click()
                try save(to: main, app: app, expecting: "pdf")

                let saved = try emptyFolder(c.name, "saved")
                rowMenu(app, choose: "Export Spectrum")
                try save(to: saved, app: app, expecting: "png")
                rowMenu(app, choose: "Export PDF Report")
                try save(to: saved, app: app, expecting: "pdf")
                // The saved export is named after the measurement, so it is the row that was imported.
                let names = try FileManager.default.contentsOfDirectory(atPath: saved.path)
                XCTAssertEqual(Set(names), ["\(c.fixture).png", "\(c.fixture).pdf"])
                app.terminate()
            }
        }
    }

    // MARK: - Driving the app

    /// Launch in a test sandbox of its own; with no microphone (as on CI) dismiss the engine error as a
    /// user would.
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GT_TEST_SANDBOX"] = "1"
        // Dates print in the local time zone; UTC, so an export's date is the same on any machine and the
        // export checker can compare it.
        app.launchEnvironment["TZ"] = "UTC"
        // No input device, as on CI: the app is idle between steps instead of drawing a live meter, and the
        // engine error below is the one CI sees.
        app.launchEnvironment["GT_NO_AUDIO_INPUT"] = "1"
        app.launch()
        let engineError = alert("Audio Engine Error", app)
        if engineError.waitForExistence(timeout: 5) {
            engineError.buttons["OK"].click()
        }
        return app
    }

    /// Saved Measurements → Import → the fixture, through the open panel; then OK and Done.
    @MainActor private func importCase(_ fixture: String, app: XCUIApplication) throws {
        openList(app)
        app.buttons["Import"].firstMatch.click()
        let path = Self.fixtures.appendingPathComponent("\(fixture).guitartap").path
        try goTo(path, app: app)
        let open = panelButton("Open", app)
        if open.waitForExistence(timeout: 2) && open.isEnabled { open.click() }

        let imported = alert("Import Successful", app)
        XCTAssertTrue(imported.waitForExistence(timeout: 10), "no Import Successful")
        imported.buttons["OK"].click()
        // Loading a measurement recorded on a microphone that is not connected warns, as it would a user.
        let unavailable = alert("Microphone Unavailable", app)
        if unavailable.waitForExistence(timeout: 1) { unavailable.buttons["OK"].click() }
        app.buttons["Done"].firstMatch.click()
    }

    @MainActor private func openList(_ app: XCUIApplication) {
        if !app.buttons["Done"].firstMatch.exists {
            app.buttons["Measurements"].firstMatch.click()
        }
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5), "Saved Measurements did not open")
    }

    /// Right-click the only row and choose `item` from its menu.
    @MainActor private func rowMenu(_ app: XCUIApplication, choose item: String) {
        openList(app)
        // The list's rows are an empty header, the total, then each measurement as a button.
        let row = app.sheets.firstMatch.cells.buttons.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no row")
        row.rightClick()
        let menuItem = app.menuItems[item].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "no \(item) in the row's menu")
        menuItem.click()
    }

    /// A SwiftUI alert, by its title: on macOS it is a sheet labelled "alert" holding the title as text.
    @MainActor private func alert(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.sheets.matching(NSPredicate(format: "label == 'alert'"))
            .containing(NSPredicate(format: "value == %@", title)).firstMatch
    }

    /// A button in the open or save panel — not the Touch Bar's button of the same name.
    @MainActor private func panelButton(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.sheets.descendants(matching: .button).matching(identifier: title).firstMatch
    }

    /// In the open or save panel: ⇧⌘G, type the path, Return — as a user goes to a location.
    @MainActor private func goTo(_ path: String, app: XCUIApplication) throws {
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "no panel")
        panel.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        enterPath(path, app: app)
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Enter a path in the panel's "Go to" field and press Return: pasted, as a user can, because XCUITest
    /// types a long path a few seconds a time.
    @MainActor private func enterPath(_ path: String, app: XCUIApplication) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
    }

    /// In the save panel: go to `folder`, Save, and wait for the one new file. The panel is a window of
    /// its own, run by the system's panel service, so it is driven from the keyboard as a user can: ⇧⌘G,
    /// paste the folder, Return, then Return for Save. The file appearing is the check.
    @MainActor private func save(to folder: URL, app: XCUIApplication, expecting ext: String) throws {
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        Thread.sleep(forTimeInterval: 1.0)   // the panel opens and takes the keyboard
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        enterPath(folder.path, app: app)
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey(.return, modifierFlags: [])

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let new = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)).subtracting(before)
            if let name = new.first(where: { $0.hasSuffix(".\(ext)") }) {
                let file = folder.appendingPathComponent(name)
                let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
                if size > 0 {
                    Thread.sleep(forTimeInterval: 0.3)   // let an atomic write finish
                    let attachment = XCTAttachment(contentsOfFile: file)
                    // <case>--<main|saved>--<file>: an attachment name cannot hold a "/".
                    attachment.name = "\(folder.deletingLastPathComponent().lastPathComponent)--\(folder.lastPathComponent)--\(name)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("no .\(ext) written to \(folder.path)")
    }

    private func emptyFolder(_ name: String, _ path: String) throws -> URL {
        let folder = Self.output.appendingPathComponent(name).appendingPathComponent(path)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
