//
//  TimelineObject.swift
//  ArcKit
//
//  Created by Matt Greenfield on 27/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

public protocol TimelineObject: class {

    var objectId: UUID { get }

    var store: TimelineStore? { get }
    var inTheStore: Bool { get }

}

