//
//  ClassifierView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import Cartography

class ClassifierView: UIScrollView {

    var baseClassifier: ActivityTypeClassifier?
    var transportClassifier: ActivityTypeClassifier?

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

        if sample != nil {
            updateTheBaseClassifier()
            updateTheTransportClassifier()
        }

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        rows.addGap(height: 18)
        rows.addSubheading(title: "Activity Type Classifier (baseTypes)")
        rows.addGap(height: 6)

        if let classifier = baseClassifier {
            rows.addRow(leftText: "Region coverageScore", rightText: classifier.coverageScoreString)
        } else {
            rows.addRow(leftText: "Region coverageScore", rightText: "-")
        }
        rows.addGap(height: 6)

        if loco.recordingState == .recording, let sample = sample {
            if let classifier = baseClassifier {
                let results = classifier.classify(sample)

                for result in results {
                    let row = rows.addRow(leftText: result.name.rawValue.capitalized,
                                                    rightText: String(format: "%.4f", result.score))

                    if result.score < 0.01 {
                        row.subviews.forEach { subview in
                            if let label = subview as? UILabel {
                                label.textColor = UIColor(white: 0.1, alpha: 0.45)
                            }
                        }
                    }
                }

            } else if Settings.enableTheClassifier {
                rows.addRow(leftText: "Fetching ML models...")
            } else {
                rows.addRow(leftText: "Classifier is turned off")
            }
        }

        rows.addGap(height: 14)
        rows.addSubheading(title: "Activity Type Classifier (transportTypes)")
        rows.addGap(height: 6)

        if let classifier = transportClassifier {
            rows.addRow(leftText: "Region coverageScore", rightText: classifier.coverageScoreString)
        } else {
            rows.addRow(leftText: "Region coverageScore", rightText: "-")
        }
        rows.addGap(height: 6)

        if loco.recordingState == .recording, let sample = sample {
            if let classifier = transportClassifier {
                let results = classifier.classify(sample)

                for result in results {
                    let row = rows.addRow(leftText: result.name.rawValue.capitalized,
                                                    rightText: String(format: "%.4f", result.score))

                    if result.score < 0.01 {
                        row.subviews.forEach { subview in
                            if let label = subview as? UILabel {
                                label.textColor = UIColor(white: 0.1, alpha: 0.45)
                            }
                        }
                    }
                }

            } else if Settings.enableTheClassifier && Settings.enableTransportClassifier {
                rows.addRow(leftText: "Fetching ML models...")
            } else {
                rows.addRow(leftText: "Classifier is turned off")
            }
        }

        rows.addGap(height: 12)
    }

    func updateTheBaseClassifier() {
        guard Settings.enableTheClassifier else {
            return
        }

        // need a coordinate to know what classifier to fetch (there's thousands of them)
        guard let coordinate = LocomotionManager.highlander.filteredLocation?.coordinate else {
            return
        }

        // no need to update anything if the current classifier is still valid
        if let classifier = baseClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // note: this will return nil if the ML models haven't been fetched yet, but will also trigger a fetch
        baseClassifier = ActivityTypeClassifier(requestedTypes: ActivityTypeName.baseTypes, coordinate: coordinate)
    }

    func updateTheTransportClassifier() {
        guard Settings.enableTheClassifier && Settings.enableTransportClassifier else {
            return
        }

        // need a coordinate to know what classifier to fetch (there's thousands of them)
        guard let coordinate = LocomotionManager.highlander.filteredLocation?.coordinate else {
            return
        }

        // no need to update anything if the current classifier is still valid
        if let classifier = transportClassifier, classifier.contains(coordinate: coordinate), !classifier.isStale {
            return
        }

        // note: this will return nil if the ML models haven't been fetched yet, but will also trigger a fetch
        transportClassifier = ActivityTypeClassifier(requestedTypes: ActivityTypeName.transportTypes, coordinate: coordinate)
    }

}
