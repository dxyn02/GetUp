import Foundation

enum RestrictionStateMachine {
    static func evaluate(_ input: EvaluationInput) -> EvaluationDecision {
        guard let rule = input.rule else {
            return inactiveDecision(
                presentationState: .configurationRequired,
                reason: .configurationMissing,
                appliedRestriction: input.appliedRestriction
            )
        }

        guard rule.isEnabled else {
            return inactiveDecision(
                presentationState: .inactive,
                reason: .ruleDisabled,
                appliedRestriction: input.appliedRestriction
            )
        }

        guard isScheduleActive(
            rule: rule,
            at: input.now,
            calendar: input.calendar,
            timeZone: input.timeZone
        ) else {
            return inactiveDecision(
                presentationState: .inactive,
                reason: .scheduleInactive,
                appliedRestriction: input.appliedRestriction
            )
        }

        let missingPermissions = missingPermissions(in: input.authorization)
        guard missingPermissions.isEmpty else {
            return EvaluationDecision(
                presentationState: .permissionRequired(
                    missingPermissions: missingPermissions
                ),
                desiredRestriction: .preserve,
                effect: .none,
                reason: .missingPermissions(missingPermissions)
            )
        }

        guard input.locationCondition.ruleRevision == rule.revision else {
            return unavailableLocationDecision(
                appliedRestriction: input.appliedRestriction,
                reason: .locationRevisionMismatch
            )
        }

        switch input.locationCondition.state {
        case .inside:
            let alreadyAppliedForCurrentRule = input.appliedRestriction.isApplied
                && input.appliedRestriction.ruleRevision == rule.revision

            return EvaluationDecision(
                presentationState: .active,
                desiredRestriction: .active,
                effect: alreadyAppliedForCurrentRule ? .none : .applyShield,
                reason: .conditionsSatisfied
            )
        case .outside:
            return inactiveDecision(
                presentationState: .inactive,
                reason: .locationOutside,
                appliedRestriction: input.appliedRestriction
            )
        case .unavailable:
            return unavailableLocationDecision(
                appliedRestriction: input.appliedRestriction,
                reason: .locationUnavailable
            )
        }
    }

    private static func inactiveDecision(
        presentationState: RestrictionPresentationState,
        reason: EvaluationReason,
        appliedRestriction: AppliedRestrictionState
    ) -> EvaluationDecision {
        EvaluationDecision(
            presentationState: presentationState,
            desiredRestriction: .inactive,
            effect: appliedRestriction.isApplied ? .removeShield : .none,
            reason: reason
        )
    }

    private static func unavailableLocationDecision(
        appliedRestriction: AppliedRestrictionState,
        reason: EvaluationReason
    ) -> EvaluationDecision {
        EvaluationDecision(
            presentationState: .locationUnavailable(
                isRestrictionApplied: appliedRestriction.isApplied
            ),
            desiredRestriction: .preserve,
            effect: .none,
            reason: reason
        )
    }

    private static func missingPermissions(
        in authorization: AuthorizationSnapshot
    ) -> Set<RequiredPermission> {
        var permissions: Set<RequiredPermission> = []

        if authorization.familyControls != .approved {
            permissions.insert(.familyControls)
        }
        if authorization.locationAuthorization != .always {
            permissions.insert(.alwaysLocation)
        }
        if authorization.locationAccuracy != .full {
            permissions.insert(.fullAccuracy)
        }

        return permissions
    }

    private static func isScheduleActive(
        rule: RestrictionRuleSnapshot,
        at date: Date,
        calendar inputCalendar: Calendar,
        timeZone: TimeZone
    ) -> Bool {
        var calendar = inputCalendar
        calendar.timeZone = timeZone

        let dateComponents = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard
            let hour = dateComponents.hour,
            let minute = dateComponents.minute,
            let weekdayValue = dateComponents.weekday,
            let currentWeekday = weekday(for: weekdayValue)
        else {
            return false
        }

        let currentMinute = hour * 60 + minute
        let startMinute = rule.startTime.hour * 60 + rule.startTime.minute
        let endMinute = rule.endTime.hour * 60 + rule.endTime.minute

        guard startMinute != endMinute else {
            return false
        }

        if startMinute < endMinute {
            return rule.weekdays.contains(currentWeekday)
                && currentMinute >= startMinute
                && currentMinute < endMinute
        }

        if currentMinute >= startMinute {
            return rule.weekdays.contains(currentWeekday)
        }

        guard
            currentMinute < endMinute,
            let previousDate = calendar.date(byAdding: .day, value: -1, to: date),
            let previousWeekdayValue = calendar.dateComponents(
                [.weekday],
                from: previousDate
            ).weekday,
            let previousWeekday = weekday(for: previousWeekdayValue)
        else {
            return false
        }

        return rule.weekdays.contains(previousWeekday)
    }

    private static func weekday(for calendarWeekday: Int) -> Weekday? {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
