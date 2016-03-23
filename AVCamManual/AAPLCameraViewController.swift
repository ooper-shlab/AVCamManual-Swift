//
//  AAPLCameraViewController.swift
//  AVCamManual
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/4/26.
//
//
/*
Copyright (C) 2015 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
View controller for camera interface.
*/

import UIKit
import AVFoundation
import Photos

private var CapturingStillImageContext = 0
private var SessionRunningContext = 0

private var FocusModeContext = 0
private var ExposureModeContext = 0
private var WhiteBalanceModeContext = 0
private var LensPositionContext = 0
private var ExposureDurationContext = 0
private var ISOContext = 0
private var ExposureTargetOffsetContext = 0
private var DeviceWhiteBalanceGainsContext = 0
private var LensStabilizationContext = 0

private enum AVCamManualSetupResult: Int {
    case Success
    case CameraNotAuthorized
    case SessionConfigurationFailed
}

@objc(AAPLCameraViewController)
class AAPLCameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    @IBOutlet weak var previewView: AAPLPreviewView!
    @IBOutlet weak var cameraUnavailableLabel: UILabel!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var stillButton: UIButton!
    @IBOutlet weak var manualSegments: UISegmentedControl!
    
    private var focusModes: [AVCaptureFocusMode] = []
    @IBOutlet weak var manualHUDFocusView: UIView!
    @IBOutlet weak var focusModeControl: UISegmentedControl!
    @IBOutlet weak var lensPositionSlider: UISlider!
    @IBOutlet weak var lensPositionNameLabel: UILabel!
    @IBOutlet weak var lensPositionValueLabel: UILabel!
    
    private var exposureModes: [AVCaptureExposureMode] = []
    @IBOutlet weak var manualHUDExposureView: UIView!
    @IBOutlet weak var exposureModeControl: UISegmentedControl!
    @IBOutlet weak var exposureDurationSlider: UISlider!
    @IBOutlet weak var exposureDurationNameLabel: UILabel!
    @IBOutlet weak var exposureDurationValueLabel: UILabel!
    @IBOutlet weak var ISOSlider: UISlider!
    @IBOutlet weak var ISONameLabel: UILabel!
    @IBOutlet weak var ISOValueLabel: UILabel!
    @IBOutlet weak var exposureTargetBiasSlider: UISlider!
    @IBOutlet weak var exposureTargetBiasNameLabel: UILabel!
    @IBOutlet weak var exposureTargetBiasValueLabel: UILabel!
    @IBOutlet weak var exposureTargetOffsetSlider: UISlider!
    @IBOutlet weak var exposureTargetOffsetNameLabel: UILabel!
    @IBOutlet weak var exposureTargetOffsetValueLabel: UILabel!
    
    private var whiteBalanceModes: [AVCaptureWhiteBalanceMode] = []
    @IBOutlet weak var manualHUDWhiteBalanceView: UIView!
    @IBOutlet weak var whiteBalanceModeControl: UISegmentedControl!
    @IBOutlet weak var temperatureSlider: UISlider!
    @IBOutlet weak var temperatureNameLabel: UILabel!
    @IBOutlet weak var temperatureValueLabel: UILabel!
    @IBOutlet weak var tintSlider: UISlider!
    @IBOutlet weak var tintNameLabel: UILabel!
    @IBOutlet weak var tintValueLabel: UILabel!
    
    @IBOutlet weak var manualHUDLensStabilizationView: UIView!
    @IBOutlet weak var lensStabilizationControl: UISegmentedControl!
    
    // Session management.
    private var sessionQueue: dispatch_queue_t!
    dynamic var session: AVCaptureSession!
    dynamic var videoDeviceInput: AVCaptureDeviceInput?
    dynamic var videoDevice: AVCaptureDevice?
    dynamic var movieFileOutput: AVCaptureMovieFileOutput?
    dynamic var stillImageOutput: AVCaptureStillImageOutput?
    
    // Utilities.
    private var setupResult: AVCamManualSetupResult = .Success
    private var sessionRunning: Bool = false
    private var backgroundRecordingID: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    private let kExposureDurationPower = 5.0 // Higher numbers will give the slider more sensitivity at shorter durations
    private let kExposureMinimumDuration = 1.0/1000 // Limit exposure duration to a useful range
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.stillButton.enabled = false

        self.manualHUDFocusView.hidden = true
        self.manualHUDExposureView.hidden = true
        self.manualHUDWhiteBalanceView.hidden = true
        self.manualHUDLensStabilizationView.hidden = true
        
        // Create the AVCaptureSession.
        self.session = AVCaptureSession()
        
        // Setup the preview view.
        self.previewView.session = self.session
        
        // Communicate with the session and other session objects on this queue.
        self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
        
        self.setupResult = AVCamManualSetupResult.Success
        
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        switch AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo) {
        case AVAuthorizationStatus.Authorized:
            // The user has previously granted access to the camera.
            break
        case AVAuthorizationStatus.NotDetermined:
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            dispatch_suspend(self.sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo) {granted in
                if !granted {
                    self.setupResult = AVCamManualSetupResult.CameraNotAuthorized
                }
                dispatch_resume(self.sessionQueue)
            }
        default:
            // The user has previously denied access.
            self.setupResult = AVCamManualSetupResult.CameraNotAuthorized
        }
        
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        dispatch_async(self.sessionQueue) {
            guard self.setupResult == AVCamManualSetupResult.Success else {
                return
            }
            
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            
            let videoDevice = AAPLCameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            let videoDeviceInput: AVCaptureDeviceInput!
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                
            } catch let error as NSError {
                videoDeviceInput = nil
                NSLog("Could not create video device input: %@", error)
            } catch _ {
                videoDeviceInput = nil
                fatalError()
            }
            
            self.session.beginConfiguration()
            
            if self.session.canAddInput(videoDeviceInput) {
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                self.videoDevice = videoDevice
                
                dispatch_async(dispatch_get_main_queue()) {
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for AAPLPreviewView and UIView
                    // can only be manipulated on the main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                    // on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                    
                    // Use the status bar orientation as the initial video orientation. Subsequent orientation changes are handled by
                    // -[viewWillTransitionToSize:withTransitionCoordinator:].
                    let statusBarOrientation = UIApplication.sharedApplication().statusBarOrientation
                    var initialVideoOrientation = AVCaptureVideoOrientation.Portrait
                    if statusBarOrientation != UIInterfaceOrientation.Unknown {
                        initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                    }
                    
                    let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                    previewLayer.connection.videoOrientation = initialVideoOrientation
                }
            } else {
                NSLog("Could not add video device input to the session")
                self.setupResult = AVCamManualSetupResult.SessionConfigurationFailed
            }
            
            let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            let audioDeviceInput: AVCaptureDeviceInput!
            do {
                audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                
            } catch let error as NSError {
                audioDeviceInput = nil
                NSLog("Could not create audio device input: %@", error)
            } catch _ {
                audioDeviceInput = nil
                fatalError()
            }
            
            if self.session.canAddInput(audioDeviceInput) {
                self.session.addInput(audioDeviceInput)
            } else {
                NSLog("Could not add audio device input to the session")
            }
            
            let movieFileOutput = AVCaptureMovieFileOutput()
            if self.session.canAddOutput(movieFileOutput) {
                self.session.addOutput(movieFileOutput)
                if let connection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                where connection.supportsVideoStabilization {
                    connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                NSLog("Could not add movie file output to the session")
                self.setupResult = AVCamManualSetupResult.SessionConfigurationFailed
            }
            
            let stillImageOutput = AVCaptureStillImageOutput()
            if self.session.canAddOutput(stillImageOutput) {
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
                self.stillImageOutput!.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                self.stillImageOutput!.highResolutionStillImageOutputEnabled = true
            } else {
                NSLog("Could not add still image output to the session")
                self.setupResult = AVCamManualSetupResult.SessionConfigurationFailed
            }
            
            self.session.commitConfiguration()
            
            dispatch_async(dispatch_get_main_queue()) {
                self.configureManualHUD()
            }
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        dispatch_async(self.sessionQueue) {
            switch self.setupResult {
            case AVCamManualSetupResult.Success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.sessionRunning = self.session.running
            case AVCamManualSetupResult.CameraNotAuthorized:
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("AVCamManual doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera" )
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: UIAlertControllerStyle.Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    // Provide quick access to Settings.
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: UIAlertActionStyle.Default) {action in
                        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                    }
                    alertController.addAction(settingsAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            case AVCamManualSetupResult.SessionConfigurationFailed:
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: UIAlertControllerStyle.Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewDidDisappear(animated: Bool) {
        dispatch_async(self.sessionQueue) {
            if self.setupResult == AVCamManualSetupResult.Success {
                self.session.stopRunning()
                self.removeObservers()
            }
        }
        
        super.viewDidDisappear(animated)
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    //MARK: Orientation
    
    override func shouldAutorotate() -> Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !(self.movieFileOutput?.recording ?? false);
    }
    
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.All
    }
    
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        
        // Note that the app delegate controls the device orientation notifications required to use the device orientation.
        let deviceOrientation = UIDevice.currentDevice().orientation
        if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            previewLayer.connection.videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
        }
    }
    
    //MARK: KVO and Notifications
    
    private func addObservers() {
        self.addObserver(self, forKeyPath: "session.running", options: .New, context: &SessionRunningContext)
        self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options: .New, context: &CapturingStillImageContext)
        
        self.addObserver(self, forKeyPath: "videoDevice.focusMode", options: [.Old, .New], context: &FocusModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.lensPosition", options: .New, context: &LensPositionContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureMode", options: [.Old, .New], context: &ExposureModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureDuration", options: .New, context: &ExposureDurationContext)
        self.addObserver(self, forKeyPath: "videoDevice.ISO", options: .New, context: &ISOContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureTargetOffset", options: .New, context: &ExposureTargetOffsetContext)
        self.addObserver(self, forKeyPath: "videoDevice.whiteBalanceMode", options: [.Old, .New], context: &WhiteBalanceModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.deviceWhiteBalanceGains", options: .New, context: &DeviceWhiteBalanceGainsContext)
        
        self.addObserver(self, forKeyPath: "stillImageOutput.lensStabilizationDuringBracketedCaptureEnabled", options: [.Old, .New], context: &LensStabilizationContext)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AAPLCameraViewController.subjectAreaDidChange(_:)), name:AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDevice!)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AAPLCameraViewController.sessionRuntimeError(_:)), name:AVCaptureSessionRuntimeErrorNotification, object: self.session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        if #available(iOS 9.0, *) {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AAPLCameraViewController.sessionWasInterrupted(_:)), name:AVCaptureSessionWasInterruptedNotification, object: self.session)
        }
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AAPLCameraViewController.sessionInterruptionEnded(_:)), name:AVCaptureSessionInterruptionEndedNotification, object: self.session)
    }
    
    private func removeObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        
        self.removeObserver(self, forKeyPath: "session.running", context: &SessionRunningContext)
        self.removeObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", context: &CapturingStillImageContext)
        
        self.removeObserver(self, forKeyPath: "videoDevice.focusMode", context: &FocusModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.lensPosition", context: &LensPositionContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureMode", context: &ExposureModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureDuration", context: &ExposureDurationContext)
        self.removeObserver(self, forKeyPath: "videoDevice.ISO", context: &ISOContext)
        
        self.removeObserver(self, forKeyPath: "videoDevice.exposureTargetOffset", context: &ExposureTargetOffsetContext)
        self.removeObserver(self, forKeyPath: "videoDevice.whiteBalanceMode", context: &WhiteBalanceModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.deviceWhiteBalanceGains", context: &DeviceWhiteBalanceGainsContext)
        
        self.removeObserver(self, forKeyPath: "stillImageOutput.lensStabilizationDuringBracketedCaptureEnabled", context: &LensStabilizationContext)
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        let oldValue: AnyObject? = change![NSKeyValueChangeOldKey]
        let newValue: AnyObject? = change![NSKeyValueChangeNewKey]
        
        switch context {
        case &FocusModeContext:
            if let value = newValue where value !== NSNull() {
                let newMode = AVCaptureFocusMode(rawValue: value as! Int)!
                self.focusModeControl.selectedSegmentIndex = self.focusModes.indexOf(newMode) ?? 0
                self.lensPositionSlider.enabled = (newMode == AVCaptureFocusMode.Locked)
                
                if let old = oldValue where old !== NSNull() {
                    let oldMode = AVCaptureFocusMode(rawValue: old as! Int)!
                    NSLog("focus mode: %@ -> %@", self.stringFromFocusMode(oldMode), self.stringFromFocusMode(newMode))
                } else {
                    NSLog("focus mode: %@", self.stringFromFocusMode(newMode))
                }
            }
        case &LensPositionContext:
            if let value = newValue where value !== NSNull() {
                let newLensPosition = value as! Float
                
                if self.videoDevice!.focusMode != AVCaptureFocusMode.Locked {
                    self.lensPositionSlider.value = newLensPosition
                }
                self.lensPositionValueLabel.text = String(format: "%.1f", Double(newLensPosition))
            }
        case &ExposureModeContext:
            if let value = newValue where value !== NSNull() {
                let newMode = AVCaptureExposureMode(rawValue: value as! Int)!
                
                self.exposureModeControl.selectedSegmentIndex = self.exposureModes.indexOf(newMode) ?? 0
                self.exposureDurationSlider.enabled = (newMode == .Custom)
                self.ISOSlider.enabled = (newMode == .Custom)
                
                if let old = oldValue where oldValue !== NSNull() {
                    let oldMode = AVCaptureExposureMode(rawValue: old as! Int)!
                    /*
                    It’s important to understand the relationship between exposureDuration and the minimum frame rate as represented by activeVideoMaxFrameDuration.
                    In manual mode, if exposureDuration is set to a value that's greater than activeVideoMaxFrameDuration, then activeVideoMaxFrameDuration will
                    increase to match it, thus lowering the minimum frame rate. If exposureMode is then changed to automatic mode, the minimum frame rate will
                    remain lower than its default. If this is not the desired behavior, the min and max frameRates can be reset to their default values for the
                    current activeFormat by setting activeVideoMaxFrameDuration and activeVideoMinFrameDuration to kCMTimeInvalid.
                    */
                    if oldMode != newMode && oldMode == AVCaptureExposureMode.Custom {
                        do {
                            try self.videoDevice!.lockForConfiguration()
                            defer {self.videoDevice!.unlockForConfiguration()}
                            self.videoDevice!.activeVideoMaxFrameDuration = kCMTimeInvalid
                            self.videoDevice!.activeVideoMinFrameDuration = kCMTimeInvalid
                        } catch let error as NSError {
                            NSLog("Could not lock device for configuration: %@", error)
                        } catch _ {}
                    }
                    NSLog("exposure mode: \(stringFromExposureMode(oldMode)) -> \(stringFromExposureMode(newMode))")
                }
            }
        case &ExposureDurationContext:
            // Map from duration to non-linear UI range 0-1
            
            if let value = newValue where value !== NSNull() {
                let newDurationSeconds = CMTimeGetSeconds(value.CMTimeValue!)
                if self.videoDevice!.exposureMode != .Custom {
                    let minDurationSeconds = max(CMTimeGetSeconds(self.videoDevice!.activeFormat.minExposureDuration), kExposureMinimumDuration)
                    let maxDurationSeconds = CMTimeGetSeconds(self.videoDevice!.activeFormat.maxExposureDuration)
                    // Map from duration to non-linear UI range 0-1
                    let p = (newDurationSeconds - minDurationSeconds) / (maxDurationSeconds - minDurationSeconds) // Scale to 0-1
                    self.exposureDurationSlider.value = Float(pow(p, 1 / kExposureDurationPower)) // Apply inverse power
                    
                    if newDurationSeconds < 1 {
                        let digits = Int32(max(0, 2 + floor(log10(newDurationSeconds))))
                        self.exposureDurationValueLabel.text = String(format: "1/%.*f", digits, 1/newDurationSeconds)
                    } else {
                        self.exposureDurationValueLabel.text = String(format: "%.2f", newDurationSeconds)
                    }
                }
            }
        case &ISOContext:
            if let value = newValue where value !== NSNull() {
                let newISO = value as! Float
                
                if self.videoDevice!.exposureMode != .Custom {
                    self.ISOSlider.value = newISO
                }
                self.ISOValueLabel.text = String(Int(newISO))
            }
        case &ExposureTargetOffsetContext:
            if let value = newValue where value !== NSNull() {
                let newExposureTargetOffset = value as! Float
                
                self.exposureTargetOffsetSlider.value = newExposureTargetOffset
                self.exposureTargetOffsetValueLabel.text = String(format: "%.1f", Double(newExposureTargetOffset))
            }
        case &WhiteBalanceModeContext:
            if let value = newValue where value !== NSNull() {
                let newMode = AVCaptureWhiteBalanceMode(rawValue: value as! Int)!
                
                self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.indexOf(newMode) ?? 0
                self.temperatureSlider.enabled = (newMode == .Locked)
                self.tintSlider.enabled = (newMode == .Locked)
                
                if let old = oldValue where old !== NSNull() {
                    let oldMode = AVCaptureWhiteBalanceMode(rawValue: old as! Int)!
                    NSLog("white balance mode: \(stringFromWhiteBalanceMode(oldMode)) -> \(stringFromWhiteBalanceMode(newMode))")
                }
            }
        case &DeviceWhiteBalanceGainsContext:
            if let value = newValue where value !== NSNull() {
                var newGains = AVCaptureWhiteBalanceGains()
                (value as! NSValue).getValue(&newGains)
                let newTemperatureAndTint = self.videoDevice!.temperatureAndTintValuesForDeviceWhiteBalanceGains(newGains)
                
                if self.videoDevice!.whiteBalanceMode != .Locked {
                    self.temperatureSlider.value = newTemperatureAndTint.temperature
                    self.tintSlider.value = newTemperatureAndTint.tint
                }
                self.temperatureValueLabel.text = String(Int(newTemperatureAndTint.temperature))
                self.tintValueLabel.text = String(Int(newTemperatureAndTint.tint))
            }
        case &CapturingStillImageContext:
            var isCapturingStillImage = false
            if let value = newValue where value !== NSNull() {
                isCapturingStillImage = value as! Bool
            }
            
            if isCapturingStillImage {
                dispatch_async(dispatch_get_main_queue()) {
                    self.previewView.layer.opacity = 0.0
                    UIView.animateWithDuration(0.25) {
                        self.previewView.layer.opacity = 1.0
                    }
                }
            }
        case &SessionRunningContext:
            var isRunning = false
            if let value = newValue where value !== NSNull() {
                isRunning = value as! Bool
            }
            
            dispatch_async(dispatch_get_main_queue()) {
                self.cameraButton.enabled = (isRunning && AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1)
                self.recordButton.enabled = isRunning
                self.stillButton.enabled = isRunning
            }
        case &LensStabilizationContext:
            if let value = newValue where value !== NSNull() {
                let newMode = value as! Bool
                self.lensStabilizationControl.selectedSegmentIndex = (newMode ? 1 : 0)
                if let old = oldValue where old !== NSNull() {
                    let oldMode = old as! Bool
                    NSLog("Lens stabilization: %@ -> %@", (oldMode ? "YES" : "NO"), (newMode ? "YES" : "NO"))
                }
            }
        default:
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    func subjectAreaDidChange(notificaiton: NSNotification) {
        let devicePoint = CGPointMake(0.5, 0.5)
        self.focusWithMode(.ContinuousAutoFocus, exposeWithMode: .ContinuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    func sessionRuntimeError(notification: NSNotification) {
        let error = notification.userInfo![AVCaptureSessionErrorKey]! as! NSError
        NSLog("Capture session runtime error: %@", error)
        
        if error.code == AVError.MediaServicesWereReset.rawValue {
            dispatch_async(self.sessionQueue) {
                // If we aren't trying to resume the session running, then try to restart it since it must have been stopped due to an error. See also -[resumeInterruptedSession:].
                if self.sessionRunning {
                    self.session.startRunning()
                    self.sessionRunning = self.session.running
                } else {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.resumeButton.hidden = false
                    }
                }
            }
        } else {
            self.resumeButton.hidden = false
        }
    }
    
    @available(iOS 9.0, *)
    func sessionWasInterrupted(notification: NSNotification) {
        // In some scenarios we want to enable the user to resume the session running.
        // For example, if music playback is initiated via control center while using AVCamManual,
        // then the user can let AVCamManual resume the session running, which will stop music playback.
        // Note that stopping music playback in control center will not automatically resume the session running.
        // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
        
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        let reason = AVCaptureSessionInterruptionReason(rawValue: notification.userInfo![AVCaptureSessionInterruptionReasonKey]! as! Int)!
        NSLog("Capture session was interrupted with reason %ld", reason.rawValue)
        
        if reason == AVCaptureSessionInterruptionReason.AudioDeviceInUseByAnotherClient ||
            reason == AVCaptureSessionInterruptionReason.VideoDeviceInUseByAnotherClient {
                // Simply fade-in a button to enable the user to try to resume the session running.
                self.resumeButton.hidden = false
                self.resumeButton.alpha = 0.0
                UIView.animateWithDuration(0.25) {
                    self.resumeButton.alpha = 1.0
                }
        } else if reason == AVCaptureSessionInterruptionReason.VideoDeviceNotAvailableWithMultipleForegroundApps {
            // Simply fade-in a label to inform the user that the camera is unavailable.
            self.cameraUnavailableLabel.hidden = false
            self.cameraUnavailableLabel.alpha = 0.0
            UIView.animateWithDuration(0.25) {
                self.cameraUnavailableLabel.alpha = 1.0
            }
        }
    }
    
    func sessionInterruptionEnded(notification: NSNotification) {
        NSLog("Capture session interruption ended")
        
        if !self.resumeButton.hidden {
            UIView.animateWithDuration(0.25, animations: {
                self.resumeButton.alpha = 0.0
                }, completion: {finished in
                    self.resumeButton.hidden = true
            })
        }
        if !self.cameraUnavailableLabel.hidden {
            UIView.animateWithDuration(0.25, animations: {
                self.cameraUnavailableLabel.alpha = 0.0
                }, completion: {finished in
                    self.cameraUnavailableLabel.hidden = true
            })
        }
    }
    
    //MARK: Actions
    
    @IBAction func resumeInterruptedSession(_: AnyObject) {
        dispatch_async(self.sessionQueue) {
            // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            self.session.startRunning()
            self.sessionRunning = self.session.running
            if !self.session.running {
                dispatch_async(dispatch_get_main_queue()) {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running" )
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: UIAlertControllerStyle.Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                }
            } else {
                dispatch_async(dispatch_get_main_queue()) {
                    self.resumeButton.hidden = true
                }
            }
        }
    }
    
    @IBAction func toggleMovieRecording(_: AnyObject) {
        // Disable the Camera button until recording finishes, and disable the Record button until recording starts or finishes. See the
        // AVCaptureFileOutputRecordingDelegate methods.
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        
        dispatch_async(self.sessionQueue) {
            if !(self.movieFileOutput?.recording ?? false) {
                if UIDevice.currentDevice().multitaskingSupported {
                    // Setup background task. This is needed because the -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]
                    // callback is not received until AVCamManual returns to the foreground unless you request background execution time.
                    // This also ensures that there will be time to write the file to the photo library when AVCamManual is backgrounded.
                    // To conclude this background execution, -endBackgroundTask is called in
                    // -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] after the recorded file has been saved.
                    self.backgroundRecordingID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler(nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieConnection = self.movieFileOutput!.connectionWithMediaType(AVMediaTypeVideo)
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                movieConnection.videoOrientation = previewLayer.connection.videoOrientation
                
                // Turn OFF flash for video recording.
                AAPLCameraViewController.setFlashMode(.Off, forDevice: self.videoDevice!)
                
                // Start recording to a temporary file.
                let outputFileName = NSProcessInfo.processInfo().globallyUniqueString as NSString
                let outputFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(outputFileName.stringByAppendingPathExtension("mov")!)
                self.movieFileOutput!.startRecordingToOutputFileURL(NSURL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                self.movieFileOutput!.stopRecording()
            }
        }
    }
    
    @IBAction func changeCamera(_: AnyObject) {
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.stillButton.enabled = false
        
        dispatch_async(self.sessionQueue) {
            var preferredPosition = AVCaptureDevicePosition.Unspecified
            
            switch self.videoDevice!.position {
            case .Unspecified,
            .Front:
                preferredPosition = .Back
            case .Back:
                preferredPosition = .Front
            }
            
            let newVideoDevice = AAPLCameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition)
            let newVideoDeviceInput: AVCaptureDeviceInput!
            do {
                newVideoDeviceInput = try AVCaptureDeviceInput(device: newVideoDevice)
            } catch _ {
                newVideoDeviceInput = nil
            }
            
            self.session.beginConfiguration()
            
            // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
            self.session.removeInput(self.videoDeviceInput)
            if self.session.canAddInput(newVideoDeviceInput) {
                NSNotificationCenter.defaultCenter().removeObserver(self,
                    name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDevice)
                
                NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AAPLCameraViewController.subjectAreaDidChange(_:)), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: newVideoDevice)
                
                self.session.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
                self.videoDevice = newVideoDevice
            } else {
                self.session.addInput(self.videoDeviceInput)
            }
            
            let connection = self.movieFileOutput!.connectionWithMediaType(AVMediaTypeVideo)
            if connection.supportsVideoStabilization {
                connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
            }
            
            self.session.commitConfiguration()
            
            dispatch_async(dispatch_get_main_queue()) {
                self.cameraButton.enabled = true
                self.recordButton.enabled = true
                self.stillButton.enabled = true
                
                self.configureManualHUD()
            }
        }
    }
    
    @IBAction func snapStillImage(_: AnyObject) {
        dispatch_async(self.sessionQueue) {
            let stillImageConnection = self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            // Update the orientation on the still image output video connection before capturing.
            stillImageConnection.videoOrientation = previewLayer.connection.videoOrientation
            
            // Flash set to Auto for Still Capture
            if self.videoDevice!.exposureMode == .Custom {
                AAPLCameraViewController.setFlashMode(.Off, forDevice: self.videoDevice!)
            } else {
                AAPLCameraViewController.setFlashMode(.Auto, forDevice: self.videoDevice!)
            }
            
            let lensStabilizationEnabled: Bool
            if #available(iOS 9.0, *) {
                lensStabilizationEnabled = self.stillImageOutput!.lensStabilizationDuringBracketedCaptureEnabled
            } else {
                lensStabilizationEnabled = false
            }
            if !lensStabilizationEnabled {
                // Capture a still image
                self.stillImageOutput?.captureStillImageAsynchronouslyFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo)) {imageDataSampleBuffer, error in
                    
                    if error != nil {
                        NSLog("Error capture still image %@", error!)
                    } else if imageDataSampleBuffer != nil {
                        let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)!
                        
                        PHPhotoLibrary.requestAuthorization {status in
                            if status == PHAuthorizationStatus.Authorized {
                                if #available(iOS 9.0, *) {
                                    PHPhotoLibrary.sharedPhotoLibrary().performChanges({
                                        PHAssetCreationRequest.creationRequestForAsset().addResourceWithType(PHAssetResourceType.Photo, data: imageData, options: nil)
                                        }, completionHandler: {success, error in
                                            if !success {
                                                NSLog("Error occured while saving image to photo library: %@", error!)
                                            }
                                    })
                                } else {
                                    let temporaryFileName = NSProcessInfo().globallyUniqueString as NSString
                                    let temporaryFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(temporaryFileName.stringByAppendingPathExtension("jpg")!)
                                    let temporaryFileURL = NSURL(fileURLWithPath: temporaryFilePath)
                                    
                                    PHPhotoLibrary.sharedPhotoLibrary().performChanges({
                                        do {
                                            try imageData.writeToURL(temporaryFileURL, options: .AtomicWrite)
                                            PHAssetChangeRequest.creationRequestForAssetFromImageAtFileURL(temporaryFileURL)
                                        } catch let error as NSError {
                                            NSLog("Error occured while writing image data to a temporary file: %@", error)
                                        } catch _ {
                                            fatalError()
                                        }
                                        }, completionHandler: {success, error in
                                            if !success {
                                                NSLog("Error occurred while saving image to photo library: %@", error!)
                                            }
                                            
                                            // Delete the temporary file.
                                            do {
                                                try NSFileManager.defaultManager().removeItemAtURL(temporaryFileURL)
                                            } catch _ {}
                                    })
                                }
                            }
                        }
                    }
                }
            } else {
                if #available(iOS 9.0, *) {
                // Capture a bracket
                let bracketSettings: [AVCaptureBracketedStillImageSettings]
                if self.videoDevice!.exposureMode == AVCaptureExposureMode.Custom {
                    bracketSettings = [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettingsWithExposureDuration(AVCaptureExposureDurationCurrent, ISO: AVCaptureISOCurrent)]
                } else {
                    bracketSettings = [AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettingsWithExposureTargetBias(AVCaptureExposureTargetBiasCurrent)];
                }
                
                self.stillImageOutput!.captureStillImageBracketAsynchronouslyFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo),
                    withSettingsArray: bracketSettings
                    
                    ) {imageDataSampleBuffer, stillImageSettings, error in
                        if error != nil {
                            NSLog("Error bracketing capture still image %@", error!)
                        } else if imageDataSampleBuffer != nil {
                            NSLog("Lens Stabilization State: \(CMGetAttachment(imageDataSampleBuffer, kCMSampleBufferAttachmentKey_StillImageLensStabilizationInfo, nil)!)")
                            let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                            
                            PHPhotoLibrary.requestAuthorization {status in
                                if status == PHAuthorizationStatus.Authorized {
                                    PHPhotoLibrary.sharedPhotoLibrary().performChanges({
                                        PHAssetCreationRequest.creationRequestForAsset().addResourceWithType(PHAssetResourceType.Photo, data: imageData, options: nil)
                                    }, completionHandler: {success, error in
                                            if !success {
                                                NSLog("Error occured while saving image to photo library: %@", error!)
                                            }
                                    })
                                }
                            }
                        }
                }
                }
            }
        }
    }
    
    @IBAction func focusAndExposeTap(gestureRecognizer: UIGestureRecognizer) {
        if self.videoDevice!.focusMode != .Locked && self.videoDevice!.exposureMode != .Custom {
            let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
            self.focusWithMode(.ContinuousAutoFocus, exposeWithMode: .ContinuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
        }
    }
    
    @IBAction func changeManualHUD(control: UISegmentedControl) {
        
        self.manualHUDFocusView.hidden = (control.selectedSegmentIndex != 1)
        self.manualHUDExposureView.hidden = (control.selectedSegmentIndex != 2)
        self.manualHUDWhiteBalanceView.hidden = (control.selectedSegmentIndex != 3)
        if #available(iOS 9.0, *) {
            self.manualHUDLensStabilizationView.hidden = (control.selectedSegmentIndex != 4)
        } else {
            self.manualHUDLensStabilizationView.hidden = true
        }
    }
    
    @IBAction func changeFocusMode(control: UISegmentedControl) {
        let mode = self.focusModes[control.selectedSegmentIndex]
        
        do {
            try self.videoDevice!.lockForConfiguration()
            if self.videoDevice!.isFocusModeSupported(mode) {
                self.videoDevice!.focusMode = mode
            } else {
                NSLog("Focus mode %@ is not supported. Focus mode is %@.", self.stringFromFocusMode(mode), self.stringFromFocusMode(self.videoDevice!.focusMode))
                self.focusModeControl.selectedSegmentIndex = self.focusModes.indexOf(self.videoDevice!.focusMode)!
            }
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeExposureMode(control: UISegmentedControl) {
        let mode = self.exposureModes[control.selectedSegmentIndex]
        
        do {
            try self.videoDevice!.lockForConfiguration()
            if self.videoDevice!.isExposureModeSupported(mode) {
                self.videoDevice!.exposureMode = mode
            } else {
                NSLog("Exposure mode %@ is not supported. Exposure mode is %@.", self.stringFromExposureMode(mode), self.stringFromExposureMode(self.videoDevice!.exposureMode))
            }
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeWhiteBalanceMode(control: UISegmentedControl) {
        let mode = self.whiteBalanceModes[control.selectedSegmentIndex]
        
        do {
            try self.videoDevice!.lockForConfiguration()
            if self.videoDevice!.isWhiteBalanceModeSupported(mode) {
                self.videoDevice!.whiteBalanceMode = mode
            } else {
                NSLog("White balance mode %@ is not supported. White balance mode is %@.", self.stringFromWhiteBalanceMode(mode), self.stringFromWhiteBalanceMode(self.videoDevice!.whiteBalanceMode))
            }
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeLensPosition(control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setFocusModeLockedWithLensPosition(control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeExposureDuration(control: UISlider) {
        
        let p = pow(Double(control.value), kExposureDurationPower) // Apply power function to expand slider's low-end range
        let minDurationSeconds = max(CMTimeGetSeconds(self.videoDevice!.activeFormat.minExposureDuration), kExposureMinimumDuration)
        let maxDurationSeconds = CMTimeGetSeconds(self.videoDevice!.activeFormat.maxExposureDuration)
        let newDurationSeconds = p * ( maxDurationSeconds - minDurationSeconds ) + minDurationSeconds; // Scale from 0-1 slider range to actual duration
        
        if self.videoDevice!.exposureMode == .Custom {
            if newDurationSeconds < 1 {
                let digits = Int32(max(0, 2 + floor(log10(newDurationSeconds))))
                self.exposureDurationValueLabel.text = String(format: "1/%.*f", digits, 1/newDurationSeconds)
            } else {
                self.exposureDurationValueLabel.text = String(format: "%.2f", newDurationSeconds)
            }
        }
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureModeCustomWithDuration(CMTimeMakeWithSeconds(newDurationSeconds, 1000*1000*1000), ISO: AVCaptureISOCurrent, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeISO(control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureModeCustomWithDuration(AVCaptureExposureDurationCurrent, ISO: control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeExposureTargetBias(control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureTargetBias(control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
            self.exposureTargetBiasValueLabel.text = String(format:"%.1f", Double(control.value))
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeTemperature(_: AnyObject) {
        let temperatureAndTint = AVCaptureWhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGainsForTemperatureAndTintValues(temperatureAndTint))
    }
    
    @IBAction func changeTint(_: AnyObject) {
        let temperatureAndTint = AVCaptureWhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGainsForTemperatureAndTintValues(temperatureAndTint))
    }
    
    @IBAction func lockWithGrayWorld(_: AnyObject) {
        self.setWhiteBalanceGains(self.videoDevice!.grayWorldDeviceWhiteBalanceGains)
    }
    
    @available(iOS 9.0, *)
    @IBAction func changeLensStabilization(control: UISegmentedControl) {
        let lensStabilizationDuringBracketedCaptureEnabled = (control.selectedSegmentIndex != 0)
        if lensStabilizationDuringBracketedCaptureEnabled {
            self.stillButton.enabled = false
        }
        dispatch_async(self.sessionQueue) {
            if self.stillImageOutput!.lensStabilizationDuringBracketedCaptureSupported {
                if lensStabilizationDuringBracketedCaptureEnabled {
                    // Still image capture will be done with the bracketed capture API.
                    self.stillImageOutput!.lensStabilizationDuringBracketedCaptureEnabled = true
                    let bracketSettings: [AVCaptureBracketedStillImageSettings]
                    if self.videoDevice!.exposureMode == AVCaptureExposureMode.Custom {
                        bracketSettings = [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettingsWithExposureDuration(AVCaptureExposureDurationCurrent, ISO: AVCaptureISOCurrent)]
                    } else {
                        bracketSettings = [AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettingsWithExposureTargetBias(AVCaptureExposureTargetBiasCurrent)]
                    }
                    self.stillImageOutput!.prepareToCaptureStillImageBracketFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo),
                        withSettingsArray: bracketSettings
                        ) {prepared, error in
                            if error != nil {
                                NSLog("Error preparing for bracketed capture %@", error!)
                            }
                            dispatch_async(dispatch_get_main_queue()) {
                                self.stillButton.enabled = true
                            }
                    }
                } else {
                    self.stillImageOutput!.lensStabilizationDuringBracketedCaptureEnabled = false
                }
            }
        }
    }
    
    @IBAction func sliderTouchBegan(slider: UISlider) {
        self.setSlider(slider, highlightColor: UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0))
    }
    
    @IBAction func sliderTouchEnded(slider: UISlider) {
        self.setSlider(slider, highlightColor: UIColor.yellowColor())
    }
    
    //MARK: UI
    
    private func configureManualHUD() {
        // Manual focus controls
        self.focusModes = [.ContinuousAutoFocus, .Locked]
        
        self.focusModeControl.enabled = (self.videoDevice != nil)
        if self.videoDevice != nil {
            self.focusModeControl.selectedSegmentIndex = self.focusModes.indexOf(self.videoDevice!.focusMode)!
            for mode in self.focusModes {
                self.focusModeControl.setEnabled(self.videoDevice!.isFocusModeSupported(mode), forSegmentAtIndex: self.focusModes.indexOf(mode)!)
            }
        }
        
        self.lensPositionSlider.minimumValue = 0.0
        self.lensPositionSlider.maximumValue = 1.0
        self.lensPositionSlider.enabled = (self.videoDevice != nil && self.videoDevice!.isFocusModeSupported(.Locked) && self.videoDevice!.focusMode == .Locked)
        
        // Manual exposure controls
        self.exposureModes = [.ContinuousAutoExposure, .Locked, .Custom]
        
        self.exposureModeControl.enabled = (self.videoDevice != nil)
        if self.videoDevice != nil {
            self.exposureModeControl.selectedSegmentIndex = self.exposureModes.indexOf(self.videoDevice!.exposureMode)!
            for mode in self.exposureModes {
                self.exposureModeControl.setEnabled(self.videoDevice!.isExposureModeSupported(mode), forSegmentAtIndex: self.exposureModes.indexOf(mode)!)
            }
        }
        
        // Use 0-1 as the slider range and do a non-linear mapping from the slider value to the actual device exposure duration
        self.exposureDurationSlider.minimumValue = 0
        self.exposureDurationSlider.maximumValue = 1
        self.exposureDurationSlider.enabled = (self.videoDevice != nil && self.videoDevice!.exposureMode == .Custom)

        if self.videoDevice != nil {
            self.ISOSlider.minimumValue = self.videoDevice!.activeFormat.minISO
            self.ISOSlider.maximumValue = self.videoDevice!.activeFormat.maxISO
        }
        self.ISOSlider.enabled = (self.videoDevice?.exposureMode == AVCaptureExposureMode.Custom)

        if self.videoDevice != nil {
            self.exposureTargetBiasSlider.minimumValue = self.videoDevice!.minExposureTargetBias
            self.exposureTargetBiasSlider.maximumValue = self.videoDevice!.maxExposureTargetBias
        }
        self.exposureTargetBiasSlider.enabled = (self.videoDevice != nil)
        
        if self.videoDevice != nil {
            self.exposureTargetOffsetSlider.minimumValue = self.videoDevice!.minExposureTargetBias
            self.exposureTargetOffsetSlider.maximumValue = self.videoDevice!.maxExposureTargetBias
        }
        self.exposureTargetOffsetSlider.enabled = false
        
        // Manual white balance controls
        self.whiteBalanceModes = [.ContinuousAutoWhiteBalance, .Locked]
        
        self.whiteBalanceModeControl.enabled = (self.videoDevice != nil)
        if self.videoDevice != nil {
            self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.indexOf(self.videoDevice!.whiteBalanceMode)!
            for mode in self.whiteBalanceModes {
                self.whiteBalanceModeControl.setEnabled(self.videoDevice!.isWhiteBalanceModeSupported(mode), forSegmentAtIndex: self.whiteBalanceModes.indexOf(mode)!)
            }
        }
        
        self.temperatureSlider.minimumValue = 3000
        self.temperatureSlider.maximumValue = 8000
        self.temperatureSlider.enabled = (self.videoDevice != nil && self.videoDevice!.whiteBalanceMode == .Locked)
        
        self.tintSlider.minimumValue = -150
        self.tintSlider.maximumValue = 150
        self.tintSlider.enabled = (self.videoDevice?.whiteBalanceMode == .Locked)
        
        if #available(iOS 9.0, *) {
            self.lensStabilizationControl.enabled = (self.videoDevice != nil)
            self.lensStabilizationControl.selectedSegmentIndex = (self.stillImageOutput!.lensStabilizationDuringBracketedCaptureEnabled ? 1 : 0)
            self.lensStabilizationControl.setEnabled(self.stillImageOutput!.lensStabilizationDuringBracketedCaptureSupported, forSegmentAtIndex:1)
        } else {
            self.manualSegments.setEnabled(false, forSegmentAtIndex: 4)
            self.lensStabilizationControl.hidden = true
        }
    }
    
    private func setSlider(slider: UISlider, highlightColor color: UIColor) {
        slider.tintColor = color
        
        if slider === self.lensPositionSlider {
            self.lensPositionNameLabel.textColor = slider.tintColor
            self.lensPositionValueLabel.textColor = slider.tintColor
        } else if slider === self.exposureDurationSlider {
            self.exposureDurationNameLabel.textColor = slider.tintColor
            self.exposureDurationValueLabel.textColor = slider.tintColor
        } else if slider === self.ISOSlider {
            self.ISONameLabel.textColor = slider.tintColor
            self.ISOValueLabel.textColor = slider.tintColor
        } else if slider === self.exposureTargetBiasSlider {
            self.exposureTargetBiasNameLabel.textColor = slider.tintColor
            self.exposureTargetBiasValueLabel.textColor = slider.tintColor
        } else if slider === self.temperatureSlider {
            self.temperatureNameLabel.textColor = slider.tintColor
            self.temperatureValueLabel.textColor = slider.tintColor
        } else if slider === self.tintSlider {
            self.tintNameLabel.textColor = slider.tintColor
            self.tintValueLabel.textColor = slider.tintColor
        }
    }
    
    //MARK: File Output Recording Delegate

    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) {
        // Enable the Record button to let the user stop the recording.
        dispatch_async( dispatch_get_main_queue()) {
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), forState: .Normal)
        }
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
        // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
        // is back to NO — which happens sometime after this method returns.
        // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
        let currentBackgroundRecordingID = self.backgroundRecordingID
        self.backgroundRecordingID = UIBackgroundTaskInvalid
        
        let cleanup: dispatch_block_t = {
            do {
                try NSFileManager.defaultManager().removeItemAtURL(outputFileURL)
            } catch _ {}
            if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                UIApplication.sharedApplication().endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        
        var success = true
        
        if error != nil {
            NSLog("Movie file finishing error: %@", error!)
            success = error!.userInfo[AVErrorRecordingSuccessfullyFinishedKey]?.boolValue ?? false
        }
        if success {
            // Check authorization status.
            PHPhotoLibrary.requestAuthorization {status in
                guard status == PHAuthorizationStatus.Authorized else {
                    cleanup()
                    return
                }
                // Save the movie file to the photo library and cleanup.
                PHPhotoLibrary.sharedPhotoLibrary().performChanges({
                    // In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
                    // This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
                    if #available(iOS 9.0, *) {
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let changeRequest = PHAssetCreationRequest.creationRequestForAsset()
                        changeRequest.addResourceWithType(PHAssetResourceType.Video, fileURL: outputFileURL, options: options)
                    } else {
                        PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(outputFileURL)
                    }
                    }, completionHandler: {success, error in
                        if !success {
                            NSLog("Could not save movie to photo library: %@", error!)
                        }
                        cleanup()
                })
            }
        } else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        dispatch_async( dispatch_get_main_queue()) {
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraButton.enabled = (AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1)
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), forState: .Normal)
        }
    }
    
    //MARK: Device Configuration
    
    private func focusWithMode(focusMode: AVCaptureFocusMode, exposeWithMode exposureMode: AVCaptureExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        dispatch_async(self.sessionQueue) {
            let device = self.videoDevice!
            do {
                try device.lockForConfiguration()
                // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = point
                    device.focusMode = focusMode
                }
                if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch let error as NSError {
                NSLog("Could not lock device for configuration: %@", error)
            } catch _ {}
        }
    }
    
    class func setFlashMode(flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } catch let error as NSError {
                NSLog("Could not lock device for configuration: %@", error)
            }
        }
    }
    
    private func setWhiteBalanceGains(gains: AVCaptureWhiteBalanceGains) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            let normalizedGains = self.normalizedGains(gains) // Conversion can yield out-of-bound values, cap to limits
            self.videoDevice!.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(normalizedGains, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    //MARK: Utilities
    
    private class func deviceWithMediaType(mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType) as! [AVCaptureDevice]
        var captureDevice = devices.first
        
        for device in devices {
            if device.position == position {
                captureDevice = device
                break
            }
        }
        
        return captureDevice
    }
    
    private func stringFromFocusMode(focusMode: AVCaptureFocusMode) -> String {
        var string: String
        
        switch focusMode {
        case .Locked:
            string = "Locked"
        case .AutoFocus:
            string = "Auto"
        case .ContinuousAutoFocus:
            string = "ContinuousAuto"
        }
        
        return string
    }
    
    private func stringFromExposureMode(exposureMode: AVCaptureExposureMode) -> String {
        var string: String
        
        switch exposureMode {
        case .Locked:
            string = "Locked"
        case .AutoExpose:
            string = "Auto"
        case .ContinuousAutoExposure:
            string = "ContinuousAuto"
        case .Custom:
            string = "Custom"
        }
        
        return string
    }
    
    private func stringFromWhiteBalanceMode(whiteBalanceMode: AVCaptureWhiteBalanceMode) -> String {
        var string: String
        
        switch whiteBalanceMode {
        case .Locked:
            string = "Locked"
        case .AutoWhiteBalance:
            string = "Auto"
        case .ContinuousAutoWhiteBalance:
            string = "ContinuousAuto"
        }
        
        return string
    }
    
    private func normalizedGains(gains: AVCaptureWhiteBalanceGains) -> AVCaptureWhiteBalanceGains {
        var g = gains
        
        g.redGain = max(1.0, g.redGain)
        g.greenGain = max(1.0, g.greenGain)
        g.blueGain = max(1.0, g.blueGain)
        
        g.redGain = min(self.videoDevice!.maxWhiteBalanceGain, g.redGain)
        g.greenGain = min(self.videoDevice!.maxWhiteBalanceGain, g.greenGain)
        g.blueGain = min(self.videoDevice!.maxWhiteBalanceGain, g.blueGain)
        
        return g
    }
    
}