//  Created by Matt Greenfield on 4/10/16.
//  Copyright © 2016 Big Paua. All rights reserved.

import MapKit

class VisitAnnotationView: MKAnnotationView {
   
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        image = UIImage(named: "dot")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
