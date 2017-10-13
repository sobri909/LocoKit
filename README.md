# ArcKit

A location and activity recording framework for iOS.

## Features

- Dynamic location data [filtering](https://en.wikipedia.org/wiki/Kalman_filter) and smoothing 
- High resolution, near real time stationary / moving state detection 
- Core Motion data filtering and sanitising
- High accuracy activity type detection (stationary, walking, running, cycling, car, train, bus,
  motorcycle, airplane, boat)
- Dynamic GPS energy use management
- A [simple API](https://sobri909.github.io/ArcKit/) that frees you from the complexity of Core
  Location and Core Motion

## Examples

- [Location filtering 
  examples](https://github.com/sobri909/ArcKit/blob/master/LocationFilteringExamples.md)
- [Activity type detection examples](https://github.com/sobri909/ArcKit/blob/master/ActivityTypeClassifierExamples.md)

## Documentation 

- [ArcKit API reference](https://sobri909.github.io/ArcKit/)

## Installation

`pod 'ArcKit'`

## Demo Apps

- To run the demo app from this repository, do a `pod install` before building
- To see the full SDK features in action in a production app try
  [Arc App](https://itunes.apple.com/app/arc-app-location-activity-tracker/id1063151918?mt=8) 
  on the App Store

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

