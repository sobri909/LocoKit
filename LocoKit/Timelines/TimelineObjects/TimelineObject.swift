//
//  TimelineObject.swift
//  LocoKit
//
//  Created by Matt Greenfield on 27/01/18.
//  Copyright © 2018 Big Paua. All rights reserved.
//

public protocol TimelineObject: class {

    var objectId: UUID { get }
    var source: String { get set }
    var store: TimelineStore? { get }

}

