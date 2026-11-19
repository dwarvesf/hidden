import AppKit
import XCTest
@testable import Hidden_Bar

private final class RetryTestEngine: MenuBarEngine {
    var state: MenuBarEngineState = .expanded
    var nextResult: CollapseResult? = .unavailable
    private(set) var requests = 0
    private var completion: ((CollapseResult) -> Void)?

    var isArrangementValid = true
    var isAlwaysHiddenSeparatorPlaced = true

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        requests += 1
        state = .calibrating
        self.completion = completion
        if let nextResult { finish(nextResult) }
    }

    func finish(_ result: CollapseResult) {
        state = result == .collapsed || result == .collapsedNothingHidden ? .collapsed : .expanded
        let report = completion
        completion = nil
        report?(result)
    }

    func expand() { state = .expanded }
    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {}
    func invalidateLayout() {}
}

// Stands in for the popover under the arrow: records what would have been said.
private final class RetryTestNotice: NoHideNoticePresenting {
    var isShown = false
    var canShow = true
    private(set) var shown: [NoHideReason] = []

    func show(_ reason: NoHideReason, from button: NSStatusBarButton?) -> Bool {
        guard canShow else { return false }
        shown.append(reason)
        isShown = true
        return true
    }

    func close() { isShown = false }
}

private final class RetryTestClock {
    private var now: TimeInterval = 0
    private var timers: [(deadline: TimeInterval, timer: Timer)] = []

    var pending: Int { timers.filter { $0.timer.isValid }.count }

    func schedule(after delay: TimeInterval, fire: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in fire() }
        timers.append((now + delay, timer))
        return timer
    }

    func advance(by interval: TimeInterval) {
        let end = now + interval
        while let index = timers.indices.filter({ timers[$0].timer.isValid && timers[$0].deadline <= end })
            .min(by: { timers[$0].deadline < timers[$1].deadline }) {
            let next = timers.remove(at: index)
            now = next.deadline
            next.timer.fire()
        }
        now = end
    }
}

