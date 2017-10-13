# Location Filtering Examples

These screenshots were taken from the ArcKit Demo App. Compile and run the Demo App on device to 
experiment with the SDK and see results in your local area. 

### Filtering and Smoothing

ArcKit uses a two pass system of filtering and smoothing location data. 

The first pass is a [Kalman filter](https://en.wikipedia.org/wiki/Kalman_filter) to remove noise from 
the raw locations. The second pass is a dynamically sized, weighted moving average, to turn potentially
erratic paths into smoothed, presentable lines.

### Short Walk Between Nearby Buildings

| Raw (red) + Smoothed (blue) | Smoothed (blue) + Visits (orange) | Smoothed (blue) + Visits (orange) |
| --------------------------- | --------------------------------- | --------------------------------- |
| ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/raw_plus_smoothed.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/smoothed_plus_visits.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/smoothed_only.png) |

The blue segments indicate locations that ArcKit determined to be moving. The orange segments indicate
stationary. Note that locations inside buildings are more likely to classified as stationary, thus 
allowing location data to be more easily clustered into "visits".

### Tuk-tuk Ride Through Traffic in Built-up City Area 

| Raw Locations | Smoothed (blue) + Stuck (orange) | Smoothed (blue) + Stuck (orange) |
| ------------- | -------------------------------- | -------------------------------- |
| ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/tuktuk_raw.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/tuktuk_smoothed_plus_visits.png) | ![](https://raw.githubusercontent.com/sobri909/ArcKit/master/Screenshots/tuktuk_smoothed.png) |

Location accuracy for this trip ranged from 30 to 100 metres, with minimal GPS line of sight and
significant "urban canyon" effects (GPS blocked on both sides by tall buildings and blocked from above by 
an elevated rail line). However stationary / moving state detection was still achieved to an accuracy of 
5 to 10 metres. 

**Note:** The orange dots in the second screenshot indicate "stuck in traffic". The third screenshot 
shows the "stuck" segments as paths, for easier inspection. 
