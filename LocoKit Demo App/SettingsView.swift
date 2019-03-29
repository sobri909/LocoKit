//
//  SettingsView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 9/10/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import SwiftNotes
import Anchorage

extension NSNotification.Name {
    public static let settingsChanged = Notification.Name("settingsChanged")
}

class SettingsView: UIScrollView {

    var locoDataToggleBoxes: [ToggleBox] = []

    lazy var rows: UIStackView = {
        let box = UIStackView()
        box.axis = .vertical
        return box
    }()

    // MARK: - 
    
    init() {
        super.init(frame: CGRect.zero)
        backgroundColor = .white
        alwaysBounceVertical = true
        buildViewTree()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        addSubview(rows)
        rows.topAnchor == rows.superview!.topAnchor
        rows.bottomAnchor == rows.superview!.bottomAnchor
        rows.leftAnchor == rows.superview!.leftAnchor + 8
        rows.rightAnchor == rows.superview!.rightAnchor - 8
        rows.rightAnchor == superview!.rightAnchor - 8
    }

    // MARK: -

    func buildViewTree() {
        rows.addGap(height: 24)
        rows.addSubheading(title: "Map Style", alignment: .center)
        rows.addGap(height: 6)
        rows.addUnderline()
        
        let currentLocation = ToggleBox(text: "Enable showsUserLocation", toggleDefault: Settings.showUserLocation) { isOn in
            Settings.showUserLocation = isOn
            trigger(.settingsChanged, on: self)
        }
        rows.addRow(views: [currentLocation])
        
        rows.addUnderline()
        
        let satellite = ToggleBox(text: "Satellite map", toggleDefault: Settings.showSatelliteMap) { isOn in
            Settings.showSatelliteMap = isOn
            trigger(.settingsChanged, on: self)
        }
        let zoom = ToggleBox(text: "Auto zoom") { isOn in
            Settings.autoZoomMap = isOn
            trigger(.settingsChanged, on: self)
        }
        rows.addRow(views: [satellite, zoom])
        
        rows.addGap(height: 18)
        rows.addSubheading(title: "Map Data", alignment: .center)
        rows.addGap(height: 6)
        rows.addUnderline()

        // toggle for showing timeline items
        let visits = ToggleBox(dotColors: [.brown, .orange], text: "Timeline", toggleDefault: Settings.showTimelineItems) { isOn in
            Settings.showTimelineItems = isOn
            self.locoDataToggleBoxes.forEach { $0.disabled = isOn }
            trigger(.settingsChanged, on: self)
        }

        // toggle for showing filtered locations
        let filtered = ToggleBox(dotColors: [.purple], text: "Filtered", toggleDefault: Settings.showFilteredLocations) { isOn in
            Settings.showFilteredLocations = isOn
            trigger(.settingsChanged, on: self)
        }
        filtered.disabled = Settings.showTimelineItems
        locoDataToggleBoxes.append(filtered)

        // add the toggles to the view
        rows.addRow(views: [visits, filtered])
        
        rows.addUnderline()
        
        // toggle for showing locomotion samples
        let samples = ToggleBox(dotColors: [.blue, .magenta], text: "Samples", toggleDefault: Settings.showLocomotionSamples) { isOn in
            Settings.showLocomotionSamples = isOn
            trigger(.settingsChanged, on: self)
        }
        samples.disabled = Settings.showTimelineItems
        locoDataToggleBoxes.append(samples)

        // toggle for showing raw locations
        let raw = ToggleBox(dotColors: [.red], text: "Raw", toggleDefault: Settings.showRawLocations) { isOn in
            Settings.showRawLocations = isOn
            trigger(.settingsChanged, on: self)
        }
        raw.disabled = Settings.showTimelineItems
        locoDataToggleBoxes.append(raw)

        // add the toggles to the view
        rows.addRow(views: [samples, raw])

        rows.addGap(height: 18)
    }

}
