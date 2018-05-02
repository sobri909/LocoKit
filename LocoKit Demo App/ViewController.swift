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

    // using an Activity Types Classifier requires an API key (see below)
    let useActivityTypesClassifier = false

    // use a plain TimelineStore instead of PersistentTimelineStore if you don't require persistent SQL storage
    let store: TimelineStore = PersistentTimelineStore()

    var recorder: TimelineRecorder

    var dataSet: TimelineSegment?

    lazy var mapView = { return MapView() }()
    lazy var timelineView = { return TimelineView() }()
    let classifierView = ClassifierView()
    let settingsView = SettingsView()
    let locoView = LocoView()
    let logView = LogView()

    // MARK: controller lifecycle

    init() {
        if useActivityTypesClassifier {

            // using an Activity Types Classifier requires an API key
            // API keys can be created at: https://www.bigpaua.com/arckit/account
            LocoKitService.apiKey = "<insert your API key here>"

            recorder = TimelineRecorder(store: store, classifier: TimelineClassifier.highlander)

        } else {
            recorder = TimelineRecorder(store: store)
        }

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let store = store as? PersistentTimelineStore {
            let query = "deleted = 0 AND endDate > datetime('now','-24 hours') AND startDate < datetime('now') ORDER BY startDate DESC"
            dataSet = TimelineSegment(for: query, in: store) {
                onMain { self.update() }
            }
        }

        // observe new timeline items
        when(.newTimelineItem) { _ in
            if let currentItem = self.recorder.currentItem {
                log(".newTimelineItem (\(String(describing: type(of: currentItem))))")
            }
            onMain {
                let items = self.itemsToShow
                self.mapView.update(with: items)
                self.timelineView.update(with: items)
            }
        }

        // observe timeline item updates
        when(.updatedTimelineItem) { _ in
            onMain {
                let items = self.itemsToShow
                self.mapView.update(with: items)
                self.timelineView.update(with: items)
            }
        }

        when(.mergedTimelineItems) { note in
            if let description = note.userInfo?["merge"] as? String {
                log(".mergedItems (\(description))")
            }
            onMain { self.timelineView.update(with: self.itemsToShow) }
        }

        let loco = LocomotionManager.highlander

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

        recorder.startRecording()

        startButton.isHidden = true
        stopButton.isHidden = false
    }
    
    @objc func tappedStop() {
        log("tappedStop()")

        recorder.stopRecording()

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
        if store is PersistentTimelineStore { return persistentItemsToShow }

        guard let currentItem = recorder.currentItem else { return [] }

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
        return dataSet?.timelineItems ?? []
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

