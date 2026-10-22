//
//  ExerciseFilter.swift
//  Iron
//
//  Created by Karim Abou Zeid on 16.09.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import Combine
import WorkoutDataKit

class ExerciseFilter: ObservableObject {
    var filter: String {
        willSet {
            if isEmpty != newValue.isEmpty {
                isEmpty = newValue.isEmpty
            }
            searchSubject.send(newValue)
        }
    }
    
    @Published var exercises: [Exercise]
    @Published var isEmpty: Bool
    
    private var searchSubject = PassthroughSubject<String, Never>()
    private var cancellable: Cancellable?
    
    init(exercises: [Exercise], filter: String = "", exerciseStore: ExerciseStore = .shared) {
        self.exercises = exerciseStore.orderedByRecency(ExerciseStore.filter(exercises: exercises, using: filter))
        self.filter = filter
        self.isEmpty = filter.isEmpty
        
        cancellable = searchSubject
            .prepend(filter)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.global(qos: .userInteractive))
            .removeDuplicates()
            .map { ExerciseStore.filter(exercises: exercises, using: $0) }
            .combineLatest(exerciseStore.$lastPerformedDates)
            .map { ExerciseRecency.ordered($0.0, dates: $0.1) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.exercises = $0 }
    }
}
