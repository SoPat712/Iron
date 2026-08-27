//
//  MuscleGroupSectionedExercisesView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 04.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct MuscleGroupSectionedExercisesView : View {
    var exerciseGroups: [ExerciseGroup]
    
    var body: some View {
        ZStack {
            IronScreenBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(exerciseGroups) { exerciseGroup in
                        Text(exerciseGroup.title.capitalized)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(IronTheme.primaryText)
                            .padding(.horizontal, IronTheme.horizontalPadding)
                            .padding(.top, 20)
                            .padding(.bottom, 8)

                    ForEach(exerciseGroup.exercises) { exercise in
                        NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                            ExerciseLibraryRow(exercise: exercise)
                        }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
    }
}

#if DEBUG
struct MuscleGroupSectionedExercisesView_Previews : PreviewProvider {
    static var previews: some View {
        NavigationView {
            MuscleGroupSectionedExercisesView(exerciseGroups: ExerciseStore.splitIntoMuscleGroups(exercises: ExerciseStore.shared.shownExercises))
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
