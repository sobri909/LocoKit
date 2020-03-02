# LocoKit

A Machine Learning based location recording and activity detection framework for iOS.

## Location and Motion Recording

- Combined, simplified Core Location and Core Motion recording
- Filtered, smoothed, and simplified location and motion data
- Near real time stationary / moving state detection
- Automatic energy use management, enabling all day recording
- Automatic stopping and restarting of recording, to avoid wasteful battery use

## Activity Type Detection

- Machine Learning based activity type detection
- Improved detection of Core Motion activity types (stationary, walking, running, cycling,
  automotive)
- Distinguish between specific transport types (car, train, bus, motorcycle, airplane, boat)

## Record High Level Visits and Paths

- Optionally produce high level `Path` and `Visit` timeline items, to represent the recording 
  session at human level. Similar to Core Location's `CLVisit`, but with much higher accuracy, much 
  more detail, and with the addition of Paths (ie the trips between Visits). 
- Optionally persist your recorded samples and timeline items to a local SQL based store, for
  retention between sessions.

[More information about timeline items can be found here](https://github.com/sobri909/LocoKit/blob/master/TimelineItemDescription.md)

## Supporting the Project

LocoKit is an LGPL licensed open source project. Its ongoing development is made possible 
thanks to the support of its backers on Patreon.

- [patreon.com/sobri909](https://www.patreon.com/sobri909)

If you have an app that uses LocoKit and is a revenue generating product, please consider
sponsoring LocoKit development, to ensure the project that your product relies on stays
healthy and actively maintained.

Thanks so much for your support!

# Installation

```ruby
pod 'LocoKit'
pod 'LocoKit/LocalStore' # optional
```

**Note:** Include the optional `LocoKit/LocalStore` subspec if you would like to retain your samples
and timeline items in the SQL persistent store.

# High Level Recording 

## Record TimelineItems (Paths and Visits)

```swift
// retain a timeline manager
self.timeline = TimelineManager()

// start recording, and producing timeline items 
self.timeline.startRecording()

// observe timeline item updates
when(timeline, does: .updatedTimelineItem) { _ in
    let currentItem = timeline.currentItem

    // duration of the current Path or Visit
    print("item.duration: \(currentItem.duration)")

    // activity type of the current Path (eg walking, cycling, car)
    if let path = currentItem as? Path {
        print("path.activityType: \(path.activityType)")
    }

    // examine each of the LocomotionSamples within the Path or Visit
    for sample in currentItem.samples {
        print("sample: \(sample)")
    }
}
```

# Low Level Recording

## Record LocomotionSamples (CLLocations combined with Core Motion data)

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

```swift
// watch for updated LocomotionSamples
when(loco, does: .locomotionSampleUpdated) { _ in

    // the raw CLLocation
    print(loco.rawLocation)

    // a more usable, de-noised CLLocation
    print(loco.filteredLocation)

    // a smoothed, simplified, combined location and motion sample
    print(loco.locomotionSample())
}
```

## Fetching TimelineItems / Samples

If you wanted to get all timeline items between the start of today and now, you might do this:

```swift
let date = Date() // some specific day
let items = store.items(
        where: "deleted = 0 AND endDate > ? AND startDate < ? ORDER BY endDate",
        arguments: [date.startOfDay, date.endOfDay])
```

You can also construct more complex queries, like for fetching all timeline items that overlap a certain geographic region. Or all samples of a specific activity type (eg all "car" samples). Or all timeline items that contain samples over a certain speed (eg paths containing fast driving).

## Detect Activity Types

Note that if you are using a `TimelineManager`, activity type classifying is already handled 
for you by the manager, on both the sample and timeline item levels. You should only need to 
directly interact with clasifiers if you are either not using a TimelineManager, or are wanting 
to do low level processing at the sample level.

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

## Background Location Monitoring

If you want the app to be relaunched after the user force quits, enable significant location change monitoring.

[More details and requirements here](https://github.com/sobri909/LocoKit/blob/master/BackgroundLocationMonitoring.md)

## Examples and Screenshots

- [Location filtering 
  examples](https://github.com/sobri909/LocoKit/blob/master/LocationFilteringExamples.md)
- [Activity type detection examples](https://github.com/sobri909/LocoKit/blob/master/ActivityTypeClassifierExamples.md)

## Documentation 

- [LocoKit API reference](https://www.bigpaua.com/arckit/docs)
- [LocoKitCore API reference](https://www.bigpaua.com/arckit/docs_core)

## Try the LocoKit Demo App

1. Download or clone this repository
2. `pod install`
3. In Xcode, change the Demo App project's "Team" to match your Apple Developer Account
4. In Xcode, change the Demo App project's "Bundle Identifier" to something unique
5. Build and run!
6. Go for a walk, cycle, drive, etc, and see the results :)

## Try Arc App on the App Store

- To see the SDK in action in a live, production app, install
  [Arc App](https://itunes.apple.com/app/arc-app-location-activity-tracker/id1063151918?mt=8) 
  from the App Store, our free life logging app based on LocoKit

