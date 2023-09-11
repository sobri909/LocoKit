//
// Created by Matt Greenfield on 14/04/16.
// Copyright (c) 2016 Big Paua. All rights reserved.
//

import CoreLocation
import SwiftUI

public extension String.StringInterpolation {
    mutating func appendInterpolation(duration: TimeInterval, fractionalUnit: Bool = false,
                                      style: DateComponentsFormatter.UnitsStyle = .full,
                                      maximumUnits: Int = 2, alwaysIncludeSeconds: Bool = false) {
        appendLiteral(String(duration: duration, fractionalUnit: fractionalUnit, style: style,
                             maximumUnits: maximumUnits, alwaysIncludeSeconds: alwaysIncludeSeconds))
    }

    mutating func appendInterpolation(metres: CLLocationDistance,
                                      style: MeasurementFormatter.UnitStyle = .medium,
                                      isAltitude: Bool = false) {
        appendLiteral(String(metres: metres, style: style, isAltitude: isAltitude))
    }

    mutating func appendInterpolation(speed: CLLocationSpeed, style: Formatter.UnitStyle? = nil) {
        appendLiteral(String(speed: speed, style: style))
    }
}

public extension LocalizedStringKey.StringInterpolation {
    mutating func appendInterpolation(duration: TimeInterval, fractionalUnit: Bool = false,
                                      style: DateComponentsFormatter.UnitsStyle = .full,
                                      maximumUnits: Int = 2, alwaysIncludeSeconds: Bool = false) {
        appendLiteral(String(duration: duration, fractionalUnit: fractionalUnit, style: style,
                             maximumUnits: maximumUnits, alwaysIncludeSeconds: alwaysIncludeSeconds))
    }
    
    mutating func appendInterpolation(metres: CLLocationDistance,
                                      style: MeasurementFormatter.UnitStyle = .medium,
                                      isAltitude: Bool = false) {
        appendLiteral(String(metres: metres, style: style, isAltitude: isAltitude))
    }
    
    mutating func appendInterpolation(speed: CLLocationSpeed, style: Formatter.UnitStyle? = nil) {
        appendLiteral(String(speed: speed, style: style))
    }
}

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

        if alwaysIncludeSeconds || duration < 60 * 3 {
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

            if #available(iOS 16, *) {
                if Locale.current.measurementSystem == .metric {
                    self.init(format: formatter.string(from: metres.measurement))
                } else {
                    self.init(format: formatter.string(from: metres.measurement.converted(to: UnitLength.feet)))
                }
            } else {
                if Locale.current.usesMetricSystem {
                    self.init(format: formatter.string(from: metres.measurement))
                } else {
                    self.init(format: formatter.string(from: metres.measurement.converted(to: UnitLength.feet)))
                }
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
    
    init(paceForSpeed mps: CLLocationSpeed) {
        let totalSeconds = TimeInterval(1000.0 / mps)
        let minutes = floor(totalSeconds / 60)
        let remainderSeconds = totalSeconds - (minutes * 60)
        print("mps: \(mps), totalSeconds: \(totalSeconds), minutes: \(minutes), remainderSeconds: \(remainderSeconds)")

        self.init(format: "%.0f'%.0f\"", minutes, remainderSeconds)
    }

    init(speed: CLLocationSpeed, style: Formatter.UnitStyle? = nil) {
        self.init(metresPerSecond: speed, style: style)
    }
    
    init(metresPerSecond mps: CLLocationSpeed, style: Formatter.UnitStyle? = nil) {
        let formatter = MeasurementFormatter()
        if let style = style {
            formatter.unitStyle = style
        }
        if mps.kmh < 30 {
            formatter.numberFormatter.maximumFractionDigits = 1
        } else {
            formatter.numberFormatter.maximumFractionDigits = 0
        }
        self.init(format: formatter.string(from: mps.speedMeasurement))
    }

    func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
    
    func appendLineToURL(fileURL: URL) throws {
        try appendingFormat("\n").appendToURL(fileURL: fileURL)
    }

    func appendToURL(fileURL: URL) throws {
        let dataObj = data(using: .utf8)!
        try dataObj.appendToURL(fileURL)
    }

}

extension Data {
    func appendToURL(_ fileURL: URL) throws {
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileURL, options: .atomic)
        }
    }
}
