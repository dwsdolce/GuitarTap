//
//  GuitarTapUITests.swift
//  GuitarTapUITests
//
//  Export regression: drive the real app as a user does, on the Mac, the iPad and the iPhone. Each
//  case is imported through Saved Measurements → Import, then exported as the spectrum image and the
//  PDF report from both places the app offers them: the main window, with the import loaded, and the
//  row's menu in Saved Measurements. Nothing is replaced — the open and save panels, the document
//  picker and the share sheet are the system's, driven as a user drives them. The app runs in a test
//  sandbox of its own (GT_TEST_SANDBOX), so its settings and library start empty and are never the
//  user's. Each export is attached to the test result, which is how the files leave the run.
//

#if os(macOS)
import AppKit
#endif
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

                openMainExports(app)
                press(app.buttons["Export Spectrum"].firstMatch)
                _ = try save(c.name, "main", app: app, expecting: "png")
                press(app.buttons["Export PDF"].firstMatch)
                _ = try save(c.name, "main", app: app, expecting: "pdf")
                closeMainExports(app)

                rowMenu(app, fixture: c.fixture, choose: "Export Spectrum")
                let png = try save(c.name, "saved", app: app, expecting: "png")
                rowMenu(app, fixture: c.fixture, choose: "Export PDF Report")
                let pdf = try save(c.name, "saved", app: app, expecting: "pdf")
                // The saved export is named after the measurement, so it is the row that was imported.
                XCTAssertEqual([png, pdf], ["\(c.fixture).png", "\(c.fixture).pdf"])
                app.terminate()
            }
        }
    }

    // MARK: - Driving the app

    /// Launch in a test sandbox of its own, with no input device (as on CI); dismiss the engine error as
    /// a user would where the app reports one.
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GT_TEST_SANDBOX"] = "1"
        // Dates print in the local time zone; UTC, so an export's date is the same on any machine and the
        // export checker can compare it.
        app.launchEnvironment["TZ"] = "UTC"
        // No input device, as on CI: the app is idle between steps instead of drawing a live meter.
        app.launchEnvironment["GT_NO_AUDIO_INPUT"] = "1"
        app.launch()
        let engineError = alert("Audio Engine Error", app)
        if engineError.waitForExistence(timeout: 5) {
            press(engineError.buttons["OK"].firstMatch)
        }
        fitWindowToScreen(app)
        return app
    }

    /// Saved Measurements → Import → the fixture, through the open panel or the document picker; then OK
    /// and Done.
    @MainActor private func importCase(_ fixture: String, app: XCUIApplication) throws {
        openList(app)
        try pickFixture(fixture, app: app)

        let imported = alert("Import Successful", app)
        XCTAssertTrue(imported.waitForExistence(timeout: 60), "no Import Successful")
        press(imported.buttons["OK"].firstMatch)
        // Loading a measurement recorded on a microphone that is not connected warns, as it would a user.
        let unavailable = alert("Microphone Unavailable", app)
        if unavailable.waitForExistence(timeout: 1) { press(unavailable.buttons["OK"].firstMatch) }
        press(listDone(app))
    }

    /// The waits below are upper bounds for slow machines (CI's simulators especially); each returns as soon
    /// as what it waits for is there.
    ///
    /// Wait for a file `ext` that was not in `folder` before, attach it as `<case>--<path>--<file>` (an
    /// attachment name cannot hold a "/"), and return its name. On iOS the file is then removed: both
    /// export paths name it the same, and Save to Files would otherwise ask to replace it.
    private func awaitExport(in folder: URL, before: Set<String>, name: String, path: String,
                             ext: String, keep: Bool) throws -> String {
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            let new = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)).subtracting(before)
            if let file = new.first(where: { $0.hasSuffix(".\(ext)") }) {
                let url = folder.appendingPathComponent(file)
                let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
                if size > 0 {
                    Thread.sleep(forTimeInterval: 0.3)   // let an atomic write finish
                    let attachment = XCTAttachment(contentsOfFile: url)
                    attachment.name = "\(name)--\(path)--\(file)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    if !keep { try FileManager.default.removeItem(at: url) }
                    return file
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("no .\(ext) written to \(folder.path)")
        return ""
    }

    // MARK: - The Mac

    #if os(macOS)
    /// Where the exports are written: `<case>/main` and `<case>/saved`. The runner is sandboxed, so this
    /// is its own temporary folder; the app reaches it through the save panel, as it would any folder a
    /// user picks.
    static let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("guitartap-uitest")

    @MainActor private func press(_ element: XCUIElement) { element.click() }

    /// On a screen smaller than the window's default size (a CI runner's 1024 × 768), Window → Fill, as a user
    /// would: otherwise the results panel, with the export buttons, runs off the screen's edge. Not Zoom — that
    /// goes to the window's preferred size (its default 1200 wide), trimmed only to the screen's height.
    @MainActor private func fitWindowToScreen(_ app: XCUIApplication) {
        // NSScreen.main is the screen with the key window, and the test runner has none: the first screen.
        guard let screen = NSScreen.screens.first?.visibleFrame,
              screen.width < 1200 || screen.height < 800 else { return }
        press(app.menuBars.menuBarItems["Window"].firstMatch)
        let fill = app.menuBars.menuItems["Fill"].firstMatch
        XCTAssertTrue(fill.waitForExistence(timeout: 20), "no Window → Fill")
        press(fill)
        Thread.sleep(forTimeInterval: 1.0)   // the window animates
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.width <= screen.width + 1 && window.height <= screen.height + 1,
                      "the window \(window.size) does not fit the screen \(screen.size) after Fill")
    }

    @MainActor private func openList(_ app: XCUIApplication) {
        if !listDone(app).exists {
            press(app.buttons["Measurements"].firstMatch)
        }
        XCTAssertTrue(listDone(app).waitForExistence(timeout: 30), "Saved Measurements did not open")
    }

    @MainActor private func listDone(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Done"].firstMatch
    }

    /// The export buttons are always in the main window.
    @MainActor private func openMainExports(_ app: XCUIApplication) {}
    @MainActor private func closeMainExports(_ app: XCUIApplication) {}

    @MainActor private func pickFixture(_ fixture: String, app: XCUIApplication) throws {
        press(app.buttons["Import"].firstMatch)
        let path = Self.fixtures.appendingPathComponent("\(fixture).guitartap").path
        try goTo(path, app: app)
        let open = panelButton("Open", app)
        if open.waitForExistence(timeout: 2) && open.isEnabled { press(open) }
    }

    /// Right-click the only row and choose `item` from its menu.
    @MainActor private func rowMenu(_ app: XCUIApplication, fixture: String, choose item: String) {
        openList(app)
        // The list's rows are an empty header, the total, then each measurement as a button.
        let row = app.sheets.firstMatch.cells.buttons.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no row")
        row.rightClick()
        let menuItem = app.menuItems[item].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 20), "no \(item) in the row's menu")
        press(menuItem)
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
        XCTAssertTrue(panel.waitForExistence(timeout: 30), "no panel")
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

    /// In the save panel: go to `<case>/<path>`, Save, and wait for the new file; returns its name. The
    /// panel is a window of its own, run by the system's panel service, so it is driven from the keyboard
    /// as a user can: ⇧⌘G, paste the folder, Return, then Return for Save. The file appearing is the
    /// check. Each path's folder is emptied before its first export, the image.
    @MainActor private func save(_ name: String, _ path: String, app: XCUIApplication,
                                 expecting ext: String) throws -> String {
        let folder = Self.output.appendingPathComponent(name).appendingPathComponent(path)
        if ext == "png" {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        Thread.sleep(forTimeInterval: 1.0)   // the panel opens and takes the keyboard
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        enterPath(folder.path, app: app)
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey(.return, modifierFlags: [])
        return try awaitExport(in: folder, before: before, name: name, path: path, ext: ext, keep: true)
    }
    #endif

    // MARK: - The iPad and the iPhone

    #if os(iOS)
    /// The simulator's own files ("On My iPad" / "On My iPhone"), where the document picker finds the
    /// fixtures and Save to Files puts the exports. The run script passes its location.
    private var files: URL {
        get throws {
            let path = try XCTUnwrap(ProcessInfo.processInfo.environment["GT_FILES_DIR"],
                                     "GT_FILES_DIR is not set: run Tooling/run-export-uitests.sh --simulator <name>")
            return URL(fileURLWithPath: path)
        }
    }

    private var local: String { UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone" }

    @MainActor private func press(_ element: XCUIElement) { element.tap() }

    /// The simulator's screen is the device's own; nothing to fit.
    @MainActor private func fitWindowToScreen(_ app: XCUIApplication) {}

    @MainActor private func openList(_ app: XCUIApplication) {
        if !listDone(app).exists {
            press(app.buttons["Measurements"].firstMatch)
        }
        XCTAssertTrue(listDone(app).waitForExistence(timeout: 30), "Saved Measurements did not open")
    }

    @MainActor private func listDone(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars["Saved Measurements"].buttons["Done"].firstMatch
    }

    /// On the iPhone the export buttons are in the Results sheet; on the iPad, in the main window.
    @MainActor private func openMainExports(_ app: XCUIApplication) {
        if !app.buttons["Export Spectrum"].exists { press(app.buttons["Results"].firstMatch) }
        XCTAssertTrue(app.buttons["Export Spectrum"].waitForExistence(timeout: 20), "no Export Spectrum")
    }

    @MainActor private func closeMainExports(_ app: XCUIApplication) {
        let done = app.navigationBars["Analysis Results"].buttons["Done"].firstMatch
        if done.exists { press(done) }
    }

    /// More → Import Measurement → the document picker: the local files, then the fixture. The fixture is
    /// put there first, as a user would have it.
    @MainActor private func pickFixture(_ fixture: String, app: XCUIApplication) throws {
        let source = Self.fixtures.appendingPathComponent("\(fixture).guitartap")
        let target = try files.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)

        press(app.navigationBars["Saved Measurements"].buttons["More"].firstMatch)
        let importItem = app.buttons["Import Measurement"].firstMatch
        XCTAssertTrue(importItem.waitForExistence(timeout: 20), "no Import Measurement")
        press(importItem)

        // The picker is the system's: on a freshly started simulator its contents can take a while.
        let file = app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", "\(fixture).guitartap")).firstMatch
        let location = app.cells[local].firstMatch
        let deadline = Date().addingTimeInterval(60)
        while !file.exists && !location.exists && app.buttons["Browse"].exists == false && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        if !file.exists {
            goToLocalFiles(app)
        }
        XCTAssertTrue(file.waitForExistence(timeout: 60), "the picker does not show \(fixture)")
        press(file)
    }

    /// The local files in the document picker or Save to Files: the sidebar on the iPad, Browse on the
    /// iPhone.
    @MainActor private func goToLocalFiles(_ app: XCUIApplication) {
        let location = app.cells[local].firstMatch
        if !location.exists, app.buttons["Browse"].exists { press(app.buttons["Browse"].firstMatch) }
        if location.waitForExistence(timeout: 20) { press(location) }
    }

    /// Long-press the imported measurement's row and choose `item` from its menu.
    @MainActor private func rowMenu(_ app: XCUIApplication, fixture: String, choose item: String) {
        openList(app)
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS %@", measurementName(fixture))).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no row for \(fixture)")
        row.press(forDuration: 1.0)
        let menuItem = app.collectionViews.buttons[item].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 20), "no \(item) in the row's menu")
        press(menuItem)
    }

    /// The name a fixture's row shows: its measurement's name.
    private func measurementName(_ fixture: String) -> String {
        let url = Self.fixtures.appendingPathComponent("\(fixture).guitartap")
        let list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [[String: Any]]
        return list?.first?["measurementName"] as? String ?? fixture
    }

    @MainActor private func alert(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.alerts[title].firstMatch
    }

    /// The share sheet → Save to Files → the local files → Save; returns the saved file's name. The share
    /// sheet lists Save to Files under View More until it has been used.
    @MainActor private func save(_ name: String, _ path: String, app: XCUIApplication,
                                 expecting ext: String) throws -> String {
        let folder = try files
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))

        let saveToFiles = app.cells["Save to Files"].firstMatch
        if !saveToFiles.waitForExistence(timeout: 5) {
            let more = app.cells["View More"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 30), "no share sheet")
            press(more)
        }
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 20), "no Save to Files")
        press(saveToFiles)

        // The panel's Save, by the document picker's own identifier: the app has buttons labelled Save too.
        let save = app.buttons["DOCPicker.actionButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 30), "no Save to Files panel")
        if !app.staticTexts[local].firstMatch.exists { goToLocalFiles(app) }
        press(save)
        return try awaitExport(in: folder, before: before, name: name, path: path, ext: ext, keep: false)
    }
    #endif
}
