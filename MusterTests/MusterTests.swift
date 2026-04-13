//
//  MusterTests.swift
//  MusterTests
//
//  Created by Ashley Williams on 4/3/2026.
//

import Testing
@testable import Muster

struct MusterTests {

    @MainActor
    @Test func smartETAEstimatorShowsRecalcWhenDistanceMissing() async throws {
        let estimator = SmartETAEstimator()

        estimator.update(distance: nil, at: Date(timeIntervalSince1970: 0))

        #expect(estimator.etaSeconds == nil)
        #expect(estimator.isRecalculating)
        #expect(estimator.displayText == "Recalc")
    }

    @MainActor
    @Test func smartETAEstimatorShowsArrivingInsideArrivalThreshold() async throws {
        let estimator = SmartETAEstimator(arrivalDistanceMeters: 50, minimumElapsedSeconds: 60)
        let now = Date(timeIntervalSince1970: 0)

        estimator.update(distance: 120, at: now)
        estimator.update(distance: 30, at: now.addingTimeInterval(90))

        #expect(estimator.etaSeconds == 0)
        #expect(estimator.isArriving)
        #expect(!estimator.isRecalculating)
        #expect(estimator.displayText == "Arriving")
    }

}
