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

private var CapturingStillImageContext = 0 //### iOS < 10.0
private var SessionRunningContext = 0
private var FocusModeContext = 0
private var ExposureModeContext = 0
private var WhiteBalanceModeContext = 0
private var LensPositionContext = 0
private var ExposureDurationContext = 0
private var ISOContext = 0
private var ExposureTargetBiasContext = 0
private var ExposureTargetOffsetContext = 0
private var DeviceWhiteBalanceGainsContext = 0
private var LensStabilizationContext = 0 //### iOS < 10.0

private enum AVCamManualSetupResult: Int {
    case success
    case cameraNotAuthorized
    case sessionConfigurationFailed
}

private enum AVCamManualCaptureMode: Int {
    case photo
    case movie
}

//### Compatibility types...
private protocol AVCaptureDeviceDiscoverySessionType: class {
    @available(iOS 10.0, *)
    var devices: [AVCaptureDevice] { get }
}
@available(iOS 10.0, *)
extension AVCaptureDevice.DiscoverySession: AVCaptureDeviceDiscoverySessionType {}
@objc protocol AVCapturePhotoOutputType {
    @available(iOS 10.0, *)
    var isLensStabilizationDuringBracketedCaptureSupported: Bool {get}
    //### `availableRawPhotoPixelFormatTypes` is temporarily renamed to `__availableRawPhotoPixelFormatTypes`,
    //### Maybe more Swiftish refinement is planned, but not yet completed.
    @available(iOS 10.0, *)
    @objc(availableRawPhotoPixelFormatTypes)
    var __availableRawPhotoPixelFormatTypes: [NSNumber] {get}
    @available(iOS 10.0, *)
    var isHighResolutionCaptureEnabled: Bool {get @objc(setHighResolutionCaptureEnabled:) set}
    @available(iOS 10.0, *)
    //### `supportedFlashModes` is temporarily renamed to `__supportedFlashModes`,
    //### Maybe more Swiftish refinement is planned, but not yet completed.
    @objc(supportedFlashModes)
    var __supportedFlashModes: [NSNumber] {get}
    @available(iOS 10.0, *)
    @objc(connectionWithMediaType:)
    func connection(with mediaType: AVMediaType) -> AVCaptureConnection?
    @available(iOS 10.0, *)
    @objc(capturePhotoWithSettings:delegate:)
    func capturePhoto(with settings: AVCapturePhotoSettings, delegate: AVCapturePhotoCaptureDelegate)
}
@available(iOS 10.0, *)
extension AVCapturePhotoOutput: AVCapturePhotoOutputType {}

