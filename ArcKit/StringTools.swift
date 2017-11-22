//
// Created by Matt Greenfield on 14/04/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

extension String {

    init(duration: TimeInterval, style: DateComponentsFormatter.UnitsStyle = .full, maximumUnits: Int = 2) {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = maximumUnits
        formatter.unitsStyle = style

        if duration < 60 {
            formatter.allowedUnits = [.second, .minute, .hour, .day, .month]
        } else {
            formatter.allowedUnits = [.minute, .hour, .day, .month]
        }

        self.init(format: formatter.string(from: duration)!)
    }

}
