//
//  ActivityTypeTrainable.swift
//  LocoKitCore
//
//  Created by Matt Greenfield on 20/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

public protocol ActivityTypeTrainable: ActivityTypeClassifiable {
    
    var confirmedType: ActivityTypeName? { get set }
    var classifiedType: ActivityTypeName? { get }
    
}
