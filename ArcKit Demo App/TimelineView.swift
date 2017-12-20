//
//  TimelineView.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import ArcKit
import Cartography

class TimelineView: UIScrollView {

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
            rows.bottom == rows.superview!.bottom - 16
            rows.left == rows.superview!.left + 16
            rows.right == rows.superview!.right - 16
            rows.right == superview.right - 16
        }
    }

    func update() {
        let timeline = DefaultTimelineManager.highlander

        // don't bother updating the UI when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        rows.addGap(height: 18)
        rows.addHeading(title: "Active Timeline Items")
        rows.addGap(height: 2)

        var nextItem: TimelineItem?

        if timeline.activeTimelineItems.isEmpty {
            rows.addRow(leftText: "-")
        } else {
            for timelineItem in timeline.activeTimelineItems.reversed() {
                if let next = nextItem, next.previousItem != timelineItem {
                    addDataGap()
                }
                nextItem = timelineItem

                add(timelineItem)
            }
        }

        rows.addGap(height: 18)
        rows.addHeading(title: "Finalised Timeline Items")
        rows.addGap(height: 2)

        if timeline.finalisedTimelineItems.isEmpty {
            rows.addRow(leftText: "-")
        } else {
            for timelineItem in timeline.finalisedTimelineItems.reversed() {
                if let next = nextItem, next.previousItem != timelineItem {
                    addDataGap()
                }
                nextItem = timelineItem

                add(timelineItem)
            }
        }
    }

    func add(_ timelineItem: TimelineItem) {
        let timeline = DefaultTimelineManager.highlander

        rows.addGap(height: 14)
        var title = ""
        if let start = timelineItem.startDate {
            title += "[\(dateFormatter.string(from: start))] "
        }
        if timelineItem == timeline.currentItem {
            title += "Current "
        }
        title += timelineItem is Visit ? "Visit" : "Path"
        if let path = timelineItem as? Path, let activityType = path.movingActivityType {
            title += " (\(activityType)"
            if Settings.showDebugTimelineDetails {
                if let modeType = path.modeMovingActivityType {
                    title += ", mode: \(modeType)"
                }
            }
            title += ")"
        }
        rows.addSubheading(title: title)
        rows.addGap(height: 6)

        rows.addRow(leftText: "Duration", rightText: String(duration: timelineItem.duration))

        if let path = timelineItem as? Path {
            rows.addRow(leftText: "Distance", rightText: String(metres: path.distance))
            rows.addRow(leftText: "Speed", rightText: String(metresPerSecond: path.metresPerSecond))
        }

        if let visit = timelineItem as? Visit {
            rows.addRow(leftText: "Radius", rightText: String(metres: visit.radius2sd))
        }

        let keeperString = timelineItem.isInvalid ? "invalid" : timelineItem.isWorthKeeping ? "keeper" : "valid"
        rows.addRow(leftText: "Keeper status", rightText: keeperString)

        // the rest of the rows are debug bits, mostly for my benefit only
        guard Settings.showDebugTimelineDetails else {
            return
        }

        let debugColor = UIColor(white: 0.94, alpha: 1)

        if timelineItem != timeline.currentItem, let end = timelineItem.endDate {
            rows.addRow(leftText: "Ended", rightText: "\(String(duration: end.age)) ago",
                background: debugColor)
        }

        if let previousItem = timelineItem.previousItem {
            if
                let timeGap = timelineItem.timeIntervalFrom(previousItem),
                let distGap = timelineItem.distance(from: previousItem)
            {
                rows.addRow(leftText: "Gap from previous",
                                    rightText: "\(String(duration: timeGap)) (\(String(metres: distGap)))",
                    background: debugColor)
            }
            let acceptableGap = timelineItem.withinMergeableDistance(from: previousItem)
            rows.addRow(leftText: "Within mergeable distance", rightText: acceptableGap ? "yes" : "no",
                                background: debugColor)
            if !acceptableGap {
                let maxMerge = timelineItem.maximumMergeableDistance(from: previousItem)
                rows.addRow(leftText: "Max merge from previous", rightText: "\(String(metres: maxMerge))",
                    background: debugColor)
            }
        }

        rows.addRow(leftText: "Samples", rightText: "\(timelineItem.samples.count)", background: debugColor)
    }

    func addDataGap(duration: TimeInterval? = nil) {
        rows.addGap(height: 14)
        rows.addUnderline()
        rows.addGap(height: 14)

        if let duration = duration {
            rows.addSubheading(title: "Timeline Gap (\(String(duration: duration)))")
        } else {
            rows.addSubheading(title: "Timeline Gap")
        }

        rows.addGap(height: 14)
        rows.addUnderline()
    }

    lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
