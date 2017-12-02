# ArcKit

A machine learning based location and activity recording and detection framework for iOS.

## Location and Motion Recording

- Combined, simplified Core Location and Core Motion recording
- Filtered, smoothed, and simplified location and motion data
- Near real time stationary / moving state detection
- Automatic energy use management, enabling all day recording 

## Activity Type Detection

- Machine Learning based activity type detection
- Improved detection of Core Motion activity types (stationary, walking, running, cycling,
  automotive)
- Distinguish between specific transport types (car, train, bus, motorcycle, airplane, boat)

## Installation

`pod 'ArcKit'`

## Record Location and Motion

```swift
// the recording manager singleton
let loco = LocomotionManager.highlander
```

```swift
// decide which Core Motion features to include
loco.recordPedometerEvents = true
loco.recordAccelerometerEvents = true
loco.recordCoreMotionActivityTypeEvents = true
```

```swift
// decide whether to use "sleep mode" to allow for all day recording 
loco.useLowPowerSleepModeWhileStationary = true
```

**Note:** The above settings are all on by default. The above snippets are unnecessary, and just here 
  to show you some of the available options. 

```swift
// start recording 
loco.startRecording()
```

## Watch For Location Updates

```swift
when(loco, does: .locomotionSampleUpdated) { _ in

    // the raw CLLocation
    print(loco.rawLocation)

    // a more usable, de-noised CLLocation
    print(loco.filteredLocation)

    // a smoothed, simplified, combined location and motion sample
    print(loco.locomotionSample())
}
```

## Watch For Moving State Changes

```swift
when(loco, does: .movingStateChanged) { _ in
    if loco.movingState == .moving {
        print("started moving")
    }

    if loco.movingState == .stationary {
        print("stopped moving")
    }
}
```

**Note:** The above code snippets use [SwiftNotes](https://github.com/sobri909/SwiftNotes) to make
  the event observing code easier to read. If you're not using SwiftNotes, your observers should be
  written something like this:

```swift
let noteCenter = NotificationCenter.default
let queue = OperationQueue.main 

// watch for updates
noteCenter.addObserver(forName: .locomotionSampleUpdated, object: loco, queue: queue) { _ in
    // do stuff
}
```

## Detect Activity Types

```swift
// fetch a geographically relevant classifier
let classifier = ActivityTypeClassifier(coordinate: location.coordinate)

// classify a locomotion sample
let results = classifier.classify(sample)

// get the best match activity type
let bestMatch = results.first

// print the best match type's name ("walking", "car", etc)
print(bestMatch.name)
```

## Examples and Screenshots

- [Location filtering 
  examples](https://github.com/sobri909/ArcKit/blob/master/LocationFilteringExamples.md)
- [Activity type detection examples](https://github.com/sobri909/ArcKit/blob/master/ActivityTypeClassifierExamples.md)

## Documentation 

- [ArcKit API reference](https://www.bigpaua.com/arckit/docs)

## Try the Demo App

- To run the ArcKit Demo App:
  1. Download or clone this repository
  1. Run `pod install` in the project folder
  2. In Xcode, change the project's "Team" to match your Apple Developer Account
  3. Build and run!
  4. Go for a walk, cycle, drive, etc, and see the results :)

## Try Arc App on the App Store

- To see the SDK in action in a live, production app, install
  [Arc App](https://itunes.apple.com/app/arc-app-location-activity-tracker/id1063151918?mt=8) 
  from the App Store, our free life logging app based on ArcKit

