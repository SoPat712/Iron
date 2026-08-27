//
//  AnimatedImageView.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 06.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import SwiftUI
import WorkoutDataKit

struct AnimatedImageView : UIViewRepresentable {
    var uiImages: [UIImage]
    var duration: TimeInterval
    var contentKey: String = ""

    final class Coordinator {
        var animationKey: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private var animationKey: String {
        let dimensions = uiImages.map {
            "\(Int($0.size.width.rounded()))x\(Int($0.size.height.rounded()))"
        }.joined(separator: ",")
        return "\(contentKey)|\(uiImages.count)|\(duration)|\(dimensions)"
    }
    
    func makeUIView(context: UIViewRepresentableContext<AnimatedImageView>) -> UIView {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        imageView.contentMode = .scaleAspectFit
        setImages(imageView: imageView)
        context.coordinator.animationKey = animationKey

        let view = UIView()
        view.addSubview(imageView)
        
        imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        imageView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<AnimatedImageView>) {
        guard context.coordinator.animationKey != animationKey,
              let imageView = uiView.subviews.first as? UIImageView else { return }
        context.coordinator.animationKey = animationKey
        setImages(imageView: imageView)
    }
    
    func setImages(imageView: UIImageView) {
        imageView.stopAnimating()
        imageView.image = uiImages.first

        guard uiImages.count > 1 else {
            imageView.animationImages = nil
            return
        }

        imageView.animationImages = uiImages
        imageView.animationDuration = duration
        imageView.startAnimating()
    }
}

#if DEBUG
struct ImageView_Previews : PreviewProvider {
    static var testImages: [UIImage] {
        guard let exercise = MockWorkoutData.metricRandom.workoutExercise.exercise(in: ExerciseStore.shared.exercises) else { return [] }
        var images = [UIImage]()
        for pdfPath in exercise.pdfPaths {
            let url = ExerciseStore.defaultBuiltInExercisesResourceURL.appendingPathComponent(pdfPath)
            if let imageData = try? Data(contentsOf: url), let image = UIImage(data: imageData) {
                images.append(image)
            }
        }
        return images
    }
    
    static var previews: some View {
        AnimatedImageView(uiImages: testImages, duration: 2)
    }
}
#endif
