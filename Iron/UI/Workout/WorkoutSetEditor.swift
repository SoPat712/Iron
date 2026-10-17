//
//  WorkoutSetEditor.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 29.06.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

private enum KeyboardType {
    case weight
    case repetitions
    case none
}

struct WorkoutSetEditor : View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var exerciseStore: ExerciseStore
    
    @ObservedObject var workoutSet: WorkoutSet
    var onDone: () -> Void = {}
    
    @State private var showHelpAlert = false
    
    @State private var activeSheet: SheetType?
    @State private var showKeyboard: KeyboardType = .none
    @State private var alwaysShowDecimalSeparator = false
    @State private var minimumFractionDigits = 0
    
    // used to immediatelly update the weight & rep texts so the keyboard feels more smooth
    @ObservedObject private var refresher = Refresher()

    private enum SheetType: String, Identifiable {
        case details
        case plates
        case warmups

        var id: String { rawValue }
    }
    
    private var workoutSetWeight: Binding<Double?> {
        Binding(
            get: {
                WeightUnit.convert(weight: self.workoutSet.weightValue, from: .metric, to: self.settingsStore.weightUnit)
            },
            set: { newValue in
                self.workoutSet.weightValue = max(min(WeightUnit.convert(weight: newValue ?? 0, from: self.settingsStore.weightUnit, to: .metric), WorkoutSet.MAX_WEIGHT), 0)
                self.refresher.refresh()
            }
        )
    }
    
    private var workoutSetRepetitions: Binding<Double?> {
        Binding(
            get: {
                Double(self.workoutSet.repetitionsValue)
            },
            set: { newValue in
                self.workoutSet.repetitionsValue = Int16(max(min(newValue ?? 0, Double(WorkoutSet.MAX_REPETITIONS)), 0))
                self.refresher.refresh()
            }
        )
    }

    private var weightNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = true
        formatter.maximumFractionDigits = settingsStore.weightUnit.maximumFractionDigits
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.alwaysShowsDecimalSeparator = alwaysShowDecimalSeparator
        return formatter
    }
    
    private func textButton(label: Text, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, minHeight: IronTheme.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(color)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var tagButton: some View {
        Button(action: {
            self.activeSheet = .details
        }) {
            HStack(spacing: 0) {
                Image(systemName: "tag")
                    .frame(width: IronTheme.controlHeight, height: IronTheme.controlHeight)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set options")
    }
    
    private var doneButton: some View {
        textButton(label: Text(workoutSet.isCompleted ? "Ok" : "Complete Set").foregroundColor(IronTheme.onAccent), color: IronTheme.accent, action: {
            self.onDone()
        })
    }
    
    private var nextButton: some View {
        textButton(label: Text("Next").foregroundColor(IronTheme.onAccent), color: IronTheme.accent, action: { self.showKeyboard = .repetitions })
    }
        
    private var hideKeyboardButton: some View {
        Button(action: {
            withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                self.showKeyboard = .none
            }
        }) {
            HStack {
                Spacer()
                ZStack {
                    Text("More") // placeholder for button size
                        .foregroundColor(.clear)
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.compact.down")
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .frame(minHeight: IronTheme.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                    .fill(IronTheme.field)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide keyboard")
    }
    
    private var weightStepSize: Double {
        // TODO: let the user configure this for barbell, dumbell and others
        (workoutSet.workoutExercise?.exercise(in: exerciseStore.exercises)?.type == .barbell) ? settingsStore.weightUnit.barbellIncrement : 1
    }
    
    private var weightDragger: some View {
        Dragger(
            value: workoutSetWeight,
            numberFormatter: weightNumberFormatter,
            unit: settingsStore.weightUnit.unit.symbol,
            stepSize: weightStepSize,
            minValue: 0,
            maxValue: WeightUnit.convert(weight: WorkoutSet.MAX_WEIGHT, from: .metric, to: settingsStore.weightUnit),
            showCursor: showKeyboard == .weight,
            onDragStep: { _ in
                self.alwaysShowDecimalSeparator = false
                self.minimumFractionDigits = self.settingsStore.weightUnit.defaultFractionDigits
            },
            onDragCompleted: {
                self.alwaysShowDecimalSeparator = false
                self.minimumFractionDigits = 0
            },
            onTextTapped: {
                if self.showKeyboard == .none {
                    withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                        self.showKeyboard = .weight
                    }
                } else {
                    self.showKeyboard = .weight
                }
            })
    }
    
    private var repetitionsDragger: some View {
        Dragger(
            value: workoutSetRepetitions,
            unit: "reps",
            minValue: 0,
            maxValue: Double(WorkoutSet.MAX_REPETITIONS),
            showCursor: showKeyboard == .repetitions,
            onTextTapped: {
                if self.showKeyboard == .none {
                    withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                        self.showKeyboard = .repetitions
                    }
                } else {
                    self.showKeyboard = .repetitions
                }
        })
    }
    
    private var moreSheet: some View {
        NavigationStack {
            MoreView(workoutSet: workoutSet)
                .navigationTitle(workoutSet.displayTitle(weightUnit: settingsStore.weightUnit))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                        self.activeSheet = nil
                    }
                    }
                }
        }
    }

    @ViewBuilder private func sheet(for type: SheetType) -> some View {
        switch type {
        case .details:
            moreSheet
        case .plates:
            IronUtilitySheet(
                title: "Plate Calculator",
                subtitle: "",
                systemImage: "plusminus",
                onClose: { activeSheet = nil }
            ) {
                PlateCalculatorView(
                    unit: settingsStore.weightUnit,
                    initialTarget: max(workoutSetWeight.wrappedValue ?? 0, settingsStore.weightUnit.barbellWeight),
                    onApply: { value in
                        workoutSetWeight.wrappedValue = value
                        activeSheet = nil
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case .warmups:
            IronUtilitySheet(
                title: "Warm-Up Calculator",
                subtitle: "",
                systemImage: "flame",
                onClose: { activeSheet = nil }
            ) {
                WarmupCalculatorView(
                    unit: settingsStore.weightUnit,
                    workingWeight: max(workoutSetWeight.wrappedValue ?? 0, settingsStore.weightUnit.barbellWeight),
                    onAdd: addWarmupSets
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func addWarmupSets(_ recommendations: [WarmupRecommendation]) {
        guard let exercise = workoutSet.workoutExercise,
              let context = workoutSet.managedObjectContext,
              exercise.workout?.isCurrentWorkout == true else { return }

        var insertionIndex = 0
        for recommendation in recommendations {
            let set = WorkoutSet.create(context: context)
            set.tagValue = .warmUp
            set.weightValue = WeightUnit.convert(weight: recommendation.weight, from: settingsStore.weightUnit, to: .metric)
            set.repetitionsValue = Int16(recommendation.repetitions)
            set.isCompleted = false
            exercise.insertIntoWorkoutSets(set, at: insertionIndex)
            insertionIndex += 1
        }
        context.saveOrCrash()
        activeSheet = nil
    }

    private var barbellTools: some View {
        HStack(spacing: 10) {
            Button(action: { activeSheet = .plates }) {
                Label("Plates", systemImage: "plusminus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: { activeSheet = .warmups }) {
                Label("Warm-up", systemImage: "flame.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var keyboard: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                NumericKeyboard(
                    value: self.showKeyboard == .weight ? self.workoutSetWeight : self.workoutSetRepetitions,
                    alwaysShowDecimalSeparator: self.showKeyboard == .weight ? self.$alwaysShowDecimalSeparator : .constant(false),
                    minimumFractionDigits: self.showKeyboard == .weight ? self.$minimumFractionDigits : .constant(0),
                    maximumFractionDigits: self.showKeyboard == .weight ? self.settingsStore.weightUnit.maximumFractionDigits : 0
                )
                VStack(spacing: 0) {
                    NumericKeyboard.imageActionKeyboardButton(label: Image(systemName: "keyboard.chevron.compact.down"), width: geometry.size.width / 4) {
                        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                            self.showKeyboard = .none
                        }
                    }
                    
                    NumericKeyboard.imageActionKeyboardButton(label: Image(systemName: "questionmark"), width: geometry.size.width / 4) {
                        self.showHelpAlert = true
                    }
                    
                    NumericKeyboard.imageActionKeyboardButton(label: Image(systemName: "tag"), width: geometry.size.width / 4) {
                        self.activeSheet = .details
                    }
                    
                    Button(action: {
                        NumericKeyboard.playButtonSound()
                        if self.showKeyboard == .weight {
                            self.showKeyboard = .repetitions
                        } else if self.showKeyboard == .repetitions {
                            self.onDone()
                            self.showKeyboard = .weight
                        }
                    }) {
                        Image(systemName: self.showKeyboard == .weight ? "arrow.right" : "checkmark")
                            .padding()
                            .foregroundColor(IronTheme.onAccent)
                            .background(
                                RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                    .foregroundColor(Color.accentColor)
                        )
                            .frame(width: geometry.size.width / 4, height: geometry.size.height / 4)
                    }
                }
                .frame(width: geometry.size.width / 4)
            }
        }.frame(height: NumericKeyboard.HEIGHT)
    }
    
    var body: some View {
        VStack { /// no spacing to the keyboard
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    /**
                     NOTE: the draggers shouldn't be too low because
                     1. the thumb would be in an uncomfortable position
                     2. one easily triggers the reachability accessibilty on devices without a home button
                     */
                    weightDragger
                    Divider().frame(height: 44)
//                    Text("×").foregroundColor(Color(.quaternaryLabel))
                    repetitionsDragger
                }
                
                if showKeyboard == .none {
                    if workoutSet.workoutExercise?.workout?.isCurrentWorkout == true,
                       workoutSet.workoutExercise?.exercise(in: exerciseStore.exercises)?.type == .barbell {
                        barbellTools
                    }
                    HStack(spacing: 16) {
                        tagButton
                        doneButton
                    }
                    .padding(.bottom, 8) /// pushes the draggers up and makes the buttons look more centered
                }
            }.padding([.leading, .trailing])
            
            if showKeyboard != .none {
                keyboard
            }
        }
        .padding([.top, .bottom])
//        .drawingGroup() /// fixes visual bug with show/hide animation of this view
        .gesture(DragGesture()
            .onEnded({ drag in
                let width = drag.predictedEndTranslation.width
                let height = drag.predictedEndTranslation.height
                
                if abs(height) > abs(width) {
                    if height > 200 {
                        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                            self.showKeyboard = .none
                        }
                    }
                } else {
                    if width > 200 {
                        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                            self.showKeyboard = .repetitions
                        }
                    } else if width < 200 {
                        withAnimation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion)) {
                            self.showKeyboard = .weight
                        }
                    }
                }
            })
        )
        .sheet(item: $activeSheet) { self.sheet(for: $0) }
        .alert(isPresented: $showHelpAlert) { Alert(title: Text("You can also drag ☰ up and down to adjust the values.")) }
    }
}

struct WarmupRecommendation: Identifiable, Hashable {
    let percentage: Double
    let weight: Double
    let repetitions: Int

    var id: String { "\(percentage)-\(weight)-\(repetitions)" }
}

/// Competition plate colours, so the diagram matches what the user is looking at
/// on the rack rather than inventing a palette.
enum PlateAppearance {
    static func color(for weight: Double, unit: WeightUnit) -> Color {
        if unit == .metric {
            switch weight {
            case 25: return Color(red: 0.80, green: 0.16, blue: 0.16)
            case 20: return Color(red: 0.13, green: 0.35, blue: 0.72)
            case 15: return Color(red: 0.90, green: 0.70, blue: 0.10)
            case 10: return Color(red: 0.16, green: 0.52, blue: 0.28)
            case 5: return Color(.systemGray5)
            case 2.5: return Color(red: 0.55, green: 0.16, blue: 0.16)
            default: return Color(.systemGray3)
            }
        }
        switch weight {
        case 45: return Color(red: 0.13, green: 0.35, blue: 0.72)
        case 35: return Color(red: 0.90, green: 0.70, blue: 0.10)
        case 25: return Color(red: 0.16, green: 0.52, blue: 0.28)
        case 10: return Color(.systemGray5)
        case 5: return Color(red: 0.80, green: 0.16, blue: 0.16)
        default: return Color(.systemGray3)
        }
    }

    /// Heavier plates are both wider and taller, matching real diameters closely
    /// enough to be read at a glance.
    static func height(for weight: Double, unit: WeightUnit, maximum: CGFloat) -> CGFloat {
        let heaviest: Double = unit == .metric ? 25 : 45
        let ratio = min(max(weight / heaviest, 0.28), 1)
        return maximum * (0.44 + 0.56 * ratio)
    }

    static func width(for weight: Double, unit: WeightUnit) -> CGFloat {
        let heaviest: Double = unit == .metric ? 25 : 45
        let ratio = min(max(weight / heaviest, 0.16), 1)
        return 7 + 7 * ratio
    }
}

private struct BarbellLoadDiagram: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let platesPerSide: [(weight: Double, count: Int)]
    let unit: WeightUnit

    private let diagramHeight: CGFloat = 92

    private var loadedPlates: [Double] {
        platesPerSide.flatMap { Array(repeating: $0.weight, count: $0.count) }
    }

    var body: some View {
        HStack(spacing: 0) {
            shaft
            collar

            if loadedPlates.isEmpty {
                Text("Empty bar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 10)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(loadedPlates.enumerated()), id: \.offset) { _, weight in
                        plate(weight)
                    }
                }
                .padding(.leading, 2)
            }
        }
        .frame(height: diagramHeight)
        .frame(maxWidth: .infinity)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: loadedPlates)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Barbell diagram")
        .accessibilityValue(
            loadedPlates.isEmpty
                ? "Empty bar"
                : platesPerSide
                    .map { "\($0.count) times \($0.weight.formatted()) \(unit.unit.symbol)" }
                    .joined(separator: ", ")
        )
    }

    private var shaft: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(.systemGray4), Color(.systemGray2), Color(.systemGray4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 66, height: 9)
    }

    private var collar: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color(.systemGray2))
            .frame(width: 8, height: 28)
    }

    private func plate(_ weight: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return shape
            .fill(PlateAppearance.color(for: weight, unit: unit))
            .overlay(shape.stroke(Color.black.opacity(0.18), lineWidth: 0.5))
            .frame(
                width: PlateAppearance.width(for: weight, unit: unit),
                height: PlateAppearance.height(for: weight, unit: unit, maximum: diagramHeight)
            )
            .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0.5, y: 1)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
    }
}

