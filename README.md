# ArcKit

A location and activity recording framework for iOS.

## Demo App Examples 

### Short Walk Between Nearby Buildings

The blue segments indicate locations that ArcKit determined to be moving. The orange segments indicate stationary. Note
that locations inside buildings are more likely to classified as stationary, thus allowing location data to be more 
easily clustered into "visits".

| Raw (red) + Smoothed (blue) | Smoothed (blue) + Visits (orange) | Smoothed (blue) + Visits (orange) |
| --------------------------- | --------------------------------- | --------------------------------- |
| ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/raw_plus_smoothed.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/smoothed_plus_visits.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/smoothed_only.png) |

### Tuk-tuk Ride Through Traffic in Built-up City Area 

Location accuracy for this trip ranged from 30 to 100 metres, with minimal GPS line of sight and
significant "urban canyon" effects (GPS blocked on both sides by tall buildings and blocked from above by an elevated 
rail line). However stationary / moving state detection was still achieved to an accuracy of 5 to 10 metres. 

**Note:** The orange dots in the second screenshot incidate "stuck in traffic". The third screenshot shows the "stuck" 
segments as paths, for easier inspection. 

| Raw Locations | Smoothed (blue) + Stuck (orange) | Smoothed (blue) + Stuck (orange) |
| ------------- | -------------------------------- | -------------------------------- |
| ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/tuktuk_raw.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/tuktuk_smoothed_plus_visits.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/tuktuk_smoothed.png) |


## Features

- Raw locations, [Kalman filtered](https://en.wikipedia.org/wiki/Kalman_filter) locations, and dynamically smoothed 
[LocomotionSamples](https://sobri909.github.io/ArcKit/Classes/LocomotionSample.html) (combined location / motion / 
activity state objects)
- High resolution, near real time stationary / moving state detection (with accuracy up to 5 metres, and reporting 
delay between 6 and 60 seconds)
- Dynamic energy use management, to achieve best possible accuracy without wasteful battery consumption
- Filtered and sanitised Core Motion accelerometer, pedometer, and activity type data
- **Coming in next release:** Machine learning based activity type detection with significantly higher accuracy than 
Core Motion, and ability to distinguish between more activity types (car, train, bus, and more). 

## Installation

`pod 'ArcKit'`

## Demo Apps

- To run the demo app from this repository, do a `pod install` before building
- To see the full SDK features in action in a production app (including as yet unreleased machine learning 
features) try [Arc App](https://itunes.apple.com/app/arc-app-location-activity-tracker/id1063151918?mt=8) on the App 
Store

## Code Example 

See the demo app source in this repo for more complete code examples.

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
```

## Documentation 

- [ArcKit API Reference](https://sobri909.github.io/ArcKit/)

