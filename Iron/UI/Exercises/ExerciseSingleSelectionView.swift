//
//  ExerciseSingleSelectionView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 20.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct ExerciseSingleSelectionView: View {
    var exerciseGroups: [ExerciseGroup]
    var onSelection: (Exercise) -> Void
    
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

                        ForEach(exerciseGroup.exercises, id: \.self) { exercise in
                            Button {
                                onSelection(exercise)
                            } label: {
                                selectionRow(exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
            }
        }
    }

    private func selectionRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 13) {
            ExerciseDiagramThumbnail(exercise: exercise, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(IronTheme.primaryText)
                    .lineLimit(2)
                Text(exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized)
                    .font(.system(size: 12))
                    .foregroundColor(IronTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(IronTheme.accent)
        }
        .padding(.horizontal, IronTheme.horizontalPadding)
        .padding(.vertical, 9)
        .background(IronTheme.background)
        .overlay(IronHairline(), alignment: .bottom)
    }
}

#if DEBUG
struct ExerciseSingleSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseSingleSelectionView(exerciseGroups: ExerciseStore.splitIntoMuscleGroups(exercises: ExerciseStore.shared.shownExercises)) { _ in }
    }
}
#endif
