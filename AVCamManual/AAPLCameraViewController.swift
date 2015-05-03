//
//  AAPLCameraViewController.swift
//  AVCamManual
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/4/26.
//
//
/*
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:

  Control of camera functions.

*/

import UIKit
import AVFoundation
import AssetsLibrary

private func contextUsing(ptr: UnsafeMutablePointer<Void>) -> UnsafeMutablePointer<Void> {
    return ptr
}
private var dummy: Int = 0
private var CapturingStillImageContext = contextUsing(&dummy)
private var RecordingContext = contextUsing(&CapturingStillImageContext)
private var SessionRunningAndDeviceAuthorizedContext = contextUsing(&RecordingContext)

private var FocusModeContext = contextUsing(&SessionRunningAndDeviceAuthorizedContext)
private var ExposureModeContext = contextUsing(&FocusModeContext)
private var WhiteBalanceModeContext = contextUsing(&ExposureModeContext)
private var LensPositionContext = contextUsing(&WhiteBalanceModeContext)
private var ExposureDurationContext = contextUsing(&LensPositionContext)
private var ISOContext = contextUsing(&ExposureDurationContext)
private var ExposureTargetOffsetContext = contextUsing(&ISOContext)
private var DeviceWhiteBalanceGainsContext = contextUsing(&ExposureTargetOffsetContext)

