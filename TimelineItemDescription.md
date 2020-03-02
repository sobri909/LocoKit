# TimelineItems

Each TimelineItem is a high level grouping of samples, representing either a `Visit` or a `Path`, depending on whether the user was stationary or travelling between places. The durations can be as brief as a few seconds and as long as days (eg if the user stays at home for several days).

Inside each `TimelineItem` there is a time ordered array of `LocomotionSample` samples. These are found in `timelineItem.samples`. The first sample in that array is the sample taken when the timeline item began, and the last sample marks the end of the timeline item.

LocomotionSamples typically represent between 6 seconds and 30 seconds. If location data accuracy is high, new samples will be produced about every 6 seconds. But if location data accuracy is low, samples can be produced less frequently, due to iOS updating the location less frequently.

The maximum frequency is configurable, with [TimelineManager.samplesPerMinute](https://www.bigpaua.com/locokit/docs/Classes/TimelineManager.html#/Settings)

So for something like a Path timeline item, for example a few minutes walk between places, the Path object itself will have an `activityType` of `.walking`, but there are also all the individual samples that make up that path, some of which might not be `.walking`. For example if the user walks for a minute, pauses for a few seconds, then starts walking again, there might be a `.stationary` sample somewhere half way through the array.