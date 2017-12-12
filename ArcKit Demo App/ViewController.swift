//
//  ViewController.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 10/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import ArcKit
import SwiftNotes
import Cartography
import CoreLocation

class ViewController: UIViewController {

    let mapView = MapView()
    let timelineView = TimelineView()
    let classifierView = ClassifierView()
    let settingsView = SettingsView()
    let locoView = LocoView()
    let logView = LogView()

    // MARK: controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // the Core Location / Core Motion singleton
        let loco = LocomotionManager.highlander

        // the Visits / Paths management singelton
        let timeline = TimelineManager.highlander

        /** SETTINGS **/

        // An ArcKit API key is necessary if you are using ActivityTypeClassifier.
        // This key is the Demo App's key, and cannot be used in another app.
        // API keys can be created at: https://www.bigpaua.com/arckit/account
        ArcKitService.apiKey = "13921b60be4611e7b6e021acca45d94f"

        // this accuracy level is excessive, and is for demo purposes only.
        // the default value (30 metres) best balances accuracy with energy use.
        loco.maximumDesiredLocationAccuracy = kCLLocationAccuracyNearestTenMeters

        // how many hours of finalised timeline items to retain
        timeline.timelineItemHistoryRetention = 60 * 60 * 3

        // this is independent of the user's setting, and will show a blue bar if user has denied "always"
        loco.locationManager.allowsBackgroundLocationUpdates = true

        /** OBSERVERS **/

        // observe new timeline items
        when(timeline, does: .newTimelineItem) { _ in
            if let currentItem = timeline.currentItem {
                log(".newTimelineItem (\(String(describing: type(of: currentItem))))")
            }
            self.mapView.update()
            self.timelineView.update()
        }

        // observe timeline item updates
        when(timeline, does: .updatedTimelineItem) { _ in
            self.mapView.update()
            self.timelineView.update()
        }

        // observe timeline items finalised after post processing
        when(timeline, does: .finalisedTimelineItem) { note in
            if let item = note.userInfo?["timelineItem"] as? TimelineItem {
                log(".finalisedTimelineItem (\(String(describing: type(of: item))))")
            }
            self.timelineView.update()
        }

        when(timeline, does: .mergedTimelineItems) { note in
            if let description = note.userInfo?["merge"] as? String {
                log(".mergedItems (\(description))")
            }
            self.timelineView.update()
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
        }

        // observe changes in the moving state (moving / stationary)
        when(loco, does: .movingStateChanged) { _ in
            log(".movingStateChanged (\(loco.movingState))")
        }

        when(loco, does: .startedSleepMode) { _ in
            log(".startedSleepMode")
            self.mapView.update()
        }

        when(loco, does: .stoppedSleepMode) { _ in
            log(".stoppedSleepMode")
        }

        when(timeline, does: .debugInfo) { note in
            if let info = note.userInfo?["info"] as? String {
                log(".debug (\(info))")
            } else {
                log(".debug (nil)")
            }
        }

        when(settingsView, does: .settingsChanged) { _ in
            self.mapView.update()
            self.setNeedsStatusBarAppearanceUpdate()
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

        let timeline = TimelineManager.highlander

        timeline.startRecording()

        startButton.isHidden = true
        stopButton.isHidden = false
    }
    
    @objc func tappedStop() {
        log("tappedStop()")

        let timeline = TimelineManager.highlander
        
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
        constrain(mapView) { map in
            map.top == map.superview!.top
            map.left == map.superview!.left
            map.right == map.superview!.right
            map.height == map.superview!.height * 0.35
        }

        view.addSubview(topButtons)
        constrain(mapView, topButtons) { map, topButtons in
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
       
        view.addSubview(locoView)
        view.addSubview(classifierView)
        view.addSubview(logView)
        view.addSubview(settingsView)
        view.addSubview(timelineView)
        view.addSubview(viewToggleBar)
        Settings.visibleTab = timelineView
        
        constrain(viewToggleBar) { bar in
            bar.bottom == bar.superview!.bottom
            bar.left == bar.superview!.left
            bar.right == bar.superview!.right
        }

        constrain(topButtons, locoView, viewToggleBar) { topButtons, scroller, viewToggleBar in
            scroller.top == topButtons.bottom
            scroller.left == scroller.superview!.left
            scroller.right == scroller.superview!.right
            scroller.bottom == viewToggleBar.top
        }
        
        constrain(timelineView, locoView, classifierView, logView, settingsView) { timeline, loco, classifier, log, settings in
            settings.edges == loco.edges
            timeline.edges == loco.edges
            classifier.edges == loco.edges
            log.edges == loco.edges
        }
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

