//
//  TimelineStoreCacheDelegate.swift
//  ArcKit
//
//  Created by Matt Greenfield on 27/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

public class TimelineStoreCacheDelegate: NSObject, NSCacheDelegate {

    public func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        if let item = object as? TimelineItem {
            item.inTheStore = false
        } else if let sample = object as? LocomotionSample {
            sample.inTheStore = false
        }
    }

}
