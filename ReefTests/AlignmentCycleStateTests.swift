import Testing
@testable import Reef

struct AlignmentCycleStateTests {

    @Test func repeatedEdgePressesCycleHalfThirdTwoThirds() {
        var state = AlignmentCycleState()
        #expect(state.layout(for: .edge(.left)) == .edge(.left, .oneHalf))
        #expect(state.layout(for: .edge(.left)) == .edge(.left, .oneThird))
        #expect(state.layout(for: .edge(.left)) == .edge(.left, .twoThirds))
        #expect(state.layout(for: .edge(.left)) == .edge(.left, .oneHalf))
    }

    @Test func changingEdgeRestartsTheCycle() {
        var state = AlignmentCycleState()
        _ = state.layout(for: .edge(.left))
        _ = state.layout(for: .edge(.left))
        // A different edge starts at a half again, not at two-thirds.
        #expect(state.layout(for: .edge(.top)) == .edge(.top, .oneHalf))
    }

    @Test func resetReturnsToTheStartOfTheCycle() {
        var state = AlignmentCycleState()
        _ = state.layout(for: .edge(.right))
        _ = state.layout(for: .edge(.right))
        state.reset()
        #expect(state.layout(for: .edge(.right)) == .edge(.right, .oneHalf))
    }

    @Test func cornerPressesWalkTheTwoCornersOnThatEdge() {
        var state = AlignmentCycleState()
        #expect(state.layout(for: .corner(.left)) == .corner(.topLeft))
        #expect(state.layout(for: .corner(.left)) == .corner(.bottomLeft))
        #expect(state.layout(for: .corner(.left)) == .corner(.topLeft))
    }

    @Test func changingCornerEdgeRestartsTheCycle() {
        var state = AlignmentCycleState()
        _ = state.layout(for: .corner(.left))   // topLeft
        // Switching to the top edge starts at its first corner, not carrying the step over.
        #expect(state.layout(for: .corner(.top)) == .corner(.topLeft))
    }

    @Test func edgeAndCornerAreDistinctGroups() {
        var state = AlignmentCycleState()
        _ = state.layout(for: .edge(.left))
        // Adding the corner modifier is a group change, so it starts fresh.
        #expect(state.layout(for: .corner(.left)) == .corner(.topLeft))
    }

    @Test func everyCornerIsReachable() {
        var reachable = Set<LayoutCorner>()
        for edge in LayoutEdge.allCases {
            for corner in AlignmentCycleState.corners(on: edge) {
                reachable.insert(corner)
            }
        }
        #expect(reachable.count == LayoutCorner.allCases.count)
    }

    @Test func pureResolutionMatchesTheMutatingInterface() {
        #expect(AlignmentCycleState.layout(for: .edge(.bottom), step: 0) == .edge(.bottom, .oneHalf))
        #expect(AlignmentCycleState.layout(for: .edge(.bottom), step: 4) == .edge(.bottom, .oneThird))
        #expect(AlignmentCycleState.layout(for: .corner(.right), step: 3) == .corner(.bottomRight))
    }
}
