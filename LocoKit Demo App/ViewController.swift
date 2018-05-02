//
//  ViewController.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 10/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import Anchorage
import SwiftNotes
import CoreLocation

class ViewController: UIViewController {

    /**
     The recording manager for Timeline Items (Visits and Paths)

     - Note: Use a plain TimelineManager() instead if you don't require persistent SQL storage
    **/
    let timeline: TimelineManager = PersistentTimelineManager()

    lazy var mapView = { return MapView(timeline: self.timeline) }()
    lazy var timelineView = { return TimelineView(timeline: self.timeline) }()
    let classifierView = ClassifierView()
    let settingsView = SettingsView()
    let locoView = LocoView()
    let logView = LogView()

    // MARK: controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // the CoreLocation / CoreMotion recording singleton
        let loco = LocomotionManager.highlander

        /** EXAMPLE SETTINGS **/

        // enable this if you have an API key and want to determine activity types
        timeline.activityTypeClassifySamples = false

        if timeline.activityTypeClassifySamples {
            // API keys can be created at: https://www.bigpaua.com/arckit/account
            LocoKitService.apiKey = "<insert your API key here>"
        }

        // this accuracy level is excessive, and is for demo purposes only.
        // the default value (30 metres) best balances accuracy with energy use.
        loco.maximumDesiredLocationAccuracy = kCLLocationAccuracyNearestTenMeters

        // this is independent of the user's setting, and will show a blue bar if user has denied "always"
        loco.locationManager.allowsBackgroundLocationUpdates = true

        /** TIMELINE STARTUP **/

        // restore the active timeline items from local db
        if let timeline = timeline as? PersistentTimelineManager {
            timeline.bootstrapActiveItems()
        }

        /** EXAMPLE OBSERVERS **/

        // observe new timeline items
        when(timeline, does: .newTimelineItem) { _ in
            if let currentItem = self.timeline.currentItem {
                log(".newTimelineItem (\(String(describing: type(of: currentItem))))")
            }
            onMain {
                let items = self.itemsToShow
                self.mapView.update(with: items)
                self.timelineView.update(with: items)
            }
        }

        // observe timeline item updates
        when(timeline, does: .updatedTimelineItem) { _ in
            onMain {
                let items = self.itemsToShow
                self.mapView.update(with: items)
                self.timelineView.update(with: items)
            }
        }

        // observe timeline items finalised after post processing
        when(timeline, does: .finalisedTimelineItem) { note in
            if let item = note.userInfo?["timelineItem"] as? TimelineItem {
                log(".finalisedTimelineItem (\(String(describing: type(of: item))))")
            }
            onMain { self.timelineView.update(with: self.itemsToShow) }
        }

        when(timeline, does: .mergedTimelineItems) { note in
            if let description = note.userInfo?["merge"] as? String {
                log(".mergedItems (\(description))")
            }
            onMain { self.timelineView.update(with: self.itemsToShow) }
        }

        // observe incoming location / locomotion updates
        when(loco, does: .locomotionSampleUpdated) { _ in
            self.locomotionSampleUpdated()
        }

        // observe changes in the recording state (recording / sleeping)
        when(loco, does: .recordingStateChanged) { _ in
            // don't log every type of state change, because it gets noisy
            if loco.recordingState == .recording || loco.recordingState == .off {
                log(".recordingStateChanged (\(loco.recordingState))")
            }
            self.locoView.update()
            self.mapView.update(with: self.itemsToShow)
        }

        // observe changes in the moving state (moving / stationary)
        when(loco, does: .movingStateChanged) { _ in
            log(".movingStateChanged (\(loco.movingState))")
        }

        when(loco, does: .startedSleepMode) { _ in
            log(".startedSleepMode")
        }

        when(loco, does: .stoppedSleepMode) { _ in
            log(".stoppedSleepMode")
        }

        when(.debugInfo) { note in
            if let info = note.userInfo?["info"] as? String {
                log(".debug (\(info))")
            } else {
                log(".debug (nil)")
            }
        }

        when(settingsView, does: .settingsChanged) { _ in
            self.mapView.update(with: self.itemsToShow)
            self.setNeedsStatusBarAppearanceUpdate()
        }

        when(.UIApplicationDidReceiveMemoryWarning) { _ in
            log("UIApplicationDidReceiveMemoryWarning")
        }

        // view tree stuff
        view.backgroundColor = .white
        buildViewTree()

