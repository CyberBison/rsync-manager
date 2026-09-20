import XCTest

final class rsync_managerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(dark: Bool = false, narrow: Bool = false, empty: Bool = false, forRun: Bool = false) throws -> XCUIApplication {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rsync-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        if !empty {
            let id = "AA747039-EA72-4BDA-BA78-5D4D50604121"
            var tasks: [[String: Any]] = [
                ["id": id, "name": "Documents Backup", "arguments": "-av --delete --exclude='.DS_Store'", "source": "/Users/example/Documents/", "destination": "/Volumes/Archive/Backups/Documents", "isActive": true, "lastSyncDate": 811800000, "lastSyncStatus": "success"],
                ["id": UUID().uuidString, "name": "Photo Library", "arguments": "-av", "source": "/Users/example/Pictures/", "destination": "/Volumes/Studio/Photos", "isActive": true],
                ["id": UUID().uuidString, "name": "Remote Archive", "arguments": "-avz", "source": "/Users/example/Projects/", "destination": "backup@studio.local:/archive/projects", "isActive": true, "lastSyncDate": 811700000, "lastSyncStatus": "error"]
            ]
            let logs: [[String: Any]] = [
                ["id": UUID().uuidString, "taskId": id, "timestamp": 811700000, "result": "rsync error: destination volume is unavailable (code 23)", "success": false],
                ["id": UUID().uuidString, "taskId": id, "timestamp": 811750000, "result": "Sync cancelled by user.\nTransfer interrupted.", "success": false],
                ["id": UUID().uuidString, "taskId": id, "timestamp": 811800000, "result": "building file list ... done\nReports/Annual Review.pdf\nNotes/Planning.md\n\nsent 42,816 bytes  received 128 bytes\ntotal size is 128,450  speedup is 2.99", "success": true]
            ]
            if forRun {
                let source = directory.appendingPathComponent("source")
                let destination = directory.appendingPathComponent("destination")
                try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Data(repeating: 65, count: 128 * 1024).write(to: source.appendingPathComponent("test.txt"))
                tasks[0]["source"] = source.path + "/"
                tasks[0]["destination"] = destination.path
                tasks[0]["arguments"] = "-av --bwlimit=1"
            }
            try JSONSerialization.data(withJSONObject: tasks).write(to: directory.appendingPathComponent("sync_tasks.json"))
            try JSONSerialization.data(withJSONObject: logs).write(to: directory.appendingPathComponent("sync_logs.json"))
        }
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + (dark ? ["-dark"] : []) + (narrow ? ["-narrow"] : [])
        app.launchEnvironment["RSYNC_TEST_DIRECTORY"] = directory.path
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.sheets.firstMatch.exists
            ? app.sheets.firstMatch.screenshot() : app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAppearanceAndSizeMatrix() throws {
        for dark in [false, true] {
            for narrow in [false, true] {
                let app = try launch(dark: dark, narrow: narrow)
                let label = "\(dark ? "Dark" : "Light")-\(narrow ? "Narrow" : "Wide")"
                XCTAssertTrue(app.buttons["Edit Profile"].waitForExistence(timeout: 5))
                capture(app, "\(label)-Profile")
                app.buttons["Profile Options"].click()
                XCTAssertTrue(app.buttons["Edit Arguments…"].waitForExistence(timeout: 3))
                capture(app, "\(label)-Inspector")
                app.buttons["Edit Arguments…"].click()
                XCTAssertTrue(app.buttons["Save Changes"].waitForExistence(timeout: 3))
                XCTAssertTrue(app.buttons["Save Changes"].isHittable)
                capture(app, "\(label)-Editor")
                app.buttons["Cancel"].click()
                if !narrow { app.buttons["Profile Options"].click() }
                app.buttons["History"].click()
                XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
                capture(app, "\(label)-History")
                app.buttons["Done"].click()
                app.typeKey(",", modifierFlags: .command)
                XCTAssertTrue(app.buttons["Open Full Disk Access Settings"].waitForExistence(timeout: 3))
                capture(app, "\(label)-Settings")
                app.terminate()
            }
        }
    }

    @MainActor func testCreateProfileFromEmptyState() throws {
        let app = try launch(empty: true)
        capture(app, "Empty-Profiles")
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Create Profile"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Create Profile"].isEnabled)
        app.textFields["Name"].click()
        app.textFields["Name"].typeText("Test Backup")
        app.textFields["Source path"].click()
        app.textFields["Source path"].typeText("/tmp/source/")
        app.textFields["Destination path"].click()
        app.textFields["Destination path"].typeText("/tmp/destination")
        app.buttons["Create Profile"].click()
        XCTAssertTrue(app.buttons["Edit Profile"].waitForExistence(timeout: 3))
        app.buttons["History"].click()
        XCTAssertTrue(app.staticTexts["No history yet"].waitForExistence(timeout: 3))
        capture(app, "Empty-History")
        app.buttons["Done"].click()
        app.terminate()
    }

    @MainActor func testRunningAndCancellation() throws {
        for dark in [false, true] {
            let app = try launch(dark: dark, forRun: true)
            app.buttons["Run Sync"].click()
            XCTAssertTrue(app.staticTexts["Sync in progress"].waitForExistence(timeout: 5))
            capture(app, "\(dark ? "Dark" : "Light")-Running")
            app.buttons["Stop Sync"].firstMatch.click()
            XCTAssertTrue(app.buttons["Run Sync"].waitForExistence(timeout: 10))
            app.buttons["History"].click()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Sync cancelled by user.")).firstMatch.waitForExistence(timeout: 5))
            capture(app, "\(dark ? "Dark" : "Light")-Cancelled")
            app.terminate()
        }
    }

    @MainActor func testDarkEmptyStates() throws {
        let app = try launch(dark: true, narrow: true, empty: true)
        capture(app, "Dark-Empty-Profiles")
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Create Profile"].waitForExistence(timeout: 3))
        capture(app, "Dark-New-Profile")
        app.buttons["Cancel"].click()
        app.buttons["History"].click()
        XCTAssertTrue(app.staticTexts["No history yet"].waitForExistence(timeout: 3))
        capture(app, "Dark-Empty-History")
        app.terminate()
    }

}
