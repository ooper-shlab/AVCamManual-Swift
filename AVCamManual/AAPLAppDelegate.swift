//
//  AAPLAppDelegate.swift
//  AVCamManual
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/5/2.
//
//
/*
Copyright (C) 2015 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
Application delegate.
*/

import UIKit

@UIApplicationMain
@objc(AAPLAppDelegate)
class AAPLAppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // We use the device orientation to set the video orientation of the video preview,
        // and to set the orientation of still images and recorded videos.
        
        // Inform the device that we want to use the device orientation.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Inform the device that we no longer require access the device orientation.
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Inform the device that we want to use the device orientation again.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Let the device power down the accelerometer if not used elsewhere while backgrounded.
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
}
