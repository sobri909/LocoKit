//
// Created by Matt Greenfield on 14/04/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import CoreLocation

public extension String {

    public init(duration: TimeInterval, style: DateComponentsFormatter.UnitsStyle = .full, maximumUnits: Int = 2) {
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

    public init(metres: CLLocationDistance, style: DateComponentsFormatter.UnitsStyle = .full) {
        let usesMetric = Locale.current.usesMetricSystem

        let number = usesMetric
            ? NumberFormatter.localizedString(from: round(metres) as NSNumber, number: .decimal)
            : NumberFormatter.localizedString(from: round(metres * CLLocationDistance.feetPerMetre) as NSNumber,
                                              number: .decimal)

        let unit: String
        switch style {
        case .full where usesMetric && ["-1", "1"].contains(number):
            unit = "metre"
        case .full where usesMetric && !["-1", "1"].contains(number):
            unit = "metres"
        case .full where !usesMetric && ["-1", "1"].contains(number):
            unit = "foot"
        case .full where !usesMetric && !["-1", "1"].contains(number):
            unit = "feet"
        case .abbreviated where usesMetric:
            unit = "m"
        case .abbreviated where !usesMetric:
            unit = "ft"
        default: // impossiblez
            unit = ""
        }

        self.init(format: "\(number) \(unit)")
    }

    public init(metresPerSecond mps: Double) {
        let kmh = mps * 3.6

        if Locale.current.usesMetricSystem {
            self.init(format: "%.1f km/h", kmh)

        } else {
            let mph = kmh / 1.609344
            self.init(format: "%.1f mph", mph)
        }
    }

}
