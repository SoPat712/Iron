//
//  ExerciseDetailView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 04.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import CoreData
import ImageIO
import MuscleMap
import WorkoutDataKit

private enum ExerciseMediaPipeline {
    private static let decodedImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 72
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()

    static func image(url: URL, animated: Bool, targetPixelSize: CGFloat) async -> UIImage? {
        let normalizedTarget = min(max(Int(targetPixelSize.rounded(.up)), 1), 1_200)
        let key = "\(url.absoluteString)|\(animated ? "animated" : "still")|\(normalizedTarget)" as NSString
        if let cached = decodedImages.object(forKey: key) {
            return cached
        }

        guard let data = await ExerciseMediaStore.shared.data(for: url),
              !Task.isCancelled,
              let image = await Task.detached(priority: .userInitiated, operation: {
                  decode(data: data, animated: animated, targetPixelSize: normalizedTarget)
              }).value else { return nil }

        let frameCount = max(image.images?.count ?? 1, 1)
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4) * frameCount
        decodedImages.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func decode(data: Data, animated: Bool, targetPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard animated, frameCount > 1 else {
            guard let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return scaledImage(frame, targetPixelSize: targetPixelSize)
        }

        var decodedFrames: [(image: CGImage, duration: TimeInterval)] = []
        decodedFrames.reserveCapacity(frameCount)
        var duration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let frameDuration = frameDuration(source: source, index: index)
            decodedFrames.append((frame, frameDuration))
            duration += frameDuration
        }

        let sourceCanvasSize = CGSize(
            width: decodedFrames.map { CGFloat($0.image.width) }.max() ?? 1,
            height: decodedFrames.map { CGFloat($0.image.height) }.max() ?? 1
        )
        let frames = decodedFrames.map {
            normalizedFrame(
                $0.image,
                sourceCanvasSize: sourceCanvasSize,
                targetPixelSize: targetPixelSize
            )
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(
            with: frames,
            duration: max(duration, Double(frames.count) * 0.08)
        )
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
        let clamped = (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        return max(unclamped ?? clamped ?? 0.1, 0.02)
    }

    private static func scaledImage(_ image: CGImage, targetPixelSize: Int) -> UIImage {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let sourceLongestEdge = max(sourceSize.width, sourceSize.height)
        let requestedEdge = CGFloat(targetPixelSize)

        // Keep the provider's native pixels for list thumbnails. Detail media
        // is enlarged once with Core Graphics' highest-quality interpolation,
        // rather than being repeatedly resampled by a web view.
        if requestedEdge <= sourceLongestEdge,
           sourceLongestEdge <= 240 {
            return UIImage(cgImage: image, scale: 1, orientation: .up)
        }

        let scale = requestedEdge / sourceLongestEdge
        let width = max(Int((sourceSize.width * scale).rounded(.up)), 1)
        let height = max(Int((sourceSize.height * scale).rounded(.up)), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return UIImage(cgImage: image, scale: 1, orientation: .up)
        }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else {
            return UIImage(cgImage: image, scale: 1, orientation: .up)
        }
        return UIImage(cgImage: scaled, scale: 1, orientation: .up)
    }

    private static func normalizedFrame(
        _ image: CGImage,
        sourceCanvasSize: CGSize,
        targetPixelSize: Int
    ) -> UIImage {
        let sourceLongestEdge = max(sourceCanvasSize.width, sourceCanvasSize.height)
        guard sourceLongestEdge > 0 else {
            return UIImage(cgImage: image, scale: 1, orientation: .up)
        }

        let scale = CGFloat(targetPixelSize) / sourceLongestEdge
        let canvasSize = CGSize(
            width: max((sourceCanvasSize.width * scale).rounded(.up), 1),
            height: max((sourceCanvasSize.height * scale).rounded(.up), 1)
        )
        let frameSize = CGSize(
            width: max((CGFloat(image.width) * scale).rounded(.up), 1),
            height: max((CGFloat(image.height) * scale).rounded(.up), 1)
        )
        let frameRect = CGRect(
            x: (canvasSize.width - frameSize.width) / 2,
            y: (canvasSize.height - frameSize.height) / 2,
            width: frameSize.width,
            height: frameSize.height
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            context.cgContext.setShouldAntialias(true)
            UIImage(cgImage: image, scale: 1, orientation: .up).draw(in: frameRect)
        }
    }
}

private final class ExercisePDFFrameCache {
    final class Entry {
        let images: [UIImage]

