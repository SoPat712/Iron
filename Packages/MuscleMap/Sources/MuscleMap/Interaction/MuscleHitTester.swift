//
//  MuscleHitTester.swift
//  MuscleMap
//
//  Public hit-testing facade for clients that need a gesture recognizer outside
//  BodyView. The renderer remains the single source of truth for path data and
//  coordinate transforms.
//

import SwiftUI

/// Resolves a point in a rendered body map to its underlying muscle region.
public enum MuscleHitTester {

    /// Returns the muscle and anatomical side under `point`, or `nil` when the
    /// point is outside the rendered body paths.
    ///
    /// The `size` must be the local size of the corresponding `BodyView`.
    /// Sub-groups follow BodyView's default behavior and resolve to their parent
    /// muscle where appropriate.
    public static func muscle(
        at point: CGPoint,
        in size: CGSize,
        gender: BodyGender = .male,
        side: BodySide = .front
    ) -> (Muscle, MuscleSide)? {
        BodyRenderer(
            gender: gender,
            side: side,
            highlights: [:],
            style: .default,
            selectedMuscles: [],
            hideSubGroups: true
        ).hitTest(at: point, in: size)
    }
}
