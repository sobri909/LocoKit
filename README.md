# ArcKit

A location and activity recording framework for iOS.

## Features

- Core Location data [filtering](https://en.wikipedia.org/wiki/Kalman_filter) and smoothing 
- Core Motion data filtering and sanitising
- Near real time stationary / moving state detection 
- Extended activity type detection (stationary, walking, running, cycling, car, train, bus,
  motorcycle, airplane, boat)
- Dynamic GPS energy use management
- A [simple API](https://arc-web.herokuapp.com/docs) that frees you from the complexity of Core
  Location and Core Motion

## Examples and Screenshots

- [Location filtering 
  examples](https://github.com/sobri909/ArcKit/blob/master/LocationFilteringExamples.md)
- [Activity type detection examples](https://github.com/sobri909/ArcKit/blob/master/ActivityTypeClassifierExamples.md)

## Documentation 

- [ArcKit API reference](https://arc-web.herokuapp.com/docs)

## Installation

`pod 'ArcKit'`

## Demo Apps

- To run the ArcKit Demo App from this repository:
  1. Download or clone the repository
  1. Run `pod install` in the project folder
  2. In Xcode, change the project's "Team" to match your Apple Developer Account
  3. Build and run!
  4. Go for a walk in your neighbourhood, to see the results :)

- To see the SDK in action in a live, production app, install
  [Arc App](https://itunes.apple.com/app/arc-app-location-activity-tracker/id1063151918?mt=8) 
  from the App Store

## Code Example 

See the ArcKit Demo App source in this repo for more complete code examples.

```swift
let locoManager = LocomotionManager.highlander
let noteCenter = NotificationCenter.default
let queue = OperationQueue.main 

// watch for location updates
noteCenter.addObserver(forName: .locomotionSampleUpdated, object: nil, queue: queue) { _ in
    print("rawLocation: \(locoManager.rawLocation)")
    print("filteredLocation: \(locoManager.filteredLocation)")
    print("locomotionSample: \(locoManager.locomotionSample())")
}

// start recording
locoManager.startCoreLocation()
locoManager.startCoreMotion()
```