// Exercises the real controller with a virtual clock and an engine that can
// fail synchronously or finish later, as a native request that times out does.
final class AutoCollapseRetryTests: XCTestCase {
    private var controller: StatusBarController!
    private var engine: RetryTestEngine!
    private var clock: RetryTestClock!
    private var notice: RetryTestNotice!
    private var defersAutoHide = false
    private var preferencesWereVisible = false
    private var saved: [String: Any] = [:]
    private let keys = [UserDefaults.Key.isAutoHide, UserDefaults.Key.numberOfSecondForAutoHide,
                        UserDefaults.Key.useFullStatusBarOnExpandEnabled, UserDefaults.Key.alwaysHiddenSectionEnabled,
                        UserDefaults.Key.areSeparatorsHidden, UserDefaults.Key.hoverToExpand,
                        UserDefaults.Key.revealOnScrollEnabled, UserDefaults.Key.revealOnEmptyClickEnabled,
                        UserDefaults.Key.revealOnShakeEnabled]

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = AppDefaults.store.object(forKey: key)
            AppDefaults.store.set(false, forKey: key)
        }
        AppDefaults.store.set(5.0, forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        preferencesWereVisible = PreferencesWindowController.isVisible
        engine = RetryTestEngine()
        clock = RetryTestClock()
        notice = RetryTestNotice()
        let engine = self.engine!
        let clock = self.clock!
        controller = StatusBarController(engineFactory: { _ in engine },
                                         scheduleAutoHide: { clock.schedule(after: $0, fire: $1) },
                                         autoHideDeferral: { [unowned self] in defersAutoHide },
                                         noHideNotice: notice)
    }

    override func tearDown() {
        controller = nil
        if !preferencesWereVisible { PreferencesWindowController.shared.close() }
        for key in keys {
            if let value = saved[key] { AppDefaults.store.set(value, forKey: key) }
            else { AppDefaults.store.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private func enableAutoHide() {
        AppDefaults.store.set(true, forKey: UserDefaults.Key.isAutoHide)
        controller.updateAutoHide()
    }

    func testPersistentFailuresStopAfterThreeAutomaticRequestsIncludingTheFirst() {
        enableAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 3)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(clock.pending, 0)
        AppDefaults.store.set(10.0, forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        controller.updateAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 3, "a preference refresh cannot replenish the exhausted budget")
    }

    func testDisablingAndReenablingAutoHideRestartsTheAttemptBudget() {
        enableAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 3)
        AppDefaults.store.set(false, forKey: UserDefaults.Key.isAutoHide)
        controller.updateAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 3)
        enableAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 6)
        XCTAssertEqual(clock.pending, 0)
    }

    func testReenablingDuringAPendingRequestGivesTheNewCycleThreeAttempts() {
        engine.nextResult = nil
        enableAutoHide()
        clock.advance(by: 5)
        XCTAssertEqual(engine.requests, 1)
        AppDefaults.store.set(false, forKey: UserDefaults.Key.isAutoHide)
        controller.updateAutoHide()
        enableAutoHide()
        engine.finish(.unavailable)
        engine.nextResult = .unavailable
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 4, "the old pending request does not consume the new cycle's budget")
        XCTAssertEqual(clock.pending, 0)
    }

    func testDeferredTimerFiringsDoNotConsumeAttempts() {
        defersAutoHide = true
        enableAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 0)
        XCTAssertEqual(clock.pending, 1)
        defersAutoHide = false
        clock.advance(by: 15)
        XCTAssertEqual(engine.requests, 3)
        XCTAssertEqual(clock.pending, 0)
    }

    func testManualFailureDoesNotStartAutoHideEvenWhenEnabled() {
        AppDefaults.store.set(true, forKey: UserDefaults.Key.isAutoHide)
        controller.expandCollapseIfNeeded()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 1)
        XCTAssertEqual(clock.pending, 0)
    }

    func testManualFailureDoesNotResetAnExhaustedBudget() {
        enableAutoHide()
        clock.advance(by: 100)
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(engine.requests, 4, "manual hiding remains available after automatic attempts are exhausted")
        controller.updateAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 4)
        XCTAssertEqual(clock.pending, 0)
    }

    func testManualFailureDoesNotPostponeAnExistingAutoHideTimer() {
        enableAutoHide()
        clock.advance(by: 2)
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(engine.requests, 1)
        clock.advance(by: 3)
        XCTAssertEqual(engine.requests, 2, "the existing automatic request still runs at five seconds")
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 4, "one manual request plus three automatic ones")
    }

    func testExpansionResetsTheAutomaticAttemptBudget() {
        enableAutoHide()
        clock.advance(by: 100)
        engine.state = .collapsed
        controller.showEverything()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 6)
        XCTAssertEqual(clock.pending, 0)
    }

    func testSuccessfulAutomaticHideResetsTheBudgetAndCancelsItsTimer() {
        enableAutoHide()
        clock.advance(by: 10)
        engine.nextResult = .collapsed
        clock.advance(by: 5)
        XCTAssertEqual(engine.requests, 3)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(clock.pending, 0)
        engine.state = .expanded
        engine.nextResult = .unavailable
        controller.updateAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 6, "success resets the budget without needing an expansion callback")
    }

    func testSuccessfulManualHideResetsTheBudget() {
        enableAutoHide()
        clock.advance(by: 100)
        engine.nextResult = .collapsed
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(engine.requests, 4)
        XCTAssertEqual(clock.pending, 0)
        engine.state = .expanded
        engine.nextResult = .unavailable
        controller.updateAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 7)
    }

    func testTimedOutAutomaticRequestsUseTheSameThreeAttemptLimit() {
        engine.nextResult = nil
        enableAutoHide()
        for attempt in 1...3 {
            clock.advance(by: 5)
            XCTAssertEqual(engine.requests, attempt)
            XCTAssertEqual(engine.state, .calibrating)
            clock.advance(by: 10)
            engine.finish(.unavailable)
        }
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 3)
        XCTAssertEqual(clock.pending, 0)
    }

    func testWaitingForAManualRequestDoesNotConsumeAutomaticAttempts() {
        engine.nextResult = nil
        enableAutoHide()
        controller.expandCollapseIfNeeded()
        clock.advance(by: 20)
        XCTAssertEqual(engine.requests, 1)
        engine.finish(.unavailable)
        engine.nextResult = .unavailable
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 4)
        XCTAssertEqual(clock.pending, 0)
    }

    func testDisablingAutoHideWhileARequestIsPendingPreventsRetries() {
        engine.nextResult = nil
        enableAutoHide()
        clock.advance(by: 5)
        AppDefaults.store.set(false, forKey: UserDefaults.Key.isAutoHide)
        controller.updateAutoHide()
        engine.finish(.unavailable)
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 1)
        XCTAssertEqual(clock.pending, 0)
    }

    // MARK: notice at the arrow

    // The click guard holds for 0.3 s; a second click needs the run loop to pass it.
    private func letTheClickGuardPass() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    func testManualClickThatHidNothingSaysWhyOncePerReason() {
        engine.nextResult = .refused(.outsideApplications)
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(notice.shown, [.outsideApplications])

        notice.close()
        letTheClickGuardPass()
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(notice.shown, [.outsideApplications], "the same reason does not repeat in one launch")

        engine.nextResult = .refused(.accessibilityNeeded)
        letTheClickGuardPass()
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(notice.shown, [.outsideApplications, .accessibilityNeeded], "another reason still speaks")
    }

    func testTimerAttemptNeverShowsANotice() {
        engine.nextResult = .refused(.accessibilityNeeded)
        enableAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 3)
        XCTAssertTrue(notice.shown.isEmpty, "only a click or the hotkey asked for hiding")
    }

    func testTimerAttemptThatHidNothingStaysQuietToo() {
        engine.nextResult = .collapsedNothingHidden
        enableAutoHide()
        clock.advance(by: 100)
        XCTAssertEqual(engine.requests, 1)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertTrue(notice.shown.isEmpty)
    }

    func testManualCollapseWithNothingLeftOfTheArrowCollapsesAndExplains() {
        engine.nextResult = .collapsedNothingHidden
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(notice.shown, [.everythingRightOfArrow])
    }

    func testAnUnreadableArrowIsTransientAndStaysSilent() {
        engine.nextResult = .unavailable
        controller.expandCollapseIfNeeded()
        XCTAssertTrue(notice.shown.isEmpty)
    }

    func testNoSecondNoticeWhileOneIsUp() {
        notice.isShown = true
        engine.nextResult = .refused(.outsideApplications)
        controller.expandCollapseIfNeeded()
        XCTAssertTrue(notice.shown.isEmpty)

        notice.isShown = false
        letTheClickGuardPass()
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(notice.shown, [.outsideApplications], "a notice that never showed does not use up its reason")
    }

    func testNoticeThatCouldNotBePutUpKeepsItsTurn() {
        notice.canShow = false
        engine.nextResult = .refused(.unkeepableIcons(names: ["JamfDaemon"]))
        controller.expandCollapseIfNeeded()
        XCTAssertTrue(notice.shown.isEmpty)

        notice.canShow = true
        letTheClickGuardPass()
        controller.expandCollapseIfNeeded()
        XCTAssertEqual(notice.shown, [.unkeepableIcons(names: ["JamfDaemon"])])
    }
}
