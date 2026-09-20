//
//  ExercisesView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 04.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

private final class ExerciseThumbnailCache {
    static let shared = ExerciseThumbnailCache()
    let images = NSCache<NSString, UIImage>()
}

struct ExerciseDiagramThumbnail: View {
    let exercise: Exercise
    var size: CGFloat = 58

    @State private var image: UIImage?
    @State private var loadedRemoteMediaURL: URL?

    private func load() {
        guard image == nil, let path = exercise.pdfPaths.first else { return }
        // The same diagram is rendered at several row sizes. Include the
        // requested pixel edge so a compact completion-summary thumbnail
        // cannot seed the cache with a blurry image that is later enlarged.
        let key = "\(path)|\(Int((size * 2).rounded(.up)))" as NSString
        if let cached = ExerciseThumbnailCache.shared.images.object(forKey: key) {
            image = cached
            return
        }

        let url = ExerciseStore.defaultBuiltInExercisesResourceURL.appendingPathComponent(path)
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return }
        let pageRect = page.getBoxRect(.mediaBox)
        let scale = min((size * 2) / pageRect.width, (size * 2) / pageRect.height)
        let renderSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let rendered = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: renderSize))
            context.cgContext.translateBy(x: 0, y: renderSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            context.cgContext.drawPDFPage(page)
        }
        ExerciseThumbnailCache.shared.images.setObject(rendered, forKey: key)
        image = rendered
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(IronTheme.diagramCanvas)
            if exercise.imageURL == nil || loadedRemoteMediaURL != exercise.imageURL {
                fallbackContent
            }
            if let remoteURL = exercise.imageURL {
                ExerciseRemoteMediaView(
                    url: remoteURL,
                    animated: false,
                    targetPixelSize: min(size * UIScreen.main.scale, 240),
                    onLoaded: { loadedRemoteMediaURL = remoteURL }
                )
                // Keep the complete movement canvas inside the circular mask.
                // Several wide machine/cable frames reach all four corners,
                // so the usual 1/sqrt(2) circle fit is still too tight.
                .frame(width: size * 0.66, height: size * 0.66)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(IronTheme.outline.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: IronTheme.mediaBackdrop.opacity(0.08), radius: 2, x: 0, y: 1)
        .onAppear(perform: load)
        .onChange(of: exercise.imageURL) { _, newURL in
            if loadedRemoteMediaURL != newURL {
                loadedRemoteMediaURL = nil
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var fallbackContent: some View {
        if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // The built-in diagrams do not all have the same amount
                    // of whitespace in their PDF canvas. A proportional inset
                    // keeps wide poses inside the circle at every row size.
                    .padding(size * 0.14)
        } else {
            VStack(spacing: 2) {
                Exercise.imageFor(muscleGroup: exercise.muscleGroup)
                    .font(.system(size: 22, weight: .bold))
                Text(exercise.muscleGroup.prefix(1).uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
            }
            .foregroundColor(Exercise.colorFor(muscleGroup: exercise.muscleGroup))
        }
    }
}

struct ExerciseLibraryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseDiagramThumbnail(exercise: exercise, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(exercise.primaryMuscleCommonName.first?.capitalized ?? exercise.muscleGroup.capitalized)
                    if let equipment = exercise.equipment.first {
                        Text("•")
                        Text(equipment.capitalized)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        let muscle = exercise.primaryMuscleCommonName.first?.capitalized
            ?? exercise.muscleGroup.capitalized
        guard let equipment = exercise.equipment.first else {
            return "\(exercise.title), \(muscle)"
        }
        return "\(exercise.title), \(muscle), \(equipment.capitalized)"
    }
}

struct ExercisesView : View {
    var exercises: [Exercise]
    
    var body: some View {
        List(exercises, id: \.id) { exercise in
            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                ExerciseLibraryRow(exercise: exercise)
            }
        }
        .listStyle(.insetGrouped)
    }
}

#if DEBUG
struct ExercisesView_Previews : PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExercisesView(exercises: ExerciseStore.shared.shownExercises)
                .mockEnvironment(weightUnit: .metric)
        }
    }
}
#endif
