//
//  LocoView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import Cartography
import CoreLocation

class LocoView: UIScrollView {

    lazy var rows: UIStackView = {
        let box = UIStackView()
        box.axis = .vertical
        return box
    }()

    init() {
        super.init(frame: CGRect.zero)
        backgroundColor = .white
        alwaysBounceVertical = true
        update()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        addSubview(rows)
        constrain(rows, superview!) { rows, superview in
            rows.top == rows.superview!.top
            rows.bottom == rows.superview!.bottom - 8
            rows.left == rows.superview!.left + 16
            rows.right == rows.superview!.right - 16
            rows.right == superview.right - 16
        }
    }

    func update(sample: LocomotionSample? = nil) {
        let loco = LocomotionManager.highlander

        // don't bother updating the UI when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        if sample != nil && Settings.visibleTab != self {
            return
        }

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        rows.addGap(height: 18)
        rows.addSubheading(title: "Locomotion Manager")
        rows.addGap(height: 6)

        rows.addRow(leftText: "Recording state", rightText: loco.recordingState.rawValue)

        if loco.recordingState == .off {
            rows.addRow(leftText: "Requesting accuracy", rightText: "-")

        } else { // must be recording or in sleep mode
            let requesting = loco.locationManager.desiredAccuracy
            if requesting == kCLLocationAccuracyBest {
                rows.addRow(leftText: "Requesting accuracy", rightText: "kCLLocationAccuracyBest")
            } else if requesting == Double.greatestFiniteMagnitude {
                rows.addRow(leftText: "Requesting accuracy", rightText: "Double.greatestFiniteMagnitude")
            } else {
                rows.addRow(leftText: "Requesting accuracy", rightText: String(format: "%.0f metres", requesting))
            }
        }

        var receivingString = "-"
        if loco.recordingState == .recording, let sample = sample {
            var receivingHertz = 0.0
            if let locations = sample.filteredLocations, let duration = locations.dateInterval?.duration, duration > 0 {
                receivingHertz = Double(locations.count) / duration
            }

            if let location = sample.filteredLocations?.last {
                receivingString = String(format: "%.0f metres @ %.1f Hz", location.horizontalAccuracy, receivingHertz)
            }
        }
        rows.addRow(leftText: "Receiving accuracy", rightText: receivingString)

        rows.addGap(height: 14)
        rows.addSubheading(title: "Locomotion Sample")
        rows.addGap(height: 6)

        if let sample = sample {
            rows.addRow(leftText: "Latest sample", rightText: sample.description)
            rows.addRow(leftText: "Behind now", rightText: String(duration: sample.date.age))
            rows.addRow(leftText: "Moving state", rightText: sample.movingState.rawValue)

            if loco.recordPedometerEvents, let stepHz = sample.stepHz {
                rows.addRow(leftText: "Steps per second", rightText: String(format: "%.1f Hz", stepHz))
            } else {
                rows.addRow(leftText: "Steps per second", rightText: "-")
            }

            if loco.recordAccelerometerEvents {
                if let xyAcceleration = sample.xyAcceleration {
                    rows.addRow(leftText: "XY Acceleration", rightText: String(format: "%.2f g", xyAcceleration))
                } else {
                    rows.addRow(leftText: "XY Acceleration", rightText: "-")
                }
                if  let zAcceleration = sample.zAcceleration {
                    rows.addRow(leftText: "Z Acceleration", rightText: String(format: "%.2f g", zAcceleration))
                } else {
                    rows.addRow(leftText: "Z Acceleration", rightText: "-")
                }
            }

            if loco.recordCoreMotionActivityTypeEvents {
                if let coreMotionType = sample.coreMotionActivityType {
                    rows.addRow(leftText: "Core Motion activity", rightText: coreMotionType.rawValue)
                } else {
                    rows.addRow(leftText: "Core Motion activity", rightText: "-")
                }
            }

        } else {
            rows.addRow(leftText: "Latest sample", rightText: "-")
        }
    }

}

