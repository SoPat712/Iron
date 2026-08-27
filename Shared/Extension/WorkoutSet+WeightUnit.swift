//
//  WorkoutSet+WeightUnit.swift
//  Iron
//
//  Created by Karim Abou Zeid on 05.12.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import WorkoutDataKit

extension WorkoutSet {
    func displayTitle(weightUnit: WeightUnit) -> String {
        displayTitle(unit: weightUnit.unit, formatter: weightUnit.formatter)
    }

    /// The compact result shown anywhere a completed set is summarized.
    /// Imported cardio and bodyweight sets should never degrade to `0 lb × reps`.
    func resultTitle(weightUnit: WeightUnit) -> String {
        if let distance = distanceValue {
            let distanceTitle = Self.distanceTitle(distance, weightUnit: weightUnit)
            if let duration = durationValue {
                return "\(distanceTitle) · \(Self.durationTitle(duration))"
            }
            return distanceTitle
        }

        if let duration = durationValue {
            if weightValue > 0 {
                let weight = WeightUnit.format(weight: weightValue, from: .metric, to: weightUnit)
                return "\(weight) · \(Self.durationTitle(duration))"
            }
            return Self.durationTitle(duration)
        }

        if weightValue > 0 {
            return displayTitle(weightUnit: weightUnit)
        }

        if repetitionsValue > 0 {
            return "\(repetitionsValue) reps"
        }

        return "—"
    }
    
    func logTitle(weightUnit: WeightUnit) -> String {
        logTitle(unit: weightUnit.unit, formatter: weightUnit.formatter)
    }

    private static func durationTitle(_ seconds: TimeInterval) -> String {
        let roundedSeconds = Int(max(seconds, 0).rounded())
        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let remainingSeconds = roundedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private static func distanceTitle(_ meters: Double, weightUnit: WeightUnit) -> String {
        switch weightUnit {
        case .metric:
            if meters >= 1_000 {
                return String(format: "%.2f km", meters / 1_000)
            }
            return String(format: "%.0f m", meters)
        case .imperial:
            let miles = Measurement(value: meters, unit: UnitLength.meters)
                .converted(to: .miles).value
            if miles >= 0.1 {
                return String(format: "%.2f mi", miles)
            }
            let feet = Measurement(value: meters, unit: UnitLength.meters)
                .converted(to: .feet).value
            return String(format: "%.0f ft", feet)
        }
    }
}
