// Created by Matt Greenfield on 21/01/16.
// Copyright (c) 2016 Big Paua. All rights reserved.

import MapKit
import LocoKit

class VisitAnnotation: NSObject, MKAnnotation {

    var coordinate: CLLocationCoordinate2D
    var visit: Visit

    init(coordinate: CLLocationCoordinate2D, visit: Visit) {
        self.coordinate = coordinate
        self.visit = visit
        super.init()
    }

    var view: VisitAnnotationView {
        return VisitAnnotationView(annotation: self, reuseIdentifier: nil)
    }
}
