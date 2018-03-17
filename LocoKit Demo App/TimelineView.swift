//
//  TimelineView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import Cartography

class TimelineView: UIScrollView {

    let timeline: TimelineManager

    lazy var rows: UIStackView = {
        let box = UIStackView()
        box.axis = .vertical
        return box
    }()

    init(timeline: TimelineManager) {
        self.timeline = timeline
        super.init(frame: CGRect.zero)
        backgroundColor = .white
        alwaysBounceVertical = true
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

    func update(with items: [TimelineItem]) {
        // don't bother updating the UI when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else { return }

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        rows.addGap(height: 18)
        rows.addHeading(title: "Timeline Items")
        rows.addGap(height: 2)

        if items.isEmpty {
            rows.addRow(leftText: "-")
            return
        }

        var nextItem: TimelineItem?
        for timelineItem in items {
            if let next = nextItem, next.previousItem != timelineItem || timelineItem.nextItem != next { addDataGap() }
            nextItem = timelineItem
            add(timelineItem)
        }
    }

    func add(_ timelineItem: TimelineItem) {
        rows.addGap(height: 14)
        var title = ""
        if let start = timelineItem.startDate {
            title += "[\(dateFormatter.string(from: start))] "
        }
        if timelineItem.isCurrentItem {
            title += "Current "
        } else if timeline.activeItems.contains(timelineItem) {
            title += "Active "
        } else {
            title += "Finalised "
        }
        title += timelineItem.isNolo ? "Nolo" : timelineItem is Visit ? "Visit" : "Path"
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

        if let previous = timelineItem.previousItem, !timelineItem.withinMergeableDistance(from: previous) {
            if
                let timeGap = timelineItem.timeInterval(from: previous),
                let distGap = timelineItem.distance(from: previous)
            {
                rows.addRow(leftText: "Unmergeable gap from previous",
                            rightText: "\(String(duration: timeGap)) (\(String(metres: distGap)))",
                    background: debugColor)
            } else {
                rows.addRow(leftText: "Unmergeable gap from previous", rightText: "unknown gap size",
                            background: debugColor)
            }
            let maxMerge = timelineItem.maximumMergeableDistance(from: previous)
            rows.addRow(leftText: "Max mergeable gap", rightText: "\(String(metres: maxMerge))", background: debugColor)
        }

        rows.addRow(leftText: "Samples", rightText: "\(timelineItem.samples.count)", background: debugColor)

        rows.addRow(leftText: "ItemId", rightText: timelineItem.itemId.uuidString, background: debugColor)
    }

    func addDataGap(duration: TimeInterval? = nil) {
        rows.addGap(height: 14)
        rows.addUnderline()
        rows.addGap(height: 14)

        if let duration = duration {
            rows.addSubheading(title: "Timeline Gap (\(String(duration: duration)))", color: .red)
        } else {
            rows.addSubheading(title: "Timeline Gap", color: .red)
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
