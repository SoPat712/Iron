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
            withAnimation {
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
                    withAnimation {
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
                    withAnimation {
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
                title: "Plate calculator",
                subtitle: "Load each side of the bar",
                systemImage: "circle.grid.cross",
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
            .presentationDetents([.fraction(0.78)])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackground(IronTheme.modalSurface)
        case .warmups:
            IronUtilitySheet(
                title: "Warm-up calculator",
                subtitle: "Build up to your working weight",
                systemImage: "flame",
                onClose: { activeSheet = nil }
            ) {
                WarmupCalculatorView(
                    unit: settingsStore.weightUnit,
                    workingWeight: max(workoutSetWeight.wrappedValue ?? 0, settingsStore.weightUnit.barbellWeight),
                    onAdd: addWarmupSets
                )
            }
            .presentationDetents([.height(620)])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackground(IronTheme.modalSurface)
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
                Label("Plates", systemImage: "circle.grid.cross")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IronSecondaryButtonStyle())

            Button(action: { activeSheet = .warmups }) {
                Label("Warm-up", systemImage: "flame.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IronSecondaryButtonStyle())
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
                        withAnimation {
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
                        withAnimation {
                            self.showKeyboard = .none
                        }
                    }
                } else {
                    if width > 200 {
                        withAnimation {
                            self.showKeyboard = .repetitions
                        }
                    } else if width < 200 {
                        withAnimation {
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

    private func plateColor(_ weight: Double) -> Color {
        if unit == .metric {
            switch weight {
            case 25: return IronTheme.danger
            case 20: return IronTheme.accent
            case 15: return Color.yellow
            case 10: return IronTheme.success
            case 5: return Color(UIColor.systemGray3)
            case 2.5: return IronTheme.danger
            case 1.25: return IronTheme.success
            default: return Color(UIColor.systemGray4)
            }
        } else {
            switch weight {
            case 45: return IronTheme.accent
            case 35: return Color.yellow
            case 25: return IronTheme.success
            case 10: return Color(UIColor.systemGray3)
            case 5: return IronTheme.danger
            case 2.5: return IronTheme.success
            default: return Color(UIColor.systemGray4)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    targetLoadCard
                    barWeightCard
                    plateLoadCard
                }
                .padding(.horizontal, IronTheme.horizontalPadding)
                .padding(.bottom, 14)
            }

            IronHairline()

            Button {
                onApply(loadedWeight)
            } label: {
                Text("Use \(weightTitle(loadedWeight)) \(unit.unit.symbol)")
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .padding(.horizontal, IronTheme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(IronTheme.modalSurface)
        }
        .background(IronTheme.modalSurface)
        .sensoryFeedback(.selection, trigger: targetWeight)
    }

    private var targetLoadCard: some View {
        VStack(spacing: 10) {
            Text("TARGET LOAD")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundColor(IronTheme.secondaryText)

            HStack(spacing: 18) {
                loadControlButton(
                    systemImage: "minus",
                    accessibilityLabel: "Decrease target load"
                ) {
                    adjustTarget(by: -unit.barbellIncrement)
                }
                .disabled(targetWeight <= barWeight)

                VStack(spacing: 0) {
                    Text(weightTitle(targetWeight))
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                        .foregroundColor(IronTheme.primaryText)
                        .contentTransition(.numericText())
                    Text(unit.unit.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundColor(IronTheme.secondaryText)
                }
                .frame(minWidth: 120)

                loadControlButton(
                    systemImage: "plus",
                    accessibilityLabel: "Increase target load"
                ) {
                    adjustTarget(by: unit.barbellIncrement)
                }
                .disabled(targetWeight >= 2000)
            }

            Text("\(weightTitle(unit.barbellIncrement)) \(unit.unit.symbol) steps")
                .font(.caption)
                .foregroundColor(IronTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
    }

    private var barWeightCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bar weight")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Text("Included in the target")
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
            }

            Spacer(minLength: 8)

            compactLoadControl(systemImage: "minus") {
                adjustBar(by: -5)
            }
            .disabled(barWeight <= 0)

            Text("\(weightTitle(barWeight)) \(unit.unit.symbol)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundColor(IronTheme.primaryText)
                .frame(minWidth: 56)

            compactLoadControl(systemImage: "plus") {
                adjustBar(by: 5)
            }
            .disabled(barWeight >= 100)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.raisedSurface)
        )
    }

    private var plateLoadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Per side")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                    Label(
                        isExactLoad ? "Exact target" : "Closest possible load",
                        systemImage: isExactLoad ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isExactLoad ? IronTheme.success : IronTheme.warning)
                }

                Spacer()

                Text("\(weightTitle(plateWeightPerSide)) \(unit.unit.symbol)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundColor(IronTheme.primaryText)
                    .accessibilityLabel("\(weightTitle(plateWeightPerSide)) \(unit.unit.symbol) per side")
            }

            if platesPerSide.isEmpty {
                Label(
                    targetWeight < barWeight ? "Target is lighter than this bar" : "Use the empty bar",
                    systemImage: "minus.circle"
                )
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            } else {
                plateStackVisualization

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(platesPerSide, id: \.weight) { plate in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(plateColor(plate.weight))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(IronTheme.outline.opacity(0.5), lineWidth: 0.5))
                            Text("\(plate.count) × \(weightTitle(plate.weight))")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundColor(IronTheme.primaryText)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Capsule(style: .continuous).fill(IronTheme.raisedSurface))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
    }

    private var plateStackVisualization: some View {
        HStack(alignment: .center, spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(IronTheme.tertiaryText)
                .frame(width: 58, height: 9)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(IronTheme.secondaryText)
                .frame(width: 18, height: 19)

            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(platesPerSide.enumerated()), id: \.offset) { _, plate in
                    ForEach(0..<plate.count, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(plateColor(plate.weight))
                            .frame(
                                width: plate.weight >= 20 ? 16 : 12,
                                height: min(82, 30 + CGFloat(plate.weight) * 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(IronTheme.outline.opacity(0.5), lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(.leading, 5)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
    }

    private func loadControlButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(IronTheme.accent)
                .frame(width: 52, height: 52)
                .background(Circle().fill(IronTheme.accentSoft))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func compactLoadControl(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(IronTheme.accent)
                .frame(width: IronTheme.iconButtonSize, height: IronTheme.iconButtonSize)
                .background(Circle().fill(IronTheme.accentSoft))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "plus" ? "Increase bar weight" : "Decrease bar weight")
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
        ZStack {
            IronModalBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Working set")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(IronTheme.secondaryText)
                        Text("\(workingWeight, specifier: "%g") \(unit.unit.symbol)")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(IronTheme.primaryText)
                        Text("Progressive sets are rounded to your barbell increment.")
                            .font(.footnote)
                            .foregroundColor(IronTheme.secondaryText)
                    }

                    if recommendations.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(IronTheme.success)
                            Text("No lighter warm-up is needed")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(IronTheme.primaryText)
                            Text("This working set is already at the selected bar weight.")
                                .font(.footnote)
                                .foregroundColor(IronTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 18)
                        .background(RoundedRectangle(cornerRadius: IronTheme.cornerRadius).fill(IronTheme.surface))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(recommendations) { item in
                                HStack {
                                    Text("\(Int(item.percentage * 100))%")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(IronTheme.accent)
                                        .frame(width: 42, alignment: .leading)
                                    Text("\(item.weight, specifier: "%g") \(unit.unit.symbol)")
                                        .font(.headline.monospacedDigit())
                                        .foregroundColor(IronTheme.primaryText)
                                    Spacer()
                                    Text("\(item.repetitions) reps")
                                        .foregroundColor(IronTheme.secondaryText)
                                }
                                .padding(.vertical, 13)
                                if item.id != recommendations.last?.id {
                                    Divider().background(IronTheme.outline)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: IronTheme.cornerRadius).fill(IronTheme.surface))

                        Button("Add \(recommendations.count) warm-up sets") {
                            onAdd(recommendations)
                        }
                        .buttonStyle(IronPrimaryButtonStyle())
                    }
                }
                .padding(IronTheme.horizontalPadding)
            }
        }
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
