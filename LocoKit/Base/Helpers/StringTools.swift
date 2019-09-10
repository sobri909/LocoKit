//
// Created by Matt Greenfield on 14/04/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import CoreLocation

public extension String {

    init(duration: TimeInterval, fractionalUnit: Bool = false, style: DateComponentsFormatter.UnitsStyle = .full,
                maximumUnits: Int = 2, alwaysIncludeSeconds: Bool = false) {
        if duration.isNaN {
            self.init(format: "NaN")
            return
        }

        if fractionalUnit {
            let unitStyle: Formatter.UnitStyle
            switch style {
            case .positional: unitStyle = .short
            case .abbreviated: unitStyle = .short
            case .short: unitStyle = .medium
            case .brief: unitStyle = .medium
            case .full: unitStyle = .long
            case .spellOut: unitStyle = .long
            }
            self.init(String(duration: Measurement(value: duration, unit: UnitDuration.seconds), style: unitStyle))
            return
        }

        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = maximumUnits
        formatter.unitsStyle = style

        if alwaysIncludeSeconds || duration < 60 * 2 {
            formatter.allowedUnits = [.second, .minute, .hour, .day, .month]
        } else {
            formatter.allowedUnits = [.minute, .hour, .day, .month]
        }

        self.init(format: formatter.string(from: duration)!)
    }

    init(duration: Measurement<UnitDuration>, style: Formatter.UnitStyle = .medium) {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = style
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        self.init(format: formatter.string(from: duration))
    }

    init(distance: CLLocationDistance, style: MeasurementFormatter.UnitStyle = .medium, isAltitude: Bool = false) {
        self.init(metres: distance, style: style, isAltitude: isAltitude)
    }

    init(metres: CLLocationDistance, style: MeasurementFormatter.UnitStyle = .medium, isAltitude: Bool = false) {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = style

        if isAltitude {
            formatter.unitOptions = .providedUnit
            formatter.numberFormatter.maximumFractionDigits = 0
            if Locale.current.usesMetricSystem {
                self.init(format: formatter.string(from: metres.measurement))
            } else {
                self.init(format: formatter.string(from: metres.measurement.converted(to: UnitLength.feet)))
            }
            return
        }

        formatter.unitOptions = .naturalScale
        if metres < 1000 || metres > 20000 {
            formatter.numberFormatter.maximumFractionDigits = 0
        } else {
            formatter.numberFormatter.maximumFractionDigits = 1
        }
        self.init(format: formatter.string(from: metres.measurement))
    }

    init(speed: CLLocationSpeed, style: Formatter.UnitStyle? = nil) {
        self.init(metresPerSecond: speed, style: style)
    }
    
    init(metresPerSecond mps: CLLocationSpeed, style: Formatter.UnitStyle? = nil) {
        let formatter = MeasurementFormatter()
        if let style = style {
            formatter.unitStyle = style
        }
        if mps.kmh < 10 {
            formatter.numberFormatter.maximumFractionDigits = 1
        } else {
            formatter.numberFormatter.maximumFractionDigits = 0
        }
        self.init(format: formatter.string(from: mps.speedMeasurement))
    }

}
