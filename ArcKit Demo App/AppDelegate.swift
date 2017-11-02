//
//  AppDelegate.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 10/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import UIKit
import ArcKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()

        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        LocomotionManager.highlander.requestLocationPermission(background: true)
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard let controller = window?.rootViewController as? ViewController else {
            return
        }
        
        // update the map and UI on appear
        controller.updateTheMap()
        controller.buildResultsViewTree()
    }

}