struct PlateCalculatorView: View {
    let unit: WeightUnit
    let onApply: (Double) -> Void

    @State private var targetWeight: Double
    @State private var barWeight: Double

    init(unit: WeightUnit, initialTarget: Double, onApply: @escaping (Double) -> Void) {
        self.unit = unit
        self.onApply = onApply
        _targetWeight = State(initialValue: initialTarget)
        _barWeight = State(initialValue: unit.barbellWeight)
    }

    private var availablePlates: [Double] {
        unit == .metric ? [25, 20, 15, 10, 5, 2.5, 1.25, 0.5] : [45, 35, 25, 10, 5, 2.5, 1.25]
    }

    private var platesPerSide: [(weight: Double, count: Int)] {
        var remaining = max((targetWeight - barWeight) / 2, 0)
        return availablePlates.compactMap { plate in
            let count = Int(floor((remaining + 0.0001) / plate))
            guard count > 0 else { return nil }
            remaining -= Double(count) * plate
            return (plate, count)
        }
    }

    private var loadedWeight: Double {
        barWeight + (2 * platesPerSide.reduce(0) { $0 + ($1.weight * Double($1.count)) })
    }

    private var plateWeightPerSide: Double {
        platesPerSide.reduce(0) { $0 + ($1.weight * Double($1.count)) }
    }

