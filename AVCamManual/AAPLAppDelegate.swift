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
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {
        // We use the device orientation to set the video orientation of the video preview,
        // and to set the orientation of still images and recorded videos.
        
        // Inform the device that we want to use the device orientation.
        UIDevice.currentDevice().beginGeneratingDeviceOrientationNotifications()
        return true
    }
    
    func applicationWillTerminate(application: UIApplication) {
        // Inform the device that we no longer require access the device orientation.
        UIDevice.currentDevice().endGeneratingDeviceOrientationNotifications()
    }
    
    func applicationWillEnterForeground(application: UIApplication) {
        // Inform the device that we want to use the device orientation again.
        UIDevice.currentDevice().beginGeneratingDeviceOrientationNotifications()
    }
    
    func applicationDidEnterBackground(application: UIApplication) {
        // Let the device power down the accelerometer if not used elsewhere while backgrounded.
        UIDevice.currentDevice().endGeneratingDeviceOrientationNotifications()
    }
    
}