        // get things started by asking permission
        loco.requestLocationPermission()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return mapView.mapType == .standard ? .default : .lightContent
    }
  
    // MARK: process incoming locations
    
    func locomotionSampleUpdated() {
        let loco = LocomotionManager.highlander

        // don't bother updating the UI when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        // get the latest sample and update the results views
        let sample = loco.locomotionSample()
        locoView.update(sample: sample)
        classifierView.update(sample: sample)
    }

    // MARK: tap actions
    
    @objc func tappedStart() {
        log("tappedStart()")

        timeline.startRecording()

        startButton.isHidden = true
        stopButton.isHidden = false
    }
    
    @objc func tappedStop() {
        log("tappedStop()")

        timeline.stopRecording()

        stopButton.isHidden = true
        startButton.isHidden = false
    }
    
    @objc func tappedClear() {
        DebugLog.deleteLogFile()
        // TODO: flush the timeline data
    }
    
    @objc func tappedViewToggle() {
        var chosenView: UIScrollView

        switch viewToggle.selectedSegmentIndex {
        case 0:
            chosenView = timelineView
        case 1:
            chosenView = locoView
        case 2:
            chosenView = classifierView
        case 3:
            chosenView = logView
        default:
            chosenView = settingsView
        }

        view.bringSubview(toFront: chosenView)
        view.bringSubview(toFront: viewToggleBar)
        chosenView.flashScrollIndicators()
        Settings.visibleTab = chosenView
    }
    
    // MARK: view tree building
    
    func buildViewTree() {        
        view.addSubview(mapView)
        mapView.topAnchor == mapView.superview!.topAnchor
        mapView.leftAnchor == mapView.superview!.leftAnchor
        mapView.rightAnchor == mapView.superview!.rightAnchor
        mapView.heightAnchor == mapView.superview!.heightAnchor * 0.35

        view.addSubview(topButtons)
        topButtons.topAnchor == mapView.bottomAnchor
        topButtons.leftAnchor == topButtons.superview!.leftAnchor
        topButtons.rightAnchor == topButtons.superview!.rightAnchor
        topButtons.heightAnchor == 56

        topButtons.addSubview(startButton)
        topButtons.addSubview(stopButton)
        topButtons.addSubview(clearButton)

        startButton.topAnchor == stopButton.topAnchor
        stopButton.topAnchor == clearButton.topAnchor
        startButton.bottomAnchor == stopButton.bottomAnchor
        stopButton.bottomAnchor == clearButton.bottomAnchor

        startButton.topAnchor == startButton.superview!.topAnchor
        startButton.bottomAnchor == startButton.superview!.bottomAnchor - 0.5
        startButton.leftAnchor == startButton.superview!.leftAnchor
        startButton.rightAnchor == startButton.superview!.centerXAnchor
            
        stopButton.edgeAnchors == startButton.edgeAnchors
            
        clearButton.leftAnchor == startButton.rightAnchor + 0.5
        clearButton.rightAnchor == clearButton.superview!.rightAnchor

        view.addSubview(locoView)
        view.addSubview(classifierView)
        view.addSubview(logView)
        view.addSubview(settingsView)
        view.addSubview(timelineView)
        view.addSubview(viewToggleBar)
        Settings.visibleTab = timelineView
        
        viewToggleBar.bottomAnchor == viewToggleBar.superview!.bottomAnchor
        viewToggleBar.leftAnchor == viewToggleBar.superview!.leftAnchor
        viewToggleBar.rightAnchor == viewToggleBar.superview!.rightAnchor

        locoView.topAnchor == topButtons.bottomAnchor
        locoView.leftAnchor == locoView.superview!.leftAnchor
        locoView.rightAnchor == locoView.superview!.rightAnchor
        locoView.bottomAnchor == viewToggleBar.topAnchor

        settingsView.edgeAnchors == locoView.edgeAnchors
        timelineView.edgeAnchors == locoView.edgeAnchors
        classifierView.edgeAnchors == locoView.edgeAnchors
        logView.edgeAnchors == locoView.edgeAnchors
    }

    func update() {
        // don't bother updating the UI when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else { return }

        let items = itemsToShow
        timelineView.update(with: items)
        mapView.update(with: items)
        logView.update()
        locoView.update()
        classifierView.update()
    }

    var itemsToShow: [TimelineItem] {
        if timeline is PersistentTimelineManager { return persistentItemsToShow }

        guard let currentItem = timeline.currentItem else { return [] }

        // collect the linked list of timeline items
        var items: [TimelineItem] = [currentItem]
        var workingItem = currentItem
        while let previous = workingItem.previousItem {
            items.append(previous)
            workingItem = previous
        }

        return items
    }

    var persistentItemsToShow: [TimelineItem] {
        guard let timeline = timeline as? PersistentTimelineManager else { return [] }

        // make sure the db is fresh
        timeline.store.save()

        // feth all items in the past 24 hours
        let boundary = Date(timeIntervalSinceNow: -60 * 60 * 24)
        return timeline.store.items(where: "deleted = 0 AND endDate > ? ORDER BY endDate DESC", arguments: [boundary])
    }

    // MARK: view property getters
    
    lazy var topButtons: UIView = {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.85, alpha: 1)
        return box
    }()

    lazy var startButton: UIButton = {
        let button = UIButton(type: .system)
       
        button.backgroundColor = .white
        button.setTitle("Start", for: .normal)
        button.addTarget(self, action: #selector(ViewController.tappedStart), for: .touchUpInside)

        return button
    }()
    
    lazy var stopButton: UIButton = {
        let button = UIButton(type: .system)
        button.isHidden = true
        
        button.backgroundColor = .white
        button.setTitle("Stop", for: .normal)
        button.setTitleColor(.red, for: .normal)
        button.addTarget(self, action: #selector(ViewController.tappedStop), for: .touchUpInside)

        return button
    }()
    
    lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        
        button.backgroundColor = .white
        button.setTitle("Clear", for: .normal)
        button.addTarget(self, action: #selector(ViewController.tappedClear), for: .touchUpInside)

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
        let toggle = UISegmentedControl(items: ["TM", "LM", "AC", "Log", "Settings"])
        toggle.setWidth(66, forSegmentAt: 0)
        toggle.setWidth(66, forSegmentAt: 1)
        toggle.setWidth(66, forSegmentAt: 2)
        toggle.setWidth(66, forSegmentAt: 3)
        toggle.setWidth(66, forSegmentAt: 4)
        toggle.selectedSegmentIndex = 0
        toggle.addTarget(self, action: #selector(tappedViewToggle), for: .valueChanged)
        return toggle
    }()
}

