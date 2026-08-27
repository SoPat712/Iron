//
//  RPE.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 22.08.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

public enum RPE {
    public static let allowedValues = stride(from: 5, through: 10, by: 0.5)
    
    public static func title(_ rpe: Double) -> String? {
        switch rpe {
        case 5:
            return "Easy effort with about 5 repetitions in reserve."
        case 5.5:
            return "Easy to moderate effort."
        case 6:
            return "You could do about 4 more repetitions."
        case 6.5:
            return "You could do 3-4 more repetitions."
        case 7:
            return "You could do 3 more repetitions."
        case 7.5:
            return "You could do 2-3 more repetitions."
        case 8:
            return "You could do 2 more repetitions."
        case 8.5:
            return "You could do 1-2 more repetitions."
        case 9:
            return "You could do 1 more repetition."
        case 9.5:
            return "You couldn't do any more repetitions, but possibly you could've increased the weight."
        case 10:
            return "You couldn't do any more repetitions."
        default:
            return nil
        }
    }
}
