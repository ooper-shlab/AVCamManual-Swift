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
    case success
    case cameraNotAuthorized
    case sessionConfigurationFailed
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
    
    fileprivate var focusModes: [AVCaptureFocusMode] = []
    @IBOutlet weak var manualHUDFocusView: UIView!
    @IBOutlet weak var focusModeControl: UISegmentedControl!
    @IBOutlet weak var lensPositionSlider: UISlider!
    @IBOutlet weak var lensPositionNameLabel: UILabel!
    @IBOutlet weak var lensPositionValueLabel: UILabel!
    
    fileprivate var exposureModes: [AVCaptureExposureMode] = []
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
    
    fileprivate var whiteBalanceModes: [AVCaptureWhiteBalanceMode] = []
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
    fileprivate var sessionQueue: DispatchQueue!
    dynamic var session: AVCaptureSession!
    dynamic var videoDeviceInput: AVCaptureDeviceInput?
    dynamic var videoDevice: AVCaptureDevice?
    dynamic var movieFileOutput: AVCaptureMovieFileOutput?
    dynamic var stillImageOutput: AVCaptureStillImageOutput?
    
    // Utilities.
    fileprivate var setupResult: AVCamManualSetupResult = .success
    fileprivate var sessionRunning: Bool = false
    fileprivate var backgroundRecordingID: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    fileprivate let kExposureDurationPower = 5.0 // Higher numbers will give the slider more sensitivity at shorter durations
    fileprivate let kExposureMinimumDuration = 1.0/1000 // Limit exposure duration to a useful range
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        self.cameraButton.isEnabled = false
        self.recordButton.isEnabled = false
        self.stillButton.isEnabled = false
        
        self.manualHUDFocusView.isHidden = true
        self.manualHUDExposureView.isHidden = true
        self.manualHUDWhiteBalanceView.isHidden = true
        self.manualHUDLensStabilizationView.isHidden = true
        
        // Create the AVCaptureSession.
        self.session = AVCaptureSession()
        
        // Setup the preview view.
        self.previewView.session = self.session
        
        // Communicate with the session and other session objects on this queue.
        self.sessionQueue = DispatchQueue(label: "session queue", attributes: [])
        
        self.setupResult = AVCamManualSetupResult.success
        
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case AVAuthorizationStatus.authorized:
            // The user has previously granted access to the camera.
            break
        case AVAuthorizationStatus.notDetermined:
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            self.sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) {granted in
                if !granted {
                    self.setupResult = AVCamManualSetupResult.cameraNotAuthorized
                }
                self.sessionQueue.resume()
            }
        default:
            // The user has previously denied access.
            self.setupResult = AVCamManualSetupResult.cameraNotAuthorized
        }
        
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        self.sessionQueue.async {
            guard self.setupResult == AVCamManualSetupResult.success else {
                return
            }
            
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            
            let videoDevice = AAPLCameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.back)
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
                
                DispatchQueue.main.async {
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for AAPLPreviewView and UIView
                    // can only be manipulated on the main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                    // on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                    
                    // Use the status bar orientation as the initial video orientation. Subsequent orientation changes are handled by
                    // -[viewWillTransitionToSize:withTransitionCoordinator:].
                    let statusBarOrientation = UIApplication.shared.statusBarOrientation
                    var initialVideoOrientation = AVCaptureVideoOrientation.portrait
                    if statusBarOrientation != UIInterfaceOrientation.unknown {
                        initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                    }
                    
                    let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                    previewLayer.connection.videoOrientation = initialVideoOrientation
                }
            } else {
                NSLog("Could not add video device input to the session")
                self.setupResult = AVCamManualSetupResult.sessionConfigurationFailed
            }
            
            let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
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
                if let connection = movieFileOutput.connection(withMediaType: AVMediaTypeVideo), connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                NSLog("Could not add movie file output to the session")
                self.setupResult = AVCamManualSetupResult.sessionConfigurationFailed
            }
            
            let stillImageOutput = AVCaptureStillImageOutput()
            if self.session.canAddOutput(stillImageOutput) {
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
                self.stillImageOutput!.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                self.stillImageOutput!.isHighResolutionStillImageOutputEnabled = true
            } else {
                NSLog("Could not add still image output to the session")
                self.setupResult = AVCamManualSetupResult.sessionConfigurationFailed
            }
            
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.configureManualHUD()
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.sessionQueue.async {
            switch self.setupResult {
            case AVCamManualSetupResult.success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.sessionRunning = self.session.isRunning
            case AVCamManualSetupResult.cameraNotAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("AVCamManual doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera" )
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: UIAlertControllerStyle.alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    // Provide quick access to Settings.
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: UIAlertActionStyle.default) {action in
                        UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                    }
                    alertController.addAction(settingsAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            case AVCamManualSetupResult.sessionConfigurationFailed:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: UIAlertControllerStyle.alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.sessionQueue.async {
            if self.setupResult == AVCamManualSetupResult.success {
                self.session.stopRunning()
                self.removeObservers()
            }
        }
        
        super.viewDidDisappear(animated)
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    //MARK: Orientation
    
    override var shouldAutorotate : Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !(self.movieFileOutput?.isRecording ?? false);
    }
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        // Note that the app delegate controls the device orientation notifications required to use the device orientation.
        let deviceOrientation = UIDevice.current.orientation
        if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            previewLayer.connection.videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
        }
    }
    
    //MARK: KVO and Notifications
    
    fileprivate func addObservers() {
        self.addObserver(self, forKeyPath: "session.running", options: .new, context: &SessionRunningContext)
        self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options: .new, context: &CapturingStillImageContext)
        
        self.addObserver(self, forKeyPath: "videoDevice.focusMode", options: [.old, .new], context: &FocusModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.lensPosition", options: .new, context: &LensPositionContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureMode", options: [.old, .new], context: &ExposureModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureDuration", options: .new, context: &ExposureDurationContext)
        self.addObserver(self, forKeyPath: "videoDevice.ISO", options: .new, context: &ISOContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureTargetOffset", options: .new, context: &ExposureTargetOffsetContext)
        self.addObserver(self, forKeyPath: "videoDevice.whiteBalanceMode", options: [.old, .new], context: &WhiteBalanceModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.deviceWhiteBalanceGains", options: .new, context: &DeviceWhiteBalanceGainsContext)
        
        self.addObserver(self, forKeyPath: "stillImageOutput.lensStabilizationDuringBracketedCaptureEnabled", options: [.old, .new], context: &LensStabilizationContext)
        
        NotificationCenter.default.addObserver(self, selector: #selector(AAPLCameraViewController.subjectAreaDidChange(_:)), name:NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: self.videoDevice!)
        NotificationCenter.default.addObserver(self, selector: #selector(AAPLCameraViewController.sessionRuntimeError(_:)), name:NSNotification.Name.AVCaptureSessionRuntimeError, object: self.session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        if #available(iOS 9.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(AAPLCameraViewController.sessionWasInterrupted(_:)), name:NSNotification.Name.AVCaptureSessionWasInterrupted, object: self.session)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(AAPLCameraViewController.sessionInterruptionEnded(_:)), name:NSNotification.Name.AVCaptureSessionInterruptionEnded, object: self.session)
    }
    
    fileprivate func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
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
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let oldValue: AnyObject? = change![NSKeyValueChangeKey.oldKey] as AnyObject?
        let newValue: AnyObject? = change![NSKeyValueChangeKey.newKey] as AnyObject?
        
        switch context {
        case (.some(&FocusModeContext)):
            if let value = newValue, value !== NSNull() {
                let newMode = AVCaptureFocusMode(rawValue: value as! Int)!
                self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: newMode) ?? 0
                self.lensPositionSlider.isEnabled = (newMode == AVCaptureFocusMode.locked)
                
                if let old = oldValue, old !== NSNull() {
                    let oldMode = AVCaptureFocusMode(rawValue: old as! Int)!
                    NSLog("focus mode: %@ -> %@", self.stringFromFocusMode(oldMode), self.stringFromFocusMode(newMode))
                } else {
                    NSLog("focus mode: %@", self.stringFromFocusMode(newMode))
                }
            }
        case (.some(&LensPositionContext)):
            if let value = newValue, value !== NSNull() {
                let newLensPosition = value as! Float
                
                if self.videoDevice!.focusMode != AVCaptureFocusMode.locked {
                    self.lensPositionSlider.value = newLensPosition
                }
                self.lensPositionValueLabel.text = String(format: "%.1f", Double(newLensPosition))
            }
        case (.some(&ExposureModeContext)):
            if let value = newValue, value !== NSNull() {
                let newMode = AVCaptureExposureMode(rawValue: value as! Int)!
                
                self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: newMode) ?? 0
                self.exposureDurationSlider.isEnabled = (newMode == .custom)
                self.ISOSlider.isEnabled = (newMode == .custom)
                
                if let old = oldValue, oldValue !== NSNull() {
                    let oldMode = AVCaptureExposureMode(rawValue: old as! Int)!
                    /*
                     It’s important to understand the relationship between exposureDuration and the minimum frame rate as represented by activeVideoMaxFrameDuration.
                     In manual mode, if exposureDuration is set to a value that's greater than activeVideoMaxFrameDuration, then activeVideoMaxFrameDuration will
                     increase to match it, thus lowering the minimum frame rate. If exposureMode is then changed to automatic mode, the minimum frame rate will
                     remain lower than its default. If this is not the desired behavior, the min and max frameRates can be reset to their default values for the
                     current activeFormat by setting activeVideoMaxFrameDuration and activeVideoMinFrameDuration to kCMTimeInvalid.
                     */
                    if oldMode != newMode && oldMode == AVCaptureExposureMode.custom {
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
        case (.some(&ExposureDurationContext)):
            // Map from duration to non-linear UI range 0-1
            
            if let value = newValue, value !== NSNull() {
                let newDurationSeconds = CMTimeGetSeconds(value.timeValue!)
                if self.videoDevice!.exposureMode != .custom {
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
        case (.some(&ISOContext)):
            if let value = newValue, value !== NSNull() {
                let newISO = value as! Float
                
                if self.videoDevice!.exposureMode != .custom {
                    self.ISOSlider.value = newISO
                }
                self.ISOValueLabel.text = String(Int(newISO))
            }
        case (.some(&ExposureTargetOffsetContext)):
            if let value = newValue, value !== NSNull() {
                let newExposureTargetOffset = value as! Float
                
                self.exposureTargetOffsetSlider.value = newExposureTargetOffset
                self.exposureTargetOffsetValueLabel.text = String(format: "%.1f", Double(newExposureTargetOffset))
            }
        case (.some(&WhiteBalanceModeContext)):
            if let value = newValue, value !== NSNull() {
                let newMode = AVCaptureWhiteBalanceMode(rawValue: value as! Int)!
                
                self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: newMode) ?? 0
                self.temperatureSlider.isEnabled = (newMode == .locked)
                self.tintSlider.isEnabled = (newMode == .locked)
                
                if let old = oldValue, old !== NSNull() {
                    let oldMode = AVCaptureWhiteBalanceMode(rawValue: old as! Int)!
                    NSLog("white balance mode: \(stringFromWhiteBalanceMode(oldMode)) -> \(stringFromWhiteBalanceMode(newMode))")
                }
            }
        case (.some(&DeviceWhiteBalanceGainsContext)):
            if let value = newValue, value !== NSNull() {
                var newGains = AVCaptureWhiteBalanceGains()
                (value as! NSValue).getValue(&newGains)
                let newTemperatureAndTint = self.videoDevice!.temperatureAndTintValues(forDeviceWhiteBalanceGains: newGains)
                
                if self.videoDevice!.whiteBalanceMode != .locked {
                    self.temperatureSlider.value = newTemperatureAndTint.temperature
                    self.tintSlider.value = newTemperatureAndTint.tint
                }
                self.temperatureValueLabel.text = String(Int(newTemperatureAndTint.temperature))
                self.tintValueLabel.text = String(Int(newTemperatureAndTint.tint))
            }
        case (.some(&CapturingStillImageContext)):
            var isCapturingStillImage = false
            if let value = newValue, value !== NSNull() {
                isCapturingStillImage = value as! Bool
            }
            
            if isCapturingStillImage {
                DispatchQueue.main.async {
                    self.previewView.layer.opacity = 0.0
                    UIView.animate(withDuration: 0.25, animations: {
                        self.previewView.layer.opacity = 1.0
                    })
                }
            }
        case (.some(&SessionRunningContext)):
            var isRunning = false
            if let value = newValue, value !== NSNull() {
                isRunning = value as! Bool
            }
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = (isRunning && AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo).count > 1)
                self.recordButton.isEnabled = isRunning
                self.stillButton.isEnabled = isRunning
            }
        case (.some(&LensStabilizationContext)):
            if let value = newValue, value !== NSNull() {
                let newMode = value as! Bool
                self.lensStabilizationControl.selectedSegmentIndex = (newMode ? 1 : 0)
                if let old = oldValue, old !== NSNull() {
                    let oldMode = old as! Bool
                    NSLog("Lens stabilization: %@ -> %@", (oldMode ? "YES" : "NO"), (newMode ? "YES" : "NO"))
                }
            }
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    func subjectAreaDidChange(_ notificaiton: Notification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(.continuousAutoFocus, exposeWithMode: .continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo![AVCaptureSessionErrorKey]! as! NSError
        NSLog("Capture session runtime error: %@", error)
        
        if error.code == AVError.Code.mediaServicesWereReset.rawValue {
            self.sessionQueue.async {
                // If we aren't trying to resume the session running, then try to restart it since it must have been stopped due to an error. See also -[resumeInterruptedSession:].
                if self.sessionRunning {
                    self.session.startRunning()
                    self.sessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            self.resumeButton.isHidden = false
        }
    }
    
    @available(iOS 9.0, *)
    func sessionWasInterrupted(_ notification: Notification) {
        // In some scenarios we want to enable the user to resume the session running.
        // For example, if music playback is initiated via control center while using AVCamManual,
        // then the user can let AVCamManual resume the session running, which will stop music playback.
        // Note that stopping music playback in control center will not automatically resume the session running.
        // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
        
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        let reason = AVCaptureSessionInterruptionReason(rawValue: notification.userInfo![AVCaptureSessionInterruptionReasonKey]! as! Int)!
        NSLog("Capture session was interrupted with reason %ld", reason.rawValue)
        
        if reason == AVCaptureSessionInterruptionReason.audioDeviceInUseByAnotherClient ||
            reason == AVCaptureSessionInterruptionReason.videoDeviceInUseByAnotherClient {
            // Simply fade-in a button to enable the user to try to resume the session running.
            self.resumeButton.isHidden = false
            self.resumeButton.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.resumeButton.alpha = 1.0
            })
        } else if reason == AVCaptureSessionInterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps {
            // Simply fade-in a label to inform the user that the camera is unavailable.
            self.cameraUnavailableLabel.isHidden = false
            self.cameraUnavailableLabel.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.cameraUnavailableLabel.alpha = 1.0
            })
        }
    }
    
    func sessionInterruptionEnded(_ notification: Notification) {
        NSLog("Capture session interruption ended")
        
        if !self.resumeButton.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                self.resumeButton.alpha = 0.0
            }, completion: {finished in
                self.resumeButton.isHidden = true
            })
        }
        if !self.cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                self.cameraUnavailableLabel.alpha = 0.0
            }, completion: {finished in
                self.cameraUnavailableLabel.isHidden = true
            })
        }
    }
    
    //MARK: Actions
    
    @IBAction func resumeInterruptedSession(_: AnyObject) {
        self.sessionQueue.async {
            // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            self.session.startRunning()
            self.sessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running" )
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: UIAlertControllerStyle.alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    @IBAction func toggleMovieRecording(_: AnyObject) {
        // Disable the Camera button until recording finishes, and disable the Record button until recording starts or finishes. See the
        // AVCaptureFileOutputRecordingDelegate methods.
        self.cameraButton.isEnabled = false
        self.recordButton.isEnabled = false
        
        self.sessionQueue.async {
            if !(self.movieFileOutput?.isRecording ?? false) {
                if UIDevice.current.isMultitaskingSupported {
                    // Setup background task. This is needed because the -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]
                    // callback is not received until AVCamManual returns to the foreground unless you request background execution time.
                    // This also ensures that there will be time to write the file to the photo library when AVCamManual is backgrounded.
                    // To conclude this background execution, -endBackgroundTask is called in
                    // -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] after the recorded file has been saved.
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieConnection = self.movieFileOutput!.connection(withMediaType: AVMediaTypeVideo)
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                movieConnection?.videoOrientation = previewLayer.connection.videoOrientation
                
                // Turn OFF flash for video recording.
                AAPLCameraViewController.setFlashMode(.off, forDevice: self.videoDevice!)
                
                // Start recording to a temporary file.
                let outputFileName = ProcessInfo.processInfo.globallyUniqueString as NSString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(outputFileName.appendingPathExtension("mov")!)
                self.movieFileOutput!.startRecording(toOutputFileURL: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                self.movieFileOutput!.stopRecording()
            }
        }
    }
    
    @IBAction func changeCamera(_: AnyObject) {
        self.cameraButton.isEnabled = false
        self.recordButton.isEnabled = false
        self.stillButton.isEnabled = false
        
        self.sessionQueue.async {
            var preferredPosition = AVCaptureDevicePosition.unspecified
            
            switch self.videoDevice!.position {
            case .unspecified,
                 .front:
                preferredPosition = .back
            case .back:
                preferredPosition = .front
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
                NotificationCenter.default.removeObserver(self,
                                                          name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: self.videoDevice)
                
                NotificationCenter.default.addObserver(self, selector: #selector(AAPLCameraViewController.subjectAreaDidChange(_:)), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: newVideoDevice)
                
                self.session.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
                self.videoDevice = newVideoDevice
            } else {
                self.session.addInput(self.videoDeviceInput)
            }
            
            let connection = self.movieFileOutput!.connection(withMediaType: AVMediaTypeVideo)
            if (connection?.isVideoStabilizationSupported)! {
                connection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
            }
            
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = true
                self.stillButton.isEnabled = true
                
                self.configureManualHUD()
            }
        }
    }
    
    @IBAction func snapStillImage(_: AnyObject) {
        self.sessionQueue.async {
            let stillImageConnection = self.stillImageOutput!.connection(withMediaType: AVMediaTypeVideo)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            // Update the orientation on the still image output video connection before capturing.
            stillImageConnection?.videoOrientation = previewLayer.connection.videoOrientation
            
            // Flash set to Auto for Still Capture
            if self.videoDevice!.exposureMode == .custom {
                AAPLCameraViewController.setFlashMode(.off, forDevice: self.videoDevice!)
            } else {
                AAPLCameraViewController.setFlashMode(.auto, forDevice: self.videoDevice!)
            }
            
            let lensStabilizationEnabled: Bool
            if #available(iOS 9.0, *) {
                lensStabilizationEnabled = self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled
            } else {
                lensStabilizationEnabled = false
            }
            if !lensStabilizationEnabled {
                // Capture a still image
                self.stillImageOutput?.captureStillImageAsynchronously(from: self.stillImageOutput!.connection(withMediaType: AVMediaTypeVideo)) {imageDataSampleBuffer, error in
                    
                    if error != nil {
                        NSLog("Error capture still image %@", (error! as NSError))
                    } else if imageDataSampleBuffer != nil {
                        let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)!
                        
                        PHPhotoLibrary.requestAuthorization {status in
                            if status == PHAuthorizationStatus.authorized {
                                if #available(iOS 9.0, *) {
                                    PHPhotoLibrary.shared().performChanges({
                                        PHAssetCreationRequest.forAsset().addResource(with: PHAssetResourceType.photo, data: imageData, options: nil)
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occured while saving image to photo library: %@", (error! as NSError))
                                        }
                                    })
                                } else {
                                    let temporaryFileName = ProcessInfo().globallyUniqueString as NSString
                                    let temporaryFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(temporaryFileName.appendingPathExtension("jpg")!)
                                    let temporaryFileURL = URL(fileURLWithPath: temporaryFilePath)
                                    
                                    PHPhotoLibrary.shared().performChanges({
                                        do {
                                            try imageData.write(to: temporaryFileURL, options: .atomicWrite)
                                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: temporaryFileURL)
                                        } catch let error as NSError {
                                            NSLog("Error occured while writing image data to a temporary file: %@", error)
                                        } catch _ {
                                            fatalError()
                                        }
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occurred while saving image to photo library: %@", (error! as NSError))
                                        }
                                        
                                        // Delete the temporary file.
                                        do {
                                            try FileManager.default.removeItem(at: temporaryFileURL)
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
                    if self.videoDevice!.exposureMode == AVCaptureExposureMode.custom {
                        bracketSettings = [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(withExposureDuration: AVCaptureExposureDurationCurrent, iso: AVCaptureISOCurrent)]
                    } else {
                        bracketSettings = [AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(withExposureTargetBias: AVCaptureExposureTargetBiasCurrent)];
                    }
                    
                    self.stillImageOutput!.captureStillImageBracketAsynchronously(from: self.stillImageOutput!.connection(withMediaType: AVMediaTypeVideo),
                                                                                  withSettingsArray: bracketSettings
                        
                    ) {imageDataSampleBuffer, stillImageSettings, error in
                        if error != nil {
                            NSLog("Error bracketing capture still image %@", (error! as NSError))
                        } else if imageDataSampleBuffer != nil {
                            NSLog("Lens Stabilization State: \(CMGetAttachment(imageDataSampleBuffer!, kCMSampleBufferAttachmentKey_StillImageLensStabilizationInfo, nil)!)")
                            let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                            
                            PHPhotoLibrary.requestAuthorization {status in
                                if status == PHAuthorizationStatus.authorized {
                                    PHPhotoLibrary.shared().performChanges({
                                        PHAssetCreationRequest.forAsset().addResource(with: PHAssetResourceType.photo, data: imageData!, options: nil)
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occured while saving image to photo library: %@", (error! as NSError))
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
    
    @IBAction func focusAndExposeTap(_ gestureRecognizer: UIGestureRecognizer) {
        if self.videoDevice!.focusMode != .locked && self.videoDevice!.exposureMode != .custom {
            let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterest(for: gestureRecognizer.location(in: gestureRecognizer.view))
            self.focusWithMode(.continuousAutoFocus, exposeWithMode: .continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
        }
    }
    
    @IBAction func changeManualHUD(_ control: UISegmentedControl) {
        
        self.manualHUDFocusView.isHidden = (control.selectedSegmentIndex != 1)
        self.manualHUDExposureView.isHidden = (control.selectedSegmentIndex != 2)
        self.manualHUDWhiteBalanceView.isHidden = (control.selectedSegmentIndex != 3)
        if #available(iOS 9.0, *) {
            self.manualHUDLensStabilizationView.isHidden = (control.selectedSegmentIndex != 4)
        } else {
            self.manualHUDLensStabilizationView.isHidden = true
        }
    }
    
    @IBAction func changeFocusMode(_ control: UISegmentedControl) {
        let mode = self.focusModes[control.selectedSegmentIndex]
        
        do {
            try self.videoDevice!.lockForConfiguration()
            if self.videoDevice!.isFocusModeSupported(mode) {
                self.videoDevice!.focusMode = mode
            } else {
                NSLog("Focus mode %@ is not supported. Focus mode is %@.", self.stringFromFocusMode(mode), self.stringFromFocusMode(self.videoDevice!.focusMode))
                self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: self.videoDevice!.focusMode)!
            }
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeExposureMode(_ control: UISegmentedControl) {
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
    
    @IBAction func changeWhiteBalanceMode(_ control: UISegmentedControl) {
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
    
    @IBAction func changeLensPosition(_ control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setFocusModeLockedWithLensPosition(control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeExposureDuration(_ control: UISlider) {
        
        let p = pow(Double(control.value), kExposureDurationPower) // Apply power function to expand slider's low-end range
        let minDurationSeconds = max(CMTimeGetSeconds(self.videoDevice!.activeFormat.minExposureDuration), kExposureMinimumDuration)
        let maxDurationSeconds = CMTimeGetSeconds(self.videoDevice!.activeFormat.maxExposureDuration)
        let newDurationSeconds = p * ( maxDurationSeconds - minDurationSeconds ) + minDurationSeconds; // Scale from 0-1 slider range to actual duration
        
        if self.videoDevice!.exposureMode == .custom {
            if newDurationSeconds < 1 {
                let digits = Int32(max(0, 2 + floor(log10(newDurationSeconds))))
                self.exposureDurationValueLabel.text = String(format: "1/%.*f", digits, 1/newDurationSeconds)
            } else {
                self.exposureDurationValueLabel.text = String(format: "%.2f", newDurationSeconds)
            }
        }
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureModeCustomWithDuration(CMTimeMakeWithSeconds(newDurationSeconds, 1000*1000*1000), iso: AVCaptureISOCurrent, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeISO(_ control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureModeCustomWithDuration(AVCaptureExposureDurationCurrent, iso: control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error as NSError {
            NSLog("Could not lock device for configuration: %@", error)
        }
    }
    
    @IBAction func changeExposureTargetBias(_ control: UISlider) {
        
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
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGains(for: temperatureAndTint))
    }
    
    @IBAction func changeTint(_: AnyObject) {
        let temperatureAndTint = AVCaptureWhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGains(for: temperatureAndTint))
    }
    
    @IBAction func lockWithGrayWorld(_: AnyObject) {
        self.setWhiteBalanceGains(self.videoDevice!.grayWorldDeviceWhiteBalanceGains)
    }
    
    @available(iOS 9.0, *)
    @IBAction func changeLensStabilization(_ control: UISegmentedControl) {
        let lensStabilizationDuringBracketedCaptureEnabled = (control.selectedSegmentIndex != 0)
        if lensStabilizationDuringBracketedCaptureEnabled {
            self.stillButton.isEnabled = false
        }
        self.sessionQueue.async {
            if self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureSupported {
                if lensStabilizationDuringBracketedCaptureEnabled {
                    // Still image capture will be done with the bracketed capture API.
                    self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled = true
                    let bracketSettings: [AVCaptureBracketedStillImageSettings]
                    if self.videoDevice!.exposureMode == AVCaptureExposureMode.custom {
                        bracketSettings = [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(withExposureDuration: AVCaptureExposureDurationCurrent, iso: AVCaptureISOCurrent)]
                    } else {
                        bracketSettings = [AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(withExposureTargetBias: AVCaptureExposureTargetBiasCurrent)]
                    }
                    self.stillImageOutput!.prepareToCaptureStillImageBracket(from: self.stillImageOutput!.connection(withMediaType: AVMediaTypeVideo),
                                                                             withSettingsArray: bracketSettings
                    ) {prepared, error in
                        if error != nil {
                            NSLog("Error preparing for bracketed capture %@", (error! as NSError))
                        }
                        DispatchQueue.main.async {
                            self.stillButton.isEnabled = true
                        }
                    }
                } else {
                    self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled = false
                }
            }
        }
    }
    
    @IBAction func sliderTouchBegan(_ slider: UISlider) {
        self.setSlider(slider, highlightColor: UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0))
    }
    
    @IBAction func sliderTouchEnded(_ slider: UISlider) {
        self.setSlider(slider, highlightColor: UIColor.yellow)
    }
    
    //MARK: UI
    
    fileprivate func configureManualHUD() {
        // Manual focus controls
        self.focusModes = [.continuousAutoFocus, .locked]
        
        self.focusModeControl.isEnabled = (self.videoDevice != nil)
        if self.videoDevice != nil {
            self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: self.videoDevice!.focusMode)!
            for mode in self.focusModes {
                self.focusModeControl.setEnabled(self.videoDevice!.isFocusModeSupported(mode), forSegmentAt: self.focusModes.index(of: mode)!)
            }
        }
        
        self.lensPositionSlider.minimumValue = 0.0
        self.lensPositionSlider.maximumValue = 1.0
        self.lensPositionSlider.isEnabled = (self.videoDevice != nil && self.videoDevice!.isFocusModeSupported(.locked) && self.videoDevice!.focusMode == .locked)
        
        // Manual exposure controls
        self.exposureModes = [.continuousAutoExposure, .locked, .custom]
        
        self.exposureModeControl.isEnabled = (self.videoDevice != nil)
        if self.videoDevice != nil {
            self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: self.videoDevice!.exposureMode)!
            for mode in self.exposureModes {
                self.exposureModeControl.setEnabled(self.videoDevice!.isExposureModeSupported(mode), forSegmentAt: self.exposureModes.index(of: mode)!)
            }
        }
        
        // Use 0-1 as the slider range and do a non-linear mapping from the slider value to the actual device exposure duration
        self.exposureDurationSlider.minimumValue = 0
        self.exposureDurationSlider.maximumValue = 1
        self.exposureDurationSlider.isEnabled = (self.videoDevice != nil && self.videoDevice!.exposureMode == .custom)
        
        if self.videoDevice != nil {
            self.ISOSlider.minimumValue = self.videoDevice!.activeFormat.minISO
            self.ISOSlider.maximumValue = self.videoDevice!.activeFormat.maxISO
        }
        self.ISOSlider.isEnabled = (self.videoDevice?.exposureMode == AVCaptureExposureMode.custom)
        
        if self.videoDevice != nil {
            self.exposureTargetBiasSlider.minimumValue = self.videoDevice!.minExposureTargetBias
            self.exposureTargetBiasSlider.maximumValue = self.videoDevice!.maxExposureTargetBias
        }
        self.exposureTargetBiasSlider.isEnabled = (self.videoDevice != nil)
        
        if self.videoDevice != nil {
            self.exposureTargetOffsetSlider.minimumValue = self.videoDevice!.minExposureTargetBias
            self.exposureTargetOffsetSlider.maximumValue = self.videoDevice!.maxExposureTargetBias
        }
        self.exposureTargetOffsetSlider.isEnabled = false
        
        // Manual white balance controls
        self.whiteBalanceModes = [.continuousAutoWhiteBalance, .locked]
        
        self.whiteBalanceModeControl.isEnabled = (self.videoDevice != nil)
        if self.videoDevice != nil {
            self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: self.videoDevice!.whiteBalanceMode)!
            for mode in self.whiteBalanceModes {
                self.whiteBalanceModeControl.setEnabled(self.videoDevice!.isWhiteBalanceModeSupported(mode), forSegmentAt: self.whiteBalanceModes.index(of: mode)!)
            }
        }
        
        self.temperatureSlider.minimumValue = 3000
        self.temperatureSlider.maximumValue = 8000
        self.temperatureSlider.isEnabled = (self.videoDevice != nil && self.videoDevice!.whiteBalanceMode == .locked)
        
        self.tintSlider.minimumValue = -150
        self.tintSlider.maximumValue = 150
        self.tintSlider.isEnabled = (self.videoDevice?.whiteBalanceMode == .locked)
        
        if #available(iOS 9.0, *) {
            self.lensStabilizationControl.isEnabled = (self.videoDevice != nil)
            self.lensStabilizationControl.selectedSegmentIndex = (self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled ? 1 : 0)
            self.lensStabilizationControl.setEnabled(self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureSupported, forSegmentAt:1)
        } else {
            self.manualSegments.setEnabled(false, forSegmentAt: 4)
            self.lensStabilizationControl.isHidden = true
        }
    }
    
    fileprivate func setSlider(_ slider: UISlider, highlightColor color: UIColor) {
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
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
        // Enable the Record button to let the user stop the recording.
        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), for: UIControlState())
        }
    }
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
        // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
        // is back to NO — which happens sometime after this method returns.
        // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
        let currentBackgroundRecordingID = self.backgroundRecordingID
        self.backgroundRecordingID = UIBackgroundTaskInvalid
        
        let cleanup: ()->() = {
            do {
                try FileManager.default.removeItem(at: outputFileURL)
            } catch _ {}
            if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        
        var success = true
        
        if error != nil {
            NSLog("Movie file finishing error: %@", (error! as NSError))
            success = ((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue ?? false
        }
        if success {
            // Check authorization status.
            PHPhotoLibrary.requestAuthorization {status in
                guard status == PHAuthorizationStatus.authorized else {
                    cleanup()
                    return
                }
                // Save the movie file to the photo library and cleanup.
                PHPhotoLibrary.shared().performChanges({
                    // In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
                    // This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
                    if #available(iOS 9.0, *) {
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let changeRequest = PHAssetCreationRequest.forAsset()
                        changeRequest.addResource(with: PHAssetResourceType.video, fileURL: outputFileURL, options: options)
                    } else {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                    }
                }, completionHandler: {success, error in
                    if !success {
                        NSLog("Could not save movie to photo library: %@", (error! as NSError))
                    }
                    cleanup()
                })
            }
        } else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async {
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraButton.isEnabled = (AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo).count > 1)
            self.recordButton.isEnabled = true
            self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), for: UIControlState())
        }
    }
    
    //MARK: Device Configuration
    
    fileprivate func focusWithMode(_ focusMode: AVCaptureFocusMode, exposeWithMode exposureMode: AVCaptureExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        self.sessionQueue.async {
            let device = self.videoDevice!
            do {
                try device.lockForConfiguration()
                // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = point
                    device.focusMode = focusMode
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch let error as NSError {
                NSLog("Could not lock device for configuration: %@", error)
            } catch _ {}
        }
    }
    
    class func setFlashMode(_ flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
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
    
    fileprivate func setWhiteBalanceGains(_ gains: AVCaptureWhiteBalanceGains) {
        
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
    
    fileprivate class func deviceWithMediaType(_ mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(withMediaType: mediaType) as! [AVCaptureDevice]
        var captureDevice = devices.first
        
        for device in devices {
            if device.position == position {
                captureDevice = device
                break
            }
        }
        
        return captureDevice
    }
    
    fileprivate func stringFromFocusMode(_ focusMode: AVCaptureFocusMode) -> String {
        var string: String
        
        switch focusMode {
        case .locked:
            string = "Locked"
        case .autoFocus:
            string = "Auto"
        case .continuousAutoFocus:
            string = "ContinuousAuto"
        }
        
        return string
    }
    
    fileprivate func stringFromExposureMode(_ exposureMode: AVCaptureExposureMode) -> String {
        var string: String
        
        switch exposureMode {
        case .locked:
            string = "Locked"
        case .autoExpose:
            string = "Auto"
        case .continuousAutoExposure:
            string = "ContinuousAuto"
        case .custom:
            string = "Custom"
        }
        
        return string
    }
    
    fileprivate func stringFromWhiteBalanceMode(_ whiteBalanceMode: AVCaptureWhiteBalanceMode) -> String {
        var string: String
        
        switch whiteBalanceMode {
        case .locked:
            string = "Locked"
        case .autoWhiteBalance:
            string = "Auto"
        case .continuousAutoWhiteBalance:
            string = "ContinuousAuto"
        }
        
        return string
    }
    
    fileprivate func normalizedGains(_ gains: AVCaptureWhiteBalanceGains) -> AVCaptureWhiteBalanceGains {
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
