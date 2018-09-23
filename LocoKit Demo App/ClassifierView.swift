//
//  ClassifierView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import Anchorage

class ClassifierView: UIScrollView {

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
        rows.topAnchor == rows.superview!.topAnchor
        rows.bottomAnchor == rows.superview!.bottomAnchor - 8
        rows.leftAnchor == rows.superview!.leftAnchor + 16
        rows.rightAnchor == rows.superview!.rightAnchor - 16
        rows.rightAnchor == superview!.rightAnchor - 16
    }

    func update(sample: LocomotionSample? = nil) {
        // don't bother updating the UI when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else { return }

        // don't bother updating the table if we're not the visible tab
        if sample != nil && Settings.visibleTab != self { return }

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        rows.addGap(height: 18)
        rows.addSubheading(title: "Sample Classifier Results")
        rows.addGap(height: 6)

        let timelineClassifier = TimelineClassifier.highlander

        if let sampleClassifier = timelineClassifier.sampleClassifier {
            rows.addRow(leftText: "Region coverageScore", rightText: sampleClassifier.coverageScoreString)
        } else {
            rows.addRow(leftText: "Region coverageScore", rightText: "-")
        }
        rows.addGap(height: 6)

        // if we weren't given a sample, then we were only here to build the initial empty table
        guard let sample = sample else { return }

        // get the classifier results for the given sample
        guard let results = timelineClassifier.classify(sample) else { return }

        for result in results {
            let row = rows.addRow(leftText: result.name.rawValue.capitalized,
                                  rightText: String(format: "%.7f", result.score))

            if result.score < 0.01 {
                row.subviews.forEach { subview in
                    if let label = subview as? UILabel {
                        label.textColor = UIColor(white: 0.1, alpha: 0.45)
                    }
                }
            }
        }
    }

}
