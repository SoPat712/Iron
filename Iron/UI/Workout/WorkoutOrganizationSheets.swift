import SwiftUI
import CoreData
import WorkoutDataKit

/// Sheet for choosing the members of a superset without mutating the workout
/// until the parent confirms the transaction.
struct WorkoutSupersetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var exerciseStore: ExerciseStore

    let source: WorkoutExercise
    let exercises: [WorkoutExercise]
    let onSave: (Set<NSManagedObjectID>) -> Bool
    let onRemove: (() -> Bool)?

    @State private var selectedPartnerIDs: Set<NSManagedObjectID>

    init(
        source: WorkoutExercise,
        exercises: [WorkoutExercise],
        onSave: @escaping (Set<NSManagedObjectID>) -> Bool,
        onRemove: (() -> Bool)? = nil
    ) {
        self.source = source
        self.exercises = exercises
        self.onSave = onSave
        self.onRemove = onRemove

        let sourceID = source.objectID
        let sourceGroupID = source.supersetUuid
        let initialSelection: Set<NSManagedObjectID>
        if let sourceGroupID {
            initialSelection = Set(
                exercises
                    .filter {
                        $0.objectID != sourceID
                            && !$0.isDeleted
                            && $0.supersetUuid == sourceGroupID
                    }
                    .map(\.objectID)
            )
        } else {
            initialSelection = []
        }
        _selectedPartnerIDs = State(initialValue: initialSelection)
    }

    private var sourceID: NSManagedObjectID {
        source.objectID
    }

    private var orderedWorkoutExercises: [WorkoutExercise] {
        var result: [WorkoutExercise] = []
        var seenIDs = Set<NSManagedObjectID>()

        for workoutExercise in exercises where !workoutExercise.isDeleted {
            guard seenIDs.insert(workoutExercise.objectID).inserted else { continue }
            result.append(workoutExercise)
        }

        // Callers normally provide the source in the workout's ordered array.
        // Keeping this fallback first preserves a useful source/member order
        // for previews when a focused source is supplied separately.
        if !seenIDs.contains(sourceID), !source.isDeleted {
            result.insert(source, at: 0)
        }
        return result
    }

    private var candidateExercises: [WorkoutExercise] {
        orderedWorkoutExercises.filter { $0.objectID != sourceID }
    }

    private var selectedMembers: [WorkoutExercise] {
        orderedWorkoutExercises.filter {
            $0.objectID == sourceID || selectedPartnerIDs.contains($0.objectID)
        }
    }

    private var actionTitle: String {
        source.supersetUuid == nil ? "Create Superset" : "Save Superset"
    }

    private var previewItems: [WorkoutSetOrderPreviewItem] {
        guard !selectedPartnerIDs.isEmpty else { return [] }
        let members = selectedMembers
        let maximumSetCount = min(members.map { setCount(for: $0) }.max() ?? 0, 2)
        guard maximumSetCount > 0 else { return [] }

        return (0..<maximumSetCount).flatMap { roundIndex in
            members.enumerated().compactMap { memberIndex, member in
                guard setCount(for: member) > roundIndex else { return nil }
                return WorkoutSetOrderPreviewItem(
                    memberIndex: memberIndex,
                    setNumber: roundIndex + 1,
                    title: member.exercise(in: exerciseStore.exercises)?.title ?? "Unknown Exercise"
                )
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Starting Exercise") {
                    WorkoutOrganizationExerciseInfo(
                        workoutExercise: source,
                        exercise: source.exercise(in: exerciseStore.exercises)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(startingExerciseAccessibilityLabel)
                }

                Section {
                    if previewItems.isEmpty {
                        Text(selectedPartnerIDs.isEmpty
                             ? "Choose a partner to preview the alternating order."
                             : "Add target sets to preview the alternating order.")
                            .font(.footnote)
                            .foregroundStyle(IronTheme.secondaryText)
                            .frame(minHeight: IronTheme.controlHeight, alignment: .leading)
                    } else {
                        previewSequence
                    }
                } header: {
                    Text("Set Order Preview")
                } footer: {
                    Text("Rounds follow workout order; exercises without a set in a round are skipped.")
                }

                Section {
                    if candidateExercises.isEmpty {
                        Text("Add another exercise to create a superset.")
                            .font(.body)
                            .foregroundStyle(IronTheme.secondaryText)
                            .frame(minHeight: IronTheme.controlHeight, alignment: .leading)
                    } else {
                        ForEach(candidateExercises, id: \.objectID) { candidate in
                            candidateRow(candidate)
                        }
                    }
                } header: {
                    Text("Pair With")
                } footer: {
                    Text("Selecting an exercise from another superset includes that whole group.")
                }

                if onRemove != nil {
                    Section {
                        Button("Remove from Superset", role: .destructive) {
                            removeSuperset()
                        }
                        .frame(minHeight: IronTheme.controlHeight, alignment: .leading)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .sensoryFeedback(.selection, trigger: selectedPartnerIDs)
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(selectedPartnerIDs.isEmpty)
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Superset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: WorkoutExercise) -> some View {
        let isSelected = selectedPartnerIDs.contains(candidate.objectID)
        Button {
            withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                toggle(candidate)
            }
        } label: {
            HStack(spacing: 8) {
                WorkoutOrganizationExerciseInfo(
                    workoutExercise: candidate,
                    exercise: candidate.exercise(in: exerciseStore.exercises)
                )

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .foregroundStyle(isSelected ? IronTheme.accent : IronTheme.tertiaryText)
                    .frame(width: IronTheme.iconButtonSize, height: IronTheme.controlHeight)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .frame(minHeight: IronTheme.controlHeight)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(selectionHint(for: candidate))
    }

    private var previewSequence: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // A separate, eager layout also replaces offscreen grid cells when
                // Dynamic Type changes while this List row is already visible.
                VStack(alignment: .leading, spacing: 8) {
                    previewChips
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2),
                    alignment: .leading,
                    spacing: 8
                ) {
                    previewChips
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(previewAccessibilityLabel)
    }

    private var previewChips: some View {
        ForEach(Array(previewItems.enumerated()), id: \.offset) { _, item in
            WorkoutSetOrderPreviewChip(
                marker: memberMarker(for: item.memberIndex),
                setNumber: item.setNumber,
                title: item.title
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewAccessibilityLabel: String {
        let sequence = previewItems.map {
            "\(memberMarker(for: $0.memberIndex))\($0.setNumber) \($0.title)"
        }
        return sequence.isEmpty ? "No set order preview" : "Set order: " + sequence.joined(separator: ", then ")
    }

    private var startingExerciseAccessibilityLabel: String {
        let title = source.exercise(in: exerciseStore.exercises)?.title ?? "Unknown Exercise"
        let count = setCount(for: source)
        return "Starting exercise, \(title), \(count) \(count == 1 ? "set" : "sets")"
    }

    private func selectionHint(for candidate: WorkoutExercise) -> String {
        if let candidateGroupID = candidate.supersetUuid,
           candidateGroupID != source.supersetUuid {
            return "Selects or removes the entire existing superset."
        }
        return "Adds or removes this exercise from the superset."
    }

    private func memberMarker(for index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard letters.indices.contains(index) else { return "\(index + 1)" }
        return String(letters[index])
    }

    private func setCount(for workoutExercise: WorkoutExercise) -> Int {
        workoutExercise.workoutSets?.array
            .compactMap { $0 as? WorkoutSet }
            .filter { !$0.isDeleted }
            .count ?? 0
    }

    private func toggle(_ candidate: WorkoutExercise) {
        guard candidate.objectID != sourceID else { return }

        let belongsToSourceGroup = source.supersetUuid != nil
            && candidate.supersetUuid == source.supersetUuid

        if belongsToSourceGroup || candidate.supersetUuid == nil {
            if selectedPartnerIDs.contains(candidate.objectID) {
                selectedPartnerIDs.remove(candidate.objectID)
            } else {
                selectedPartnerIDs.insert(candidate.objectID)
            }
            return
        }

        guard let candidateGroupID = candidate.supersetUuid else { return }
        let groupIDs = Set(
            orderedWorkoutExercises
                .filter { $0.supersetUuid == candidateGroupID && $0.objectID != sourceID }
                .map(\.objectID)
        )

        if selectedPartnerIDs.contains(candidate.objectID) {
            selectedPartnerIDs.subtract(groupIDs)
        } else {
            selectedPartnerIDs.formUnion(groupIDs)
        }
    }

    private func save() {
        guard onSave(selectedPartnerIDs) else { return }
        dismiss()
    }

    private func removeSuperset() {
        guard let onRemove, onRemove() else { return }
        dismiss()
    }
}

/// Compact native editor for the workout's ordered exercise list.
struct WorkoutArrangeExercisesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore

    let exercises: [WorkoutExercise]
    let onSave: ([NSManagedObjectID]) -> Bool

    @State private var orderedIDs: [NSManagedObjectID]

    init(
        exercises: [WorkoutExercise],
        onSave: @escaping ([NSManagedObjectID]) -> Bool
    ) {
        self.exercises = exercises
        self.onSave = onSave
        _orderedIDs = State(initialValue: exercises.map(\.objectID))
    }

    private var workoutExerciseByID: [NSManagedObjectID: WorkoutExercise] {
        Dictionary(uniqueKeysWithValues: exercises.map { ($0.objectID, $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(orderedIDs.enumerated()), id: \.element) { index, id in
                        arrangedRow(id: id, index: index)
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Drag to reorder. Superset relationships stay with their exercises.")
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        orderedIDs.move(fromOffsets: offsets, toOffset: destination)
    }

    private func move(id: NSManagedObjectID, by offset: Int) {
        guard let index = orderedIDs.firstIndex(of: id) else { return }
        let destination = index + offset
        guard orderedIDs.indices.contains(destination) else { return }

        let insertionOffset = offset > 0 ? destination + 1 : destination
        orderedIDs.move(
            fromOffsets: IndexSet(integer: index),
            toOffset: insertionOffset
        )
    }

    private func save() {
        guard onSave(orderedIDs) else { return }
        dismiss()
    }

    private func arrangedRow(id: NSManagedObjectID, index: Int) -> AnyView {
        guard let workoutExercise = workoutExerciseByID[id] else {
            return AnyView(EmptyView())
        }

        let row = WorkoutOrganizationExerciseInfo(
            workoutExercise: workoutExercise,
            exercise: workoutExercise.exercise(in: exerciseStore.exercises)
        )
        let accessibleRow = row
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: workoutExercise))
            .accessibilityHint("Touch and hold, then drag to reorder.")
        let lastIndex = orderedIDs.count - 1

        if index == 0 && index == lastIndex {
            return AnyView(accessibleRow)
        }
        if index == 0 {
            return AnyView(
                accessibleRow.accessibilityAction(named: Text("Move Down")) {
                    move(id: id, by: 1)
                }
            )
        }
        if index == lastIndex {
            return AnyView(
                accessibleRow.accessibilityAction(named: Text("Move Up")) {
                    move(id: id, by: -1)
                }
            )
        }
        return AnyView(
            accessibleRow
                .accessibilityAction(named: Text("Move Up")) {
                    move(id: id, by: -1)
                }
                .accessibilityAction(named: Text("Move Down")) {
                    move(id: id, by: 1)
                }
        )
    }

    private func accessibilityLabel(for workoutExercise: WorkoutExercise) -> String {
        let title = workoutExercise.exercise(in: exerciseStore.exercises)?.title ?? "Unknown Exercise"
        let count = workoutExercise.workoutSets?.array
            .compactMap { $0 as? WorkoutSet }
            .filter { !$0.isDeleted }
            .count ?? 0
        let relation = workoutExercise.supersetUuid == nil ? "" : ", in a superset"
        return "\(title), \(count) \(count == 1 ? "set" : "sets")\(relation)"
    }
}

private struct WorkoutOrganizationExerciseInfo: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let workoutExercise: WorkoutExercise
    let exercise: Exercise?

    private var setCount: Int {
        workoutExercise.workoutSets?.array
            .compactMap { $0 as? WorkoutSet }
            .filter { !$0.isDeleted }
            .count ?? 0
    }

    private var equipmentTitle: String? {
        guard let exercise, !exercise.equipment.isEmpty else { return nil }
        return exercise.equipment.map { $0.capitalized }.joined(separator: ", ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    thumbnail
                    details
                }
            } else {
                HStack(spacing: 12) {
                    thumbnail
                    details
                }
            }
        }
        .frame(minHeight: IronTheme.controlHeight, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise?.title ?? "Unknown Exercise")
                .font(.headline)
                .foregroundStyle(IronTheme.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(setCount)")
                    .font(.ironMetric(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.metricSets)
                Text(setCount == 1 ? "set" : "sets")
                    .font(.caption)
                    .foregroundStyle(IronTheme.secondaryText)
            }

            if let equipmentTitle {
                Text(equipmentTitle)
                    .font(.caption)
                    .foregroundStyle(IronTheme.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }

            if workoutExercise.supersetUuid != nil {
                Label("Superset", systemImage: "link")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(IronTheme.accent)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let exercise {
            ExerciseDiagramThumbnail(exercise: exercise, size: 52)
        } else {
            Circle()
                .fill(IronTheme.tertiaryFill)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(IronTheme.secondaryText)
                }
                .accessibilityHidden(true)
        }
    }
}

private struct WorkoutSetOrderPreviewItem {
    let memberIndex: Int
    let setNumber: Int
    let title: String
}

private struct WorkoutSetOrderPreviewChip: View {
    let marker: String
    let setNumber: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(marker)\(setNumber)")
                .font(.ironMetric(.caption, weight: .bold))
                .foregroundStyle(IronTheme.accent)
            Text(title)
                .font(.caption2)
                .foregroundStyle(IronTheme.primaryText)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: IronTheme.controlHeight, alignment: .leading)
        .background(
            IronTheme.accentSoft,
            in: RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(marker)\(setNumber), \(title)")
    }
}
