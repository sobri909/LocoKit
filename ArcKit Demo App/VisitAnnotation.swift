// Created by Matt Greenfield on 21/01/16.
// Copyright (c) 2016 Big Paua. All rights reserved.

import MapKit

class VisitAnnotation: NSObject, MKAnnotation {

    var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }

    var view: VisitAnnotationView {
        return VisitAnnotationView(annotation: self, reuseIdentifier: nil)
    }
}
