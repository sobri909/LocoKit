# ArcKit

Location and activity recording framework for iOS.

## Examples 

#### A 200 Metre Walk Between Nearby Buildings

The orange segments are locations that ArcKit determined to be stationary. The blue segments indicate moving.

Note that locations inside buildings are more likely to classified as stationary. This allows location data to be more 
easily clustered into "visits".  

| Raw (red) + Smoothed (blue) | Smoothed (blue) + Visits (orange) | Smoothed (blue) + Visits (orange) |
| --------------------------- | --------------------------------- | --------------------------------- |
| ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/raw_plus_smoothed.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/smoothed_plus_visits.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/smoothed_only.png) |

## Features

- Kalman filtered and dynamically smoothed location, motion and activity data
- High resolution, near real time stationary / moving state detection, with accuracy up to 5 metres, and reporting 
delay between 6 and 60 seconds
- Lots more I need to fill in here…

## Installation

`pod 'ArcKit'`

## Demo Apps

- To run the demo app from this repository, do a `pod install` before building
- To see the full SDK features in action, including as yet unreleased machine learning 
features, try [Arc App](https://itunes.apple.com/app/arc-app-location-activity-tracker/id1063151918?mt=8) on the App 
Store

## Example 

[code snippet goes here]

## Documentation 

- [ArcKit API Reference](https://sobri909.github.io/ArcKit/)

