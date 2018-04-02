//
//  MapView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import MapKit

class MapView: MKMapView {

    let timeline: TimelineManager

    init(timeline: TimelineManager) {
        self.timeline = timeline

        super.init(frame: CGRect.zero)

        self.delegate = self
        self.isRotateEnabled = false
        self.isPitchEnabled = false
        self.showsScale = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with items: [TimelineItem]) {
        let loco = LocomotionManager.highlander

        // don't bother updating the map when we're not in the foreground
        guard UIApplication.shared.applicationState == .active else { return }

        removeOverlays(overlays)
        removeAnnotations(annotations)

        showsUserLocation = Settings.showUserLocation && (loco.recordingState == .recording || loco.recordingState == .wakeup)

        let newMapType: MKMapType = Settings.showSatelliteMap ? .hybrid : .standard
        if mapType != newMapType {
            self.mapType = newMapType
        }

        if Settings.showTimelineItems {
            for timelineItem in items {
                if let path = timelineItem as? Path {
                    add(path)

                } else if let visit = timelineItem as? Visit {
                    add(visit)
                }
            }

        } else {
            var samples: [LocomotionSample] = []

            // do these as sets, because need to deduplicate
            var rawLocations: Set<CLLocation> = []
            var filteredLocations: Set<CLLocation> = []

            // collect samples and locations from the timeline items
            for timelineItem in items.reversed() {
                for sample in timelineItem.samples {
                    samples.append(sample)
                    if let locations = sample.rawLocations {
                        rawLocations = rawLocations.union(locations)
                    }
                    if let locations = sample.filteredLocations {
                        filteredLocations = filteredLocations.union(locations)
                    }
                }
            }

            if Settings.showRawLocations {
                add(rawLocations.sorted { $0.timestamp < $1.timestamp }, color: .red)
            }

            if Settings.showFilteredLocations {
                add(filteredLocations.sorted { $0.timestamp < $1.timestamp }, color: .purple)
            }

            if Settings.showLocomotionSamples {
                let groups = sampleGroups(from: samples)
                for group in groups {
                    add(group)
                }
            }
        }

        if Settings.autoZoomMap {
            zoomToShow(overlays: overlays)
        }
    }

    func sampleGroups(from samples: [LocomotionSample]) -> [[LocomotionSample]] {
        var groups: [[LocomotionSample]] = []
        var currentGroup: [LocomotionSample]?

        for sample in samples where sample.location != nil {
            let currentState = sample.movingState

            // state changed? close off the previous group, add to the collection, and start a new one
            if let previousState = currentGroup?.last?.movingState, previousState != currentState {

                // add new sample to previous grouping, to link them end to end
                currentGroup?.append(sample)

                // add it to the collection
                groups.append(currentGroup!)

                currentGroup = nil
            }

            currentGroup = currentGroup ?? []
            currentGroup?.append(sample)
        }

        // add the final grouping to the collection
        if let grouping = currentGroup {
            groups.append(grouping)
        }

        return groups
    }

    func add(_ locations: [CLLocation], color: UIColor) {
        guard !locations.isEmpty else {
            return
        }

        var coords = locations.compactMap { $0.coordinate }
        let path = PathPolyline(coordinates: &coords, count: coords.count)
        path.color = color

        add(path)
    }

    func add(_ samples: [LocomotionSample]) {
        guard let movingState = samples.first?.movingState else {
            return
        }

        let locations = samples.compactMap { $0.location }

        switch movingState {
        case .moving:
            add(locations, color: .blue)

        case .stationary:
            add(locations, color: .orange)

        case .uncertain:
            add(locations, color: .magenta)
        }
    }

    func add(_ path: Path) {
        if path.samples.isEmpty { return }

        var coords = path.samples.compactMap { $0.location?.coordinate }
        let line = PathPolyline(coordinates: &coords, count: coords.count)
        line.color = timeline.activeItems.contains(path) ? .brown : .darkGray

        add(line)
    }

    func add(_ visit: Visit) {
        guard let center = visit.center else { return }

        addAnnotation(VisitAnnotation(coordinate: center.coordinate, visit: visit))

        let circle = VisitCircle(center: center.coordinate, radius: visit.radius2sd)
        circle.color = timeline.activeItems.contains(visit) ? .orange : .darkGray
        add(circle, level: .aboveLabels)
    }


    func zoomToShow(overlays: [MKOverlay]) {
        guard !overlays.isEmpty else { return }

        var mapRect: MKMapRect?
        for overlay in overlays {
            if mapRect == nil {
                mapRect = overlay.boundingMapRect
            } else {
                mapRect = MKMapRectUnion(mapRect!, overlay.boundingMapRect)
            }
        }

        let padding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        setVisibleMapRect(mapRect!, edgePadding: padding, animated: true)
    }
}

extension MapView: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let path = overlay as? PathPolyline {
            return path.renderer

        } else if let circle = overlay as? VisitCircle {
            return circle.renderer

        } else {
            fatalError("you wot?")
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let annotation = annotation as? VisitAnnotation {
            let view = annotation.view
            if !timeline.activeItems.contains(annotation.visit) {
                view.image = UIImage(named: "inactiveDot")
            }
            return view
        }
        return nil
    }

}
