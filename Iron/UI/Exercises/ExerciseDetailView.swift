//
//  ExerciseDetailView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 04.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
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

    final class Coordinator {
        var requestKey: String?
        var task: Task<Void, Never>?

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
    var exercise: Exercise
    
    @State private var showingEditExercise = false

    private var currentExercise: Exercise {
        exerciseStore.find(with: exercise.uuid) ?? exercise
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
    
    @ViewBuilder private func mediaSection(geometry: GeometryProxy) -> some View {
        let mediaSide = min(geometry.size.width - (IronTheme.horizontalPadding * 2), 330)
        let mediaHeight = min(mediaSide * 0.76, 252)

        ZStack {
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.diagramCanvas)
            if !currentExercise.pdfPaths.isEmpty {
                AnimatedImageView(
                    uiImages: self.exerciseImages(width: geometry.size.width, height: mediaHeight),
                    duration: 2,
                    contentKey: currentExercise.uuid.uuidString
                )
                    .padding(16)
            } else {
                Exercise.imageFor(muscleGroup: currentExercise.muscleGroup)
                    .font(.system(size: 72, weight: .black))
                    .foregroundColor(Exercise.colorFor(muscleGroup: currentExercise.muscleGroup))
            }
            if let animationURL = currentExercise.animationURL {
                ExerciseRemoteMediaView(
                    url: animationURL,
                    animated: true,
                    targetPixelSize: min(mediaSide * UIScreen.main.scale, 1_200)
                )
                    // Match the thumbnail's conservative optical fit. Some
                    // animation frames extend farther than their first frame,
                    // especially on cable and machine exercises.
                    .scaleEffect(0.69)
            } else if let imageURL = currentExercise.imageURL {
                ExerciseRemoteMediaView(
                    url: imageURL,
                    animated: false,
                    targetPixelSize: min(mediaSide * UIScreen.main.scale, 1_200)
                )
                .scaleEffect(0.69)
            }
        }
        .frame(width: mediaSide, height: mediaHeight)
        .clipped()
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .stroke(IronTheme.outline.opacity(0.5), lineWidth: 1)
        )
    }
    
    private var popupActions: [IronPopupAction] {
        var actions: [IronPopupAction] = []
        if currentExercise.isCustom {
            actions.append(IronPopupAction(title: "Edit Exercise", systemImage: "pencil") {
                showingEditExercise = true
            })
        }
        if exerciseStore.isHidden(exercise: currentExercise) {
            actions.append(IronPopupAction(title: "Unhide Exercise", systemImage: "eye") {
                exerciseStore.show(exercise: currentExercise)
            })
        } else if !currentExercise.isCustom {
            actions.append(IronPopupAction(title: "Hide Exercise", systemImage: "eye.slash") {
                exerciseStore.hide(exercise: currentExercise)
            })
        }
        return actions
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                IronScreenBackground()
                overviewContent(geometry: geometry)
            }
        }
        .sheet(isPresented: $showingEditExercise) {
            EditCustomExerciseSheet(exercise: currentExercise)
                .environmentObject(exerciseStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(IronTheme.modalSurface)
        }
        .navigationTitle(currentExercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IronPopupMenu(title: "Exercise actions", actions: popupActions) {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Exercise actions")
            }
        }
    }

    private func overviewContent(geometry: GeometryProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                mediaSection(geometry: geometry)
                    .padding(.bottom, 18)

                trainingDataLinks
                metadataCard

                if !displayAliases.isEmpty {
                    aliasesCard
                }

                if !primaryMapMuscles.isEmpty || !secondaryMapMuscles.isEmpty {
                    muscleMapCard
                }

                if let description = currentExercise.description, !description.isEmpty {
                    detailCard(title: "About", icon: "info.circle") {
                        Text(description)
                            .font(.body)
                            .foregroundColor(IronTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !currentExercise.steps.isEmpty {
                    detailCard(title: "Instructions", icon: "list.number") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(currentExercise.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundColor(IronTheme.accent)
                                        .frame(width: 24, alignment: .leading)
                                    Text(step)
                                        .font(.body)
                                        .foregroundColor(IronTheme.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                if !currentExercise.tips.isEmpty {
                    detailCard(title: "Tips", icon: "lightbulb") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(currentExercise.tips, id: \.self) { tip in
                                Label(tip, systemImage: "checkmark.circle")
                                    .font(.body)
                                    .foregroundColor(IronTheme.primaryText)
                            }
                        }
                    }
                }

                if !referenceLinks.isEmpty {
                    referencesCard
                }
            }
            .padding(IronTheme.horizontalPadding)
            .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
        }
    }

    private var trainingDataLinks: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ExerciseHistoryView(exercise: currentExercise)
                    .navigationTitle("History")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                destinationRow(
                    title: "History",
                    subtitle: "Logged sets and previous sessions",
                    systemImage: "clock.arrow.circlepath"
                )
            }

            Divider()
                .padding(.leading, 44)

            NavigationLink {
                ExerciseStatisticsView(exercise: currentExercise)
                    .navigationTitle("Progress")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                destinationRow(
                    title: "Progress",
                    subtitle: "Strength, volume, and personal records",
                    systemImage: "chart.xyaxis.line"
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
    }

    private func destinationRow(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundColor(IronTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(IronTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(IronTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(IronTheme.tertiaryText)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private var aliasesCard: some View {
        detailCard(title: "Also known as", icon: "text.bubble.fill") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Array(displayAliases.enumerated()), id: \.offset) { _, alias in
                    Text(alias)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(IronTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: IronTheme.compactCornerRadius, style: .continuous)
                                .fill(IronTheme.field)
                        )
                }
            }
        }
    }

    private var howToContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if !hasHowToContent {
                    howToEmptyState
                        .padding(.bottom, 18)
                }

                if let description = currentExercise.description, !description.isEmpty {
                    detailCard(title: "About", icon: "info.circle.fill") {
                        Text(description)
                            .foregroundColor(IronTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !currentExercise.steps.isEmpty {
                    detailCard(title: "How to perform", icon: "list.number") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(currentExercise.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(IronTheme.onAccent)
                                        .frame(width: 24, height: 24)
                                        .background(IronTheme.accent)
                                        .clipShape(Circle())
                                    Text(step)
                                        .foregroundColor(IronTheme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                if !currentExercise.tips.isEmpty {
                    detailCard(title: "Coach cues", icon: "lightbulb.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(currentExercise.tips, id: \.self) { tip in
                                Label(tip, systemImage: "checkmark.circle.fill")
                                    .foregroundColor(IronTheme.secondaryText)
                            }
                        }
                    }
                }

                if !referenceLinks.isEmpty {
                    referencesCard
                }
            }
            .padding(IronTheme.horizontalPadding)
            .padding(.bottom, IronTheme.floatingWorkoutBottomClearance)
        }
    }

    private var hasHowToContent: Bool {
        !(currentExercise.description?.isEmpty ?? true)
            || !currentExercise.steps.isEmpty
            || !currentExercise.tips.isEmpty
            || !referenceLinks.isEmpty
    }

    private var howToEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(IronTheme.accent)
            Text("No instructions yet")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            Text("Iron will show setup instructions and coaching cues here when they are available.")
                .font(.subheadline)
                .foregroundColor(IronTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 42)
        .background(
            RoundedRectangle(cornerRadius: IronTheme.cornerRadius, style: .continuous)
                .fill(IronTheme.surface)
        )
    }

    private var referencesCard: some View {
        detailCard(title: "References", icon: "link") {
            VStack(spacing: 0) {
                ForEach(Array(referenceLinks.enumerated()), id: \.offset) { index, item in
                    Link(destination: item.url) {
                        HStack(spacing: 12) {
                            Image(systemName: "safari.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(IronTheme.accent)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(IronTheme.accentSoft))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(IronTheme.primaryText)
                                    .lineLimit(1)
                                Text(item.url.absoluteString)
                                    .font(.caption)
                                    .foregroundColor(IronTheme.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(IronTheme.accent)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < referenceLinks.count - 1 {
                        IronHairline().padding(.leading, 46)
                    }
                }
            }
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Target & equipment", systemImage: "scope")
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            HStack(alignment: .top, spacing: 20) {
                metadataColumn(title: "Primary", values: currentExercise.primaryMuscleCommonName)
                metadataColumn(title: "Secondary", values: currentExercise.secondaryMuscleCommonName)
            }
            if !currentExercise.equipment.isEmpty {
                IronHairline()
                Label(
                    currentExercise.equipment.map { $0.capitalized }.joined(separator: ", "),
                    systemImage: "dumbbell.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(IronTheme.secondaryText)
            }
        }
        .padding(.vertical, 18)
        .overlay(IronHairline(opacity: 0.52), alignment: .bottom)
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

    private var muscleMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Muscle map", systemImage: "figure.strengthtraining.traditional")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(IronTheme.primaryText)
                Spacer()
                HStack(spacing: 12) {
                    muscleLegend(color: IronTheme.accent, label: "Primary")
                    muscleLegend(color: IronTheme.accent.opacity(0.42), label: "Secondary")
                }
            }

            HStack(spacing: 8) {
                muscleBody(side: .front)
                muscleBody(side: .back)
            }
            .frame(height: 210)

            HStack {
                Text("FRONT")
                Spacer()
                Text("BACK")
            }
            .font(.caption2.weight(.bold))
            .foregroundColor(IronTheme.tertiaryText)
        }
        .padding(.vertical, 18)
    }

    private func muscleLegend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(IronTheme.secondaryText)
        }
    }

    private var primaryMapMuscles: [Muscle] {
        mappedMuscles(currentExercise.primaryMuscle)
    }

    private var secondaryMapMuscles: [Muscle] {
        mappedMuscles(currentExercise.secondaryMuscle).filter { !primaryMapMuscles.contains($0) }
    }

    private func muscleBody(side: BodySide) -> BodyView {
        let style = BodyViewStyle(
            defaultFillColor: IronTheme.secondaryText.opacity(0.16),
            strokeColor: IronTheme.secondaryText.opacity(0.18),
            strokeWidth: 0.6,
            selectionColor: IronTheme.accent,
            selectionStrokeColor: IronTheme.accent,
            selectionStrokeWidth: 1.5,
            headColor: IronTheme.secondaryText.opacity(0.22),
            hairColor: IronTheme.secondaryText.opacity(0.12)
        )
        return BodyView(gender: .male, side: side, style: style)
            .highlight(secondaryMapMuscles, color: IronTheme.accent, opacity: 0.42)
            .highlight(primaryMapMuscles, color: IronTheme.accent)
    }

    private func mappedMuscles(_ names: [String]) -> [Muscle] {
        var result: [Muscle] = []
        for name in names {
            guard let muscle = mapMuscle(name), !result.contains(muscle) else { continue }
            result.append(muscle)
        }
        return result
    }

    private func mapMuscle(_ name: String) -> Muscle? {
        switch name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "abs", "abdominals", "core": return .abs
        case "lower abs": return .lowerAbs
        case "obliques": return .obliques
        case "serratus anterior": return .serratus
        case "biceps", "biceps brachii", "brachialis": return .biceps
        case "triceps", "triceps brachii": return .triceps
        case "forearm", "forearms", "forerm", "wrists", "wrist flexors", "wrist extensors", "grip muscles": return .forearm
        case "hands": return .hands
        case "shoulders", "deltoid", "deltoids", "delts": return .deltoids
        case "rear deltoids": return .rearDeltoid
        case "rotator cuff": return .rotatorCuff
        case "trapezius", "traps", "levator scapulae": return .trapezius
        case "rhomboids": return .rhomboids
        case "sternocleidomastoid": return .neck
        case "chest", "pectorals", "pectoralis major": return .chest
        case "upper chest": return .upperChest
        case "lats", "latissimus dorsi", "upper back", "back": return .upperBack
        case "lower back", "spine", "erector spinae": return .lowerBack
        case "glutes", "glutaeus maximus", "abductors": return .gluteal
        case "hamstrings", "ischiocrural muscles": return .hamstring
        case "quadriceps", "quads": return .quadriceps
        case "adductors", "groin", "inner thighs": return .adductors
        case "hip flexors": return .hipFlexors
        case "calves", "gastrocnemius", "soleus": return .calves
        case "shins": return .tibialis
        case "ankles", "ankle stabilizers": return .ankles
        case "feet": return .feet
        default: return nil
        }
    }

    private func metadataColumn(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(IronTheme.tertiaryText)
            Text(values.isEmpty ? "—" : values.map { $0.capitalized }.joined(separator: ", "))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))
                .foregroundColor(IronTheme.primaryText)
            content()
        }
        .padding(.vertical, 18)
        .overlay(IronHairline(opacity: 0.52), alignment: .bottom)
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