@objc(AAPLCameraViewController)
class AAPLCameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    @IBOutlet weak var previewView: AAPLPreviewView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var stillButton: UIButton!
    
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
    private var sessionQueue: dispatch_queue_t! // Communicate with the session and other session objects on this queue.
    dynamic var session: AVCaptureSession!
    dynamic var videoDeviceInput: AVCaptureDeviceInput?
    private var videoDevice: AVCaptureDevice?
    dynamic var movieFileOutput: AVCaptureMovieFileOutput?
    dynamic var stillImageOutput: AVCaptureStillImageOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    private var deviceAuthorized: Bool = false
    private var lockInterfaceRotation: Bool = false
    private var runtimeErrorHandlingObserver: AnyObject?
    
    private let EXPOSURE_DURATION_POWER = 5.0 // Higher numbers will give the slider more sensitivity at shorter durations
    private let EXPOSURE_MINIMUM_DURATION = 1.0/1000 // Limit exposure duration to a useful range
    
    private let CONTROL_NORMAL_COLOR = UIColor.yellowColor()
    private let CONTROL_HIGHLIGHT_COLOR = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0) // A nice blue
    
    class func keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized() -> Set<NSObject> {
        return ["session.running", "deviceAuthorized"]
    }
    
    @objc var sessionRunningAndDeviceAuthorized: Bool {
        @objc(isSessionRunningAndDeviceAuthorized) get {
            return self.session.running && self.deviceAuthorized
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.autoresizingMask = UIViewAutoresizing.FlexibleWidth | UIViewAutoresizing.FlexibleHeight
        
        (self.recordButton.layer.cornerRadius, self.stillButton.layer.cornerRadius, self.cameraButton.layer.cornerRadius) = (4, 4, 4)
        (self.recordButton.clipsToBounds, self.stillButton.clipsToBounds, self.cameraButton.clipsToBounds) = (true, true, true)
        
        // Create the AVCaptureSession
        let session = AVCaptureSession()
        self.session = session
        
        // Set up preview
        self.previewView.session = session
        
        // Check for device authorization
        self.checkDeviceAuthorizationStatus()
        
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue so that the main queue isn't blocked (which keeps the UI responsive).
        
        let sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
        self.sessionQueue = sessionQueue
        
        dispatch_async(sessionQueue) {
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            
            var error: NSError? = nil
            
            let videoDevice = AAPLCameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: .Back)
            let videoDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(videoDevice, error: &error) as! AVCaptureDeviceInput?
            
            if error != nil {
                NSLog("%@", error!)
            }
            
            self.session.beginConfiguration()
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                self.videoDevice = videoDeviceInput?.device
                
                dispatch_async(dispatch_get_main_queue()) {
                    // Why are we dispatching this to the main queue?
                    // Because AVCaptureVideoPreviewLayer is the backing layer for our preview view and UIView can only be manipulated on main thread.
                    // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                    
                    let orientation = UIApplication.sharedApplication().statusBarOrientation
                    (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue)!
                }
            }
            assert(self.videoDevice != nil, "Video capturing device is not available for this target")
            
            let audioDevice = AVCaptureDevice.devicesWithMediaType(AVMediaTypeAudio).first as! AVCaptureDevice?
            let audioDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(audioDevice, error: &error) as! AVCaptureDeviceInput?
            
            if error != nil {
                NSLog("%@", error!)
            }
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            }
            
            let movieFileOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieFileOutput) {
                session.addOutput(movieFileOutput)
                let connection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                if connection.activeVideoStabilizationMode != .Off {
                    connection.preferredVideoStabilizationMode = .Auto
                }
                self.movieFileOutput = movieFileOutput
            }
            
            let stillImageOutput = AVCaptureStillImageOutput()
            if session.canAddOutput(stillImageOutput) {
                stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            }
            
            self.session.commitConfiguration()
            
            dispatch_async(dispatch_get_main_queue()) {
                self.configureManualHUD()
            }
        }
        
        self.manualHUDFocusView.hidden = true
        self.manualHUDExposureView.hidden = true
        self.manualHUDWhiteBalanceView.hidden = true
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        dispatch_async(self.sessionQueue) {
            self.addObservers()
            
            self.session.startRunning()
        }
    }
    
    override func viewDidDisappear(animated: Bool) {
        dispatch_async(self.sessionQueue) {
            self.session.stopRunning()
            
            self.removeObservers()
        }
        
        super.viewDidDisappear(animated)
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    override func shouldAutorotate() -> Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !self.lockInterfaceRotation
    }
    
    override func supportedInterfaceOrientations() -> Int {
        return Int(UIInterfaceOrientationMask.All.rawValue)
    }
    
    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation = AVCaptureVideoOrientation(rawValue: toInterfaceOrientation.rawValue)!
    }
    
    override func willAnimateRotationToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        self.positionManualHUD()
    }
    
    //MARK: Actions
    
    @IBAction func toggleMovieRecording(AnyObject) {
        self.recordButton.enabled = false
        
        dispatch_async(self.sessionQueue) {
            if !(self.movieFileOutput?.recording ?? false) {
                self.lockInterfaceRotation = true
                
                if UIDevice.currentDevice().multitaskingSupported {
                    // Setup background task. This is needed because the captureOutput:didFinishRecordingToOutputFileAtURL: callback is not received until the app returns to the foreground unless you request background execution time. This also ensures that there will be time to write the file to the assets library when the app is backgrounded. To conclude this background execution, -endBackgroundTask is called in -recorder:recordingDidFinishToOutputFileURL:error: after the recorded file has been saved.
                    self.backgroundRecordingID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler{}
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                self.movieFileOutput!.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
                
                // Turn OFF flash for video recording
                AAPLCameraViewController.setFlashMode(.Off, forDevice: self.videoDevice!)
                
                // Start recording to a temporary file.
                let outputFilePath = NSTemporaryDirectory().stringByAppendingPathComponent("movie.mov")
                self.movieFileOutput!.startRecordingToOutputFileURL(NSURL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                self.movieFileOutput!.stopRecording()
            }
        }
    }
    
    @IBAction func changeCamera(AnyObject) {
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.stillButton.enabled = false
        
        dispatch_async(self.sessionQueue) {
            let currentVideoDevice = self.videoDevice!
            var preferredPosition = AVCaptureDevicePosition.Unspecified
            let currentPosition = currentVideoDevice.position
            
            switch currentPosition {
            case .Unspecified:
                preferredPosition = .Back
            case .Back:
                preferredPosition = .Front
            case .Front:
                preferredPosition = .Back
            }
            
            let newVideoDevice = AAPLCameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition)
            let newVideoDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(newVideoDevice, error: nil) as! AVCaptureDeviceInput
            
            self.session.beginConfiguration()
            
            self.session.removeInput(self.videoDeviceInput)
            if self.session.canAddInput(newVideoDeviceInput) {
                NSNotificationCenter.defaultCenter().removeObserver(self,
                    name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: currentVideoDevice)
                
                NSNotificationCenter.defaultCenter().addObserver(self, selector: "subjectAreaDidChange:", name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: newVideoDevice)
                
                self.session.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
                self.videoDevice = newVideoDeviceInput.device
            } else {
                self.session.addInput(self.videoDeviceInput)
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
    
    @IBAction func snapStillImage(AnyObject) {
        dispatch_async(self.sessionQueue) {
            // Update the orientation on the still image output video connection before capturing.
            self.stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection.videoOrientation
            
            // Flash set to Auto for Still Capture
            if self.videoDevice!.exposureMode == .Custom {
                AAPLCameraViewController.setFlashMode(.Off, forDevice: self.videoDevice!)
            } else {
                AAPLCameraViewController.setFlashMode(.Auto, forDevice: self.videoDevice!)
            }
            
            // Capture a still image
            self.stillImageOutput?.captureStillImageAsynchronouslyFromConnection(self.stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo)) {imageDataSampleBuffer, error in
                
                if imageDataSampleBuffer != nil {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)!
                    let image = UIImage(data: imageData)!
                    ALAssetsLibrary().writeImageToSavedPhotosAlbum(image.CGImage, orientation: ALAssetOrientation(rawValue: image.imageOrientation.rawValue)!, completionBlock: nil)
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
        
        self.positionManualHUD()
        
        self.manualHUDFocusView.hidden = (control.selectedSegmentIndex == 1) ? false : true
        self.manualHUDExposureView.hidden = (control.selectedSegmentIndex == 2) ? false : true
        self.manualHUDWhiteBalanceView.hidden = (control.selectedSegmentIndex == 3) ? false : true
    }
    
    @IBAction func changeFocusMode(control: UISegmentedControl) {
        let mode = self.focusModes[control.selectedSegmentIndex]
        var error: NSError? = nil
        
        if self.videoDevice!.lockForConfiguration(&error) {
            if self.videoDevice!.isFocusModeSupported(mode) {
                self.videoDevice!.focusMode = mode
            } else {
                NSLog("Focus mode %@ is not supported. Focus mode is %@.", self.stringFromFocusMode(mode), self.stringFromFocusMode(self.videoDevice!.focusMode))
                self.focusModeControl.selectedSegmentIndex = find(self.focusModes, self.videoDevice!.focusMode)!
            }
            self.videoDevice!.unlockForConfiguration()
        } else {
            NSLog("%@", error!)
        }
    }
    @IBAction func changeExposureMode(control: UISegmentedControl) {
        var error: NSError? = nil
        let mode = self.exposureModes[control.selectedSegmentIndex]
        
        if self.videoDevice!.lockForConfiguration(&error) {
            if self.videoDevice!.isExposureModeSupported(mode) {
                self.videoDevice!.exposureMode = mode
            } else {
                NSLog("Exposure mode %@ is not supported. Exposure mode is %@.", self.stringFromExposureMode(mode), self.stringFromExposureMode(self.videoDevice!.exposureMode))
            }
            self.videoDevice!.unlockForConfiguration()
        } else {
            NSLog("%@", error!)
        }
    }
    
    @IBAction func changeWhiteBalanceMode(control: UISegmentedControl) {
        let mode = self.whiteBalanceModes[control.selectedSegmentIndex]
        var error: NSError? = nil
        
        if self.videoDevice!.lockForConfiguration(&error) {
            if self.videoDevice!.isWhiteBalanceModeSupported(mode) {
                self.videoDevice!.whiteBalanceMode = mode
            } else {
                NSLog("White balance mode %@ is not supported. White balance mode is %@.", self.stringFromWhiteBalanceMode(mode), self.stringFromWhiteBalanceMode(self.videoDevice!.whiteBalanceMode))
            }
            self.videoDevice!.unlockForConfiguration()
        } else {
            NSLog("%@", error!)
        }
    }
    
    @IBAction func changeLensPosition(control: UISlider) {
        var error: NSError? = nil
        
        if self.videoDevice!.isFocusModeSupported(.Locked)
            && self.videoDevice!.lockForConfiguration(&error)  {
                self.videoDevice!.setFocusModeLockedWithLensPosition(control.value, completionHandler: nil)
                self.videoDevice!.unlockForConfiguration()
        } else {
            NSLog("%@", error!)
        }
    }
    
    @IBAction func changeExposureDuration(control: UISlider) {
        var error: NSError? = nil
        
        let p = pow(Double(control.value), EXPOSURE_DURATION_POWER) // Apply power function to expand slider's low-end range
        let minDurationSeconds = max(CMTimeGetSeconds(self.videoDevice!.activeFormat.minExposureDuration), EXPOSURE_MINIMUM_DURATION)
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
        
        if self.videoDevice!.lockForConfiguration(&error) {
            self.videoDevice!.setExposureModeCustomWithDuration(CMTimeMakeWithSeconds(newDurationSeconds, 1000*1000*1000), ISO: AVCaptureISOCurrent, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } else {
            NSLog("%@", error!)
        }
    }
    
    @IBAction func changeISO(control: UISlider) {
        var error: NSError? = nil
        
        if self.videoDevice!.lockForConfiguration(&error) {
            self.videoDevice!.setExposureModeCustomWithDuration(AVCaptureExposureDurationCurrent, ISO: control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } else {
            NSLog("%@", error!)
        }
    }
    
    @IBAction func changeExposureTargetBias(control: UISlider) {
        var error: NSError? = nil
        
        if self.videoDevice!.lockForConfiguration(&error) {
            self.videoDevice!.setExposureTargetBias(control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
            self.exposureTargetBiasValueLabel.text = String(format:"%.1f", Double(control.value))
        } else {
            NSLog("%@", error!)
        }
    }
    
    @IBAction func changeTemperature(AnyObject) {
        let temperatureAndTint = AVCaptureWhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGainsForTemperatureAndTintValues(temperatureAndTint))
    }
    
    @IBAction func changeTint(AnyObject) {
        let temperatureAndTint = AVCaptureWhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGainsForTemperatureAndTintValues(temperatureAndTint))
    }
    
    @IBAction func lockWithGrayWorld(AnyObject) {
        self.setWhiteBalanceGains(self.videoDevice!.grayWorldDeviceWhiteBalanceGains)
    }
    
    @IBAction func sliderTouchBegan(slider: UISlider) {
        self.setSlider(slider, highlightColor: CONTROL_HIGHLIGHT_COLOR)
    }
    
    @IBAction func sliderTouchEnded(slider: UISlider) {
        self.setSlider(slider, highlightColor: CONTROL_NORMAL_COLOR)
    }
    
    //MARK: UI
    
    private func runStillImageCaptureAnimation() {
        dispatch_async(dispatch_get_main_queue()) {
            self.previewView.layer.opacity = 0.0
            UIView.animateWithDuration(0.25) {
                self.previewView.layer.opacity = 1.0
            }
        }
    }
    
    private func configureManualHUD() {
        // Manual focus controls
        self.focusModes = [.ContinuousAutoFocus, .Locked]
        
        self.focusModeControl.selectedSegmentIndex = find(self.focusModes, self.videoDevice!.focusMode)!
        for mode in self.focusModes {
            self.focusModeControl.setEnabled(self.videoDevice!.isFocusModeSupported(mode), forSegmentAtIndex: find(self.focusModes, mode)!)
        }
        
        self.lensPositionSlider.minimumValue = 0.0
        self.lensPositionSlider.maximumValue = 1.0
        self.lensPositionSlider.enabled = (self.videoDevice!.isFocusModeSupported(.Locked) && self.videoDevice!.focusMode == .Locked)
        
        // Manual exposure controls
        self.exposureModes = [.ContinuousAutoExposure, .Locked, .Custom]
        
        self.exposureModeControl.selectedSegmentIndex = find(self.exposureModes, self.videoDevice!.exposureMode)!
        for mode in self.exposureModes {
            self.exposureModeControl.setEnabled(self.videoDevice!.isExposureModeSupported(mode), forSegmentAtIndex: find(self.exposureModes, mode)!)
        }
        
        // Use 0-1 as the slider range and do a non-linear mapping from the slider value to the actual device exposure duration
        self.exposureDurationSlider.minimumValue = 0
        self.exposureDurationSlider.maximumValue = 1
        self.exposureDurationSlider.enabled = (self.videoDevice!.exposureMode == .Custom)
        
        self.ISOSlider.minimumValue = self.videoDevice!.activeFormat.minISO
        self.ISOSlider.maximumValue = self.videoDevice!.activeFormat.maxISO
        self.ISOSlider.enabled = (self.videoDevice!.exposureMode == AVCaptureExposureMode.Custom)
        
        self.exposureTargetBiasSlider.minimumValue = self.videoDevice!.minExposureTargetBias
        self.exposureTargetBiasSlider.maximumValue = self.videoDevice!.maxExposureTargetBias
        self.exposureTargetBiasSlider.enabled = true
        
        self.exposureTargetOffsetSlider.minimumValue = self.videoDevice!.minExposureTargetBias
        self.exposureTargetOffsetSlider.maximumValue = self.videoDevice!.maxExposureTargetBias
        self.exposureTargetOffsetSlider.enabled = false
        
        // Manual white balance controls
        self.whiteBalanceModes = [.ContinuousAutoWhiteBalance, .Locked]
        
        self.whiteBalanceModeControl.selectedSegmentIndex = find(self.whiteBalanceModes, self.videoDevice!.whiteBalanceMode)!
        for mode in self.whiteBalanceModes {
            self.whiteBalanceModeControl.setEnabled(self.videoDevice!.isWhiteBalanceModeSupported(mode), forSegmentAtIndex: find(self.whiteBalanceModes, mode)!)
        }
        
        self.temperatureSlider.minimumValue = 3000
        self.temperatureSlider.maximumValue = 8000
        self.temperatureSlider.enabled = (self.videoDevice!.whiteBalanceMode == .Locked)
        
        self.tintSlider.minimumValue = -150
        self.tintSlider.maximumValue = 150
        self.tintSlider.enabled = (self.videoDevice!.whiteBalanceMode == .Locked)
    }
    
    private func positionManualHUD() {
        // Since we only show one manual view at a time, put them all in the same place (at the top)
        self.manualHUDExposureView.frame = CGRectMake(self.manualHUDFocusView.frame.origin.x, self.manualHUDFocusView.frame.origin.y, self.manualHUDExposureView.frame.size.width, self.manualHUDExposureView.frame.size.height)
        self.manualHUDWhiteBalanceView.frame = CGRectMake(self.manualHUDFocusView.frame.origin.x, self.manualHUDFocusView.frame.origin.y, self.manualHUDWhiteBalanceView.frame.size.width, self.manualHUDWhiteBalanceView.frame.size.height)
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
    
    //MARK: File Output Delegate
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        if error != nil {
            NSLog("%@", error!)
        }
        
        self.lockInterfaceRotation = false
        
        // Note the backgroundRecordingID for use in the ALAssetsLibrary completion handler to end the background task associated with this recording. This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's -isRecording is back to NO — which happens sometime after this method returns.
        let backgroundRecordingID = self.backgroundRecordingID
        self.backgroundRecordingID = UIBackgroundTaskInvalid
        
        ALAssetsLibrary().writeVideoAtPathToSavedPhotosAlbum(outputFileURL) {assetURL, error in
            if error != nil {
                NSLog("%@", error!)
            }
            
            NSFileManager.defaultManager().removeItemAtURL(outputFileURL, error: nil)
            
            if backgroundRecordingID != UIBackgroundTaskInvalid {
                UIApplication.sharedApplication().endBackgroundTask(backgroundRecordingID)
            }
        }
    }
    
    //MARK: Device Configuration
    
    private func focusWithMode(focusMode: AVCaptureFocusMode, exposeWithMode exposureMode: AVCaptureExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        dispatch_async(self.sessionQueue) {
            let device = self.videoDevice!
            var error: NSError? = nil
            if device.lockForConfiguration(&error) {
                if device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusMode = focusMode
                    device.focusPointOfInterest = point
                }
                if device.exposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposureMode = exposureMode
                    device.exposurePointOfInterest = point
                }
                device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } else {
                NSLog("%@", error!)
            }
        }
    }
    
    class func setFlashMode(flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            var error: NSError? = nil
            if device.lockForConfiguration(&error) {
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } else {
                NSLog("%@", error!)
            }
        }
    }
    
    private func setWhiteBalanceGains(gains: AVCaptureWhiteBalanceGains) {
        var error: NSError? = nil
        
        if self.videoDevice!.lockForConfiguration(&error) {
            let normalizedGains = self.normalizedGains(gains) // Conversion can yield out-of-bound values, cap to limits
            self.videoDevice!.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(normalizedGains, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } else {
            NSLog("%@", error!)
        }
    }
    
    //MARK: KVO
    
    private func addObservers() {
        self.addObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", options: .Old | .New, context: SessionRunningAndDeviceAuthorizedContext)
        self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options: .Old | .New, context: CapturingStillImageContext)
        self.addObserver(self, forKeyPath: "movieFileOutput.recording", options: .Old | .New, context: RecordingContext)
        
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.focusMode", options: .Initial | .Old | .New, context: FocusModeContext)
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.lensPosition", options: .Old | .New, context: LensPositionContext)
        
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.exposureMode", options: .Initial | .Old | .New, context: ExposureModeContext)
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.exposureDuration", options: .Old | .New, context: ExposureDurationContext)
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.ISO", options: .Old | .New, context:ISOContext)
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.exposureTargetOffset", options: .Old | .New, context: ExposureTargetOffsetContext)
        
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.whiteBalanceMode", options: .Initial | .Old | .New, context: WhiteBalanceModeContext)
        self.addObserver(self, forKeyPath: "videoDeviceInput.device.deviceWhiteBalanceGains", options: .Old | .New, context: DeviceWhiteBalanceGainsContext)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "subjectAreaDidChange:", name:AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDevice!)
        
        self.runtimeErrorHandlingObserver = NSNotificationCenter.defaultCenter().addObserverForName(AVCaptureSessionRuntimeErrorNotification, object: self.session, queue: nil) {[weak self] note in
            dispatch_async(self!.sessionQueue) {
                // Manually restart the session since it must have been stopped due to an error
                self!.session.startRunning()
                self!.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), forState: .Normal)
            }
        }
    }
    
    private func removeObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object:self.videoDevice!)
        NSNotificationCenter.defaultCenter().removeObserver(self.runtimeErrorHandlingObserver!)
        
        self.removeObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", context:SessionRunningAndDeviceAuthorizedContext)
        self.removeObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", context: CapturingStillImageContext)
        self.removeObserver(self, forKeyPath: "movieFileOutput.recording", context: RecordingContext)
        
        self.removeObserver(self, forKeyPath: "videoDevice.focusMode", context: FocusModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.lensPosition", context: LensPositionContext)
        
        self.removeObserver(self, forKeyPath: "videoDevice.exposureMode", context: ExposureModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureDuration", context: ExposureDurationContext)
        self.removeObserver(self, forKeyPath: "videoDevice.ISO", context: ISOContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureTargetOffset", context: ExposureTargetOffsetContext)
        
        self.removeObserver(self, forKeyPath: "videoDevice.whiteBalanceMode", context: WhiteBalanceModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.deviceWhiteBalanceGains", context: DeviceWhiteBalanceGainsContext)
    }
    
    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject: AnyObject], context: UnsafeMutablePointer<Void>) {
        switch context {
        case FocusModeContext:
            let oldMode = AVCaptureFocusMode(rawValue: change[NSKeyValueChangeOldKey] as! Int? ?? 0)!
            let newMode = AVCaptureFocusMode(rawValue: change[NSKeyValueChangeNewKey] as! Int? ?? 0)!
            NSLog("focus mode: \(stringFromFocusMode(oldMode)) -> \(stringFromFocusMode(newMode))")
            
            self.focusModeControl.selectedSegmentIndex = find(self.focusModes, newMode) ?? 0
            self.lensPositionSlider.enabled = (newMode == .Locked)
        case LensPositionContext:
            let newLensPosition = change[NSKeyValueChangeNewKey] as! Float? ?? 0.0
            
            if self.videoDevice!.focusMode != .Locked {
                self.lensPositionSlider.value = newLensPosition
            }
            self.lensPositionValueLabel.text = String(format: "%.1f", Double(newLensPosition))
        case ExposureModeContext:
            let oldMode = AVCaptureExposureMode(rawValue: change[NSKeyValueChangeOldKey] as! Int? ?? 0)!
            let newMode = AVCaptureExposureMode(rawValue: change[NSKeyValueChangeNewKey] as! Int? ?? 0)!
            NSLog("exposure mode: \(stringFromExposureMode(oldMode)) -> \(stringFromExposureMode(newMode))")
            
            self.exposureModeControl.selectedSegmentIndex = find(self.exposureModes, newMode) ?? 0
            self.exposureDurationSlider.enabled = (newMode == .Custom)
            self.ISOSlider.enabled = (newMode == .Custom)
            
            /*
            It’s important to understand the relationship between exposureDuration and the minimum frame rate as represented by activeVideoMaxFrameDuration.
            In manual mode, if exposureDuration is set to a value that's greater than activeVideoMaxFrameDuration, then activeVideoMaxFrameDuration will
            increase to match it, thus lowering the minimum frame rate. If exposureMode is then changed to automatic mode, the minimum frame rate will
            remain lower than its default. If this is not the desired behavior, the min and max frameRates can be reset to their default values for the
            current activeFormat by setting activeVideoMaxFrameDuration and activeVideoMinFrameDuration to kCMTimeInvalid.
            */
            if oldMode == .Custom {
                var error: NSError? = nil
                if self.videoDevice!.lockForConfiguration(&error) {
                    self.videoDevice!.activeVideoMaxFrameDuration = kCMTimeInvalid
                    self.videoDevice!.activeVideoMinFrameDuration = kCMTimeInvalid
                    self.videoDevice!.unlockForConfiguration()
                }
            }
        case ExposureDurationContext:
            let newDurationSeconds = CMTimeGetSeconds(change[NSKeyValueChangeNewKey]!.CMTimeValue)
            if self.videoDevice!.exposureMode != .Custom {
                let minDurationSeconds = max(CMTimeGetSeconds(self.videoDevice!.activeFormat.minExposureDuration), EXPOSURE_MINIMUM_DURATION)
                let maxDurationSeconds = CMTimeGetSeconds(self.videoDevice!.activeFormat.maxExposureDuration)
                // Map from duration to non-linear UI range 0-1
                let p = (newDurationSeconds - minDurationSeconds) / (maxDurationSeconds - minDurationSeconds) // Scale to 0-1
                self.exposureDurationSlider.value = Float(pow(p, 1 / EXPOSURE_DURATION_POWER)) // Apply inverse power
                
                if newDurationSeconds < 1 {
                    let digits = Int32(max(0, 2 + floor(log10(newDurationSeconds))))
                    self.exposureDurationValueLabel.text = String(format: "1/%.*f", digits, 1/Double(newDurationSeconds))
                } else {
                    self.exposureDurationValueLabel.text = String(format: "%.2f", Double(newDurationSeconds))
                }
            }
        case ISOContext:
            let newISO = change[NSKeyValueChangeNewKey] as! Float? ?? 0.0
            
            if self.videoDevice!.exposureMode != .Custom {
                self.ISOSlider.value = newISO
            }
            self.ISOValueLabel.text = String(Int(newISO))
        case ExposureTargetOffsetContext:
            let newExposureTargetOffset = change[NSKeyValueChangeNewKey] as! Float? ?? 0.0
            
            self.exposureTargetOffsetSlider.value = newExposureTargetOffset
            self.exposureTargetOffsetValueLabel.text = String(format: "%.1f", Double(newExposureTargetOffset))
        case WhiteBalanceModeContext:
            let oldMode = AVCaptureWhiteBalanceMode(rawValue: change[NSKeyValueChangeOldKey] as! Int? ?? 0)!
            let newMode = AVCaptureWhiteBalanceMode(rawValue: change[NSKeyValueChangeNewKey] as! Int? ?? 0)!
            NSLog("white balance mode: \(stringFromWhiteBalanceMode(oldMode)) -> \(stringFromWhiteBalanceMode(newMode))")
            
            self.whiteBalanceModeControl.selectedSegmentIndex = find(self.whiteBalanceModes, newMode) ?? 0
            self.temperatureSlider.enabled = (newMode == .Locked)
            self.tintSlider.enabled = (newMode == .Locked)
        case DeviceWhiteBalanceGainsContext:
            var newGains = AVCaptureWhiteBalanceGains()
            (change[NSKeyValueChangeNewKey] as! NSValue).getValue(&newGains)
            let newTemperatureAndTint = self.videoDevice!.temperatureAndTintValuesForDeviceWhiteBalanceGains(newGains)
            
            if self.videoDevice!.whiteBalanceMode != .Locked {
                self.temperatureSlider.value = newTemperatureAndTint.temperature
                self.tintSlider.value = newTemperatureAndTint.tint
            }
            self.temperatureValueLabel.text = String(Int(newTemperatureAndTint.temperature))
            self.tintValueLabel.text = String(Int(newTemperatureAndTint.tint))
        case CapturingStillImageContext:
            let isCapturingStillImage = change[NSKeyValueChangeNewKey] as! Bool? ?? false
            
            if isCapturingStillImage {
                self.runStillImageCaptureAnimation()
            }
        case RecordingContext:
            let isRecording = change[NSKeyValueChangeNewKey] as! Bool? ?? false
            
            dispatch_async(dispatch_get_main_queue()) {
                if isRecording {
                    self.cameraButton.enabled = false
                    self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), forState: .Normal)
                    self.recordButton.enabled = true
                } else {
                    self.cameraButton.enabled = true
                    self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), forState: .Normal)
                    self.recordButton.enabled = true
                }
            }
        case SessionRunningAndDeviceAuthorizedContext:
            let isRunning = change[NSKeyValueChangeNewKey] as! Bool? ?? false
            
            dispatch_async(dispatch_get_main_queue()) {
                if isRunning {
                    self.cameraButton.enabled = true
                    self.recordButton.enabled = true
                    self.stillButton.enabled = true
                } else {
                    self.cameraButton.enabled = false
                    self.recordButton.enabled = false
                    self.stillButton.enabled = false
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
    
    private func checkDeviceAuthorizationStatus() {
        let mediaType = AVMediaTypeVideo
        
        AVCaptureDevice.requestAccessForMediaType(mediaType) {granted in
            if granted {
                self.deviceAuthorized = true
            } else {
                dispatch_async(dispatch_get_main_queue()) {
                    let alert = UIAlertController(title: "AVCamManual",
                        message: "AVCamManual doesn't have permission to use the Camera",
                        preferredStyle: .Alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                    self.presentViewController(alert, animated: true, completion: nil)
                    self.deviceAuthorized = false
                }
            }
        }
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