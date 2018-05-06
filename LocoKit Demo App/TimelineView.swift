//
//  TimelineView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import Anchorage

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
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        addSubview(rows)
        rows.topAnchor == rows.superview!.topAnchor
        rows.bottomAnchor == rows.superview!.bottomAnchor - 16
        rows.leftAnchor == rows.superview!.leftAnchor + 16
        rows.rightAnchor == rows.superview!.rightAnchor - 16
        rows.rightAnchor == superview!.rightAnchor - 16
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

        for timelineItem in items {
            if timelineItem.isDataGap {
                addDataGap(timelineItem)
            } else {
                add(timelineItem)
            }
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

        if timelineItem.hasBrokenEdges {
            if timelineItem.nextItem == nil && !timelineItem.isCurrentItem {
                rows.addRow(leftText: "nextItem is nil", color: .red)
            }
            if timelineItem.previousItem == nil {
                rows.addRow(leftText: "previousItem is nil", color: .red)
            }
        }

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

    func addDataGap(_ timelineItem: TimelineItem) {
        guard timelineItem.isDataGap else { return }

        rows.addGap(height: 14)
        rows.addUnderline()
        rows.addGap(height: 14)

        rows.addSubheading(title: "Timeline Gap (\(String(duration: timelineItem.duration)))", color: .red)

        rows.addGap(height: 14)
        rows.addUnderline()
    }

    lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
