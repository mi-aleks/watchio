import XCTest

@MainActor
final class WatchioUITests: XCTestCase {
  func testDemoServicesExposeAccessibleControls() {
    let app = launchApp()

    XCTAssertTrue(app.staticTexts["4 services · 4 AI active"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["scan-now"].exists)
    XCTAssertEqual(app.buttons["service-demo-web"].value as? String, "Node.js icon")
    XCTAssertEqual(app.buttons["service-demo-api"].value as? String, "Go icon")
    XCTAssertEqual(app.buttons["service-demo-db"].value as? String, "Database icon")
  }

  func testDemoAIActivityExposesToolAndHostSemantics() {
    let app = launchApp(additionalArguments: ["--ai-mode"])

    let codexValue = try? XCTUnwrap(
      app.buttons["ai-activity-demo-ai-codex"].value as? String)
    XCTAssertTrue(codexValue?.contains("Codex, Desktop") == true)
    XCTAssertTrue(codexValue?.contains("CPU 2.4%") == true)
    XCTAssertTrue(codexValue?.contains("RAM") == true)

    let claudeValue = try? XCTUnwrap(
      app.buttons["ai-activity-demo-ai-claude-atlas"].value as? String)
    XCTAssertTrue(claudeValue?.contains("Claude, CLI") == true)
    XCTAssertTrue(claudeValue?.contains("CPU 1.6%") == true)
    XCTAssertTrue(claudeValue?.contains("RAM") == true)
  }

  func testProcessTreeStopRequiresExplicitConfirmation() {
    let app = launchApp(additionalArguments: ["--ai-mode"])
    let activity = app.buttons["ai-activity-demo-ai-codex"]
    XCTAssertTrue(activity.waitForExistence(timeout: 5))
    activity.click()

    let stopTree = app.buttons["stop-ai-demo-ai-codex"]
    XCTAssertTrue(stopTree.waitForExistence(timeout: 3))
    stopTree.click()

    let confirmation = app.windows["Watchio"].sheets.firstMatch
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
    let stopNow = confirmation.buttons["Stop now"]
    let cancel = confirmation.buttons["Cancel"]
    XCTAssertTrue(stopNow.waitForExistence(timeout: 3))
    XCTAssertTrue(cancel.exists)
    XCTAssertTrue(confirmation.staticTexts["Stop Codex process tree?"].exists)
    cancel.click()
    XCTAssertTrue(stopNow.waitForNonExistence(timeout: 2))
  }

  func testOnboardingDefaultActionCompletesIntroduction() {
    let app = launchApp(additionalArguments: ["--show-onboarding"])

    let completeOnboarding = app.buttons["Got it"]
    XCTAssertTrue(completeOnboarding.waitForExistence(timeout: 5))
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(completeOnboarding.waitForNonExistence(timeout: 2))
  }

  func testSettingsExposeLoginAndDetectionControls() {
    let app = launchApp()
    app.buttons["Settings"].click()

    app.buttons["General"].click()
    let launchAtLogin = app.descendants(matching: .any)["launch-at-login"]
    XCTAssertTrue(launchAtLogin.waitForExistence(timeout: 5))

    app.buttons["Detection"].click()
    XCTAssertTrue(app.textFields["include-rule"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.textFields["ignore-rule"].exists)
    XCTAssertTrue(app.checkBoxes["detect-ai-activity"].exists)
  }

  private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--demo-data", "--screenshot-mode"] + additionalArguments
    app.launch()
    return app
  }
}
