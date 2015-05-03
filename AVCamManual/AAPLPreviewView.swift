//
//  AAPLPreviewView.swift
//  AVCamManual
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/4/26.
//
//
/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:

  Camera preview.

*/

import UIKit
import AVFoundation

@objc(AAPLPreviewView)
class AAPLPreviewView: UIView {
    
    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var session: AVCaptureSession? {
        get {
            return (self.layer as! AVCaptureVideoPreviewLayer).session
        }
        
        set {
            (self.layer as! AVCaptureVideoPreviewLayer).session = newValue
        }
    }
    
}