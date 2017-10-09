# Changelog

## [2.0.1] - 2017-10-09

### Added

- Added isStale property to classifiers, to know whether it's worth fetching a
  replacement classifier yet. 
- Added coverageScore property to classifiers, to give an indication of the usability of the
  model data in the classifier's geographic region. (The score is the result of 
  completenessScore * accuracyScore.)

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
