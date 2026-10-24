import UIKit
import XCTest

/// Adaptive layout checks for the native `AppShell` (`TabView` with four tabs:
/// Chat, Agents, Activity, Settings). The shell has no sidebar drawer anymore.
@MainActor
final class AdaptiveLayoutUITests: XCTestCase {
    private static let tabTitles = ["Chat", "Agents", "Activity", "Settings"]

    func testOfflineChatAdaptsAcrossRotationAndKeepsFourTabs() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--openclaw-initial-destination", "chat",
            "--openclaw-appearance", "light",
            "--openclaw-ui-test-readiness",
            "-onboarding.completed", "YES",
            "-gateway.preferredStableID", "adaptive-offline",
            "-onboarding.quickSetupDismissed", "YES",
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let root = app.descendants(matching: .any)["AppShell.Root"].firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 30))
        self.assertFourTabs(in: app)
        self.capture("portrait-four-tabs")

        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForLandscape(in: app, minimumWidth: 0)
        XCTAssertTrue(root.exists)
        self.assertFourTabs(in: app)
        self.capture("landscape-four-tabs")

        XCUIDevice.shared.orientation = .portrait
        self.waitForPortrait(in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 10))
        self.assertFourTabs(in: app)
    }

    func testPhoneOfflineChatKeepsCompactLayout() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone compact layout")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--openclaw-initial-destination", "chat",
            "--openclaw-appearance", "light",
            "--openclaw-ui-test-readiness",
            "-onboarding.completed", "YES",
            "-gateway.preferredStableID", "adaptive-offline",
            "-onboarding.quickSetupDismissed", "YES",
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let composer = app.otherElements["chat-composer-surface"].firstMatch
        XCTAssertTrue(self.tabButton("Chat", in: app).waitForExistence(timeout: 30))
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(composer.frame.width, app.frame.width - 32)
        self.capture("iphone-portrait-compact-chat")
        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForLandscape(in: app, minimumWidth: 0)
        XCTAssertTrue(self.tabButton("Chat", in: app).exists)
        // Large iPhones must not inherit the iPad's 760pt reading cap.
        if app.frame.width >= 900 {
            XCTAssertGreaterThan(composer.frame.width, 760)
        }
        self.capture("iphone-landscape-compact-chat")
        XCUIDevice.shared.orientation = .portrait
        self.waitForPortrait(in: app)

        // Activity hosts Overview, Activity and Automations behind one tab.
        let activity = self.tabButton("Activity", in: app)
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        let readiness = app.descendants(matching: .any)["RootTabs.Ready"].firstMatch
        XCTAssertTrue(readiness.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["AppShell.Activity"].firstMatch.waitForExistence(timeout: 10))
        self.tabButton("Chat", in: app).tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "Selecting Chat must restore the composer")
    }

    /// Synthetic conversation content is used only to exercise native interaction.
    /// This test deliberately does not attach screenshots as product evidence.
    func testChatDraftAndFocusSurviveRotationAndTabSwitches() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires an iPad")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--openclaw-initial-destination", "chat",
            "--openclaw-screenshot-mode",
            "--openclaw-ui-test-readiness",
            "--openclaw-appearance", "light",
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        self.waitForPortrait(in: app)
        let readiness = app.descendants(matching: .any)["RootTabs.Ready"].firstMatch
        XCTAssertTrue(readiness.waitForExistence(timeout: 30))
        self.expectation(for: NSPredicate(format: "value == %@", "ready:chat"), evaluatedWith: readiness)
        self.waitForExpectations(timeout: 15)

        let input = app.descendants(matching: .any)["chat-message-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        // Application-level typing does not re-tap the field: subsequent keystrokes
        // prove that the same composer remains the keyboard's recipient. One
        // identifying key per transition avoids conflating focus with batch typing latency.
        app.typeText("draft")
        self.assertDraft("draft", in: input)

        XCUIDevice.shared.orientation = .landscapeLeft
        self.waitForLandscape(in: app)
        self.assertDraft("draft", in: input)
        app.typeText("1")
        self.assertDraft("draft1", in: input)
        let composer = app.otherElements["chat-composer-surface"].firstMatch
        XCTAssertTrue(composer.exists)
        XCTAssertLessThanOrEqual(composer.frame.width, 760)

        XCUIDevice.shared.orientation = .portrait
        self.waitForPortrait(in: app)
        self.assertDraft("draft1", in: input)
        app.typeText("2")
        self.assertDraft("draft12", in: input)
    }

    /// Synthetic transport data exercises the real completed and streaming renderers.
    /// No fixture screenshots are attached as product evidence.
    func testAssistantAndStreamingResponsesShareComposerColumn() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires an iPad")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "--openclaw-initial-destination", "chat",
            "--openclaw-screenshot-mode", "--openclaw-ui-test-readiness",
            "--openclaw-hold-initial-chat-run", "--openclaw-streaming-layout-fixture",
        ]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let composer = app.otherElements["chat-composer-surface"].firstMatch
        let completed = app.descendants(matching: .any)["chat-assistant-message-body"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 30))
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        self.waitForLandscape(in: app)
        self.assertReadingColumn(completed, composer: composer, responseInset: 2)
        XCTAssertGreaterThan(completed.frame.width, 700, "Must detect the former 560pt assistant cap")

        let input = app.descendants(matching: .any)["chat-message-input"].firstMatch
        input.tap()
        input.typeText("Check streaming width")
        app.buttons["chat-send-message"].tap()
        let streaming = app.descendants(matching: .any)["chat-streaming-assistant-body"].firstMatch
        XCTAssertTrue(streaming.waitForExistence(timeout: 10))
        self.assertReadingColumn(streaming, composer: composer, responseInset: 0)
        XCTAssertGreaterThan(streaming.frame.width, 700, "Must detect the former streaming bubble cap")
        XCUIDevice.shared.orientation = .portrait
        self.waitForPortrait(in: app)
        self.assertReadingColumn(streaming, composer: composer, responseInset: 0)
    }

    // MARK: - Helpers

    /// The system draws the tab bar (top floating bar or sidebar on iPad). English titles are
    /// forced by the launch arguments of the callers, so tabs are found by label.
    private func tabButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons[title].firstMatch
    }

    private func assertFourTabs(in app: XCUIApplication) {
        for title in Self.tabTitles {
            XCTAssertTrue(
                self.tabButton(title, in: app).waitForExistence(timeout: 10),
                "Tab \(title) must exist in the shell tab bar")
        }
    }

    private func assertReadingColumn(_ response: XCUIElement, composer: XCUIElement, responseInset: CGFloat) {
        let responseFrame = response.frame
        let composerFrame = composer.frame
        XCTAssertGreaterThan(responseFrame.height, 0)
        XCTAssertGreaterThan(composerFrame.width, 0)
        XCTAssertLessThanOrEqual(responseFrame.width, 760)
        // Composer chrome sits inside 4pt padding; completed rows inset their body by 2pt.
        print("Reading column: response=\(responseFrame), composer=\(composerFrame)")
        XCTAssertEqual(responseFrame.width + responseInset * 2, composerFrame.width + 8, accuracy: 1)
        XCTAssertEqual(responseFrame.midX, composerFrame.midX, accuracy: 2)
    }

    private func assertDraft(_ draft: String, in input: XCUIElement) {
        // Use XCUI's normal snapshot synchronization rather than a second deadline
        // that can expire while a successful accessibility query is still running.
        let started = Date()
        let actual = input.value as? String
        print("Draft snapshot in \(Date().timeIntervalSince(started))s: \(String(describing: actual))")
        XCTAssertEqual(actual, draft)
    }

    private func waitForPortrait(in app: XCUIApplication) {
        let portrait = NSPredicate { _, _ in
            MainActor.assumeIsolated { app.frame.width < app.frame.height }
        }
        self.expectation(for: portrait, evaluatedWith: app)
        self.waitForExpectations(timeout: 10)
    }

    private func waitForLandscape(in app: XCUIApplication, minimumWidth: CGFloat = 800) {
        let landscape = NSPredicate { _, _ in
            MainActor.assumeIsolated { app.frame.width >= minimumWidth && app.frame.width > app.frame.height }
        }
        self.expectation(for: landscape, evaluatedWith: app)
        self.waitForExpectations(timeout: 10)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
