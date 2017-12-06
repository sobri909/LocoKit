//
//  SettingsView.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 9/10/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import SwiftNotes
import Cartography

extension NSNotification.Name {
    public static let settingsChanged = Notification.Name("settingsChanged")
}

class SettingsView: UIScrollView {

    var showTimelineItems = true

    var showRawLocations = true
    var showFilteredLocations = true
    var showLocomotionSamples = true

    var showSatelliteMap = false
    var showUserLocation = true
    var autoZoomMap = true
    
    var enableTheClassifier = true
    var enableTransportClassifier = true

    var locoDataToggleBoxes: [ToggleBox] = []

    var transportClassifierToggleBox: UIView?
    var transportClassifierToggle: UISwitch?
    
    lazy var settingsRows: UIStackView = {
        let box = UIStackView()
        box.axis = .vertical
        box.isHidden = true
        
        let background = UIView()
        background.backgroundColor = UIColor(white: 0.85, alpha: 1)
        
        box.addSubview(background)
        constrain(background) { background in
            background.edges == background.superview!.edges
        }
        
        return box
    }()
    
    init() {
        super.init(frame: CGRect.zero)
        alwaysBounceVertical = true
        buildSettingsViewTree()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        addSubview(settingsRows)
        constrain(settingsRows, superview!) { box, superview in
            box.top == box.superview!.top
            box.bottom == box.superview!.bottom
            box.left == box.superview!.left + 8
            box.right == box.superview!.right - 8
            box.right == superview.right - 8
        }
    }
    
    func buildSettingsViewTree() {
        settingsRows.addGap(height: 24)
        settingsRows.addHeading(title: "Map Style", alignment: .center)
        settingsRows.addGap(height: 6)
        settingsRows.addUnderline()
        
        let currentLocation = ToggleBox(text: "Enable showsUserLocation", toggleDefault: showUserLocation) { isOn in
            self.showUserLocation = isOn
            trigger(.settingsChanged, on: self)
        }
        settingsRows.addRow(views: [currentLocation])
        
        settingsRows.addUnderline()
        
        let satellite = ToggleBox(text: "Satellite map", toggleDefault: showSatelliteMap) { isOn in
            self.showSatelliteMap = isOn
            trigger(.settingsChanged, on: self)
        }
        let zoom = ToggleBox(text: "Auto zoom") { isOn in
            self.autoZoomMap = isOn
            trigger(.settingsChanged, on: self)
        }
        settingsRows.addRow(views: [satellite, zoom])
        
        settingsRows.addGap(height: 18)
        settingsRows.addHeading(title: "Map Data", alignment: .center)
        settingsRows.addGap(height: 6)
        settingsRows.addUnderline()

        // toggle for showing timeline items
        let visits = ToggleBox(dotColors: [.brown, .orange], text: "Timeline", toggleDefault: showTimelineItems) { isOn in
            self.showTimelineItems = isOn
            self.locoDataToggleBoxes.forEach { $0.disabled = isOn }
            trigger(.settingsChanged, on: self)
        }

        // toggle for showing filtered locations
        let filtered = ToggleBox(dotColors: [.purple], text: "Filtered", toggleDefault: showFilteredLocations) { isOn in
            self.showFilteredLocations = isOn
            trigger(.settingsChanged, on: self)
        }
        filtered.disabled = showTimelineItems
        locoDataToggleBoxes.append(filtered)

        // add the toggles to the view
        settingsRows.addRow(views: [visits, filtered])
        
        settingsRows.addUnderline()
        
        // toggle for showing locomotion samples
        let samples = ToggleBox(dotColors: [.blue, .magenta], text: "Samples", toggleDefault: showLocomotionSamples) { isOn in
            self.showLocomotionSamples = isOn
            trigger(.settingsChanged, on: self)
        }
        samples.disabled = showTimelineItems
        locoDataToggleBoxes.append(samples)

        // toggle for showing raw locations
        let raw = ToggleBox(dotColors: [.red], text: "Raw", toggleDefault: showRawLocations) { isOn in
            self.showRawLocations = isOn
            trigger(.settingsChanged, on: self)
        }
        raw.disabled = showTimelineItems
        locoDataToggleBoxes.append(raw)

        // add the toggles to the view
        settingsRows.addRow(views: [samples, raw])

        settingsRows.addGap(height: 18)
        settingsRows.addHeading(title: "Activity Type Classifiers", alignment: .center)
        settingsRows.addGap(height: 6)
        settingsRows.addUnderline()
        
        let classifierBox = ToggleBox(text: "Base types") { isOn in
            self.enableTheClassifier = isOn
            self.transportClassifierToggle?.isEnabled = isOn
            self.transportClassifierToggleBox?.subviews.forEach { $0.alpha = isOn ? 1 : 0.45 }
        }
        let extended = ToggleBox(text: "Transport") { isOn in
            self.enableTransportClassifier = isOn
        }
        settingsRows.addRow(views: [classifierBox, extended])
        
        transportClassifierToggleBox = extended
        transportClassifierToggle = extended.toggle
        
        settingsRows.addGap(height: 18)
    }
}
