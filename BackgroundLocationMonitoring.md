# Background location monitoring

If you want the app to be relaunched after the user force quits, enable significant location change monitoring. (And I always throw in CLVisit monitoring as well, even though signicant location monitoring makes it redundant.) 

**Note:** You will most likely want the optional `LocoKit/LocalStore` subspec to retain your samples and timeline items in the SQL persistent store.

There are four general requirements for background location recording:

1. Your app has been granted "always" location permission
2. Your app has "Location updates" toggled on in Xcode's "Background Modes"
3. You called `startRecording()` while in the foreground
4. You start monitoring visits and significant location changes
```swift
loco.locationManager.startMonitoringVisits()
loco.locationManager.startMonitoringSignificantLocationChanges()
```

## Background task

If you want the app to continue recording after being launched in the background, start a background task when you `startRecording()`. 

```swift
var backgroundTask = UIBackgroundTaskInvalid

func startBackgroundTask() {
    guard backgroundTask == UIBackgroundTaskInvalid else {
        return
    }

    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LocoKitBackground") { [weak self] in
        self?.endBackgroundTask()
    }
}

func endBackgroundTask() {
    guard backgroundTask != UIBackgroundTaskInvalid else {
        return
    }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = UIBackgroundTaskInvalid
}

```
