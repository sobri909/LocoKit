//
//  DeviceMotion.swift
//  LearnerCoacher
//
//  Created by Matt Greenfield on 21/03/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import CoreMotion

internal class DeviceMotion {
    
    let cmMotion: CMDeviceMotion
    
    init(cmMotion: CMDeviceMotion) {
        self.cmMotion = cmMotion
    }
    
    lazy var userAccelerationInReferenceFrame: CMAcceleration = {
        return self.cmMotion.userAccelerationInReferenceFrame
    }()
    
}
