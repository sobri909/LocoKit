//
//  ViewController.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 10/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import UIKit
import MapKit
import ArcKit
import MGEvents
import Cartography
import CoreLocation

class ViewController: UIViewController {
    
    var rawLocations: [CLLocation] = []
    var filteredLocations: [CLLocation] = []
    var locomotionSamples: [LocomotionSample] = []
    
    var showRawLocations = true
    var showFilteredLocations = true
    var showLocomotionSamples = true
    var showStationaryCircles = true
    var showSatelliteMap = false
    var autoZoomMap = true
    
    var visitsToggleBox: UIView?
    var visitsToggle: UISwitch?
    
    // MARK: controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
       
        buildViewTree()

        let loco = LocomotionManager.highlander
        let centre = NotificationCenter.default
        
        centre.addObserver(forName: .locomotionSampleUpdated, object: loco, queue: OperationQueue.main) { note in
            self.locomotionSampleUpdated(note: note)
        }
        
        loco.requestLocationPermission()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return map.mapType == .standard ? .default : .lightContent
    }
  
    // MARK: process incoming locations
    
    func locomotionSampleUpdated(note: Notification) {
        if let location = note.userInfo?["rawLocation"] as? CLLocation {
            rawLocations.append(location)
        }
        
        if let location = note.userInfo?["filteredLocation"] as? CLLocation {
            filteredLocations.append(location)
        }
       
        let sample = LocomotionManager.highlander.locomotionSample()
        
        locomotionSamples.append(sample)
        
        updateTheStatusBar(sample: sample)
        updateTheMap()
    }
    
    // MARK: tap actions
    
    func tappedStart() {
        let loco = LocomotionManager.highlander
        
        // for demo purposes only. the default value already best balances accuracy with battery use
        loco.maximumDesiredLocationAccuracy = kCLLocationAccuracyBest
        
        // this is independent of the user's setting, and will show a blue bar if user has denied "always"
        loco.locationManager.allowsBackgroundLocationUpdates = true
        
        loco.startCoreLocation()
        
        startButton.isHidden = true
        stopButton.isHidden = false
    }
    
    func tappedStop() {
        LocomotionManager.highlander.stopCoreLocation()
        
        stopButton.isHidden = true
        startButton.isHidden = false
    }
    
    func tappedClear() {
        rawLocations.removeAll()
        filteredLocations.removeAll()
        locomotionSamples.removeAll()
        
        updateTheMap()
    }
    
    // MARK: UI updating
    
    func updateTheStatusBar(sample: LocomotionSample) {
        let desired = LocomotionManager.highlander.locationManager.desiredAccuracy
        desiredAccuracyLabel.text = String(format: "requesting %.0f metres", desired)
        
        var hertz = 0.0
        if let duration = sample.filteredLocations.dateInterval?.duration, duration > 0 {
            hertz = Double(sample.filteredLocations.count) / duration
        }
        
        if let location = sample.filteredLocations.last {
            achievedAccuracyLabel.text = String(format: "receiving %.0f metres @ %.1f Hz", location.horizontalAccuracy, hertz)
        } else {
            achievedAccuracyLabel.text = "receiving nothing"
        }
        
        statusRowBackground.backgroundColor = .blue
        UIView.animate(withDuration: 1) {
            self.statusRowBackground.backgroundColor = UIColor(white: 0.85, alpha: 1)
        }
    }
    
    func updateTheMap() {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let mapType: MKMapType = showSatelliteMap ? .hybrid : .standard
        if mapType != map.mapType {
            map.mapType = mapType
            setNeedsStatusBarAppearanceUpdate()
        }
        
        if showRawLocations {
            addPath(locations: rawLocations, color: .red)
        }
        
        if showFilteredLocations {
            addPath(locations: filteredLocations, color: .purple)
        }
        
        if showLocomotionSamples {
            addSamples(samples: locomotionSamples)
        }
        
        if autoZoomMap {
            zoomToShow(overlays: map.overlays)
        }
    }
    
    func zoomToShow(overlays: [MKOverlay]) {
        guard !overlays.isEmpty else {
            return
        }
        
        var mapRect: MKMapRect?
        for overlay in overlays {
            if mapRect == nil {
                mapRect = overlay.boundingMapRect
            } else {
                mapRect = MKMapRectUnion(mapRect!, overlay.boundingMapRect)
            }
        }
        
        let padding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        map.setVisibleMapRect(mapRect!, edgePadding: padding, animated: true)
    }
    
    // MARK: view tree building
    
    func buildViewTree() {
        view.addSubview(map)
        constrain(map) { map in
            map.top == map.superview!.top
            map.left == map.superview!.left
            map.right == map.superview!.right
            map.height == map.superview!.height * 0.5
        }
        
        view.addSubview(rowsBox)
        constrain(map, rowsBox) { map, box in
            box.top == map.bottom
            box.left == box.superview!.left + 6
            box.right == box.superview!.right - 6
        }
        
        let background = UIView()
        background.backgroundColor = UIColor(white: 0.85, alpha: 1)
        
        rowsBox.addSubview(background)
        constrain(background) { background in
            background.edges == background.superview!.edges
        }
        
        let topButtons = UIView()
        rowsBox.addArrangedSubview(topButtons)
        topButtons.addSubview(startButton)
        topButtons.addSubview(stopButton)
        topButtons.addSubview(clearButton)
        
        constrain(startButton, stopButton, clearButton) { startButton, stopButton, clearButton in
            align(top: startButton, stopButton, clearButton)
            align(bottom: startButton, stopButton, clearButton)
            
            startButton.top == startButton.superview!.top
            startButton.bottom == startButton.superview!.bottom
            startButton.height == 60
            
            startButton.left == startButton.superview!.left
            startButton.right == startButton.superview!.centerX
            
            stopButton.edges == startButton.edges
            
            clearButton.left == startButton.right + 0.5
            clearButton.right == clearButton.superview!.right
        }
        
        addUnderline()
        addGap(height: 30)
        
        let satellite = toggleBox(text: "Satellite map", toggleDefault: false) { isOn in
            self.showSatelliteMap = isOn
            self.updateTheMap()
        }
        let zoom = toggleBox(text: "Auto zoom") { isOn in
            self.autoZoomMap = isOn
            self.updateTheMap()
        }
        addRow([satellite.box, zoom.box])

        addGap(height: 30)
        
        let raw = toggleBox(dotColors: [.red], text: "Raw") { isOn in
            self.showRawLocations = isOn
            self.updateTheMap()
        }
        let smoothed = toggleBox(dotColors: [.blue, .magenta], text: "Samples") { isOn in
            self.showLocomotionSamples = isOn
            self.visitsToggle?.isEnabled = isOn
            self.visitsToggleBox?.subviews.forEach { $0.alpha = isOn ? 1 : 0.45 }
            self.updateTheMap()
        }
        addRow([raw.box, smoothed.box])
        
        addUnderline()
        
        let filtered = toggleBox(dotColors: [.purple], text: "Filtered") { isOn in
            self.showFilteredLocations = isOn
            self.updateTheMap()
        }
        let visits = toggleBox(dotColors: [.orange], text: "Visits") { isOn in
            self.showStationaryCircles = isOn
            self.updateTheMap()
        }
        addRow([filtered.box, visits.box])
        
        visitsToggleBox = visits.box
        visitsToggle = visits.toggle

        let statusRow = UIStackView()
        statusRow.distribution = .fillProportionally
        statusRow.axis = .horizontal
        
        view.addSubview(statusRow)
        constrain(statusRow) { statusRow in
            statusRow.left == statusRow.superview!.left + 6
            statusRow.right == statusRow.superview!.right - 6
            statusRow.bottom == statusRow.superview!.bottom
            statusRow.height == 30
        }
        
        statusRow.addSubview(statusRowBackground)
        constrain(statusRowBackground) { background in
            background.top == background.superview!.top - 0.5
            background.bottom == background.superview!.bottom
            background.left == background.superview!.left
            background.right == background.superview!.right
        }
        
        statusRow.addArrangedSubview(desiredAccuracyLabel)
        statusRow.addArrangedSubview(achievedAccuracyLabel)
        statusRow.addArrangedSubview(locationHertzLabel)
    }
   
    // MARK: map building
    
    func addPath(locations: [CLLocation], color: UIColor) {
        guard !locations.isEmpty else {
            return
        }
        
        var coords = locations.flatMap { $0.coordinate }
        let path = PathPolyline(coordinates: &coords, count: coords.count)
        path.color = color
        
        map.add(path)
    }
    
    func addSamples(samples: [LocomotionSample]) {
        var currentGrouping: [LocomotionSample]?
        
        for sample in samples where sample.location != nil {
            let currentState = sample.movingState
            
            // state changed? close off the previous grouping, add to map, and start a new one
            if let previousState = currentGrouping?.last?.movingState, previousState != currentState {
                
                // add new sample to previous grouping, to link them end to end
                currentGrouping?.append(sample)
              
                // add it to the map
                addGrouping(currentGrouping!)
                
                currentGrouping = nil
            }
            
            currentGrouping = currentGrouping ?? []
            currentGrouping?.append(sample)
        }
        
        // add the final grouping to the map
        if let grouping = currentGrouping {
            addGrouping(grouping)
        }
    }
    
    func addGrouping(_ samples: [LocomotionSample]) {
        guard let movingState = samples.first?.movingState else {
            return
        }
        
        let locations = samples.flatMap { $0.location }
        
        switch movingState {
        case .moving:
            addPath(locations: locations, color: .blue)
            
        case .stationary:
            if showStationaryCircles {
                addVisit(locations: locations)
            } else {
                addPath(locations: locations, color: .orange)
            }
            
        case .uncertain:
            addPath(locations: locations, color: .magenta)
        }
    }

    func addVisit(locations: [CLLocation]) {
        if let center = CLLocation(locations: locations) {
            map.addAnnotation(VisitAnnotation(coordinate: center.coordinate))
           
            let radius = locations.radiusFrom(center: center)
            let circle = VisitCircle(center: center.coordinate, radius: radius.mean + radius.sd * 2)
            circle.color = .orange
            map.add(circle, level: .aboveLabels)
        }
    }

    func addUnderline() {
        let underline = UIView()
        rowsBox.addArrangedSubview(underline)
        
        constrain(underline) { underline in
            underline.height == 0.5
        }
    }
    
    func addGap(height: CGFloat) {
        let gap = UIView()
        gap.backgroundColor = .white
        rowsBox.addArrangedSubview(gap)
        
        constrain(gap) { gap in
            gap.height == height
        }
    }
    
    func addRow(_ views: [UIView]) {
        let row = UIStackView()
        row.distribution = .fillEqually
        row.spacing = 0.5
        
        for view in views {
            row.addArrangedSubview(view)
        }
        
        rowsBox.addArrangedSubview(row)
    }
    
    // MARK: view factories
    
    func dot(color: UIColor) -> UIView {
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
        
        let shape = CAShapeLayer()
        shape.fillColor = color.cgColor
        shape.path = UIBezierPath(roundedRect: dot.bounds, cornerRadius: 7).cgPath
        shape.strokeColor = UIColor.white.cgColor
        shape.lineWidth = 2
        dot.layer.addSublayer(shape)
        
        return dot
    }
    
    func toggleBox(dotColors: [UIColor] = [], text: String, toggleDefault: Bool = true, onChange: @escaping ((Bool) -> Void))
        -> (box: UIView, toggle: UISwitch)
    {
        let box = UIView()
        box.backgroundColor = .white
        
        var lastDot: UIView?
        for color in dotColors {
            let dot = self.dot(color: color)
            let dotWidth = dot.frame.size.width
            box.addSubview(dot)
            
            constrain(dot) { dot in
                dot.centerY == dot.superview!.centerY
                dot.height == dotWidth
                dot.width == dotWidth
            }
            
            if let lastDot = lastDot {
                constrain(dot, lastDot) { dot, lastDot in
                    dot.left == lastDot.right - 4
                }
            } else {
                constrain(dot) { dot in
                    dot.left == dot.superview!.left + 8
                }
            }
            
            lastDot = dot
        }
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = UIColor(white: 0.1, alpha: 1)
        
        let toggle = UISwitch()
        toggle.isOn = toggleDefault
        
        toggle.onControlEvent(.valueChanged) {
            onChange(toggle.isOn)
        }
        
        box.addSubview(label)
        box.addSubview(toggle)
        
        if let lastDot = lastDot {
            constrain(lastDot, label) { dot, label in
                label.left == dot.right + 5
            }
            
        } else {
            constrain(label, toggle) { label, toggle in
                label.left == label.superview!.left + 9
            }
        }
        
        constrain(label, toggle) { label, toggle in
            label.top == label.superview!.top
            label.bottom == label.superview!.bottom
            label.height == 50
            
            toggle.centerY == toggle.superview!.centerY
            toggle.right == toggle.superview!.right - 10
            toggle.left == label.right
        }
        
        return (box: box, toggle: toggle)
    }

    // MARK: view property getters
    
    lazy var map: MKMapView = {
        let map = MKMapView()
        map.delegate = self
        
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsScale = true
        
        return map
    }()
    
    lazy var rowsBox: UIStackView = {
        let box = UIStackView()
        box.axis = .vertical
        return box
    }()
    
    lazy var startButton: UIButton = {
        let button = UIButton(type: .system)
       
        button.backgroundColor = .white
        button.setTitle("Start", for: .normal)
        
        button.onControlEvent(.touchUpInside) { [weak self] in
            self?.tappedStart()
        }
        
        return button
    }()
    
    lazy var stopButton: UIButton = {
        let button = UIButton(type: .system)
        button.isHidden = true
        
        button.backgroundColor = .white
        button.setTitle("Stop", for: .normal)
        button.setTitleColor(.red, for: .normal)
        
        button.onControlEvent(.touchUpInside) { [weak self] in
            self?.tappedStop()
        }
        
        return button
    }()
    
    lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        
        button.backgroundColor = .white
        button.setTitle("Clear", for: .normal)
        
        button.onControlEvent(.touchUpInside) { [weak self] in
            self?.tappedClear()
        }
        
        return button
    }()
    
    lazy var statusRowBackground: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.85, alpha: 1)
        return view
    }()
    
    lazy var desiredAccuracyLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = UIColor(white: 0.3, alpha: 1)
        label.textAlignment = .center
        return label
    }()
    
    lazy var achievedAccuracyLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = UIColor(white: 0.3, alpha: 1)
        label.textAlignment = .center
        return label
    }()
    
    lazy var locationHertzLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .white
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = UIColor(white: 0.3, alpha: 1)
        label.textAlignment = .center
        return label
    }()
}

// MARK: MKMapViewDelegate

extension ViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let path = overlay as? PathPolyline {
            return path.renderer
            
        } else if let circle = overlay as? VisitCircle {
            return circle.renderer
            
        } else {
            fatalError("you wot?")
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let annotation = annotation as? VisitAnnotation {
            return annotation.view
        }
        return nil
    }
    
}

