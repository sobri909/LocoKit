//
//  SettingsView.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 9/10/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Cartography

extension NSNotification.Name {
    public static let settingsChanged = Notification.Name("settingsChanged")
}

class SettingsView: UIScrollView {
    
    var showRawLocations = true
    var showFilteredLocations = true
    var showLocomotionSamples = true
    var showStationaryCircles = true
    var showSatelliteMap = false
    var showUserLocation = true
    var autoZoomMap = true
    
    var enableTheClassifier = true
    var enableTransportClassifier = true
    
    var visitsToggleBox: UIView?
    var visitsToggle: UISwitch?
    
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
        
        let currentLocation = ToggleBox(text: "Enable showsUserLocation", toggleDefault: true) { isOn in
            self.showUserLocation = isOn
            NotificationCenter.default.post(Notification(name: .settingsChanged, object: self))
        }
        settingsRows.addRow(views: [currentLocation])
        
        settingsRows.addUnderline()
        
        let satellite = ToggleBox(text: "Satellite map", toggleDefault: false) { isOn in
            self.showSatelliteMap = isOn
            NotificationCenter.default.post(Notification(name: .settingsChanged, object: self))
        }
        let zoom = ToggleBox(text: "Auto zoom") { isOn in
            self.autoZoomMap = isOn
            NotificationCenter.default.post(Notification(name: .settingsChanged, object: self))
        }
        settingsRows.addRow(views: [satellite, zoom])
        
        settingsRows.addGap(height: 18)
        settingsRows.addHeading(title: "Map Data Overlays", alignment: .center)
        settingsRows.addGap(height: 6)
        settingsRows.addUnderline()
        
        let raw = ToggleBox(dotColors: [.red], text: "Raw") { isOn in
            self.showRawLocations = isOn
            NotificationCenter.default.post(Notification(name: .settingsChanged, object: self))
        }
        let smoothed = ToggleBox(dotColors: [.blue, .magenta], text: "Samples") { isOn in
            self.showLocomotionSamples = isOn
            self.visitsToggle?.isEnabled = isOn
            self.visitsToggleBox?.subviews.forEach { $0.alpha = isOn ? 1 : 0.45 }
            NotificationCenter.default.post(Notification(name: .settingsChanged, object: self))
        }
        settingsRows.addRow(views: [raw, smoothed])
        
        settingsRows.addUnderline()
        
        let filtered = ToggleBox(dotColors: [.purple], text: "Filtered") { isOn in
            self.showFilteredLocations = isOn
            NotificationCenter.default.post(Notification(name: .settingsChanged, object: self))
        }
        let visits = ToggleBox(dotColors: [.orange], text: "Visits") { isOn in
            self.showStationaryCircles = isOn
            NotificationCenter.default.post(Notification(name: .settingsChanged, object: self))
        }
        settingsRows.addRow(views: [filtered, visits])
        
        visitsToggleBox = visits
        visitsToggle = visits.toggle
        
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
