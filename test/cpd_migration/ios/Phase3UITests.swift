import XCTest

final class Phase3UITests: XCTestCase {
  private func matching(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", label, label))
      .firstMatch
  }

  func testShareAndPickOriginals() throws {
    let app = XCUIApplication()
    let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    app.launch()
    let share = app.buttons["Share sample PDF"]
    XCTAssertTrue(share.waitForExistence(timeout: 25))
    share.tap()
    let close = app.buttons["Close"]
    let sample = matching("CPD-Phase3-Sample", in: app)
    XCTAssertTrue(close.waitForExistence(timeout: 8) || sample.exists, app.debugDescription)
    if close.exists && close.isHittable {
      close.tap()
    } else {
      app.swipeDown()
    }

    let open = app.buttons["Pick sample from files"]
    XCTAssertTrue(open.waitForExistence(timeout: 12))
    for item in ["CPD-Phase3-Sample", "CPD-Phase3-Photo"] {
      open.tap()
      let roots = [app, files]
      func pick(_ label: String) -> Bool {
        for root in roots {
          let match = matching(label, in: root)
          if match.exists && match.isHittable {
            match.tap()
            return true
          }
        }
        return false
      }
      var selected = false
      for _ in 0..<8 {
        if pick(item) {
          selected = true
          break
        }
        if pick("On My iPhone") || pick("Recording Validation") || pick("recording_validation") {
          continue
        }
        if pick("Browse") {
          continue
        }
        Thread.sleep(forTimeInterval: 0.5)
      }
      XCTAssertTrue(selected, app.debugDescription + files.debugDescription)
      if !selected { return }
      XCTAssertTrue(open.waitForExistence(timeout: 15))
    }
  }
}
