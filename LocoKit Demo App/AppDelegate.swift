//
//  AppDelegate.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 10/07/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)
        
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()

        DebugLog.deleteLogFile()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // request "always" location permission
        LocomotionManager.highlander.requestLocationPermission(background: true)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard let controller = window?.rootViewController as? ViewController else { return }
        
        // update the UI on appear
        controller.updateAllViews()
    }

}

