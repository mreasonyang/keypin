import AppKit
import SwiftUI
import XCTest
@testable import keypin

/// Geometry checks use real SwiftUI layout with in-memory services. They do not
/// launch the app, switch input sources, create login items, or render screenshots.
/// Packaged localized copy is covered by native preview acceptance separately.
final class PanelLayoutTests: XCTestCase {
    private var originalLanguage: String?

    override func setUp() {
        super.setUp()
        originalLanguage = L10n.languageCode
    }

    override func tearDown() {
        L10n.languageCode = originalLanguage
        super.tearDown()
    }

    private func model(sourceCount: Int = 2, initialSetup: Bool = false) -> AppModel {
        let choices = (0..<sourceCount).map {
            InputChoice(id: "layout.\($0)", name: $0 == 0 ? "ABC" : "日本語 — 入力ソース \($0)")
        }
        var config = Config(sourceID: initialSetup ? nil : choices.first?.id,
                            enabled: !initialSetup, language: "en", onboardingCompleted: !initialSetup)
        let services = AppServices(load: { config }, save: { config = $0 }, choices: { choices },
                                   current: { choices.first ?? InputChoice(id: "", name: "") },
                                   loginEnabled: { false }, setLogin: { _ in }, apply: { $0(.success) })
        let model = AppModel(services: services, isPreview: true)
        model.start()
        return model
    }

    @MainActor
    private func fittingSize<V: View>(_ view: V) -> CGSize {
        let host = NSHostingController(rootView: view)
        let result = host.sizeThatFits(in: CGSize(width: 320, height: 10_000))
        XCTAssertTrue(result.width.isFinite && result.height.isFinite)
        XCTAssertGreaterThan(result.height, 0)
        return result
    }

    @MainActor
    func testShortListUsesLessSpaceThanLongListAndLongListHeightPlateaus() async {
        let shortModel = model(sourceCount: 2)
        let short = fittingSize(Panel(model: shortModel, inWindow: true))
        shortModel.pauseKeeping()
        let paused = fittingSize(Panel(model: shortModel, inWindow: true))
        XCTAssertEqual(short.height, paused.height, accuracy: 1, "Selecting Follow system should not move the list or resize the panel")
        let long = fittingSize(Panel(model: model(sourceCount: 12), inWindow: true))
        let veryLong = fittingSize(Panel(model: model(sourceCount: 200), inWindow: true))

        XCTAssertLessThan(short.height, 240, "The everyday two-source panel should remain compact")
        XCTAssertGreaterThan(long.height - short.height, 100, "Available space should expand for a useful list viewport")
        XCTAssertEqual(long.height, veryLong.height, accuracy: 1, "More installed sources must scroll instead of growing the window")
        XCTAssertEqual(short.width, long.width, accuracy: 1)
        XCTAssertEqual(long.width, veryLong.width, accuracy: 1)
    }

    @MainActor
    func testFilteringLongListToOneOrZeroResultsKeepsItsViewport() async {
        let choices = (0..<20).map { InputChoice(id: "filter.\($0)", name: "Keyboard \($0)") }
        let full = fittingSize(SourceList(sources: choices, totalCount: choices.count, selectedID: nil,
                                          currentID: choices[0].id, followSystem: FollowSystemChoice(selected: true, action: {}),
                                          onSelect: { _ in }).frame(width: 292))
        let filtered = fittingSize(SourceList(sources: [choices[7]], totalCount: choices.count, selectedID: nil,
                                              currentID: choices[0].id, followSystem: FollowSystemChoice(selected: true, action: {}),
                                          onSelect: { _ in }).frame(width: 292))
        let noResults = fittingSize(SourceList(sources: [], totalCount: choices.count, selectedID: nil,
                                               currentID: choices[0].id, followSystem: FollowSystemChoice(selected: true, action: {}),
                                          onSelect: { _ in }).frame(width: 292))

        XCTAssertEqual(full.height, filtered.height, accuracy: 1, "Typing a search must not move the panel under the pointer")
        XCTAssertEqual(full.height, noResults.height, accuracy: 1, "An unsuccessful search must keep the same viewport too")
        XCTAssertGreaterThan(filtered.height, 150, "The filtered state should retain the list viewport")
    }

    @MainActor
    func testOnboardingKeepsLongSourceListBounded() async {
        let short = fittingSize(Panel(model: model(sourceCount: 2, initialSetup: true), inWindow: true))
        let long = fittingSize(Panel(model: model(sourceCount: 12, initialSetup: true), inWindow: true))
        let veryLong = fittingSize(Panel(model: model(sourceCount: 200, initialSetup: true), inWindow: true))

        XCTAssertGreaterThan(long.height, short.height)
        XCTAssertEqual(long.height, veryLong.height, accuracy: 1)
        XCTAssertLessThanOrEqual(long.height, 580, "Setup navigation must fit on a small display")
    }

    @MainActor
    func testLongDiagnosticCannotPushPanelOutsideSmallDisplay() async {
        let model = model(sourceCount: 12)
        model.warning = "Could not switch input sources: " + String(repeating: "The input method service did not respond. ", count: 16)
        for page: PanelPage in [.main, .settings] {
            let size = fittingSize(Panel(model: model, inWindow: true, page: page, maximumHeight: 420))
            XCTAssertLessThanOrEqual(size.height, 420, "Long diagnostic text must scroll without making the footer unreachable on \(page)")
        }
    }

    @MainActor
    func testLongInputMethodNameCannotHideOnboardingConfirmation() async {
        let model = model(initialSetup: true)
        model.sources[0] = InputChoice(id: "layout.0", name: String(repeating: "日本語カスタム入力メソッド", count: 16))
        model.setupSourceID = model.sources[0].id
        model.setupStep = 1
        let size = fittingSize(Panel(model: model, inWindow: true, maximumHeight: 420))

        XCTAssertLessThanOrEqual(size.height, 420, "The selected source name must not push setup confirmation off screen")
    }
}