@objc(AVCamManualCameraViewController)
class AVCamManualCameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    @IBOutlet weak var previewView: AVCamManualPreviewView!
    @IBOutlet weak var captureModeControl: UISegmentedControl!
    @IBOutlet weak var cameraUnavailableLabel: UILabel!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var photoButton: UIButton!
    @IBOutlet weak var HUDButton: UIButton!
    @IBOutlet weak var manualSegments: UISegmentedControl! //###
    
    @IBOutlet weak var manualHUD: UIView!
    
    private var focusModes: [AVCaptureDevice.FocusMode] = []
    @IBOutlet weak var manualHUDFocusView: UIView!
    @IBOutlet weak var focusModeControl: UISegmentedControl!
    @IBOutlet weak var lensPositionSlider: UISlider!
    @IBOutlet weak var lensPositionNameLabel: UILabel!
    @IBOutlet weak var lensPositionValueLabel: UILabel!
    
    private var exposureModes: [AVCaptureDevice.ExposureMode] = []
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
    
    private var whiteBalanceModes: [AVCaptureDevice.WhiteBalanceMode] = []
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
    
    @IBOutlet weak var manualHUDPhotoView: UIView!
    @IBOutlet weak var rawControl: UISegmentedControl!
    
    // Session management.
    private var sessionQueue: DispatchQueue!
    @objc dynamic var session: AVCaptureSession!
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput?
    private var videoDeviceDiscoverySession: AVCaptureDeviceDiscoverySessionType?
    @objc dynamic var videoDevice: AVCaptureDevice?
    @objc dynamic var movieFileOutput: AVCaptureMovieFileOutput?
    @objc dynamic var photoOutput: AVCapturePhotoOutputType?
    @objc dynamic var stillImageOutput: AVCaptureStillImageOutput? //### iOS < 10.0
    
    private var inProgressPhotoCaptureDelegates: [Int64: AVCamManualPhotoCaptureDelegateType] = [:]
    
    // Utilities.
    private var setupResult: AVCamManualSetupResult = .success
    private var isSessionRunning: Bool = false
    private var backgroundRecordingID: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    private let kExposureDurationPower = 5.0 // Higher numbers will give the slider more sensitivity at shorter durations
    private let kExposureMinimumDuration = 1.0/1000 // Limit exposure duration to a useful range
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable UI. The UI is enabled if and only if the session starts running.
        self.cameraButton.isEnabled = false
        self.recordButton.isEnabled = false
        self.photoButton.isEnabled = false
        self.captureModeControl.isEnabled = false
        self.HUDButton.isEnabled = false
        
        self.manualHUD.isHidden = true
        self.manualHUDPhotoView.isHidden = true
        self.manualHUDFocusView.isHidden = true
        self.manualHUDExposureView.isHidden = true
        self.manualHUDWhiteBalanceView.isHidden = true
        self.manualHUDLensStabilizationView.isHidden = true
        
        // Create the AVCaptureSession.
        self.session = AVCaptureSession()
        
        // Create a device discovery session
        if #available(iOS 10.0, *) {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [AVCaptureDevice.DeviceType.builtInWideAngleCamera, AVCaptureDevice.DeviceType.builtInDuoCamera, AVCaptureDevice.DeviceType.builtInTelephotoCamera]
            self.videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaType.video, position: .unspecified)
        }
        
        // Setup the preview view.
        self.previewView.session = self.session
        
        // Communicate with the session and other session objects on this queue.
        self.sessionQueue = DispatchQueue(label: "session queue", attributes: [])
        
        self.setupResult = .success
        
        // Check video authorization status. Video access is required and audio access is optional.
        // If audio access is denied, audio is not recorded during movie recording.
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
        case .notDetermined:
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session running until the access request has completed.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            self.sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video) {granted in
                if !granted {
                    self.setupResult = .cameraNotAuthorized
                }
                self.sessionQueue.resume()
            }
        default:
            // The user has previously denied access.
            self.setupResult = .cameraNotAuthorized
        }
        
        // Setup the capture session.
        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
        // so that the main queue isn't blocked, which keeps the UI responsive.
        self.sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
            case .cameraNotAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("AVCamManual doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera" )
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    // Provide quick access to Settings.
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .default) {action in
                        if #available(iOS 10.0, *) {
                            UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!)
                        } else {
                            UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                        }
                    }
                    alertController.addAction(settingsAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            case .sessionConfigurationFailed:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.removeObservers()
            }
        }
        
        super.viewDidDisappear(animated)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        let deviceOrientation = UIDevice.current.orientation
        
        if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
        }
    }
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.all
    }
    
    override var shouldAutorotate : Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !(self.movieFileOutput?.isRecording ?? false);
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    //MARK: HUD
    
    private func configureManualHUD() {
        // Manual focus controls
        self.focusModes = [.continuousAutoFocus, .locked]
        
        self.focusModeControl.isEnabled = (self.videoDevice != nil)
        if let videoDevice = self.videoDevice {//###
            self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: videoDevice.focusMode)!
            for mode in self.focusModes {
                self.focusModeControl.setEnabled(videoDevice.isFocusModeSupported(mode), forSegmentAt: self.focusModes.index(of: mode)!)
            }
        }
        
        self.lensPositionSlider.minimumValue = 0.0
        self.lensPositionSlider.maximumValue = 1.0
        self.lensPositionSlider.value = self.videoDevice?.lensPosition ?? 0
        self.lensPositionSlider.isEnabled = (self.videoDevice != nil && self.videoDevice!.isFocusModeSupported(.locked) && self.videoDevice!.focusMode == .locked)
        
        // Manual exposure controls
        self.exposureModes = [.continuousAutoExposure, .locked, .custom]
        
        
        self.exposureModeControl.isEnabled = (self.videoDevice != nil)
        if let videoDevice = self.videoDevice {
            self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: videoDevice.exposureMode)!
            for mode in self.exposureModes {
                self.exposureModeControl.setEnabled(videoDevice.isExposureModeSupported(mode), forSegmentAt: self.exposureModes.index(of: mode)!)
            }
        }
        
        // Use 0-1 as the slider range and do a non-linear mapping from the slider value to the actual device exposure duration
        self.exposureDurationSlider.minimumValue = 0
        self.exposureDurationSlider.maximumValue = 1
        let exposureDurationSeconds = CMTimeGetSeconds(self.videoDevice?.exposureDuration ?? CMTime())
        let minExposureDurationSeconds = max(CMTimeGetSeconds(self.videoDevice?.activeFormat.minExposureDuration ?? CMTime()), kExposureMinimumDuration)
        let maxExposureDurationSeconds = CMTimeGetSeconds(self.videoDevice?.activeFormat.maxExposureDuration ?? CMTime())
        // Map from duration to non-linear UI range 0-1
        let p = (exposureDurationSeconds - minExposureDurationSeconds) / (maxExposureDurationSeconds - minExposureDurationSeconds) // Scale to 0-1
        self.exposureDurationSlider.value = Float(pow(p, 1 / kExposureDurationPower)) // Apply inverse power
        self.exposureDurationSlider.isEnabled = (self.videoDevice != nil && self.videoDevice!.exposureMode == .custom)
        
        self.ISOSlider.minimumValue = self.videoDevice?.activeFormat.minISO ?? 0.0
        self.ISOSlider.maximumValue = self.videoDevice?.activeFormat.maxISO ?? 0.0
        self.ISOSlider.value = self.videoDevice?.iso ?? 0.0
        self.ISOSlider.isEnabled = (self.videoDevice?.exposureMode == .custom)
        
        self.exposureTargetBiasSlider.minimumValue = self.videoDevice?.minExposureTargetBias ?? 0.0
        self.exposureTargetBiasSlider.maximumValue = self.videoDevice?.maxExposureTargetBias ?? 0.0
        self.exposureTargetBiasSlider.value = self.videoDevice?.exposureTargetBias ?? 0.0
        self.exposureTargetBiasSlider.isEnabled = (self.videoDevice != nil)
        
        self.exposureTargetOffsetSlider.minimumValue = self.videoDevice?.minExposureTargetBias ?? 0.0
        self.exposureTargetOffsetSlider.maximumValue = self.videoDevice?.maxExposureTargetBias ?? 0.0
        self.exposureTargetOffsetSlider.value = self.videoDevice?.exposureTargetOffset ?? 0.0
        self.exposureTargetOffsetSlider.isEnabled = false
        
        // Manual white balance controls
        self.whiteBalanceModes = [.continuousAutoWhiteBalance, .locked]
        
        self.whiteBalanceModeControl.isEnabled = (self.videoDevice != nil)
        if let videoDevice = self.videoDevice {
            self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: videoDevice.whiteBalanceMode)!
            for mode in self.whiteBalanceModes {
                self.whiteBalanceModeControl.setEnabled(videoDevice.isWhiteBalanceModeSupported(mode), forSegmentAt: self.whiteBalanceModes.index(of: mode)!)
            }
        }
        
        let whiteBalanceGains = self.videoDevice?.deviceWhiteBalanceGains ?? AVCaptureDevice.WhiteBalanceGains()
        let whiteBalanceTemperatureAndTint = self.videoDevice?.temperatureAndTintValues(for: whiteBalanceGains) ?? AVCaptureDevice.WhiteBalanceTemperatureAndTintValues()
        
        self.temperatureSlider.minimumValue = 3000
        self.temperatureSlider.maximumValue = 8000
        self.temperatureSlider.value = whiteBalanceTemperatureAndTint.temperature
        self.temperatureSlider.isEnabled = (self.videoDevice?.whiteBalanceMode == .locked)
        
        self.tintSlider.minimumValue = -150
        self.tintSlider.maximumValue = 150
        self.tintSlider.value = whiteBalanceTemperatureAndTint.tint
        self.tintSlider.isEnabled = (self.videoDevice?.whiteBalanceMode == .locked)
        
        if #available(iOS 10.0, *) {
            self.lensStabilizationControl.isEnabled = (self.videoDevice != nil)
            self.lensStabilizationControl.selectedSegmentIndex = 0
            self.lensStabilizationControl.setEnabled(self.photoOutput!.isLensStabilizationDuringBracketedCaptureSupported, forSegmentAt: 1)
        } else if #available(iOS 9.0, *) {
            self.lensStabilizationControl.isEnabled = (self.videoDevice != nil)
            self.lensStabilizationControl.selectedSegmentIndex = (self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled ? 1 : 0)
            self.lensStabilizationControl.setEnabled(self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureSupported, forSegmentAt: 1)
        } else {
            self.manualSegments.setEnabled(false, forSegmentAt: 4)
            self.lensStabilizationControl.isHidden = true
        }
        
        self.rawControl.isEnabled = (self.videoDevice != nil)
        self.rawControl.selectedSegmentIndex = 0
    }
    
    @IBAction func toggleHUD(_ sender: Any) {
        self.manualHUD.isHidden = !self.manualHUD.isHidden
    }
    
    @IBAction func changeManualHUD(_ control: UISegmentedControl) {
        
        self.manualHUDPhotoView.isHidden = (control.selectedSegmentIndex != 0)
        self.manualHUDFocusView.isHidden = (control.selectedSegmentIndex != 1)
        self.manualHUDExposureView.isHidden = (control.selectedSegmentIndex != 2)
        self.manualHUDWhiteBalanceView.isHidden = (control.selectedSegmentIndex != 3)
        if #available(iOS 9.0, *) {
            self.manualHUDLensStabilizationView.isHidden = (control.selectedSegmentIndex != 4)
        } else {
            self.manualHUDLensStabilizationView.isHidden = true
        }
    }
    
    private func set(_ slider: UISlider, highlight color: UIColor) {
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
    
    @IBAction func sliderTouchBegan(_ slider: UISlider) {
        self.set(slider, highlight: UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0))
    }
    
    @IBAction func sliderTouchEnded(_ slider: UISlider) {
        self.set(slider, highlight: UIColor.yellow)
    }
    
    //MARK: Session Management
    
    // Should be called on the session queue
    private func configureSession() {
        guard self.setupResult == .success else {
            return
        }
        
        self.session.beginConfiguration()
        
        self.session.sessionPreset = AVCaptureSession.Preset.photo
        
        // Add video input
        let videoDevice: AVCaptureDevice!
        if #available(iOS 10.0, *) {
            videoDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for:AVMediaType.video, position: .unspecified)
        } else {
            videoDevice = AVCamManualCameraViewController.deviceWithMediaType(AVMediaType.video.rawValue, preferringPosition: .back)
        }
        let videoDeviceInput: AVCaptureDeviceInput
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device:videoDevice)
        } catch {
            NSLog("Could not create video device input: \(error)")
            self.setupResult = .sessionConfigurationFailed
            self.session.commitConfiguration()
            return
        }
        
        if self.session.canAddInput(videoDeviceInput) {
            self.session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            self.videoDevice = videoDevice
            
            DispatchQueue.main.async {
                /*
                 Why are we dispatching this to the main queue?
                 Because AVCaptureVideoPreviewLayer is the backing layer for AVCamManualPreviewView and UIView
                 can only be manipulated on the main thread.
                 Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                 on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                 
                 Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
                 handled by -[AVCamManualCameraViewController viewWillTransitionToSize:withTransitionCoordinator:].
                 */
                let statusBarOrientation = UIApplication.shared.statusBarOrientation
                var initialVideoOrientation = AVCaptureVideoOrientation.portrait
                if statusBarOrientation != UIInterfaceOrientation.unknown {
                    initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                }
                
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                previewLayer.connection?.videoOrientation = initialVideoOrientation
            }
        } else {
            NSLog("Could not add video device input to the session")
            self.setupResult = .sessionConfigurationFailed
            self.session.commitConfiguration()
            return
        }
        
        // Add audio input
        let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
        let audioDeviceInput: AVCaptureDeviceInput!
        do {
            audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
        } catch let error {
            audioDeviceInput = nil
            NSLog("Could not create audio device input: \(error)")
        }
        if self.session.canAddInput(audioDeviceInput) {
            self.session.addInput(audioDeviceInput)
        } else {
            NSLog("Could not add audio device input to the session")
        }
        
        if #available(iOS 10.0, *) {
            // Add photo output
            let photoOutput = AVCapturePhotoOutput()
            if self.session.canAddOutput(photoOutput) {
                self.session.addOutput(photoOutput)
                self.photoOutput = photoOutput
                photoOutput.isHighResolutionCaptureEnabled = true
                
                self.inProgressPhotoCaptureDelegates = [:]
            } else {
                NSLog("Could not add photo output to the session")
                self.setupResult = .sessionConfigurationFailed
                self.session.commitConfiguration()
                return
            }
        } else {
            let movieFileOutput = AVCaptureMovieFileOutput()
            if self.session.canAddOutput(movieFileOutput) {
                self.session.addOutput(movieFileOutput)
                if let connection = movieFileOutput.connection(with: AVMediaType.video), connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                NSLog("Could not add movie file output to the session")
                self.setupResult = .sessionConfigurationFailed
                self.session.commitConfiguration()
                return
            }
            
            let stillImageOutput = AVCaptureStillImageOutput()
            if self.session.canAddOutput(stillImageOutput) {
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
                self.stillImageOutput!.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                self.stillImageOutput!.isHighResolutionStillImageOutputEnabled = true
            } else {
                NSLog("Could not add still image output to the session")
                self.setupResult = .sessionConfigurationFailed
                self.session.commitConfiguration()
                return
            }
        }
        
        // We will not create an AVCaptureMovieFileOutput when configuring the session because the AVCaptureMovieFileOutput does not support movie recording with AVCaptureSessionPresetPhoto
        self.backgroundRecordingID = UIBackgroundTaskInvalid
        
        self.session.commitConfiguration()
        
        DispatchQueue.main.async {
            self.configureManualHUD()
        }
    }
    
    // Should be called on the main queue
    @available(iOS 10.0, *)
    private func currentPhotoSettings() -> AVCapturePhotoSettings? {
        guard let photoOutput = self.photoOutput else {
            return nil
        }
        let lensStabilizationEnabled = self.lensStabilizationControl.selectedSegmentIndex == 1
        let rawEnabled = self.rawControl.selectedSegmentIndex == 1
        var photoSettings: AVCapturePhotoSettings? = nil
        
        if lensStabilizationEnabled && photoOutput.isLensStabilizationDuringBracketedCaptureSupported {
            let bracketedSettings: [AVCaptureBracketedStillImageSettings]
            if self.videoDevice?.exposureMode == .custom {
                bracketedSettings = [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(exposureDuration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO)]
            } else {
                bracketedSettings = [AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: AVCaptureDevice.currentExposureTargetBias)]
            }
            
            if rawEnabled && !photoOutput.__availableRawPhotoPixelFormatTypes.isEmpty {
                photoSettings = AVCapturePhotoBracketSettings(rawPixelFormatType: photoOutput.__availableRawPhotoPixelFormatTypes[0].uint32Value, processedFormat: nil, bracketedSettings: bracketedSettings)
            } else {
                photoSettings = AVCapturePhotoBracketSettings(rawPixelFormatType: 0, processedFormat: [AVVideoCodecKey: AVVideoCodecJPEG], bracketedSettings: bracketedSettings)
            }
            
            (photoSettings as! AVCapturePhotoBracketSettings).isLensStabilizationEnabled = true
        } else {
            if rawEnabled && !photoOutput.__availableRawPhotoPixelFormatTypes.isEmpty {
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: photoOutput.__availableRawPhotoPixelFormatTypes[0].uint32Value, processedFormat: [AVVideoCodecKey : AVVideoCodecJPEG])
            } else {
                photoSettings = AVCapturePhotoSettings()
            }
            
            // We choose not to use flash when doing manual exposure
            if self.videoDevice?.exposureMode == .custom {
                photoSettings?.flashMode = .off
            } else {
                photoSettings?.flashMode = photoOutput.__supportedFlashModes.contains(AVCaptureDevice.FlashMode.auto.rawValue as NSNumber) ? .auto : .off
            }
        }
        
        //### `availablePreviewPhotoPixelFormatTypes` is temporarily renamed to `__availablePreviewPhotoPixelFormatTypes`,
        //### Maybe more Swiftish refinement is planned, but not yet completed.
        if !(photoSettings?.__availablePreviewPhotoPixelFormatTypes.isEmpty ?? true) {
            photoSettings?.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings!.__availablePreviewPhotoPixelFormatTypes[0]] // The first format in the array is the preferred format
        }
        
        if self.videoDevice?.exposureMode == .custom {
            photoSettings?.isAutoStillImageStabilizationEnabled = true
        }
        
        photoSettings?.isHighResolutionPhotoEnabled = true
        
        return photoSettings
    }
    
    @IBAction func resumeInterruptedSession(_: AnyObject) {
        self.sessionQueue.async {
            // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running" )
                    let alertController = UIAlertController(title: "AVCamManual", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
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
    
    @IBAction func changeCaptureMode(_ captureModeControl: UISegmentedControl) {
        if captureModeControl.selectedSegmentIndex == AVCamManualCaptureMode.photo.rawValue {
            self.recordButton.isEnabled = false
            
            self.sessionQueue.async {
                // Remove the AVCaptureMovieFileOutput from the session because movie recording is not supported with AVCaptureSessionPresetPhoto. Additionally, Live Photo
                // capture is not supported when an AVCaptureMovieFileOutput is connected to the session.
                self.session.beginConfiguration()
                self.session.removeOutput(self.movieFileOutput!)
                self.session.sessionPreset = AVCaptureSession.Preset.photo
                self.session.commitConfiguration()
                
                self.movieFileOutput = nil
            }
        } else if captureModeControl.selectedSegmentIndex == AVCamManualCaptureMode.movie.rawValue {
            
            self.sessionQueue.async {
                let movieFileOutput = AVCaptureMovieFileOutput()
                
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.beginConfiguration()
                    self.session.addOutput(movieFileOutput)
                    self.session.sessionPreset = AVCaptureSession.Preset.high
                    let connection = movieFileOutput.connection(with: AVMediaType.video)
                    if connection?.isVideoStabilizationSupported ?? false {
                        connection?.preferredVideoStabilizationMode = .auto
                    }
                    self.session.commitConfiguration()
                    
                    self.movieFileOutput = movieFileOutput
                    
                    DispatchQueue.main.async {
                        self.recordButton.isEnabled = true
                    }
                }
            }
        }
    }
    
    //MARK: Device Configuration
    
    @IBAction func chooseNewCamera(_: Any) {
        if #available(iOS 10.0, *) {
            chooseNewCamera()
        } else {
            changeCamera()
        }
    }
    @available(iOS 10.0, *)
    private func chooseNewCamera() {
        // Present all available cameras
        let cameraOptionsController = UIAlertController(title: "Choose a camera", message: nil, preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        cameraOptionsController.addAction(cancelAction)
        for device in self.videoDeviceDiscoverySession?.devices ?? [] {
            let newDeviceOption = UIAlertAction(title: device.localizedName, style: .default) {action in
                self.changeCameraWithDevice(device)
            }
            cameraOptionsController.addAction(newDeviceOption)
        }
        
        self.present(cameraOptionsController, animated: true, completion: nil)
    }
    
    private func changeCameraWithDevice(_ newVideoDevice: AVCaptureDevice) {
        // Check if device changed
        if newVideoDevice === self.videoDevice {
            return
        }
        
        self.manualHUD.isUserInteractionEnabled = false
        self.cameraButton.isEnabled = false
        self.recordButton.isEnabled = false
        self.photoButton.isEnabled = false
        self.captureModeControl.isEnabled = false
        self.HUDButton.isEnabled = false
        
        self.sessionQueue.async {
            let newVideoDeviceInput = try! AVCaptureDeviceInput(device: newVideoDevice)
            
            self.session.beginConfiguration()
            
            // Remove the existing device input first, since using the front and back camera simultaneously is not supported
            self.session.removeInput(self.videoDeviceInput!)
            if self.session.canAddInput(newVideoDeviceInput) {
                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: self.videoDevice)
                
                NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: newVideoDevice)
                
                self.session.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
                self.videoDevice = newVideoDevice
            } else {
                self.session.addInput(self.videoDeviceInput!)
            }
            
            let connection = self.movieFileOutput?.connection(with: AVMediaType.video)
            if connection?.isVideoStabilizationSupported ?? false {
                connection!.preferredVideoStabilizationMode = .auto
            }
            
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.configureManualHUD()
                
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = self.captureModeControl.selectedSegmentIndex == AVCamManualCaptureMode.movie.rawValue
                self.photoButton.isEnabled = true
                self.captureModeControl.isEnabled = true
                self.HUDButton.isEnabled = true
                self.manualHUD.isUserInteractionEnabled = true
            }
        }
    }
    
    @IBAction func changeFocusMode(_ control: UISegmentedControl) {
        let mode = self.focusModes[control.selectedSegmentIndex]
        
        do {
            try self.videoDevice!.lockForConfiguration()
            if self.videoDevice!.isFocusModeSupported(mode) {
                self.videoDevice!.focusMode = mode
            } else {
                NSLog("Focus mode %@ is not supported. Focus mode is %@.", mode.description, self.videoDevice!.focusMode.description)
                self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: self.videoDevice!.focusMode)!
            }
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeLensPosition(_ control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setFocusModeLocked(lensPosition: control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    private func focusWithMode(_ focusMode: AVCaptureDevice.FocusMode, exposeWithMode exposureMode: AVCaptureDevice.ExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        guard let device = self.videoDevice else {
            print("videoDevice unavailable")
            return
        }
        self.sessionQueue.async {
            
            do {
                try device.lockForConfiguration()
                // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                if focusMode != .locked && device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = point
                    device.focusMode = focusMode
                }
                
                if exposureMode != .custom && device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch let error {
                NSLog("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    @IBAction func focusAndExposeTap(_ gestureRecognizer: UIGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        self.focusWithMode(.continuousAutoFocus, exposeWithMode: .continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }
    
    @IBAction func changeExposureMode(_ control: UISegmentedControl) {
        let mode = self.exposureModes[control.selectedSegmentIndex]
        
        do {
            try self.videoDevice!.lockForConfiguration()
            if self.videoDevice!.isExposureModeSupported(mode) {
                self.videoDevice!.exposureMode = mode
            } else {
                NSLog("Exposure mode %@ is not supported. Exposure mode is %@.", mode.description, self.videoDevice!.exposureMode.description)
                self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: self.videoDevice!.exposureMode)!
            }
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeExposureDuration(_ control: UISlider) {
        
        let p = pow(Double(control.value), kExposureDurationPower) // Apply power function to expand slider's low-end range
        let minDurationSeconds = max(CMTimeGetSeconds(self.videoDevice!.activeFormat.minExposureDuration), kExposureMinimumDuration)
        let maxDurationSeconds = CMTimeGetSeconds(self.videoDevice!.activeFormat.maxExposureDuration)
        let newDurationSeconds = p * ( maxDurationSeconds - minDurationSeconds ) + minDurationSeconds; // Scale from 0-1 slider range to actual duration
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureModeCustom(duration: CMTimeMakeWithSeconds(newDurationSeconds, 1000*1000*1000), iso: AVCaptureDevice.currentISO, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeISO(_ control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeExposureTargetBias(_ control: UISlider) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            self.videoDevice!.setExposureTargetBias(control.value, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeWhiteBalanceMode(_ control: UISegmentedControl) {
        let mode = self.whiteBalanceModes[control.selectedSegmentIndex]
        
        do {
            try self.videoDevice!.lockForConfiguration()
            if self.videoDevice!.isWhiteBalanceModeSupported(mode) {
                self.videoDevice!.whiteBalanceMode = mode
            } else {
                NSLog("White balance mode %@ is not supported. White balance mode is %@.", mode.description, self.videoDevice!.whiteBalanceMode.description)
                self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: self.videoDevice!.whiteBalanceMode)!
            }
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    private func setWhiteBalanceGains(_ gains: AVCaptureDevice.WhiteBalanceGains) {
        
        do {
            try self.videoDevice!.lockForConfiguration()
            let normalizedGains = self.normalizedGains(gains) // Conversion can yield out-of-bound values, cap to limits
            self.videoDevice!.setWhiteBalanceModeLocked(with: normalizedGains, completionHandler: nil)
            self.videoDevice!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeTemperature(_: AnyObject) {
        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGains(for: temperatureAndTint))
    }
    
    @IBAction func changeTint(_: AnyObject) {
        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoDevice!.deviceWhiteBalanceGains(for: temperatureAndTint))
    }
    
    @IBAction func lockWithGrayWorld(_: AnyObject) {
        self.setWhiteBalanceGains(self.videoDevice!.grayWorldDeviceWhiteBalanceGains)
    }
    
    private func normalizedGains(_ gains: AVCaptureDevice.WhiteBalanceGains) -> AVCaptureDevice.WhiteBalanceGains {
        var g = gains
        
        g.redGain = max(1.0, g.redGain)
        g.greenGain = max(1.0, g.greenGain)
        g.blueGain = max(1.0, g.blueGain)
        
        g.redGain = min(self.videoDevice!.maxWhiteBalanceGain, g.redGain)
        g.greenGain = min(self.videoDevice!.maxWhiteBalanceGain, g.greenGain)
        g.blueGain = min(self.videoDevice!.maxWhiteBalanceGain, g.blueGain)
        
        return g
    }
    
    //MARK: Capturing Photos
    
    @IBAction func capturePhoto(_: Any) {
        if #available(iOS 10.0, *) {
            self.capturePhoto()
        } else {
            self.snapStillImage()
        }
    }
    @available(iOS 10.0, *)
    private func capturePhoto() {
        // Retrieve the video preview layer's video orientation on the main queue before entering the session queue
        // We do this to ensure UI elements are accessed on the main thread and session configuration is done on the session queue
        let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
        let videoPreviewLayerVideoOrientation = previewLayer.connection?.videoOrientation
        
        let settings = self.currentPhotoSettings()
        self.sessionQueue.async {
            
            // Update the orientation on the photo output video connection before capturing
            let photoOutputConnection = self.photoOutput?.connection(with: .video)
            photoOutputConnection?.videoOrientation = videoPreviewLayerVideoOrientation!
            
            // Use a separate object for the photo capture delegate to isolate each capture life cycle.
            let photoCaptureDelegate = AVCamManualPhotoCaptureDelegate(requestedPhotoSettings: settings!, willCapturePhotoAnimation: {
                // Perform a shutter animation.
                DispatchQueue.main.async {
                    self.previewView.layer.opacity = 0.0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.layer.opacity = 1.0
                    }
                }
            }, completed: {photoCaptureDelegate in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = nil
                }
            })
            
            /*
             The Photo Output keeps a weak reference to the photo capture delegate so
             we store it in an array to maintain a strong reference to this object
             until the capture is completed.
             */
            self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = photoCaptureDelegate
            self.photoOutput?.capturePhoto(with: settings!, delegate: photoCaptureDelegate)
        }
    }
    
    //MARK: Recording Movies
    
    @IBAction func toggleMovieRecording(_: Any) {
        // Disable the Camera button until recording finishes, and disable the Record button until recording starts or finishes (see the AVCaptureFileOutputRecordingDelegate methods)
        self.cameraButton.isEnabled = false
        self.recordButton.isEnabled = false
        self.captureModeControl.isEnabled = false
        
        // Retrieve the video preview layer's video orientation on the main queue before entering the session queue. We do this to ensure UI
        // elements are accessed on the main thread and session configuration is done on the session queue.
        let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
        let previewLayerVideoOrientation = previewLayer.connection?.videoOrientation
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
                let movieConnection = self.movieFileOutput?.connection(with: AVMediaType.video)
                movieConnection?.videoOrientation = previewLayerVideoOrientation!
                
                // Start recording to temporary file
                let outputFileName = ProcessInfo.processInfo.globallyUniqueString
                let outputFileURL: URL
                if #available(iOS 10.0, *) {
                    outputFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName).appendingPathExtension("mov")
                } else {
                    outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(outputFileName).appendingPathExtension("mov")
                }
                self.movieFileOutput!.startRecording(to: outputFileURL, recordingDelegate: self)
            } else {
                self.movieFileOutput!.stopRecording()
            }
        }
    }
    
    func fileOutput(_ captureOutput: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Enable the Record button to let the user stop the recording.
        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), for: .normal)
        }
    }
    
    func fileOutput(_ captureOutput: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
        // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
        // is back to NO — which happens sometime after this method returns.
        // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
        let currentBackgroundRecordingID = self.backgroundRecordingID
        self.backgroundRecordingID = UIBackgroundTaskInvalid
        
        let cleanup: ()->() = {
            if FileManager.default.fileExists(atPath: outputFileURL.path) {
                do {
                    try FileManager.default.removeItem(at: outputFileURL)
                } catch _ {}
            }
            
            if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        
        var success = true
        
        if error != nil {
            NSLog("Error occurred while capturing movie: \(error!)")
            success = (error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
        }
        if success {
            // Check authorization status.
            PHPhotoLibrary.requestAuthorization {status in
                guard status == .authorized else {
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
                        changeRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    } else {
                        //### Error occurred while capturing movie
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                    }
                }, completionHandler: {success, error in
                    if !success {
                        NSLog("Could not save movie to photo library: \(error!)")
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
            if #available(iOS 10.0, *) {
                self.cameraButton.isEnabled = (self.videoDeviceDiscoverySession?.devices.count ?? 0 > 1)
            } else {
                self.cameraButton.isEnabled = (AVCaptureDevice.devices(for: AVMediaType.video).count > 1)
            }
            self.recordButton.isEnabled = self.captureModeControl.selectedSegmentIndex == AVCamManualCaptureMode.movie.rawValue
            self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), for: .normal)
            self.captureModeControl.isEnabled = true
        }
    }
    
    //MARK: KVO and Notifications
    
    private func addObservers() {
        self.addObserver(self, forKeyPath: "session.running", options: .new, context: &SessionRunningContext)
        self.addObserver(self, forKeyPath: "videoDevice.focusMode", options: [.old, .new], context: &FocusModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.lensPosition", options: .new, context: &LensPositionContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureMode", options: [.old, .new], context: &ExposureModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureDuration", options: .new, context: &ExposureDurationContext)
        self.addObserver(self, forKeyPath: "videoDevice.ISO", options: .new, context: &ISOContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureTargetBias", options: .new, context: &ExposureTargetBiasContext)
        self.addObserver(self, forKeyPath: "videoDevice.exposureTargetOffset", options: .new, context: &ExposureTargetOffsetContext)
        self.addObserver(self, forKeyPath: "videoDevice.whiteBalanceMode", options: [.old, .new], context: &WhiteBalanceModeContext)
        self.addObserver(self, forKeyPath: "videoDevice.deviceWhiteBalanceGains", options: .new, context: &DeviceWhiteBalanceGainsContext)
        
        if #available(iOS 10.0, *) {
        } else {
            self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options: .new, context: &CapturingStillImageContext)
            self.addObserver(self, forKeyPath: "stillImageOutput.lensStabilizationDuringBracketedCaptureEnabled", options: [.old, .new], context: &LensStabilizationContext)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: self.videoDevice!)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: self.session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        if #available(iOS 9.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: .AVCaptureSessionWasInterrupted, object: self.session)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: .AVCaptureSessionInterruptionEnded, object: self.session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        self.removeObserver(self, forKeyPath: "session.running", context: &SessionRunningContext)
        self.removeObserver(self, forKeyPath: "videoDevice.focusMode", context: &FocusModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.lensPosition", context: &LensPositionContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureMode", context: &ExposureModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureDuration", context: &ExposureDurationContext)
        self.removeObserver(self, forKeyPath: "videoDevice.ISO", context: &ISOContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureTargetBias", context: &ExposureTargetBiasContext)
        self.removeObserver(self, forKeyPath: "videoDevice.exposureTargetOffset", context: &ExposureTargetOffsetContext)
        self.removeObserver(self, forKeyPath: "videoDevice.whiteBalanceMode", context: &WhiteBalanceModeContext)
        self.removeObserver(self, forKeyPath: "videoDevice.deviceWhiteBalanceGains", context: &DeviceWhiteBalanceGainsContext)
        
        if #available(iOS 10.0, *) {
        } else {
            self.removeObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", context: &CapturingStillImageContext)
            self.removeObserver(self, forKeyPath: "stillImageOutput.lensStabilizationDuringBracketedCaptureEnabled", context: &LensStabilizationContext)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let oldValue = change![.oldKey]
        let newValue = change![.newKey]
        
        guard let context = context else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: nil)
            return
        }
        switch context {
        case &FocusModeContext:
            if let value = newValue as? Int {
                let newMode = AVCaptureDevice.FocusMode(rawValue: value)!
                DispatchQueue.main.async {
                    self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: newMode)!
                    self.lensPositionSlider.isEnabled = (newMode == .locked)
                    
                    if let old = oldValue as? Int {
                        let oldMode = AVCaptureDevice.FocusMode(rawValue: old)!
                        NSLog("focus mode: \(oldMode) -> \(newMode)")
                    } else {
                        NSLog("focus mode: \(newMode)")
                    }
                }
            }
        case &LensPositionContext:
            if let value = newValue as? Float {
                let focusMode = self.videoDevice!.focusMode
                let newLensPosition = value
                
                DispatchQueue.main.async {
                    if focusMode != .locked {
                        self.lensPositionSlider.value = newLensPosition
                    }
                    
                    self.lensPositionValueLabel.text = String(format: "%.1f", Double(newLensPosition))
                }
            }
        case &ExposureModeContext:
            if let value = newValue as? Int {
                let newMode = AVCaptureDevice.ExposureMode(rawValue: value)!
                if let old = oldValue as? Int {
                    let oldMode = AVCaptureDevice.ExposureMode(rawValue: old)!
                    /*
                     It’s important to understand the relationship between exposureDuration and the minimum frame rate as represented by activeVideoMaxFrameDuration.
                     In manual mode, if exposureDuration is set to a value that's greater than activeVideoMaxFrameDuration, then activeVideoMaxFrameDuration will
                     increase to match it, thus lowering the minimum frame rate. If exposureMode is then changed to automatic mode, the minimum frame rate will
                     remain lower than its default. If this is not the desired behavior, the min and max frameRates can be reset to their default values for the
                     current activeFormat by setting activeVideoMaxFrameDuration and activeVideoMinFrameDuration to kCMTimeInvalid.
                     */
                    if oldMode != newMode && oldMode == .custom {
                        do {
                            try self.videoDevice!.lockForConfiguration()
                            defer {self.videoDevice!.unlockForConfiguration()}
                            self.videoDevice!.activeVideoMaxFrameDuration = kCMTimeInvalid
                            self.videoDevice!.activeVideoMinFrameDuration = kCMTimeInvalid
                        } catch let error {
                            NSLog("Could not lock device for configuration: \(error)")
                        }
                    }
                }
                DispatchQueue.main.async {
                    
                    self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: newMode)!
                    self.exposureDurationSlider.isEnabled = (newMode == .custom)
                    self.ISOSlider.isEnabled = (newMode == .custom)
                    
                    if let old = oldValue as? Int {
                        let oldMode = AVCaptureDevice.ExposureMode(rawValue: old)!
                        NSLog("exposure mode: \(oldMode) -> \(newMode)")
                    } else {
                        NSLog("exposure mode: \(newMode)")
                    }
                }
            }
        case &ExposureDurationContext:
            // Map from duration to non-linear UI range 0-1
            
            if let value = newValue as? CMTime {
                let newDurationSeconds = CMTimeGetSeconds(value)
                let exposureMode = self.videoDevice!.exposureMode
                
                let minDurationSeconds = max(CMTimeGetSeconds(self.videoDevice!.activeFormat.minExposureDuration), kExposureMinimumDuration)
                let maxDurationSeconds = CMTimeGetSeconds(self.videoDevice!.activeFormat.maxExposureDuration)
                // Map from duration to non-linear UI range 0-1
                let p = (newDurationSeconds - minDurationSeconds) / (maxDurationSeconds - minDurationSeconds) // Scale to 0-1
                DispatchQueue.main.async {
                    if exposureMode != .custom {
                        self.exposureDurationSlider.value = Float(pow(p, 1 / self.kExposureDurationPower)) // Apply inverse power
                    }
                    if newDurationSeconds < 1 {
                        let digits = max(0, 2 + Int(floor(log10(newDurationSeconds))))
                        self.exposureDurationValueLabel.text = String(format: "1/%.*f", digits, 1/newDurationSeconds)
                    } else {
                        self.exposureDurationValueLabel.text = String(format: "%.2f", newDurationSeconds)
                    }
                }
            }
        case &ISOContext:
            if let value = newValue as? Float {
                let newISO = value
                let exposureMode = self.videoDevice!.exposureMode
                
                DispatchQueue.main.async {
                    if exposureMode != .custom {
                        self.ISOSlider.value = newISO
                    }
                    self.ISOValueLabel.text = String(Int(newISO))
                }
            }
        case &ExposureTargetBiasContext:
            if let value = newValue as? Float {
                let newExposureTargetBias = value
                DispatchQueue.main.async {
                    self.exposureTargetBiasValueLabel.text = String(format: "%.1f", Double(newExposureTargetBias))
                }
            }
        case &ExposureTargetOffsetContext:
            if let value = newValue as? Float {
                let newExposureTargetOffset = value
                DispatchQueue.main.async {
                    self.exposureTargetOffsetSlider.value = newExposureTargetOffset
                    self.exposureTargetOffsetValueLabel.text = String(format: "%.1f", Double(newExposureTargetOffset))
                }
            }
        case &WhiteBalanceModeContext:
            if let value = newValue as? Int {
                let newMode = AVCaptureDevice.WhiteBalanceMode(rawValue: value)!
                DispatchQueue.main.async {
                    self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: newMode)!
                    self.temperatureSlider.isEnabled = (newMode == .locked)
                    self.tintSlider.isEnabled = (newMode == .locked)
                    
                    if let old = oldValue as? Int {
                        let oldMode = AVCaptureDevice.WhiteBalanceMode(rawValue: old)!
                        NSLog("white balance mode: \(oldMode) -> \(newMode)")
                    }
                }
            }
        case &DeviceWhiteBalanceGainsContext:
            if let value = newValue as? NSValue {
                var newGains = AVCaptureDevice.WhiteBalanceGains()
                value.getValue(&newGains)
                
                let newTemperatureAndTint = self.videoDevice!.temperatureAndTintValues(for: newGains)
                let whiteBalanceMode = self.videoDevice!.whiteBalanceMode
                DispatchQueue.main.async {
                    if whiteBalanceMode != .locked {
                        self.temperatureSlider.value = newTemperatureAndTint.temperature
                        self.tintSlider.value = newTemperatureAndTint.tint
                    }
                    
                    self.temperatureValueLabel.text = String(Int(newTemperatureAndTint.temperature))
                    self.tintValueLabel.text = String(Int(newTemperatureAndTint.tint))
                }
            }
        case &SessionRunningContext:
            var isRunning = false
            if let value = newValue as? Bool {
                isRunning = value
            }
            
            DispatchQueue.main.async {
                if #available(iOS 10.0, *) {
                    self.cameraButton.isEnabled = isRunning && (self.videoDeviceDiscoverySession?.devices.count ?? 0 > 1)
                } else {
                    self.cameraButton.isEnabled = (isRunning && AVCaptureDevice.devices(for: AVMediaType.video).count > 1)
                }
                self.recordButton.isEnabled = isRunning && (self.captureModeControl.selectedSegmentIndex == AVCamManualCaptureMode.movie.rawValue)
                self.photoButton.isEnabled = isRunning
                self.HUDButton.isEnabled = isRunning
                self.captureModeControl.isEnabled = isRunning
            }
        case &CapturingStillImageContext:
            if #available(iOS 10.0, *) {
            } else {
                var isCapturingStillImage = false
                if let value = newValue as? Bool {
                    isCapturingStillImage = value
                }
                
                if isCapturingStillImage {
                    DispatchQueue.main.async {
                        self.previewView.layer.opacity = 0.0
                        UIView.animate(withDuration: 0.25, animations: {
                            self.previewView.layer.opacity = 1.0
                        })
                    }
                }
            }
        case &LensStabilizationContext:
            if #available(iOS 10.0, *) {
            } else {
                if let value = newValue as? Bool {
                    let newMode = value
                    self.lensStabilizationControl.selectedSegmentIndex = (newMode ? 1 : 0)
                    if let old = oldValue as? Bool {
                        let oldMode = old
                        NSLog("Lens stabilization: %@ -> %@", (oldMode ? "YES" : "NO"), (newMode ? "YES" : "NO"))
                    }
                }
            }
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc func subjectAreaDidChange(_ notificaiton: Notification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(.continuousAutoFocus, exposeWithMode: .continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo![AVCaptureSessionErrorKey]! as! NSError
        NSLog("Capture session runtime error: %@", error)
        
        if error.code == AVError.Code.mediaServicesWereReset.rawValue {
            self.sessionQueue.async {
                // If we aren't trying to resume the session, try to restart it, since it must have been stopped due to an error (see -[resumeInterruptedSession:])
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
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
    
    @objc @available(iOS 9.0, *)
    func sessionWasInterrupted(_ notification: Notification) {
        // In some scenarios we want to enable the user to restart the capture session.
        // For example, if music playback is initiated via Control Center while using AVCamManual,
        // then the user can let AVCamManual resume the session running, which will stop music playback.
        // Note that stopping music playback in Control Center will not automatically resume the session.
        // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
        // In iOS 9 and later, the notification's userInfo dictionary contains information about why the session was interrupted
        let reason = AVCaptureSession.InterruptionReason(rawValue: notification.userInfo![AVCaptureSessionInterruptionReasonKey]! as! Int)!
        NSLog("Capture session was interrupted with reason %ld", reason.rawValue)
        
        if reason == .audioDeviceInUseByAnotherClient ||
            reason == .videoDeviceInUseByAnotherClient {
            // Simply fade-in a button to enable the user to try to resume the session running.
            self.resumeButton.isHidden = false
            self.resumeButton.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.resumeButton.alpha = 1.0
            })
        } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
            // Simply fade-in a label to inform the user that the camera is unavailable.
            self.cameraUnavailableLabel.isHidden = false
            self.cameraUnavailableLabel.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.cameraUnavailableLabel.alpha = 1.0
            })
        }
    }
    
    @objc func sessionInterruptionEnded(_ notification: Notification) {
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
    
    //MARK: ### Compatibility
    
    @available(iOS, deprecated: 10.0)
    private func changeCamera() {
        self.cameraButton.isEnabled = false
        self.recordButton.isEnabled = false
        //        self.stillButton.isEnabled = false
        self.photoButton.isEnabled = false
        
        self.sessionQueue.async {
            var preferredPosition = AVCaptureDevice.Position.unspecified
            
            switch self.videoDevice!.position {
            case .unspecified,
                 .front:
                preferredPosition = .back
            case .back:
                preferredPosition = .front
            }
            
            let newVideoDevice = AVCamManualCameraViewController.deviceWithMediaType(AVMediaType.video.rawValue, preferringPosition: preferredPosition)
            let newVideoDeviceInput: AVCaptureDeviceInput!
            do {
                newVideoDeviceInput = try AVCaptureDeviceInput(device: newVideoDevice!)
            } catch _ {
                newVideoDeviceInput = nil
            }
            
            self.session.beginConfiguration()
            
            // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
            self.session.removeInput(self.videoDeviceInput!)
            if self.session.canAddInput(newVideoDeviceInput) {
                NotificationCenter.default.removeObserver(self,
                                                          name: .AVCaptureDeviceSubjectAreaDidChange, object: self.videoDevice)
                
                NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: newVideoDevice)
                
                self.session.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
                self.videoDevice = newVideoDevice
            } else {
                self.session.addInput(self.videoDeviceInput!)
            }
            
            let connection = self.movieFileOutput!.connection(with: AVMediaType.video)
            if (connection?.isVideoStabilizationSupported)! {
                connection?.preferredVideoStabilizationMode = .auto
            }
            
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = true
                //                self.stillButton.isEnabled = true
                self.photoButton.isEnabled = true
                
                self.configureManualHUD()
            }
        }
    }
    
    @available(iOS, deprecated: 10.0)
    private class func deviceWithMediaType(_ mediaType: String, preferringPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(for: AVMediaType(rawValue: mediaType)) 
        var captureDevice = devices.first
        
        for device in devices {
            if device.position == position {
                captureDevice = device
                break
            }
        }
        
        return captureDevice
    }
    
    @available(iOS, deprecated: 10.0)
    private func snapStillImage() {
        self.sessionQueue.async {
            let stillImageConnection = self.stillImageOutput!.connection(with: AVMediaType.video)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            // Update the orientation on the still image output video connection before capturing.
            stillImageConnection?.videoOrientation = (previewLayer.connection?.videoOrientation)!
            
            // Flash set to Auto for Still Capture
            if self.videoDevice!.exposureMode == .custom {
                AVCamManualCameraViewController.setFlashMode(.off, forDevice: self.videoDevice!)
            } else {
                AVCamManualCameraViewController.setFlashMode(.auto, forDevice: self.videoDevice!)
            }
            
            let lensStabilizationEnabled: Bool
            if #available(iOS 9.0, *) {
                lensStabilizationEnabled = self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled
            } else {
                lensStabilizationEnabled = false
            }
            if !lensStabilizationEnabled {
                // Capture a still image
                self.stillImageOutput?.captureStillImageAsynchronously(from: self.stillImageOutput!.connection(with: AVMediaType.video)!) {imageDataSampleBuffer, error in
                    
                    if error != nil {
                        NSLog("Error capture still image \(error!)")
                    } else if imageDataSampleBuffer != nil {
                        let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer!)!
                        
                        PHPhotoLibrary.requestAuthorization {status in
                            if status == PHAuthorizationStatus.authorized {
                                if #available(iOS 9.0, *) {
                                    PHPhotoLibrary.shared().performChanges({
                                        PHAssetCreationRequest.forAsset().addResource(with: PHAssetResourceType.photo, data: imageData, options: nil)
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occured while saving image to photo library: \(error!)")
                                        }
                                    })
                                } else {
                                    let temporaryFileURL: URL
                                    if #available(iOS 10.0, *) {
                                        temporaryFileURL = FileManager.default
                                            .temporaryDirectory
                                            .appendingPathComponent(ProcessInfo().globallyUniqueString)
                                            .appendingPathExtension("jpg")
                                    } else {
                                        let temporaryFileName = ProcessInfo().globallyUniqueString as NSString
                                        let temporaryFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(temporaryFileName.appendingPathExtension("jpg")!)
                                        temporaryFileURL = URL(fileURLWithPath: temporaryFilePath)
                                    }
                                    
                                    PHPhotoLibrary.shared().performChanges({
                                        do {
                                            try imageData.write(to: temporaryFileURL, options: .atomicWrite)
                                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: temporaryFileURL)
                                        } catch let error {
                                            NSLog("Error occured while writing image data to a temporary file: \(error)")
                                        }
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occurred while saving image to photo library: \(error!)")
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
                    if self.videoDevice!.exposureMode == .custom {
                        bracketSettings = [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(exposureDuration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO)]
                    } else {
                        bracketSettings = [AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: AVCaptureDevice.currentExposureTargetBias)];
                    }
                    
                    self.stillImageOutput!.captureStillImageBracketAsynchronously(from: self.stillImageOutput!.connection(with: AVMediaType.video)!,
                                                                                  withSettingsArray: bracketSettings
                        
                    ) {imageDataSampleBuffer, stillImageSettings, error in
                        if error != nil {
                            NSLog("Error bracketing capture still image \(error!)")
                        } else if imageDataSampleBuffer != nil {
                            NSLog("Lens Stabilization State: \(CMGetAttachment(imageDataSampleBuffer!, kCMSampleBufferAttachmentKey_StillImageLensStabilizationInfo, nil)!)")
                            let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer!)
                            
                            PHPhotoLibrary.requestAuthorization {status in
                                if status == PHAuthorizationStatus.authorized {
                                    PHPhotoLibrary.shared().performChanges({
                                        PHAssetCreationRequest.forAsset().addResource(with: PHAssetResourceType.photo, data: imageData!, options: nil)
                                    }, completionHandler: {success, error in
                                        if !success {
                                            NSLog("Error occured while saving image to photo library: \(error!)")
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
    
    @available(iOS, deprecated: 10.0)
    class func setFlashMode(_ flashMode: AVCaptureDevice.FlashMode, forDevice device: AVCaptureDevice) {
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } catch let error {
                NSLog("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    @available(iOS 9.0, *)
    @IBAction func changeLensStabilization(_ control: UISegmentedControl) {
        if #available(iOS 10.0, *) {
            return
        }
        let lensStabilizationDuringBracketedCaptureEnabled = (control.selectedSegmentIndex != 0)
        if lensStabilizationDuringBracketedCaptureEnabled {
            self.photoButton.isEnabled = false
        }
        self.sessionQueue.async {
            if self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureSupported {
                if lensStabilizationDuringBracketedCaptureEnabled {
                    // Still image capture will be done with the bracketed capture API.
                    self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled = true
                    let bracketSettings: [AVCaptureBracketedStillImageSettings]
                    if self.videoDevice!.exposureMode == AVCaptureDevice.ExposureMode.custom {
                        bracketSettings = [AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(exposureDuration: AVCaptureDevice.currentExposureDuration, iso: AVCaptureDevice.currentISO)]
                    } else {
                        bracketSettings = [AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: AVCaptureDevice.currentExposureTargetBias)]
                    }
                    self.stillImageOutput!.prepareToCaptureStillImageBracket(from: self.stillImageOutput!.connection(with: AVMediaType.video)!,
                                                                             withSettingsArray: bracketSettings
                    ) {prepared, error in
                        if error != nil {
                            NSLog("Error preparing for bracketed capture \(error!)")
                        }
                        DispatchQueue.main.async {
                            self.photoButton.isEnabled = true
                        }
                    }
                } else {
                    self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled = false
                }
            }
        }
    }
}

//MARK: Utilities

extension AVCaptureDevice.FocusMode: CustomStringConvertible {
    public var description: String {
        var string: String
        
        switch self {
        case .locked:
            string = "Locked"
        case .autoFocus:
            string = "Auto"
        case .continuousAutoFocus:
            string = "ContinuousAuto"
        }
        
        return string
    }
}

extension AVCaptureDevice.ExposureMode: CustomStringConvertible {
    public var description: String {
        var string: String
        
        switch self {
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
}

extension AVCaptureDevice.WhiteBalanceMode: CustomStringConvertible {
    public var description: String {
        var string: String
        
        switch self {
        case .locked:
            string = "Locked"
        case .autoWhiteBalance:
            string = "Auto"
        case .continuousAutoWhiteBalance:
            string = "ContinuousAuto"
        }
        
        return string
    }
}