        init(images: [UIImage]) {
            self.images = images
        }
    }

    static let shared = ExercisePDFFrameCache()
    let entries = NSCache<NSString, Entry>()
}

struct ExerciseRemoteMediaView: UIViewRepresentable {
    let url: URL
    var animated = false
    var targetPixelSize: CGFloat
    var onLoaded: (() -> Void)? = nil

    final class Coordinator {
        var requestKey: String?
        var task: Task<Void, Never>?
        var onLoaded: (() -> Void)?

        deinit {
            task?.cancel()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.layer.magnificationFilter = .trilinear
        view.layer.minificationFilter = .trilinear
        view.layer.allowsEdgeAntialiasing = true
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIImageView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.onLoaded = onLoaded
        let requestKey = "\(url.absoluteString)|\(animated)|\(Int(targetPixelSize.rounded(.up)))"
        guard context.coordinator.requestKey != requestKey else { return }
        context.coordinator.requestKey = requestKey
        context.coordinator.task?.cancel()

        context.coordinator.task = Task { @MainActor in
            guard let image = await ExerciseMediaPipeline.image(
                url: url,
                animated: animated,
                targetPixelSize: targetPixelSize
            ),
            !Task.isCancelled,
            context.coordinator.requestKey == requestKey else { return }

            view.stopAnimating()
            view.image = image
            if animated {
                view.startAnimating()
            }
            context.coordinator.onLoaded?()
        }
    }

    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        view.stopAnimating()
        view.image = nil
    }
}

struct ExerciseDetailView : View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var exerciseStore: ExerciseStore
    @Environment(\.managedObjectContext) var managedObjectContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var exercise: Exercise
    
    @State private var showingEditExercise = false
    @State private var showingMedia = false
    @State private var loadedRemoteMediaURL: URL?

    private var currentExercise: Exercise {
        exerciseStore.find(with: exercise.uuid) ?? exercise
    }

    private var currentRemoteMediaURL: URL? {
        currentExercise.animationURL ?? currentExercise.imageURL
    }

    private func pdfToImage(url: URL, fit: CGSize) -> UIImage? {
        guard fit.width.isFinite,
              fit.height.isFinite,
              fit.width > 0,
              fit.height > 0 else { return nil }
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        guard let page = document.page(at: 1) else { return nil }
        
        let pageRect = page.getBoxRect(.mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }
        let scale = min(fit.width / pageRect.width, fit.height / pageRect.height)
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        guard scale.isFinite,
              scale > 0,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else { return nil }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            // flip
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            
            // aspect fit
            ctx.cgContext.scaleBy(x: scale, y: scale)
            
            // draw
            ctx.cgContext.drawPDFPage(page)
        }
        
