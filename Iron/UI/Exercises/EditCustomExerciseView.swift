//
//  CreateCustomExerciseView.swift
//  Iron
//
//  Created by Karim Abou Zeid on 17.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct CustomExerciseSaveFailure: Identifiable {
    let id = UUID()
    let error: Error
}

struct EditCustomExerciseView: View {
    struct ExerciseValues {
        var title: String
        var description: String
        var muscles: Set<ExerciseMuscle>
        var type: Exercise.ExerciseType
        var stepsText: String = ""
        var tipsText: String = ""

        var steps: [String] {
            Self.instructionItems(from: stepsText)
        }

        var tips: [String] {
            Self.instructionItems(from: tipsText)
        }

        private static func instructionItems(from text: String) -> [String] {
            text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        
        struct ExerciseMuscle: Hashable {
            enum MuscleType: CaseIterable, Hashable {
                case primary
                case secondary

                var title: String {
                    switch self {
                    case .primary: return "Primary"
                    case .secondary: return "Secondary"
                    }
                }
            }
            
            let type: MuscleType
            let muscle: String
        }
    }
    
    @Binding var exerciseValues: ExerciseValues
    var titleValidationMessage: String? = nil
    var onSelectMuscles: () -> Void = {}
    var usesModalSurface = false
    
    private var primaryMuscles: [ExerciseValues.ExerciseMuscle] {
        exerciseValues.muscles
            .map { $0 }
            .sorted { $0.shortDisplayTitle < $1.shortDisplayTitle }
            .filter { $0.type == .primary }
    }
    
    private var secondaryMuscles: [ExerciseValues.ExerciseMuscle] {
        exerciseValues.muscles
            .map { $0 }
            .sorted { $0.shortDisplayTitle < $1.shortDisplayTitle }
            .filter { $0.type == .secondary }
    }

    private var hasPrimaryMuscle: Bool {
        !primaryMuscles.isEmpty
    }

    private var typePopupActions: [IronPopupAction] {
        Exercise.ExerciseType.allCases.map { type in
            IronPopupAction(
                id: "type-\(type.title)",
                title: type.title.capitalized,
                systemImage: "dumbbell",
                isSelected: exerciseValues.type == type
            ) {
                exerciseValues.type = type
            }
        }
    }
    
