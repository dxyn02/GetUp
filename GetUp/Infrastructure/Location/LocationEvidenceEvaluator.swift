enum LocationEvidenceEvaluator {
    static func evaluate(
        distanceMeters: Double,
        horizontalAccuracyMeters: Double,
        radiusMeters: Double
    ) -> LocationConditionState {
        guard
            distanceMeters.isFinite,
            horizontalAccuracyMeters.isFinite,
            radiusMeters.isFinite,
            distanceMeters >= 0,
            horizontalAccuracyMeters >= 0,
            radiusMeters >= 0
        else {
            return .unavailable
        }

        if distanceMeters + horizontalAccuracyMeters <= radiusMeters {
            return .inside
        }

        if max(0, distanceMeters - horizontalAccuracyMeters) > radiusMeters {
            return .outside
        }

        return .unavailable
    }
}
