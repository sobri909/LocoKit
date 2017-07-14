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
    var showSmoothedLocations = true
    var showVisits = true
    
    var visitsToggleRow: UIView?
    var visitsToggle: UISwitch?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
       
        buildViewTree()

        let loco = LocomotionManager.highlander
        let centre = NotificationCenter.default
        
        centre.addObserver(forName: .didUpdateLocations, object: loco, queue: OperationQueue.main) { note in
            self.didUpdateLocations(note: note)
        }
        
        loco.requestLocationPermission()
    }
    
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
            box.left == box.superview!.left + 16
            box.right == box.superview!.right - 16
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
        addGap(height: 16)
        
        addToggleRow(color: .red, text: "Show raw locations") { isOn in
            self.showRawLocations = isOn
            self.updateTheMap()
        }
        
        addUnderline()
        
        addToggleRow(color: .purple, text: "Show filtered locations") { isOn in
            self.showFilteredLocations = isOn
            self.updateTheMap()
        }
        
        addUnderline()
        
        addToggleRow(color: .blue, text: "Show smoothed locations") { isOn in
            self.showSmoothedLocations = isOn
            self.visitsToggle?.isEnabled = isOn
            self.visitsToggleRow?.subviews.forEach { $0.alpha = isOn ? 1 : 0.4 }
            self.updateTheMap()
        }
        
        addUnderline()
        
        let bits = addToggleRow(color: .orange, text: "Show stationary periods") { isOn in
            self.showVisits = isOn
            self.updateTheMap()
        }
        
        visitsToggleRow = bits.row
        visitsToggle = bits.toggle
    }
  
    // MARK: process incoming locations
    
    func didUpdateLocations(note: Notification) {
        if let location = note.userInfo?["location"] as? CLLocation {
            rawLocations.append(location)
        }
        
        if let location = note.userInfo?["filteredLocation"] as? CLLocation {
            filteredLocations.append(location)
        }
        
        locomotionSamples.append(LocomotionManager.highlander.locomotionSample)
        
        updateTheMap()
    }
    
    // MARK: tap actions
    
    func tappedStart() {
        LocomotionManager.highlander.start()
        
        startButton.isHidden = true
        stopButton.isHidden = false
    }
    
    func tappedStop() {
        LocomotionManager.highlander.stop()
        
        stopButton.isHidden = true
        startButton.isHidden = false
    }
    
    func tappedClear() {
        rawLocations.removeAll()
        filteredLocations.removeAll()
        locomotionSamples.removeAll()
        
        updateTheMap()
    }
    
    // MARK: updating and zooming the map
    
    func updateTheMap() {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        
        if showRawLocations {
            addPath(locations: rawLocations, color: .red)
        }
        
        if showFilteredLocations {
            addPath(locations: filteredLocations, color: .purple)
        }
        
        if showSmoothedLocations {
            let smoothedLocations = locomotionSamples.flatMap { $0.location }
            
            if showVisits {
                addPathsAndVisits(samples: locomotionSamples)
            
            } else {
                addPath(locations: smoothedLocations, color: .blue)
            }
        }
        
        zoomToShow(overlays: map.overlays)
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
   
    // MARK: adding map overlays and annotations
    
    func addPath(locations: [CLLocation], color: UIColor) {
        guard !locations.isEmpty else {
            return
        }
        
        var coords = locations.flatMap { $0.coordinate }
        let path = PathPolyline(coordinates: &coords, count: coords.count)
        path.color = color
        
        map.add(path)
    }
    
    func addPathsAndVisits(samples: [LocomotionSample]) {
        var currentPath: [CLLocation]?
        var currentVisit: [CLLocation]?
        
        for sample in samples {
            guard let location = sample.location else {
                continue
            }
            
            if sample.movingState == .stationary {
                
                // add the previous path to the map
                if var path = currentPath {
                    path.append(location)
                    
                    addPath(locations: path, color: .blue)
                    currentPath = nil
                }
                
                currentVisit = currentVisit ?? []
                currentVisit?.append(location)
                
            } else { // movingState is either .moving or .uncertain
                
                // add the previous visit to the map
                if var visit = currentVisit {
                    visit.append(location)

                    addVisit(locations: visit)
                    currentVisit = nil
                }
                
                currentPath = currentPath ?? []
                currentPath?.append(location)
            }
        }
        
        // add the final path to the map
        if let path = currentPath {
            addPath(locations: path, color: .blue)
        }
        
        // add the final visit to the map
        if let visit = currentVisit {
            addVisit(locations: visit)
        }
    }

    func addVisit(locations: [CLLocation]) {
        if let center = CLLocation(locations: locations) {
            map.addAnnotation(VisitAnnotation(coordinate: center.coordinate))
           
            let radius = locations.radiusFrom(center: center)
            let circle = VisitCircle(center: center.coordinate, radius: radius.mean + radius.sd)
            circle.color = .orange
            map.add(circle, level: .aboveLabels)
        }
    }

    // MARK: UI building helpers
    
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
    
    func dot(color: UIColor) -> UIView {
        let dot = UIView()
        dot.backgroundColor = color
        dot.layer.cornerRadius = 7
        return dot
    }
    
    @discardableResult
    func addToggleRow(color: UIColor, text: String, onChange: @escaping ((Bool) -> Void))
        -> (row: UIView, toggle: UISwitch)
    {
        let dot = self.dot(color: color)
        let dotWidth = dot.layer.cornerRadius * 2
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = UIColor(white: 0.1, alpha: 1)
        
        let toggle = UISwitch()
        toggle.isOn = true
        
        toggle.onControlEvent(.valueChanged) {
            onChange(toggle.isOn)
        }
        
        let row = UIView()
        row.backgroundColor = .white
        rowsBox.addArrangedSubview(row)
        
        row.addSubview(dot)
        row.addSubview(label)
        row.addSubview(toggle)
        
        constrain(dot, label, toggle) { dot, label, toggle in
            dot.left == dot.superview!.left + 8
            dot.centerY == dot.superview!.centerY
            dot.height == dotWidth
            dot.width == dotWidth
            
            label.top == label.superview!.top
            label.bottom == label.superview!.bottom
            label.left == dot.right + 8
            label.height == 50
           
            toggle.centerY == toggle.superview!.centerY
            toggle.right == toggle.superview!.right - 8
            toggle.left == label.right
        }
        
        return (row: row, toggle: toggle)
    }

    // MARK: view getters
    
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

