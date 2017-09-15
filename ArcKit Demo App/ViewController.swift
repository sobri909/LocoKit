//
//  ViewController.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 10/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import ArcKit
import MapKit
import MGEvents
import Cartography
import CoreLocation

class ViewController: UIViewController {
    
    var rawLocations: [CLLocation] = []
    var filteredLocations: [CLLocation] = []
    var locomotionSamples: [LocomotionSample] = []
    var baseClassifier: ActivityTypeClassifier<ActivityTypesCache>?
    var transportClassifier: ActivityTypeClassifier<ActivityTypesCache>?
   
    var showRawLocations = true
    var showFilteredLocations = true
    var showLocomotionSamples = true
    var showStationaryCircles = true
    var showSatelliteMap = false
    var autoZoomMap = true
    
    var enableTheClassifier = true
    var enableTransportClassifier = true
    
    var visitsToggleBox: UIView?
    var visitsToggle: UISwitch?
    
    var transportClassifierToggleBox: UIView?
    var transportClassifierToggle: UISwitch?
    
    // MARK: controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
       
        buildViewTree()
        buildSettingsViewTree()
        buildResultsViewTree()

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
        
        updateTheBaseClassifier()
        updateTheTransportClassifier()
        
        buildResultsViewTree(sample: sample)
        updateTheMap()
    }
    
    func updateTheBaseClassifier() {
        guard enableTheClassifier else {
            return
        }
       
        // need a coordinate to know what classifier to fetch (there's thousands of them)
        guard let coordinate = LocomotionManager.highlander.filteredLocation?.coordinate else {
            return
        }
       
        // no need to update anything if the current classifier is still valid
        if let classifier = baseClassifier, classifier.contains(coordinate: coordinate) {
            return
        }
        
        // note: this will return nil if the ML models haven't been fetched yet, but will also trigger a fetch
        baseClassifier = ActivityTypeClassifier(requestedTypes: ActivityTypeName.baseTypes, coordinate: coordinate)
    }
    
    func updateTheTransportClassifier() {
        guard enableTheClassifier && enableTransportClassifier else {
            return
        }
        
        // need a coordinate to know what classifier to fetch (there's thousands of them)
        guard let coordinate = LocomotionManager.highlander.filteredLocation?.coordinate else {
            return
        }
        
        // no need to update anything if the current classifier is still valid
        if let classifier = transportClassifier, classifier.contains(coordinate: coordinate) {
            return
        }
        
        // note: this will return nil if the ML models haven't been fetched yet, but will also trigger a fetch
        transportClassifier = ActivityTypeClassifier(requestedTypes: ActivityTypeName.transportTypes, coordinate: coordinate)
    }
    
    // MARK: tap actions
    
    func tappedStart() {
        let loco = LocomotionManager.highlander
        
        // for demo purposes only. the default value already best balances accuracy with battery use
        loco.maximumDesiredLocationAccuracy = kCLLocationAccuracyBest
        
        // this is independent of the user's setting, and will show a blue bar if user has denied "always"
        loco.locationManager.allowsBackgroundLocationUpdates = true
        
        loco.startCoreLocation()
        loco.startCoreMotion()
        
        startButton.isHidden = true
        stopButton.isHidden = false
    }
    
    func tappedStop() {
        let loco = LocomotionManager.highlander
        
        loco.stopCoreLocation()
        loco.stopCoreMotion()
        
        stopButton.isHidden = true
        startButton.isHidden = false
    }
    
    func tappedClear() {
        rawLocations.removeAll()
        filteredLocations.removeAll()
        locomotionSamples.removeAll()
        
        updateTheMap()
        buildResultsViewTree()
    }
    
    @objc func tappedViewToggle() {
        switch viewToggle.selectedSegmentIndex {
        case 0:
            settingsRows.isHidden = true
            resultsScroller.isHidden = false
            resultsScroller.flashScrollIndicators()
        default:
            settingsRows.isHidden = false
            resultsScroller.isHidden = true
        }
    }
    
    // MARK: UI updating
    
    func updateTheMap() {
        
        // don't bother updating the map when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        
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
            map.height == map.superview!.height * 0.35
        }

        view.addSubview(topButtons)
        constrain(map, topButtons) { map, topButtons in
            topButtons.top == map.bottom
            topButtons.left == topButtons.superview!.left
            topButtons.right == topButtons.superview!.right
            topButtons.height == 56
        }
        
        topButtons.addSubview(startButton)
        topButtons.addSubview(stopButton)
        topButtons.addSubview(clearButton)
        constrain(startButton, stopButton, clearButton) { startButton, stopButton, clearButton in
            align(top: startButton, stopButton, clearButton)
            align(bottom: startButton, stopButton, clearButton)
            
            startButton.top == startButton.superview!.top
            startButton.bottom == startButton.superview!.bottom - 0.5
            startButton.left == startButton.superview!.left
            startButton.right == startButton.superview!.centerX
            
            stopButton.edges == startButton.edges
            
            clearButton.left == startButton.right + 0.5
            clearButton.right == clearButton.superview!.right
        }
       
        view.addSubview(settingsRows)
        view.addSubview(resultsScroller)
        view.addSubview(viewToggleBar)
        
        constrain(viewToggleBar) { bar in
            bar.bottom == bar.superview!.bottom
            bar.left == bar.superview!.left
            bar.right == bar.superview!.right
        }
        
        constrain(topButtons, settingsRows) { topButtons, box in
            box.top == topButtons.bottom
            box.left == box.superview!.left + 8
            box.right == box.superview!.right - 8
        }

        constrain(topButtons, resultsScroller, viewToggleBar) { topButtons, scroller, viewToggleBar in
            scroller.top == topButtons.bottom
            scroller.left == scroller.superview!.left
            scroller.right == scroller.superview!.right
            scroller.bottom == viewToggleBar.top
        }
        
        resultsScroller.addSubview(resultsRows)
        constrain(resultsRows, view) { box, view in
            box.top == box.superview!.top
            box.bottom == box.superview!.bottom
            box.left == box.superview!.left + 16
            box.right == box.superview!.right - 16
            box.right == view.right - 16
        }
    }
    
    func buildSettingsViewTree() {
        settingsRows.addGap(height: 24)
        settingsRows.addHeading(title: "Map Style", alignment: .center)
        settingsRows.addGap(height: 6)
        settingsRows.addUnderline()
        
        let satellite = ToggleBox(text: "Satellite map", toggleDefault: false) { isOn in
            self.showSatelliteMap = isOn
            self.updateTheMap()
        }
        let zoom = ToggleBox(text: "Auto zoom") { isOn in
            self.autoZoomMap = isOn
            self.updateTheMap()
        }
        settingsRows.addRow(views: [satellite, zoom])
        
        settingsRows.addGap(height: 18)
        settingsRows.addHeading(title: "Map Data Overlays", alignment: .center)
        settingsRows.addGap(height: 6)
        settingsRows.addUnderline()
        
        let raw = ToggleBox(dotColors: [.red], text: "Raw") { isOn in
            self.showRawLocations = isOn
            self.updateTheMap()
        }
        let smoothed = ToggleBox(dotColors: [.blue, .magenta], text: "Samples") { isOn in
            self.showLocomotionSamples = isOn
            self.visitsToggle?.isEnabled = isOn
            self.visitsToggleBox?.subviews.forEach { $0.alpha = isOn ? 1 : 0.45 }
            self.updateTheMap()
        }
        settingsRows.addRow(views: [raw, smoothed])
        
        settingsRows.addUnderline()
        
        let filtered = ToggleBox(dotColors: [.purple], text: "Filtered") { isOn in
            self.showFilteredLocations = isOn
            self.updateTheMap()
        }
        let visits = ToggleBox(dotColors: [.orange], text: "Visits") { isOn in
            self.showStationaryCircles = isOn
            self.updateTheMap()
        }
        settingsRows.addRow(views: [filtered, visits])
        
        visitsToggleBox = visits
        visitsToggle = visits.toggle
        
        settingsRows.addGap(height: 18)
        settingsRows.addHeading(title: "Activity Type Classifiers", alignment: .center)
        settingsRows.addGap(height: 6)
        settingsRows.addUnderline()
        
        let classifierBox = ToggleBox(text: "Base types") { isOn in
            self.baseClassifier = nil
            self.transportClassifier = nil
            self.enableTheClassifier = isOn
            self.transportClassifierToggle?.isEnabled = isOn
            self.transportClassifierToggleBox?.subviews.forEach { $0.alpha = isOn ? 1 : 0.45 }
            self.updateTheBaseClassifier()
            self.updateTheTransportClassifier()
        }
        let extended = ToggleBox(text: "Transport") { isOn in
            self.transportClassifier = nil
            self.enableTransportClassifier = isOn
            self.updateTheTransportClassifier()
        }
        settingsRows.addRow(views: [classifierBox, extended])
        
        transportClassifierToggleBox = extended
        transportClassifierToggle = extended.toggle
    }
    
    func buildResultsViewTree(sample: LocomotionSample? = nil) {
        
        // don't bother updating the UI when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        
        let loco = LocomotionManager.highlander
        
        resultsRows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        resultsRows.addGap(height: 22)
        resultsRows.addHeading(title: "Core Location")
        resultsRows.addGap(height: 10)
        
        if loco.recordingCoreLocation {
            let requesting = LocomotionManager.highlander.locationManager.desiredAccuracy
            if requesting == kCLLocationAccuracyBest {
                resultsRows.addRow(leftText: "Requesting accuracy", rightText: "kCLLocationAccuracyBest")
            } else {
                resultsRows.addRow(leftText: "Requesting accuracy", rightText: String(format: "%.0f metres", requesting))
            }
        } else {
            resultsRows.addRow(leftText: "Requesting accuracy", rightText: "-")
        }
        
        var receivingString = "-"
        if loco.recordingCoreLocation, let sample = sample {
            var receivingHertz = 0.0
            if let duration = sample.filteredLocations.dateInterval?.duration, duration > 0 {
                receivingHertz = Double(sample.filteredLocations.count) / duration
            }
            
            if let location = sample.filteredLocations.last {
                receivingString = String(format: "%.0f metres @ %.1f Hz", location.horizontalAccuracy, receivingHertz)
            }
        }
        resultsRows.addRow(leftText: "Receiving accuracy", rightText: receivingString)
        
        resultsRows.addGap(height: 18)
        resultsRows.addHeading(title: "Locomotion Sample")
        resultsRows.addGap(height: 10)
        
        if let sample = sample {
            resultsRows.addRow(leftText: "Latest sample", rightText: sample.description)
            resultsRows.addRow(leftText: "Behind now", rightText: String(duration: sample.date.age))
        } else {
            resultsRows.addRow(leftText: "Latest sample", rightText: "-")
            resultsRows.addRow(leftText: "Behind now", rightText: "-")
        }
        
        resultsRows.addGap(height: 18)
        resultsRows.addHeading(title: "Activity Type Classifier (baseTypes)")
        resultsRows.addGap(height: 10)
        
        if loco.recordingCoreLocation, let sample = sample {
            if let classifier = baseClassifier {
                let results = classifier.classify(sample)
                
                for result in results {
                    let row = resultsRows.addRow(leftText: result.name.rawValue.capitalized,
                                                 rightText: String(format: "%.4f", result.score))
                    
                    if result.score < 0.01 {
                        row.subviews.forEach { subview in
                            if let label = subview as? UILabel {
                                label.textColor = UIColor(white: 0.1, alpha: 0.45)
                            }
                        }
                    }
                }
                
            } else if enableTheClassifier {
                resultsRows.addRow(leftText: "Fetching ML models...")
            } else {
                resultsRows.addRow(leftText: "Classifier is turned off")
            }
            
        } else {
            resultsRows.addRow(leftText: "Unknown", rightText: "-")
        }
        
        resultsRows.addGap(height: 18)
        resultsRows.addHeading(title: "Activity Type Classifier (transportTypes)")
        resultsRows.addGap(height: 10)
        
        if loco.recordingCoreLocation, let sample = sample {
            if let classifier = transportClassifier {
                let results = classifier.classify(sample)
                
                for result in results {
                    let row = resultsRows.addRow(leftText: result.name.rawValue.capitalized,
                                                 rightText: String(format: "%.4f", result.score))
                    
                    if result.score < 0.01 {
                        row.subviews.forEach { subview in
                            if let label = subview as? UILabel {
                                label.textColor = UIColor(white: 0.1, alpha: 0.45)
                            }
                        }
                    }
                }
                
            } else if enableTheClassifier && enableTransportClassifier {
                resultsRows.addRow(leftText: "Fetching ML models...")
            } else {
                resultsRows.addRow(leftText: "Classifier is turned off")
            }
            
        } else {
            resultsRows.addRow(leftText: "Unknown", rightText: "-")
        }

        resultsRows.addGap(height: 12)
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
    
    // MARK: view property getters
    
    lazy var map: MKMapView = {
        let map = MKMapView()
        map.delegate = self
        
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsScale = true
        
        return map
    }()
    
    lazy var topButtons: UIView = {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.85, alpha: 1)
        return box
    }()
    
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
    
    lazy var resultsRows: UIStackView = {
        let box = UIStackView()
        box.axis = .vertical
        
        let background = UIView()
        background.backgroundColor = UIColor(white: 0.85, alpha: 1)
        
        box.addSubview(background)
        constrain(background) { background in
            background.edges == background.superview!.edges
        }
        
        return box
    }()
    
    lazy var resultsScroller: UIScrollView = {
        let scroller = UIScrollView()
        scroller.alwaysBounceVertical = true
        return scroller
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
    
    lazy var viewToggleBar: UIToolbar = {
        let bar = UIToolbar()
        bar.isTranslucent = false
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(customView: self.viewToggle),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        ]
        return bar
    }()
    
    lazy var viewToggle: UISegmentedControl = {
        let toggle = UISegmentedControl(items: ["Results", "Settings"])
        toggle.setWidth(120, forSegmentAt: 0)
        toggle.setWidth(120, forSegmentAt: 1)
        toggle.selectedSegmentIndex = 0
        toggle.addTarget(self, action: #selector(tappedViewToggle), for: .valueChanged)
        return toggle
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
