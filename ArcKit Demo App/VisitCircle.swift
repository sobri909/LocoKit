// Created by Matt Greenfield on 9/11/15.
// Copyright (c) 2015 Big Paua. All rights reserved.

import MapKit

class VisitCircle: MKCircle {
    
    var color: UIColor?

    var renderer: MKCircleRenderer {
        let renderer = MKCircleRenderer(circle: self)
        renderer.fillColor = color?.withAlphaComponent(0.2)
        renderer.strokeColor = nil
        renderer.lineWidth = 0
        return renderer
    }
}
