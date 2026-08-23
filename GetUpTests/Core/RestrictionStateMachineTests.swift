import Foundation
import Testing
@testable import GetUp

@Suite("Restriction state machine")
struct RestrictionStateMachineTests {
    @Test("No rule removes an applied restriction")
    func missingConfigurationRemovesAppliedRestriction() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                rule: nil,
                appliedRestriction: TestFixtures.makeAppliedRestriction(
                    isApplied: true,
                    ruleRevision: 1
                )
            )
        )

        #expect(decision.presentationState == .configurationRequired)
        #expect(decision.desiredRestriction == .inactive)
        #expect(decision.effect == .removeShield)
        #expect(decision.reason == .configurationMissing)
    }

    @Test("A disabled rule removes an applied restriction")
    func disabledRuleRemovesAppliedRestriction() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                rule: TestFixtures.makeRule(isEnabled: false),
                appliedRestriction: TestFixtures.makeAppliedRestriction(
                    isApplied: true,
                    ruleRevision: 1
                )
            )
        )

        #expect(decision.presentationState == .inactive)
        #expect(decision.desiredRestriction == .inactive)
        #expect(decision.effect == .removeShield)
        #expect(decision.reason == .ruleDisabled)
    }

    @Test("Time, location, authorization, and applied-state matrix")
    func completeStateMatrix() {
        let activeTimes = [true, false]
        let locationStates: [LocationConditionState] = [.inside, .outside, .unavailable]
        let authorizationStates = [true, false]
        let appliedStates = [true, false]

        for isScheduleActive in activeTimes {
            for locationState in locationStates {
                for isAuthorized in authorizationStates {
                    for isApplied in appliedStates {
                        let decision = RestrictionStateMachine.evaluate(
                            makeInput(
                                now: isScheduleActive ? TestFixtures.now : inactiveDate,
                                locationCondition: TestFixtures.makeLocationCondition(
                                    state: locationState
                                ),
                                authorization: isAuthorized
                                    ? TestFixtures.makeAuthorization()
                                    : TestFixtures.makeAuthorization(familyControls: .denied),
                                appliedRestriction: TestFixtures.makeAppliedRestriction(
                                    isApplied: isApplied,
                                    ruleRevision: isApplied ? 1 : nil
                                )
                            )
                        )

                        if !isScheduleActive {
                            #expect(decision.presentationState == .inactive)
                            #expect(decision.desiredRestriction == .inactive)
                            #expect(decision.effect == (isApplied ? .removeShield : .none))
                            #expect(decision.reason == .scheduleInactive)
                        } else if !isAuthorized {
                            #expect(
                                decision.presentationState
                                    == .permissionRequired(missingPermissions: [.familyControls])
                            )
                            #expect(decision.effect != .applyShield)
                            #expect(decision.reason == .missingPermissions([.familyControls]))
                        } else if locationState == .outside {
                            #expect(decision.presentationState == .inactive)
                            #expect(decision.desiredRestriction == .inactive)
                            #expect(decision.effect == (isApplied ? .removeShield : .none))
                            #expect(decision.reason == .locationOutside)
                        } else if locationState == .unavailable {
                            #expect(
                                decision.presentationState
                                    == .locationUnavailable(isRestrictionApplied: isApplied)
                            )
                            #expect(decision.desiredRestriction == .preserve)
                            #expect(decision.effect == .none)
                            #expect(decision.reason == .locationUnavailable)
                        } else {
                            #expect(decision.presentationState == .active)
                            #expect(decision.desiredRestriction == .active)
                            #expect(decision.effect == (isApplied ? .none : .applyShield))
                            #expect(decision.reason == .conditionsSatisfied)
                        }
                    }
                }
            }
        }
    }

    @Test("Time ending takes priority over location and authorization problems")
    func scheduleEndHasPriority() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                now: inactiveDate,
                locationCondition: TestFixtures.makeLocationCondition(state: .unavailable),
                authorization: TestFixtures.makeAuthorization(
                    familyControls: .denied,
                    locationAuthorization: .denied,
                    locationAccuracy: .reduced
                ),
                appliedRestriction: TestFixtures.makeAppliedRestriction(
                    isApplied: true,
                    ruleRevision: 1
                )
            )
        )

        #expect(decision.presentationState == .inactive)
        #expect(decision.effect == .removeShield)
        #expect(decision.reason == .scheduleInactive)
    }

    @Test("Unavailable location preserves the actual restriction state", arguments: [true, false])
    func unavailableLocationPreservesRestriction(isApplied: Bool) {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                locationCondition: TestFixtures.makeLocationCondition(state: .unavailable),
                appliedRestriction: TestFixtures.makeAppliedRestriction(
                    isApplied: isApplied,
                    ruleRevision: isApplied ? 1 : nil
                )
            )
        )

        #expect(
            decision.presentationState
                == .locationUnavailable(isRestrictionApplied: isApplied)
        )
        #expect(decision.desiredRestriction == .preserve)
        #expect(decision.effect == .none)
    }

    @Test("A location snapshot from another rule revision is unavailable")
    func mismatchedLocationRevisionPreservesRestriction() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                locationCondition: TestFixtures.makeLocationCondition(ruleRevision: 2),
                appliedRestriction: TestFixtures.makeAppliedRestriction(
                    isApplied: true,
                    ruleRevision: 1
                )
            )
        )

        #expect(decision.presentationState == .locationUnavailable(isRestrictionApplied: true))
        #expect(decision.desiredRestriction == .preserve)
        #expect(decision.effect == .none)
        #expect(decision.reason == .locationRevisionMismatch)
    }

    @Test("An already-applied matching revision does not write the shield again")
    func repeatedActivationHasNoEffect() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                appliedRestriction: TestFixtures.makeAppliedRestriction(
                    isApplied: true,
                    ruleRevision: 1
                )
            )
        )

        #expect(decision.presentationState == .active)
        #expect(decision.effect == .none)
    }

    @Test("A new rule revision reapplies the shield")
    func changedRevisionAppliesRestriction() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                appliedRestriction: TestFixtures.makeAppliedRestriction(
                    isApplied: true,
                    ruleRevision: 0
                )
            )
        )

        #expect(decision.presentationState == .active)
        #expect(decision.effect == .applyShield)
    }

    @Test("Removing an already-inactive shield has no effect")
    func repeatedRemovalHasNoEffect() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                locationCondition: TestFixtures.makeLocationCondition(state: .outside),
                appliedRestriction: TestFixtures.makeAppliedRestriction()
            )
        )

        #expect(decision.presentationState == .inactive)
        #expect(decision.effect == .none)
    }

    @Test("All required authorization problems are reported")
    func missingPermissionsAreCombined() {
        let decision = RestrictionStateMachine.evaluate(
            makeInput(
                authorization: TestFixtures.makeAuthorization(
                    familyControls: .denied,
                    locationAuthorization: .whenInUse,
                    locationAccuracy: .reduced,
                    backgroundRefresh: .denied
                )
            )
        )

        let expected: Set<RequiredPermission> = [
            .familyControls,
            .alwaysLocation,
            .fullAccuracy,
        ]
        #expect(decision.presentationState == .permissionRequired(missingPermissions: expected))
        #expect(decision.effect != .applyShield)
        #expect(decision.reason == .missingPermissions(expected))
    }

    private var inactiveDate: Date {
        TestFixtures.calendar.date(byAdding: .hour, value: 3, to: TestFixtures.now)!
    }

    private func makeInput(
        rule: RestrictionRuleSnapshot? = TestFixtures.makeRule(),
        now: Date = TestFixtures.now,
        locationCondition: LocationConditionSnapshot = TestFixtures.makeLocationCondition(),
        authorization: AuthorizationSnapshot = TestFixtures.makeAuthorization(),
        appliedRestriction: AppliedRestrictionState = TestFixtures.makeAppliedRestriction()
    ) -> EvaluationInput {
        EvaluationInput(
            rule: rule,
            now: now,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.timeZone,
            locationCondition: locationCondition,
            authorization: authorization,
            appliedRestriction: appliedRestriction
        )
    }
}
