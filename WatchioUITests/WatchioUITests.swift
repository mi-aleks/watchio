import XCTest

@MainActor
final class WatchioUITests: XCTestCase {
  func testDemoServicesExposeAccessibleControls() {
    let app = launchApp()

    XCTAssertTrue(app.staticTexts["4 development services"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["scan-now"].exists)
    XCTAssertTrue(app.buttons["service-demo-web"].exists)
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
  }

  private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--demo-data", "--screenshot-mode"] + additionalArguments
    app.launch()
    return app
  }
}
