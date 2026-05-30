import XCTest
@testable import noribar

/// Tests the **D6 one-animation-per-view rule** on `SymbolAnimator.Resolution` — the pure
/// planner behind the live coalescing. No window server needed, so this runs in CI.
final class SymbolAnimatorTests: XCTestCase {

    private typealias Resolver = SymbolAnimator.Resolution

    /// The core invariant: a resolved plan never carries more than one *animating* mutation
    /// (a content transition or a discrete effect), across every request shape.
    func testInvariantHoldsAcrossAllRequestShapes() {
        let desireds: [String?] = [nil, "clock", "clock.fill"]
        // Qualify: Apple's `Symbols.SymbolEffect` protocol is also visible here.
        let effects: [noribar.SymbolEffect?] = [nil, .replace, .bounce, .pulse, .scale]
        for desired in desireds {
            for effect in effects {
                let plan = Resolver.resolve(currentIcon: "clock", desiredIcon: desired, effect: effect)
                XCTAssertTrue(Resolver.isValid(plan),
                              "invariant violated for desired=\(desired ?? "nil") "
                              + "effect=\(effect?.rawValue ?? "nil"): \(plan)")
            }
        }
    }

    func testReplaceWithIconChangeIsSingleContentTransition() {
        XCTAssertEqual(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock.fill", effect: .replace),
                       [.contentTransition(icon: "clock.fill")])
    }

    func testDiscreteEffectWithIconChangeIsPlainSetPlusOneEffect() {
        XCTAssertEqual(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock.fill", effect: .bounce),
                       [.setImage(icon: "clock.fill"), .discreteEffect(.bounce)])
    }

    func testDiscreteEffectWithoutIconChangeIsJustTheEffect() {
        XCTAssertEqual(Resolver.resolve(currentIcon: "clock", desiredIcon: nil, effect: .pulse),
                       [.discreteEffect(.pulse)])
    }

    func testReplaceWithUnchangedIconIsNoOp() {
        XCTAssertEqual(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock", effect: .replace), [])
    }

    func testIconChangeWithoutEffectIsPlainSet() {
        XCTAssertEqual(Resolver.resolve(currentIcon: "clock", desiredIcon: "clock.fill", effect: nil),
                       [.setImage(icon: "clock.fill")])
    }

    func testNoChangeNoEffectIsNoOp() {
        XCTAssertEqual(Resolver.resolve(currentIcon: "clock", desiredIcon: nil, effect: nil), [])
    }
}
