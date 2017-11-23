# Changelog

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
