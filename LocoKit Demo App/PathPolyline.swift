// Created by Matt Greenfield on 16/11/15.
// Copyright (c) 2015 Big Paua. All rights reserved.

import MapKit

class PathPolyline: MKPolyline {

    var color: UIColor?

    var renderer: MKPolylineRenderer {
        let renderer = MKPolylineRenderer(polyline: self)
        renderer.strokeColor = color
        renderer.lineWidth = 3
        return renderer
    }
}
