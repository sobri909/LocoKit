# Changelog

## [5.0.0] - 2018-03-18

### Added

- Added a high level `TimelineManager`, for post processing LocomotionSamples into Visits and 
  Paths,  See the `TimelineManager` API docs for details, and the LocoKit Demo App for code examples.
- Added `PersistentTimelineManager`, an optional persistent SQL store for timeline items. To make 
  use of the persistent store, add `pod "LocoKit/LocalStore"` to your Podfile and use 
  `PersistentTimelineManager` instead of `TimelineManager`. 
- Added `TimelineClassifier` to make it easier to classify collections of LocomotionSamples.
- Added convenience methods to arrays of LocomotionSamples, for example 
  `arrayOfSamples.weightedCenter`, `arrayOfSamples.duration`.

### Changed

- Renamed ArcKit to LocoKit, to avoid confusion with Arc App. Note that you now need to set 
  your API key on `LocoKitService.apiKey` instead of `ArcKitService.apiKey`. All other methods 
  and classes remain unaffected by the project name change. 
- Made various `LocomotionSample` properties (`stepHz`, `courseVariance`, `xyAcceleration`, 
  `zAcceleration`) optional, to avoid requiring magic numbers when 
  their source data is unavailable. 

## [4.0.2] - 2017-11-27

- Stopped doing unnecessary ArcKitService API requests, and tidied up some console logging

## [4.0.1] - 2017-11-27

### Fixed

- Fixed overly aggressive reentry to sleep mode after calling `stopRecording()` then 
  `startRecording()`.  

## [4.0.0] - 2017-11-27

### Added

- Added a low power Sleep Mode. Read the `LocomotionManager.useLowPowerSleepModeWhileStationary` API 
  docs for more details.
- Added ability to disable dynamic desiredAccuracy adjustments. Read the  
  `LocomotionManager.dynamicallyAdjustDesiredAccuracy` API docs for more details.
- Added LocomotionManager settings for configuring which (if any) Core Motion features to make use of
  whilst recording.

### Removed

- `startCoreLocation()` has been renamed to `startRecording()` and now starts both Core Location 
  and Core Motion recording (depending on your LocomotionManager settings). Additionally, 
  `stopCoreLocation()` has been renamed to `stopRecording()`, and `startCoreMotion()` and 
  `stopCoreMotion()` have been removed. 
- `recordingCoreLocation` and `recordingCoreMotion` have been removed, and replaced by 
  `recordingState`. 
- The `locomotionSampleUpdated` notification no longer includes a userInfo dict. 

## [3.0.0] - 2017-11-23

### Added

- Open sourced `LocomotionManager` and `LocomotionSample`. 

### Changed

- Moved `apiKey` from `LocomotionManager` to `ArcKitService`. Note that this is a breaking 
  change - you will need up update your code to set the API key in the new location.
- Split the SDK into two separate frameworks. The `ArcKit` framework now contains only the open 
  source portions, while the new `ArcKitCore` contains the binary framework. (Over time I will 
  be open sourcing more code by migrating it from the binary framework to the source framework.)

## [2.1.0] - 2017-11-02

### Added

- Supports / requires Xcode 9.1 (pin to `~> 2.0.1` if you require Xcode 9.0 support)
- Added a `locomotionManager.locationManagerDelegate` to allow forwarding of 
  CLLocationManagerDelegate events from the internal CLLocationManager
- Made public the `classifier.accuracyScore` property
- Added an `isEmpty` property to `ClassifierResults`

### Fixed 

- Properly reports ArcKit API request failures to console

## [2.0.1] - 2017-10-09

### Added

- Added `isStale` property to classifiers, to know whether it's worth fetching a
  replacement classifier yet
- Added `coverageScore` property to classifiers, to give an indication of the usability of the
  model data in the classifier's geographic region. (The score is the result of 
  `completenessScore * accuracyScore`)

## [2.0.0] - 2017-09-15

### Added

- New machine learning engine for activity type detection. Includes the same base types
  supported by Core Motion, plus also car, train, bus, motorcycle, boat, airplane, where 
  data is available.

### Fixed

- Misc minor tweaks and improvements to the location data filtering, smoothing, and dynamic 
  accuracy adjustments


## [1.0.0] - 2017-07-28

- Initial release