    private var isExactLoad: Bool {
        abs(loadedWeight - targetWeight) < 0.001
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("\(weightTitle(loadedWeight)) \(unit.unit.symbol)")
                            .font(.system(size: 42, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText())

                        Text(isExactLoad
                             ? "Loads your target exactly"
                             : "Closest to \(weightTitle(targetWeight)) \(unit.unit.symbol)")
                        .font(.footnote)
                        .foregroundStyle(isExactLoad ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Loaded weight")
                    .accessibilityValue("\(weightTitle(loadedWeight)) \(unit.unit.symbol)")

                    BarbellLoadDiagram(platesPerSide: platesPerSide, unit: unit)

                    Text(platesPerSide.isEmpty
                         ? "Empty bar"
                         : "\(weightTitle(plateWeightPerSide)) \(unit.unit.symbol) per side")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }

            Section {
                Stepper(
                    onIncrement: targetWeight >= 2000 ? nil : { adjustTarget(by: unit.barbellIncrement) },
                    onDecrement: targetWeight <= barWeight ? nil : { adjustTarget(by: -unit.barbellIncrement) }
                ) {
                    LabeledContent("Target", value: "\(weightTitle(targetWeight)) \(unit.unit.symbol)")
                        .monospacedDigit()
                }

                Stepper(
                    onIncrement: barWeight >= 100 ? nil : { adjustBar(by: 5) },
                    onDecrement: barWeight <= 0 ? nil : { adjustBar(by: -5) }
                ) {
                    LabeledContent("Bar", value: "\(weightTitle(barWeight)) \(unit.unit.symbol)")
                        .monospacedDigit()
                }
            } header: {
                Text("Load")
            } footer: {
                Text("Target moves in \(weightTitle(unit.barbellIncrement)) \(unit.unit.symbol) steps and includes the bar.")
            }

            if !platesPerSide.isEmpty {
                Section("Plates Per Side") {
                    ForEach(platesPerSide, id: \.weight) { plate in
                        LabeledContent {
                            Text("× \(plate.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } label: {
                            HStack(spacing: 10) {
                                Capsule()
                                    .fill(PlateAppearance.color(for: plate.weight, unit: unit))
                                    .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                                    .frame(width: 12, height: 20)
                                Text("\(weightTitle(plate.weight)) \(unit.unit.symbol)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }

            Section {
                Button("Use \(weightTitle(loadedWeight)) \(unit.unit.symbol)") {
                    onApply(loadedWeight)
                }
                .fontWeight(.semibold)
            } footer: {
                if platesPerSide.isEmpty && targetWeight < barWeight {
                    Text("Your target is lighter than the bar on its own.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sensoryFeedback(.selection, trigger: targetWeight)
    }

    private func adjustTarget(by amount: Double) {
        targetWeight = min(max(targetWeight + amount, barWeight), 2000)
    }

    private func adjustBar(by amount: Double) {
        barWeight = min(max(barWeight + amount, 0), 100)
        targetWeight = max(targetWeight, barWeight)
    }

    private func weightTitle(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }
}

struct WarmupCalculatorView: View {
    let unit: WeightUnit
    let workingWeight: Double
    let onAdd: ([WarmupRecommendation]) -> Void

    private var recommendations: [WarmupRecommendation] {
        let templates: [(Double, Int)] = [(0.40, 10), (0.55, 8), (0.70, 5), (0.82, 3), (0.92, 1)]
        var seen = Set<Double>()
        return templates.compactMap { percentage, reps in
            let raw = workingWeight * percentage
            let rounded = max((raw / unit.barbellIncrement).rounded() * unit.barbellIncrement, unit.barbellWeight)
            guard rounded < workingWeight, seen.insert(rounded).inserted else { return nil }
            return WarmupRecommendation(percentage: percentage, weight: rounded, repetitions: reps)
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Working Set", value: "\(String(format: "%g", workingWeight)) \(unit.unit.symbol)")
                    .monospacedDigit()
            } footer: {
                Text("Warm-up weights are rounded to your barbell increment.")
            }

            if recommendations.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Warm-Up Needed",
                        systemImage: "checkmark.circle",
                        description: Text("This working set is already at the selected bar weight.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Warm-Up Sets") {
                    ForEach(recommendations) { item in
                        LabeledContent {
                            Text("\(item.repetitions) reps")
                                .foregroundStyle(.secondary)
                        } label: {
                            Text("\(item.weight, specifier: "%g") \(unit.unit.symbol)")
                                .monospacedDigit()
                            Text("\(Int(item.percentage * 100))% of working set")
                        }
                    }
                }

                Section {
                    Button("Add \(recommendations.count) Warm-Up Sets") {
                        onAdd(recommendations)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct MoreView: View {
    @ObservedObject var workoutSet: WorkoutSet
    
    @State private var activeAlert: AlertType?
    
    private enum AlertType: Identifiable {
        case tagInfo
        case rpeInfo
        
        var id: Self { self }
    }
    
    private func alertFor(type: AlertType) -> Alert {
        switch type {
        case .tagInfo:
            return Alert(title: Text("Mark a set as Failure if you've tried to do more reps but failed."))
        case .rpeInfo:
            return Alert(title: Text("The rating of perceived exertion (RPE) is a way to determine and regulate your workout intensity."))
        }
    }
    
    @State private var workoutSetCommentInput: String? // cannot use ValueHolder here, since it would be recreated on changes
    private var workoutSetComment: Binding<String> {
        Binding(
            get: {
                self.workoutSetCommentInput ?? self.workoutSet.comment ?? ""
            },
            set: { newValue in
                self.workoutSetCommentInput = newValue
            }
        )
    }
    private func adjustAndSaveWorkoutSetCommentInput() {
        guard let newValue = workoutSetCommentInput?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        workoutSetCommentInput = newValue
        workoutSet.comment = newValue.isEmpty ? nil : newValue
        workoutSet.managedObjectContext?.saveOrCrash()
    }

    private func tagButton(tag: WorkoutSetTag) -> some View {
        Button(action: {
            if self.workoutSet.tagValue == tag {
                self.workoutSet.tagValue = nil
            } else {
                self.workoutSet.tagValue = tag
            }
        }) {
            HStack {
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .foregroundColor(tag.color)
                Text(tag.title.capitalized)
                Spacer()
                if self.workoutSet.tagValue == tag {
                    Image(systemName: "checkmark")
                        .foregroundColor(.secondary)
                }
            }.background(Color.fakeClear)
        }
        .buttonStyle(.plain)
    }
    
    private func rpeButton(rpe: Double) -> some View {
        Button(action: {
            if self.workoutSet.rpeValue == rpe {
                self.workoutSet.rpeValue = nil
            } else {
                self.workoutSet.rpeValue = rpe
            }
        }) {
            HStack {
                Text(String(format: "%.1f", rpe))
                Text(RPE.title(rpe) ?? "")
                    .lineLimit(nil)
                    .foregroundColor(.secondary)
                Spacer()
                if self.workoutSet.rpeValue == rpe {
                    Image(systemName: "checkmark")
                        .foregroundColor(.secondary)
                }
            }.background(Color.fakeClear)
        }
        .buttonStyle(.plain)
    }
    
    var body: some View {
        List {
            Section(header:
                HStack {
                    Text("Tag".uppercased())
                    Spacer()
                    Button(action: {
                        self.activeAlert = .tagInfo
                    }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.accentColor)
                    }
                }) {
                ForEach(WorkoutSetTag.allCases, id: \.self) { tag in
                    self.tagButton(tag: tag)
                }
            }
            
            Section(header: Text("Comment".uppercased())) {
                TextField("Comment", text: workoutSetComment, onEditingChanged: { isEditingTextField in
                    if !isEditingTextField {
                        self.adjustAndSaveWorkoutSetCommentInput()
                    }
                })
            }
            
            Section(header:
                HStack {
                    Text("RPE (Rating of Perceived Exertion)")
                    Spacer()
                    Button(action: {
                        self.activeAlert = .rpeInfo
                    }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.accentColor)
                    }
                }) {
                ForEach(RPE.allowedValues.reversed(), id: \.self) { rpe in
                    self.rpeButton(rpe: rpe)
                }
            }
        }
        .listStyleCompat_InsetGroupedListStyle()
        .alert(item: $activeAlert) { self.alertFor(type: $0) }
    }
}

#if DEBUG
struct WorkoutSetEditor_Previews : PreviewProvider {
    static var previews: some View {
        return Group {
            WorkoutSetEditor(workoutSet: MockWorkoutData.metricRandom.workoutSet)
                .mockEnvironment(weightUnit: .metric)
                .previewDisplayName("Metric")
                .previewLayout(.sizeThatFits)
            
            WorkoutSetEditor(workoutSet: MockWorkoutData.imperialRandom.workoutSet)
                .mockEnvironment(weightUnit: .imperial)
                .previewDisplayName("Imperial")
                .previewLayout(.sizeThatFits)
            
            MoreView(workoutSet: MockWorkoutData.metricRandom.workoutSet)
                .mockEnvironment(weightUnit: .metric)
                .previewLayout(.sizeThatFits)
                .listStyle(GroupedListStyle())
        }
    }
}
#endif