    var body: some View {
        ZStack {
            shellBackground
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    editorCard(title: "Exercise details", detail: "CUSTOM") {
                        VStack(spacing: 10) {
                            TextField("Exercise name", text: $exerciseValues.title)
                                .font(.body.weight(.medium))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 50)
                                .background(editorFieldBackground)

                            TextField(
                                "Description (optional)",
                                text: $exerciseValues.description,
                                axis: .vertical
                            )
                            .font(.body)
                            .lineLimit(2...4)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .frame(minHeight: 54, alignment: .topLeading)
                            .background(editorFieldBackground)

                            if let titleValidationMessage = titleValidationMessage {
                                validationRow(
                                    titleValidationMessage,
                                    systemImage: "exclamationmark.circle.fill"
                                )
                            }
                        }
                    }

                    editorCard(title: "Muscles", detail: "PRIMARY + SECONDARY") {
                        VStack(alignment: .leading, spacing: 14) {
                            if primaryMuscles.isEmpty && secondaryMuscles.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "figure.strengthtraining.traditional")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(IronTheme.accent)
                                        .frame(width: 42, height: 42)
                                        .background(Circle().fill(IronTheme.accentSoft))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("No muscles selected")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(IronTheme.primaryText)
                                        Text("Choose at least one primary muscle. Secondary muscles are optional.")
                                            .font(.caption)
                                            .foregroundColor(IronTheme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            } else {
                                if !primaryMuscles.isEmpty {
                                    selectedMuscleChips(title: "Primary", muscles: primaryMuscles)
                                }
                                if !secondaryMuscles.isEmpty {
                                    selectedMuscleChips(title: "Secondary", muscles: secondaryMuscles)
                                }
                            }

                            Button {
                                onSelectMuscles()
                            } label: {
                                Label("Select Muscles", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(IronSecondaryButtonStyle())

                            if !hasPrimaryMuscle {
                                validationRow(
                                    "A primary muscle is required to power muscle maps and statistics.",
                                    systemImage: "figure.strengthtraining.traditional"
                                )
                            }
                        }
                    }

                    editorCard(title: "Equipment style", detail: "SETUP") {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundColor(IronTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(IronTheme.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Equipment style")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(IronTheme.primaryText)
                                Text("Controls rest defaults and barbell tools")
                                    .font(.caption)
                                    .foregroundColor(IronTheme.secondaryText)
                            }
                            Spacer(minLength: 8)
                            IronPopupMenu(
                                title: "Equipment style",
                                actions: typePopupActions,
                                arrowEdge: .bottom
                            ) {
                                HStack(spacing: 7) {
                                    Text(exerciseValues.type.title.capitalized)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.bold))
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(IronTheme.accent)
                                .padding(.horizontal, 12)
                                .frame(minHeight: IronTheme.controlHeight)
                                .background(Capsule(style: .continuous).fill(IronTheme.accentSoft))
                            }
                        }
                    }

                    editorCard(title: "How to", detail: "OPTIONAL") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "list.number")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(IronTheme.accent)
                                    .frame(width: 40, height: 40)
                                    .background(IronTheme.accentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Add your own instructions")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(IronTheme.primaryText)
                                    Text("Use one line for each step or coaching cue. They appear in the exercise’s How to tab.")
                                        .font(.caption)
                                        .foregroundColor(IronTheme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            instructionField(
                                title: "Steps",
                                placeholder: "One instruction per line",
                                text: $exerciseValues.stepsText,
                                systemImage: "list.number"
                            )
                            instructionField(
                                title: "Coach cues",
                                placeholder: "One coaching cue per line",
                                text: $exerciseValues.tipsText,
                                systemImage: "lightbulb.fill"
                            )
                        }
                    }
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
        }
        .ironScreen()
    }

    private var editorFieldBackground: some View {
        RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
            .fill(IronTheme.field)
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .stroke(IronTheme.outline.opacity(0.38), lineWidth: 1)
            )
    }

    private func editorCard<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            IronSectionTitle(title: title, detail: detail)
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .stroke(IronTheme.outline.opacity(0.36), lineWidth: 1)
        )
    }

    private func validationRow(_ message: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundColor(IronTheme.warning)
                .padding(.top, 1)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundColor(IronTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instructionField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.65)
                .foregroundColor(IronTheme.secondaryText)

            TextField(placeholder, text: text, axis: .vertical)
                .font(.body)
                .textInputAutocapitalization(.sentences)
                .lineLimit(3...7)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 84, alignment: .topLeading)
                .background(editorFieldBackground)
        }
    }

    @ViewBuilder
    private var shellBackground: some View {
        if usesModalSurface {
            IronModalBackground()
        } else {
            IronScreenBackground()
        }
    }

    private func selectedMuscleChips(
        title: String,
        muscles: [ExerciseValues.ExerciseMuscle]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(IronTheme.secondaryText)
                Spacer()
                Text("\(muscles.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.accent)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(muscles, id: \.self) { muscle in
                    IronChip(
                        title: muscle.shortDisplayTitle,
                        icon: "checkmark",
                        isSelected: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

extension EditCustomExerciseView.ExerciseValues.ExerciseMuscle {
    var shortDisplayTitle: String {
        let title = Exercise.commonMuscleName(for: muscle) ?? "other"
        return title.capitalized
    }
    
    var displayTitle: String {
        var title = shortDisplayTitle
        if title.lowercased() != muscle.lowercased() {
            title.append(" (\(muscle))")
        }
        return title.capitalized
    }
}

struct MuscleSelectionView: View {
    private struct MuscleOption: Identifiable, Hashable {
        let id: String
        let title: String
        let aliases: [String]
    }

    var muscles: [String]
    @Binding var selection: Set<EditCustomExerciseView.ExerciseValues.ExerciseMuscle>
    var usesModalSurface = false

    @State private var activeRole: EditCustomExerciseView.ExerciseValues.ExerciseMuscle.MuscleType = .primary
    @State private var search = ""

    private var options: [MuscleOption] {
        let grouped = Dictionary(grouping: muscles) { muscle in
            canonicalName(for: muscle)
        }

        return grouped.map { name, aliases in
            MuscleOption(
                id: name,
                title: name.capitalized,
                aliases: aliases.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var filteredOptions: [MuscleOption] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { option in
            option.title.localizedCaseInsensitiveContains(query) ||
                option.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var primaryCount: Int {
        selectedOptionCount(for: .primary)
    }

    private var secondaryCount: Int {
        selectedOptionCount(for: .secondary)
    }

    var body: some View {
        ZStack {
            shellBackground
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    selectionSummary
                    rolePicker
                    searchField
                    muscleGrid
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .ironScreen()
    }

    @ViewBuilder
    private var shellBackground: some View {
        if usesModalSurface {
            IronModalBackground()
        } else {
            IronScreenBackground()
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Muscle focus")
                    .font(.title3.weight(.bold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Choose a role, then tap each muscle. A muscle can only have one role.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                countTile(
                    title: "Primary",
                    count: primaryCount,
                    icon: "scope",
                    tint: IronTheme.accent
                )
                countTile(
                    title: "Secondary",
                    count: secondaryCount,
                    icon: "circle.dotted",
                    tint: IronTheme.accent
                )
            }
        }
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADDING AS")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundColor(IronTheme.secondaryText)

            HStack(spacing: 4) {
                ForEach(EditCustomExerciseView.ExerciseValues.ExerciseMuscle.MuscleType.allCases, id: \.self) { role in
                    let isActive = activeRole == role
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            activeRole = role
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: role == .primary ? "scope" : "circle.dotted")
                            Text(role.title)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isActive ? IronTheme.onAccent : IronTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isActive ? roleTint(role) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule(style: .continuous).fill(IronTheme.field))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(IronTheme.secondaryText)
                .accessibilityHidden(true)
            TextField("Search muscles", text: $search)
                .foregroundColor(IronTheme.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(IronTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Capsule(style: .continuous).fill(IronTheme.field))
    }

    @ViewBuilder
    private var muscleGrid: some View {
        if filteredOptions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(IronTheme.secondaryText)
                Text("No muscles found")
                    .font(.headline)
                    .foregroundColor(IronTheme.primaryText)
                Text("Try a broader anatomical or common name.")
                    .font(.subheadline)
                    .foregroundColor(IronTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(search.isEmpty ? "All muscles" : "Results")
                        .font(.headline)
                        .foregroundColor(IronTheme.primaryText)
                    Spacer()
                    Text("\(filteredOptions.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundColor(IronTheme.secondaryText)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(filteredOptions) { option in
                        muscleButton(option)
                    }
                }
            }
        }
    }

    private func muscleButton(_ option: MuscleOption) -> some View {
        let selectedRole = role(for: option)
        let isSelected = selectedRole != nil

        return Button {
            toggle(option)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedRole == .primary ? "scope" : (selectedRole == .secondary ? "circle.dotted" : "plus"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isSelected ? roleTint(selectedRole!) : IronTheme.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isSelected ? roleTint(selectedRole!).opacity(0.14) : IronTheme.field)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(selectedRole?.title ?? "Not selected")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(isSelected ? roleTint(selectedRole!) : IronTheme.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(isSelected ? roleTint(selectedRole!).opacity(0.09) : IronTheme.raisedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .stroke(isSelected ? roleTint(selectedRole!).opacity(0.48) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(selectedRole.map { "Selected as \($0.title.lowercased())" } ?? "Not selected")
        .accessibilityHint("Adds or removes this muscle as \(activeRole.title.lowercased())")
    }

    private func countTile(title: String, count: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.primaryText)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(IronTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
    }

    private func canonicalName(for muscle: String) -> String {
        (Exercise.commonMuscleName(for: muscle) ?? muscle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func role(
        for option: MuscleOption
    ) -> EditCustomExerciseView.ExerciseValues.ExerciseMuscle.MuscleType? {
        if selection.contains(where: { canonicalName(for: $0.muscle) == option.id && $0.type == .primary }) {
            return .primary
        }
        if selection.contains(where: { canonicalName(for: $0.muscle) == option.id && $0.type == .secondary }) {
            return .secondary
        }
        return nil
    }

    private func roleTint(
        _ role: EditCustomExerciseView.ExerciseValues.ExerciseMuscle.MuscleType
    ) -> Color {
        IronTheme.accent
    }

    private func selectedOptionCount(
        for role: EditCustomExerciseView.ExerciseValues.ExerciseMuscle.MuscleType
    ) -> Int {
        Set(selection.compactMap { muscle in
            muscle.type == role ? canonicalName(for: muscle.muscle) : nil
        }).count
    }

    private func toggle(_ option: MuscleOption) {
        let existing = selection.filter { canonicalName(for: $0.muscle) == option.id }
        let wasSelectedForActiveRole = existing.contains { $0.type == activeRole }
        let preservedRawValue = existing.first?.muscle

        selection.subtract(existing)

        if !wasSelectedForActiveRole {
            let representative = preservedRawValue
                ?? option.aliases.first(where: { $0.localizedCaseInsensitiveCompare(option.id) == .orderedSame })
                ?? option.aliases.first

            if let representative = representative {
                selection.insert(
                    EditCustomExerciseView.ExerciseValues.ExerciseMuscle(
                        type: activeRole,
                        muscle: representative
                    )
                )
            }
        }

        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }
}

#if DEBUG
struct CreateCustomExerciseView_Previews: PreviewProvider {
    static var previews: some View {
        EditCustomExerciseView(exerciseValues: .constant(.init(title: "", description: "", muscles: Set(), type: .other)))
            .mockEnvironment(weightUnit: .metric)
    }
}
#endif
