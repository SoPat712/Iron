//
//  Exercise+SwiftUI.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 27.06.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import SwiftUI
import WorkoutDataKit

extension Exercise {
    static func displayName(forMuscleGroup muscleGroup: String) -> String {
        switch muscleGroup.lowercased() {
        case "abdominals": return "Abs"
        case "arms": return "Arms"
        case "shoulders": return "Shoulders"
        case "back": return "Back"
        case "legs": return "Legs"
        case "chest": return "Chest"
        case "cardio": return "Cardio"
        default: return muscleGroup.capitalized
        }
    }

    static func colorFor(muscleGroup: String) -> Color {
        switch muscleGroup {
        case "abdominals":
            return .yellow
        case "arms":
            return .purple
        case "shoulders":
            return .orange
        case "back":
            return .blue
        case "legs":
            return .green
        case "chest":
            return .red
        case "cardio":
            return .pink
        default:
            return .secondary
        }
    }
    
    static func imageFor(muscleGroup: String) -> Image {
        switch muscleGroup {
        case "abdominals":
            return Image(systemName: "a.circle.fill")
        case "arms":
            return Image(systemName: "a.circle.fill")
        case "shoulders":
            return Image(systemName: "s.circle.fill")
        case "back":
            return Image(systemName: "b.circle.fill")
        case "legs":
            return Image(systemName: "l.circle.fill")
        case "chest":
            return Image(systemName: "c.circle.fill")
        case "cardio":
            return Image(systemName: "heart.circle.fill")
        default:
            return Image(systemName: "dumbbell.fill")
        }
    }
}

extension Exercise {
    var muscleGroupImage: some View {
        Exercise.imageFor(muscleGroup: muscleGroup).foregroundColor(Exercise.colorFor(muscleGroup: muscleGroup))
    }
    
    var muscleGroupColor: Color {
        Exercise.colorFor(muscleGroup: muscleGroup)
    }
}

/// Compact named muscle tags for history and recents. Letter-circle badges
/// hid the actual groups behind L / c / O.
struct MuscleGroupPills: View {
    let groups: [String]
    var limit: Int = 3

    private var visible: [String] {
        Array(
            groups
                .filter { !$0.isEmpty && $0.lowercased() != "other" }
                .prefix(limit)
        )
    }

    var body: some View {
        if !visible.isEmpty {
            HStack(spacing: 6) {
                ForEach(visible, id: \.self) { group in
                    Text(Exercise.displayName(forMuscleGroup: group))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Color(UIColor.secondarySystemFill),
                            in: Capsule(style: .continuous)
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(visible.map { Exercise.displayName(forMuscleGroup: $0) }.joined(separator: ", "))
        }
    }
}