        return img
    }

    private func exerciseImages(width: CGFloat, height: CGFloat) -> [UIImage] {
        let cacheKey = "\(currentExercise.uuid.uuidString)|\(Int(width.rounded(.up)))x\(Int(height.rounded(.up)))" as NSString
        if let cached = ExercisePDFFrameCache.shared.entries.object(forKey: cacheKey) {
            return cached.images
        }

        let images = currentExercise.pdfPaths
            .map { ExerciseStore.defaultBuiltInExercisesResourceURL.appendingPathComponent($0) }
            .compactMap { pdfToImage(url: $0, fit: CGSize(width: width, height: height)) }
            // The diagram always sits on a white media canvas. Dynamic
            // `label` becomes white in dark mode and made the fallback
            // illustration disappear whenever remote media was unavailable.
            .compactMap { $0.tinted(with: UIColor(white: 0.18, alpha: 1)) }

        ExercisePDFFrameCache.shared.entries.setObject(
            ExercisePDFFrameCache.Entry(images: images),
            forKey: cacheKey
        )
        return images
    }
    
    /// The provider's diagram canvas is intentionally fixed white; the media
    /// keeps a continuous corner and no decorative stroke so it reads as a hero
    /// rather than another bordered card.
    private var mediaHero: some View {
        GeometryReader { geometry in
            ZStack {
                IronTheme.diagramCanvas

                if currentRemoteMediaURL == nil || loadedRemoteMediaURL != currentRemoteMediaURL {
                    if !currentExercise.pdfPaths.isEmpty {
                        AnimatedImageView(
                            uiImages: exerciseImages(width: geometry.size.width, height: geometry.size.height),
                            duration: 2,
                            contentKey: currentExercise.uuid.uuidString
                        )
                        .padding(16)
                    } else {
                        Exercise.imageFor(muscleGroup: currentExercise.muscleGroup)
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let animationURL = currentExercise.animationURL {
                    ExerciseRemoteMediaView(
                        url: animationURL,
                        animated: true,
                        targetPixelSize: min(geometry.size.width * UIScreen.main.scale, 1_200),
                        onLoaded: { loadedRemoteMediaURL = animationURL }
                    )
                    // Match the thumbnail's conservative optical fit. Some
                    // animation frames extend farther than their first frame,
                    // especially on cable and machine exercises.
                    .scaleEffect(0.69)
                } else if let imageURL = currentExercise.imageURL {
                    ExerciseRemoteMediaView(
                        url: imageURL,
                        animated: false,
                        targetPixelSize: min(geometry.size.width * UIScreen.main.scale, 1_200),
                        onLoaded: { loadedRemoteMediaURL = imageURL }
                    )
                    .scaleEffect(0.69)
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.heroCornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if currentRemoteMediaURL != nil {
                Link(destination: URL(string: "https://gymvisual.com/")!) {
                    Text(Exercise.mediaAttribution)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                }
                .tint(.secondary)
                .padding(10)
                .accessibilityLabel("Exercise media by Gym Visual")
            }
        }
        .onChange(of: currentRemoteMediaURL) { _, newURL in
            if loadedRemoteMediaURL != newURL {
                loadedRemoteMediaURL = nil
            }
        }
    }

    var body: some View {
        List {
            Section {
                exerciseHeader
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ExerciseInlineProgressView(exercise: currentExercise)
                    .id(currentExercise.uuid)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ExerciseTargetMuscleMap(
                    primary: primaryMapMuscles,
                    secondary: secondaryMapMuscles,
                    equipment: currentExercise.equipment.map { $0.capitalized }
                )
                .id(currentExercise.uuid)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let description = currentExercise.description, !description.isEmpty {
                Section("About") {
                    Text(description)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !currentExercise.steps.isEmpty {
                Section("Instructions") {
                    ForEach(Array(currentExercise.steps.enumerated()), id: \.offset) { index, step in
                        instructionRow(number: index + 1, step: step)
                    }
                }
            }

            if !currentExercise.tips.isEmpty {
                Section("Tips") {
                    ForEach(currentExercise.tips, id: \.self) { tip in
                        Label {
                            Text(tip).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                }
            }

            if !displayAliases.isEmpty {
                Section("Also Known As") {
                    ForEach(Array(displayAliases.enumerated()), id: \.offset) { _, alias in
                        Text(alias)
                    }
                }
            }

            if !referenceLinks.isEmpty {
                Section("References") {
                    ForEach(Array(referenceLinks.enumerated()), id: \.offset) { _, item in
                        Link(destination: item.url) {
                            LabeledContent {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            } label: {
                                Label(item.title, systemImage: "safari")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: IronTheme.floatingWorkoutBottomClearance - 28)
        }
        .sheet(isPresented: $showingEditExercise) {
            EditCustomExerciseSheet(exercise: currentExercise)
                .environmentObject(exerciseStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingMedia) {
            NavigationStack {
                mediaHero
                    .padding(IronTheme.horizontalPadding)
                    .navigationTitle(currentExercise.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Close", systemImage: "xmark") { showingMedia = false }
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("Close exercise media")
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .navigationTitle(currentExercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if currentExercise.isCustom {
                        Button("Edit Exercise", systemImage: "pencil") {
                            showingEditExercise = true
                        }
                    }
                    if exerciseStore.isHidden(exercise: currentExercise) {
                        Button("Unhide Exercise", systemImage: "eye") {
                            exerciseStore.show(exercise: currentExercise)
                        }
                    } else if !currentExercise.isCustom {
                        Button("Hide Exercise", systemImage: "eye.slash") {
                            exerciseStore.hide(exercise: currentExercise)
                        }
                    }
                } label: {
                    Label("Exercise Actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func instructionRow(number: Int, step: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.ironMetric(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, alignment: .trailing)
            Text(step)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(step)")
    }

    private var exerciseHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(currentExercise.title)
                    .font(.title.bold())
                    .foregroundStyle(IronTheme.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { showingMedia = true } label: {
                ExerciseDiagramThumbnail(exercise: currentExercise, size: 60)
                    .overlay(alignment: .bottomTrailing) {
                        if currentExercise.animationURL != nil || (currentRemoteMediaURL == nil && currentExercise.pdfPaths.count > 1) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(IronTheme.onAccent)
                                .frame(width: 22, height: 22)
                                .background(IronTheme.accent, in: Circle())
                                .overlay(Circle().stroke(IronTheme.background, lineWidth: 2))
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View demonstration of \(currentExercise.title)")
        }
        .padding(4)
    }

    private var headerSubtitle: String {
        [currentExercise.equipment.map { $0.capitalized }.joined(separator: ", "),
         currentExercise.primaryMuscle.map { $0.capitalized }.joined(separator: ", ")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var displayAliases: [String] {
        currentExercise.alias
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var referenceLinks: [(title: String, url: URL)] {
        currentExercise.references.compactMap { reference in
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), !trimmed.isEmpty else { return nil }
            let host = url.host?.replacingOccurrences(of: "www.", with: "")
            let title = host.flatMap { $0.isEmpty ? nil : $0 } ?? "Open source"
            return (title, url)
        }
    }

    private var primaryMapMuscles: [Muscle] {
        mappedMuscles(currentExercise.primaryMuscle)
    }

    private var secondaryMapMuscles: [Muscle] {
        mappedMuscles(currentExercise.secondaryMuscle).filter { !primaryMapMuscles.contains($0) }
    }

    private func mappedMuscles(_ names: [String]) -> [Muscle] {
        var result: [Muscle] = []
        for name in names {
            guard let muscle = ironMapMuscle(name), !result.contains(muscle) else { continue }
            result.append(muscle)
        }
        return result
    }


}

/// B6 fallback: the package's hit tester is internal and its drag begins at 1 pt.
/// Tap + long press preserve List scrolling. The package delivers long press on
/// release; do not enable onMuscleDragged until it supports a hold-gated drag.
private struct ExerciseTargetMuscleMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let primary: [Muscle]
    let secondary: [Muscle]
    let equipment: [String]

    @State private var selectedMuscle: Muscle?
    @State private var selectedSide: BodySide?
    @State private var selectionID = UUID()
    @State private var tooltipSize = CGSize(width: 180, height: 37)

    private var hasMuscles: Bool { !primary.isEmpty || !secondary.isEmpty }

    private var accessibilitySummary: String {
        let primaryNames = primary.map(\.displayName).joined(separator: ", ")
        let secondaryNames = secondary.map(\.displayName).joined(separator: ", ")
        let targets = hasMuscles
            ? "Target muscles. Primary: \(primaryNames.isEmpty ? "None" : primaryNames). Secondary: \(secondaryNames.isEmpty ? "None" : secondaryNames)."
            : "No target muscles listed."
        return targets + (equipment.isEmpty ? "" : " Equipment: \(equipment.joined(separator: ", ")).")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            headerLayout {
                Text("Target")
                    .font(.title3.bold())
                    .foregroundStyle(IronTheme.primaryText)
                if hasMuscles {
                    Text("Touch and hold a muscle")
                        .font(.footnote)
                        .foregroundStyle(IronTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                }
            }

            if hasMuscles {
                HStack(alignment: .top, spacing: 44) {
                    bodyColumn(side: .front, title: "Front")
                    bodyColumn(side: .back, title: "Back")
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("No target muscles listed")
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.secondaryText)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    if hasMuscles { legends }
                    Spacer(minLength: 0)
                    equipmentChips
                }
                VStack(alignment: .leading, spacing: 8) {
                    if hasMuscles { legends }
                    equipmentChips
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IronTheme.surface, in: RoundedRectangle(cornerRadius: IronTheme.heroCornerRadius, style: .continuous))
        .overlayPreferenceValue(ExerciseMuscleAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let anchor, let muscle = selectedMuscle, let role = role(for: muscle) {
                    let point = geometry[anchor].origin
                    let halfWidth = tooltipSize.width / 2
                    let halfHeight = tooltipSize.height / 2
                    let x = max(halfWidth + 8, min(point.x, geometry.size.width - halfWidth - 8))
                    let y = max(halfHeight + 8, min(point.y, geometry.size.height - halfHeight - 8))
                    tooltip(muscle: muscle, role: role, pointerOffset: point.x - x)
                        .frame(maxWidth: geometry.size.width - 16)
                        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                        .background {
                            GeometryReader { tooltipGeometry in
                                Color.clear.preference(key: ExerciseMuscleTooltipSizeKey.self, value: tooltipGeometry.size)
                            }
                        }
                        .position(x: x, y: y)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
        }
        .onPreferenceChange(ExerciseMuscleTooltipSizeKey.self) { size in
            if size.width > 0, size.height > 0 { tooltipSize = size }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isImage)
        .animation(IronMotion.preferred(IronMotion.snappy, reduceMotion: reduceMotion), value: selectedMuscle)
        .sensoryFeedback(.selection, trigger: selectedMuscle) { _, muscle in muscle != nil }
        .task(id: selectionID) {
            guard selectedMuscle != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            selectedMuscle = nil
            selectedSide = nil
        }
        .onDisappear {
            selectedMuscle = nil
            selectedSide = nil
        }
    }

    private var legends: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            legend("Primary", opacity: 1)
            legend("Secondary", opacity: 0.42)
        }
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }

    private func legend(_ title: String, opacity: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(IronTheme.accent.opacity(opacity)).frame(width: 8, height: 8)
            Text(title).font(.caption)
        }
        .foregroundStyle(IronTheme.secondaryText)
    }

    private var equipmentChips: some View {
        ExerciseChipFlowLayout(spacing: 6) {
            ForEach(equipment, id: \.self) { name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IronTheme.primaryText)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 24)
                    .background(IronTheme.tertiaryFill, in: Capsule())
            }
        }
    }

    private func bodyColumn(side: BodySide, title: String) -> some View {
        VStack(spacing: 4) {
            muscleBody(side: side).frame(width: 96, height: 169)
            Text(title).font(.caption2).foregroundStyle(IronTheme.secondaryText)
        }
    }

    private func muscleBody(side: BodySide) -> some View {
        let style = BodyViewStyle(
            defaultFillColor: Color(.tertiaryLabel).opacity(0.35),
            strokeColor: Color(.separator),
            strokeWidth: 0.5,
            selectionColor: IronTheme.accent,
            selectionStrokeColor: IronTheme.accent,
            selectionStrokeWidth: 1,
            headColor: Color(.tertiaryLabel).opacity(0.45),
            hairColor: Color(.quaternaryLabel)
        )
        return BodyView(gender: .male, side: side, style: style)
            .highlight(secondary, color: IronTheme.accent, opacity: 0.42)
            .highlight(primary, color: IronTheme.accent)
            .selected(selectedSide == side ? selectedMuscle : nil)
            .onMuscleSelected { muscle, _ in select(muscle, side: side) }
            .onMuscleLongPressed(duration: 0.25) { muscle, _ in select(muscle, side: side) }
            .tooltip { _, _ in
                // Lift the package's muscle anchor into the whole card, so a
                // tooltip can be clamped to the card instead of the 96 pt body.
                Color.clear.frame(width: 1, height: 1)
                    .anchorPreference(key: ExerciseMuscleAnchorKey.self, value: .bounds) { $0 }
            }
    }

    private func tooltip(muscle: Muscle, role: String, pointerOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(IronTheme.accent.opacity(role == "Primary" ? 1 : 0.42))
                    .frame(width: 8, height: 8)
                Text(muscle.displayName).font(.caption.bold()).foregroundStyle(IronTheme.primaryText)
                Text(role).font(.caption).foregroundStyle(IronTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(IronTheme.outline, lineWidth: 0.5))
            ExerciseTooltipPointer()
                .fill(.regularMaterial)
                .frame(width: 14, height: 7)
                .offset(x: max(-tooltipSize.width / 2 + 14, min(pointerOffset, tooltipSize.width / 2 - 14)))
        }
        .shadow(color: IronTheme.mediaBackdrop.opacity(0.28), radius: 18, x: 0, y: 6)
    }

    private func select(_ muscle: Muscle, side: BodySide) {
        guard role(for: muscle) != nil else {
            selectedMuscle = nil
            selectedSide = nil
            return
        }
        selectedSide = side
        selectedMuscle = muscle
        selectionID = UUID()
    }

    private func role(for muscle: Muscle) -> String? {
        if primary.contains(muscle) { return "Primary" }
        if secondary.contains(muscle) { return "Secondary" }
        return nil
    }
}

private struct ExerciseMuscleAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct ExerciseMuscleTooltipSizeKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct ExerciseTooltipPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

#if DEBUG
struct ExerciseDetailView_Previews : PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExerciseDetailView(exercise: ExerciseStore.shared.exercises.first(where: { $0.everkineticId == 99 })!)
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
