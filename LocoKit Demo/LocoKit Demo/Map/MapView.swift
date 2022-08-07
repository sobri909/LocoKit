//
//  MapView.swift
//  LocoKit Demo
//
//  Created by Matt Greenfield on 4/8/22.
//

import SwiftUI
import LocoKit
import MapKit

struct MapView: UIViewRepresentable {

    @EnvironmentObject var session: Session

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .light
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard LocomotionManager.highlander.applicationState == .active else { return }

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        if session.showTimelineItems {
            for timelineItem in session.timelineSegment.timelineItems {
                if let path = timelineItem as? LocoKit.Path {
                    add(path, to: map)

                } else if let visit = timelineItem as? Visit {
                    add(visit, to: map)
                }
            }

        } else {
            var samples: [LocomotionSample] = []

            // do these as sets, because need to deduplicate
            var rawLocations: Set<CLLocation> = []
            var filteredLocations: Set<CLLocation> = []

            // collect samples and locations from the timeline items
            for timelineItem in session.timelineSegment.timelineItems.reversed() {
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

            add(
                rawLocations.sorted { $0.timestamp < $1.timestamp },
                color: session.showRawLocations ? .systemRed : .black.withAlphaComponent(0.2),
                to: map
            )
            add(
                filteredLocations.sorted { $0.timestamp < $1.timestamp },
                color: session.showFilteredLocations ? .systemPurple : .black.withAlphaComponent(0.2),
                to: map
            )

            if session.showLocomotionSamples {
                let segments = session.timelineSegment.timelineItems.map { $0.segments }.reduce([], +)
                for segment in segments {
                    add(segment.samples, to: map)
                }
            }
        }

        zoomToShow(overlays: map.overlays, in: map)
    }

    // MARK: - Adding map elements

    func add(_ locations: [CLLocation], color: UIColor, to map: MKMapView) {
        guard !locations.isEmpty else {
            return
        }

        var coords = locations.compactMap { $0.coordinate }
        let path = PathPolyline(coordinates: &coords, count: coords.count)
        path.color = color

        map.addOverlay(path)
    }

    func add(_ samples: [LocomotionSample], to map: MKMapView) {
        guard let movingState = samples.first?.movingState else {
            return
        }

        let locations = samples.compactMap { $0.location }

        switch movingState {
        case .moving:
            add(locations, color: .blue, to: map)

        case .stationary:
            add(locations, color: .orange, to: map)

        case .uncertain:
            add(locations, color: .magenta, to: map)
        }
    }

    func add(_ path: LocoKit.Path, to map: MKMapView) {
        if path.samples.isEmpty { return }

        var coords = path.samples.compactMap { $0.location?.coordinate }
        let line = PathPolyline(coordinates: &coords, count: coords.count)
        line.color = .systemBrown

        map.addOverlay(line)
    }

    func add(_ visit: Visit, to map: MKMapView) {
        guard let center = visit.center else { return }

        map.addAnnotation(VisitAnnotation(coordinate: center.coordinate, visit: visit))

        let circle = VisitCircle(center: center.coordinate, radius: visit.radius2sd)
        circle.color = .orange
        map.addOverlay(circle, level: .aboveLabels)
    }

    // MARK: - Zoom

    func zoomToShow(overlays: [MKOverlay], in map: MKMapView) {
        guard !overlays.isEmpty else { return }

        var mapRect: MKMapRect?
        for overlay in overlays {
            if mapRect == nil {
                mapRect = overlay.boundingMapRect
            } else {
                mapRect = mapRect!.union(overlay.boundingMapRect)
            }
        }

        var bottomPadding: CGFloat = 20
        if session.selectedSheetDetent == .height(100) {
            bottomPadding += 100
        }
        if session.selectedSheetDetent == .height(220) {
            bottomPadding += 220
        }
        if session.selectedSheetDetent == .medium {
            bottomPadding += UIScreen.main.bounds.height * 0.5
        }

        let padding = UIEdgeInsets(top: 20, left: 20, bottom: bottomPadding, right: 20)

        map.setVisibleMapRect(mapRect!, edgePadding: padding, animated: true)
    }

    // MARK: - MKMapViewDelegate

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let path = overlay as? PathPolyline { return path.renderer }
            if let circle = overlay as? VisitCircle { return circle.renderer }
            fatalError("you wot?")
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            return (annotation as? VisitAnnotation)?.view
        }
    }

}
