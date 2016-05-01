//
//  CameraViewController.swift
//  AVCamSample
//
//  Created by Masanori Kuze on 2016/04/18.
//  Copyright © 2016年 Masanori Kuze. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

enum AVCamSetupResult {
    case AVCamSetupResultSuccess
    case AVCamSetupResultCameraNotAuthorized
    case AVCamSetupResultSessionConfigurationFailed
}

private var CapturingStillImageContext = "CaputuringStillImageContext"
private var SessionRunnningContext = "SessionRunningContext"

class CameraViewController : UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    @IBOutlet weak var previewView: Preview!
    @IBOutlet weak var cameraUnavailaleLabel: UILabel!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var stillButton: UIButton!
    
    var sessionQueue : dispatch_queue_t!
    var session : AVCaptureSession!
    var videoDeviceInput : AVCaptureDeviceInput!
    var movieFileOutput : AVCaptureMovieFileOutput!
    var stillImageOutput: AVCaptureStillImageOutput!
    
    var setupResult : AVCamSetupResult =  AVCamSetupResult.AVCamSetupResultSuccess
    var sessionRunning : Bool = false
    var backgroundRecordingID : UIBackgroundTaskIdentifier!
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
//        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        cameraButton.enabled = false
        recordButton.enabled = false
        stillButton.enabled = false
        
        session = AVCaptureSession()
        
        previewView.session = session
        
        sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL)
        
        setupResult = AVCamSetupResult.AVCamSetupResultSuccess
        
        switch (AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)) {
        case AVAuthorizationStatus.Authorized:
            break
        case AVAuthorizationStatus.NotDetermined:
            dispatch_suspend(self.sessionQueue)
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: { (granted) in
                if(!granted){
                    self.setupResult = AVCamSetupResult.AVCamSetupResultCameraNotAuthorized
                }
            })
            break
        default:
            self.setupResult = AVCamSetupResult.AVCamSetupResultCameraNotAuthorized
            break
        }
        
        dispatch_sync(self.sessionQueue ) {
            if(self.setupResult != AVCamSetupResult.AVCamSetupResultSuccess){
                return
            }
            
            self.backgroundRecordingID = UIBackgroundTaskInvalid
            
            let videoDevice : AVCaptureDevice = CameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            
            let videoDeviceInput : AVCaptureDeviceInput?
            do {
                videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            } catch  {
                videoDeviceInput = nil
            }
            
            self.session.beginConfiguration()
            
            if(self.session.canAddInput(videoDeviceInput)){
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                dispatch_async(dispatch_get_main_queue(), {
                    let statusBarOrientation : UIInterfaceOrientation = UIApplication.sharedApplication().statusBarOrientation
                    var initialViedoOrientation : AVCaptureVideoOrientation = AVCaptureVideoOrientation.Portrait
                    if(statusBarOrientation != UIInterfaceOrientation.Unknown) {
                        switch statusBarOrientation {
                        case .LandscapeLeft:
                            initialViedoOrientation = AVCaptureVideoOrientation.LandscapeLeft
                            break
                        case .LandscapeRight:
                            initialViedoOrientation = AVCaptureVideoOrientation.LandscapeRight
                            break
                        case .Portrait:
                            initialViedoOrientation = AVCaptureVideoOrientation.Portrait
                            break
                        case .PortraitUpsideDown:
                            initialViedoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
                            break
                        default:
                            initialViedoOrientation = AVCaptureVideoOrientation.Portrait
                            break
                        }
                    }
                    
                    let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                    previewLayer.connection.videoOrientation = initialViedoOrientation
                })
            } else {
                print("Could not add video input to the session")
                self.setupResult = AVCamSetupResult.AVCamSetupResultSessionConfigurationFailed
            }
            
            let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            var audioDeviceInput : AVCaptureDeviceInput!
            do {
                audioDeviceInput =  try AVCaptureDeviceInput(device: audioDevice)
            } catch {
                audioDeviceInput = nil
                print("Could not create audio device input to the session")
            }
            
            if(self.session.canAddInput(audioDeviceInput)){
                self.session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
            
            let movieFileOutput : AVCaptureMovieFileOutput = AVCaptureMovieFileOutput.init()
            if(self.session.canAddOutput(movieFileOutput)){
                self.session.addOutput(movieFileOutput)
                let connection : AVCaptureConnection = movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                if(connection.supportsVideoStabilization){
                    connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
                }
                self.movieFileOutput = movieFileOutput
            } else {
                print("Could not add movie file output to the session")
                self.setupResult = AVCamSetupResult.AVCamSetupResultSessionConfigurationFailed
            }
            
            let stillImageOutput : AVCaptureStillImageOutput = AVCaptureStillImageOutput.init()
            if(self.session.canAddOutput(stillImageOutput)){
                stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
                self.session.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            } else {
                print("Could not add still image output to the session")
                self.setupResult = AVCamSetupResult.AVCamSetupResultSessionConfigurationFailed
            }
            
            self.session.commitConfiguration()
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        dispatch_async(self.sessionQueue, {
            switch(self.setupResult){
            case .AVCamSetupResultSuccess:
                self.addObservers()
                self.session .startRunning()
                self.sessionRunning = self.session.running
                break
            case .AVCamSetupResultCameraNotAuthorized:
                dispatch_async(dispatch_get_main_queue(), {
                    let message = NSLocalizedString("AVCam dosen't have permision to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let alertController : UIAlertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .Cancel, handler: nil)
                    
                    alertController.addAction(cancelAction)
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .Default, handler: { (action) in
                        UIApplication.sharedApplication().openURL(NSURL.fileURLWithPath(UIApplicationOpenSettingsURLString))
                    })
                    alertController.addAction(settingsAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                })
                break
            case .AVCamSetupResultSessionConfigurationFailed:
                dispatch_async(dispatch_get_main_queue(), {
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .Cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                })
                break
            }
        })
    }
    
    
    override func viewDidDisappear(animated: Bool) {
        dispatch_async(self.sessionQueue, {
            if(self.setupResult == .AVCamSetupResultSuccess){
                self.session.stopRunning()
                self.removeObservers()
            }
        })
        
        super.viewDidDisappear(animated)
    }
    
    //MARK: Orientation
    
    override func shouldAutorotate() -> Bool {
        return !self.movieFileOutput.recording
    }
    
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.All
    }
    
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
        
        let deviceOrientation : UIDeviceOrientation = UIDevice.currentDevice().orientation
        if(UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation)){
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            previewLayer.connection.videoOrientation = { () -> AVCaptureVideoOrientation in
                switch deviceOrientation {
                case .Portrait:
                    return AVCaptureVideoOrientation.Portrait
                case .LandscapeLeft:
                    return AVCaptureVideoOrientation.LandscapeLeft
                case .LandscapeRight:
                    return AVCaptureVideoOrientation.LandscapeRight
                case .PortraitUpsideDown:
                    return AVCaptureVideoOrientation.PortraitUpsideDown
                default:
                    return AVCaptureVideoOrientation.Portrait
                }
                }()
        }
    }
    
    
    // MARK: KVO and Notifications
    
    func addObservers() {
        self.session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.New, context: &SessionRunnningContext)
        self.stillImageOutput.addObserver(self, forKeyPath: "capturingStillImage", options: NSKeyValueObservingOptions.New, context:&CapturingStillImageContext)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.subjectAreaDidChange(_:)), name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: self.videoDeviceInput.device)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.sessionRuntimeError(_:)), name: AVCaptureSessionRuntimeErrorNotification, object: self.session)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.sessionWasInterrupted(_:)), name: AVCaptureSessionWasInterruptedNotification, object: self.session)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.sessionInterruptionEnded(_:)), name: AVCaptureSessionInterruptionEndedNotification, object: self.session)
    }
    
    func removeObservers() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        
        self.session.removeObserver(self, forKeyPath: "runnnig", context: &SessionRunnningContext)
        self.stillImageOutput.removeObserver(self, forKeyPath: "capturingStillImage", context: &CapturingStillImageContext)
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if(context == &CapturingStillImageContext){
            guard let isCapturingStillImage = change![NSKeyValueChangeNewKey]?.boolValue else {
                return
            }
            
            if(isCapturingStillImage) {
                dispatch_async(dispatch_get_main_queue(), {
                    self.previewView.layer.opacity = 0.0
                    UIView.animateWithDuration(0.25, animations: { 
                        self.previewView.layer.opacity = 1.0
                    })
                })
            }
        } else if(context == &SessionRunnningContext){
            guard let isSessionRunning = change![NSKeyValueChangeNewKey]?.boolValue else {
                return
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                self.cameraButton.enabled = isSessionRunning && (AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1)
                self.recordButton.enabled = isSessionRunning
                self.stillButton.enabled = isSessionRunning
            })
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    
    func subjectAreaDidChange(notification : NSNotification){
        let devicePoint = CGPointMake(0.5, 0.5)
        self.focusWithMode(AVCaptureFocusMode.ContinuousAutoFocus, exposeWithMode: AVCaptureExposureMode.ContinuousAutoExposure, atDevicePoint: devicePoint, motiorSubjectAreaChange: false)
    }
    
    
    func sessionRuntimeError(notification : NSNotification){
        print("Capture session runtime error")
        
        guard let error = notification.userInfo![AVCaptureSessionErrorKey] else {
            self.resumeButton.hidden = false
            return
        }
        
        if(error.code == AVError.MediaServicesWereReset.rawValue){
            dispatch_async(self.sessionQueue, {
                if(self.sessionRunning){
                    self.session.startRunning()
                    self.sessionRunning = self.session.running
                } else {
                    dispatch_async(dispatch_get_main_queue(), {
                        self.resumeButton.hidden = false
                    })
                }
            })
        } else {
            self.resumeButton.hidden = false
        }
    }
    
    func sessionWasInterrupted(notification : NSNotification){
        var showResumeButton = false
        
        if #available(iOS 9.0, *){
            if let reason = notification.userInfo![AVCaptureSessionInterruptionReasonKey] where reason is Int {
                if(reason as! Int == AVCaptureSessionInterruptionReason.AudioDeviceInUseByAnotherClient.rawValue || reason as! Int == AVCaptureSessionInterruptionReason.VideoDeviceInUseByAnotherClient.rawValue){
                    showResumeButton = true
                } else if (reason as! Int == AVCaptureSessionInterruptionReason.VideoDeviceNotAvailableWithMultipleForegroundApps.rawValue) {
                    self.cameraUnavailaleLabel.hidden = false
                    self.cameraUnavailaleLabel.alpha = 0.0
                    UIView.animateWithDuration(0.25, animations: {
                        self.cameraUnavailaleLabel.alpha = 1.0
                    })
                }
            }
        } else {
            print("Capture session was interrupted")
            showResumeButton = UIApplication.sharedApplication().applicationState == UIApplicationState.Inactive
        }
    }
    
    func sessionInterruptionEnded(notification : NSNotification){
        print("Capture session interruption ended")
        
        if(!self.resumeButton.hidden){
            UIView.animateWithDuration(0.25, animations: {
                self.resumeButton.alpha = 0.0
                }, completion: { (finished) in
                    self.resumeButton.hidden = true
            })
        }
        if(!self.cameraUnavailaleLabel.hidden){
            UIView.animateWithDuration(0.25, animations: { 
                self.cameraUnavailaleLabel.alpha = 0.0
                }, completion: { (finished) in
                    self.cameraUnavailaleLabel.hidden = true
            })
        }
    }
    
    //MARK: Actions
    
    @IBAction func resumeInterruptedSession(sender: AnyObject) {
        dispatch_async(self.sessionQueue, {
            self.session.startRunning()
            self.sessionRunning = self.session.running
            if(!self.session.running){
                dispatch_async(dispatch_get_main_queue(), {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle:.Alert)
                    let cancleAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .Cancel, handler: nil)
                    alertController.addAction(cancleAction)
                    self.presentViewController(alertController, animated: true, completion: nil)
                })
            } else {
                dispatch_async(dispatch_get_main_queue(), {
                    self.resumeButton.hidden = true
                })
            }
        })
    }
    
    
    @IBAction func toggleMovieRecording(sender: AnyObject) {
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        
        dispatch_async(self.sessionQueue, {
            if(!self.movieFileOutput.recording){
                if(UIDevice.currentDevice().multitaskingSupported){
                    self.backgroundRecordingID = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler(nil)
                }
                
                let connection = self.movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
                connection.videoOrientation = { () -> AVCaptureVideoOrientation in
                    switch previewLayer.connection.videoOrientation {
                    case .Portrait:
                        return AVCaptureVideoOrientation.Portrait
                    case .LandscapeLeft:
                        return AVCaptureVideoOrientation.LandscapeLeft
                    case .LandscapeRight:
                        return AVCaptureVideoOrientation.LandscapeRight
                    case .PortraitUpsideDown:
                        return AVCaptureVideoOrientation.PortraitUpsideDown
                    }
                    }()
                
                CameraViewController.setFlashMode(AVCaptureFlashMode.Off, forDevice: self.videoDeviceInput.device)
                
                let outputFileName : NSString = NSProcessInfo.processInfo().globallyUniqueString
                let outputFilepath = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent(outputFileName.stringByAppendingPathExtension("mov")!)
                self.movieFileOutput.startRecordingToOutputFileURL(outputFilepath, recordingDelegate: self)
            } else {
                self.movieFileOutput.stopRecording()
            }
        })
    }
    
    
    @IBAction func changeCamera(sender: AnyObject) {
        self.cameraButton.enabled = false
        self.recordButton.enabled = false
        self.stillButton.enabled = false
        
        dispatch_async(self.sessionQueue, {
            let currentVideoDevice = self.videoDeviceInput.device
            var preferredPosition = AVCaptureDevicePosition.Unspecified
            let currentPosition = currentVideoDevice.position
            
            switch(currentPosition){
            case AVCaptureDevicePosition.Unspecified:
                break
            case AVCaptureDevicePosition.Front:
                preferredPosition = AVCaptureDevicePosition.Back
                break
            case AVCaptureDevicePosition.Back:
                preferredPosition = AVCaptureDevicePosition.Front
                break
            }
            
            let videoDevice = CameraViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition)
            do {
                let videoDeviceInput =  try AVCaptureDeviceInput(device: videoDevice)
                
                self.session.beginConfiguration()
                
                self.session.removeInput(self.videoDeviceInput)
                
                if(self.session.canAddInput(videoDeviceInput)){
                    NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: currentVideoDevice)
                    
                    CameraViewController.setFlashMode(AVCaptureFlashMode.Auto, forDevice: videoDevice)
                    NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.subjectAreaDidChange(_:)), name:AVCaptureDeviceSubjectAreaDidChangeNotification, object: videoDevice)
                    
                    self.session.addInput(videoDeviceInput)
                    self.videoDeviceInput = videoDeviceInput
                } else {
                    self.session.addInput(self.videoDeviceInput)
                }
                
                let connection = self.movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
                if(connection.supportsVideoStabilization){
                    connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.Auto
                }
                
                self.session.commitConfiguration()
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.cameraButton.enabled = true
                    self.recordButton.enabled = true
                    self.stillButton.enabled = true
                })
            } catch {
                
            }
            
        })
    }
    
    @IBAction func snapStillImage(sender: AnyObject) {
        
        dispatch_async(self.sessionQueue, {
            let connection = self.stillImageOutput.connectionWithMediaType(AVMediaTypeVideo)
            let previewLayer = self.previewView.layer as! AVCaptureVideoPreviewLayer
            
            connection.videoOrientation = { () -> AVCaptureVideoOrientation in
                switch previewLayer.connection.videoOrientation {
                case .Portrait:
                    return AVCaptureVideoOrientation.Portrait
                case .LandscapeLeft:
                    return AVCaptureVideoOrientation.LandscapeLeft
                case .LandscapeRight:
                    return AVCaptureVideoOrientation.LandscapeRight
                case .PortraitUpsideDown:
                    return AVCaptureVideoOrientation.PortraitUpsideDown
                }
                }()

            
            CameraViewController.setFlashMode(AVCaptureFlashMode.Auto, forDevice: self.videoDeviceInput.device)
            
            self.stillImageOutput.captureStillImageAsynchronouslyFromConnection(connection, completionHandler: { (imageDataSampleBuffer, error) in

                if((imageDataSampleBuffer) != nil){
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    PHPhotoLibrary.requestAuthorization({ (status) in
                        if(status == PHAuthorizationStatus.Authorized){
                            PHPhotoLibrary.sharedPhotoLibrary().performChanges({PHAssetCreationRequest.creationRequestForAsset().addResourceWithType(PHAssetResourceType.Photo, data: imageData, options: nil)}, completionHandler: { (success, error) in
                                if(!success){
                                    print("Error occurred while saving image to photo library: \(error?.description)")
                                }
                            })
                        }
                    })
                } else {
                    print("Could not capture still image: \(error.description)")
                }
            })
        })
    }
   

    @IBAction func focusAndExposeTap(gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = (self.previewView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterestForPoint(gestureRecognizer.locationInView(gestureRecognizer.view))
        self.focusWithMode(AVCaptureFocusMode.AutoFocus, exposeWithMode: AVCaptureExposureMode.AutoExpose, atDevicePoint: devicePoint, motiorSubjectAreaChange: true)
    }
    
    //MARK: File Output Recording Delegate
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) {
        
        dispatch_async(dispatch_get_main_queue(), {
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop tile"), forState: UIControlState.Normal)
        })
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        
        let currentBackroundRecordingID = self.backgroundRecordingID
        self.backgroundRecordingID = UIBackgroundTaskInvalid
        
        let cleanup : dispatch_block_t = {
            do {
                try NSFileManager.defaultManager().removeItemAtURL(outputFileURL)
                if(currentBackroundRecordingID != UIBackgroundTaskInvalid){
                    UIApplication.sharedApplication().endBackgroundTask(currentBackroundRecordingID)
                }
            } catch {
                
            }
        }
        
        var success : Bool = true
        
        if((error) != nil){
            print("Movie file finishing error \(error.description)")
            success = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey]?.boolValue)!
        }
        if(success){
            PHPhotoLibrary.requestAuthorization({ (status) in
                if(status == PHAuthorizationStatus.Authorized){
                    PHPhotoLibrary.sharedPhotoLibrary().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let changeRequest = PHAssetCreationRequest.creationRequestForAsset()
                        changeRequest.addResourceWithType(PHAssetResourceType.Video, fileURL: outputFileURL, options: options)
                        }, completionHandler: { (success, error) in
                            if(!success){
                                print("Could not save movie to photo library: \(error?.description)")
                            }
                            cleanup()
                    })
                } else {
                    cleanup()
                }
            })
        } else {
            cleanup()
        }
        
        dispatch_async(dispatch_get_main_queue(), {
            self.cameraButton.enabled = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count > 1
            self.recordButton.enabled = true
            self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), forState: UIControlState.Normal)
        })
    }
    
    
    //MARK: Device Configuration
    
    func focusWithMode(focusMode : AVCaptureFocusMode, exposeWithMode expusureMode :AVCaptureExposureMode, atDevicePoint point:CGPoint, motiorSubjectAreaChange monitorSubjectAreaChange:Bool) {
        
        dispatch_async(self.sessionQueue, {
            let device : AVCaptureDevice = self.videoDeviceInput.device
            
            do {
                try device.lockForConfiguration()
                if(device.focusPointOfInterestSupported && device.isFocusModeSupported(focusMode)){
                    device.focusPointOfInterest = point
                    device.focusMode = focusMode
                }
                if(device.exposurePointOfInterestSupported && device.isExposureModeSupported(expusureMode)){
                    device.exposurePointOfInterest = point
                    device.exposureMode = expusureMode
                }
                
                device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
                
            } catch let error as NSError {
                print("Could not lock device for configuration: \(error.debugDescription)")
            }
            
        })
    }

    
    class func setFlashMode(flashMode : AVCaptureFlashMode, forDevice device:AVCaptureDevice){
        if(device.hasFlash && device.isFlashModeSupported(flashMode)){
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } catch let error as NSError {
                print("Could not lock device for configuration: \(error.debugDescription)")
            }
        }
    }
    
    
    class func deviceWithMediaType(mediaType: String!, preferringPosition position: AVCaptureDevicePosition!) -> AVCaptureDevice {
        
        let devices : NSArray = AVCaptureDevice.devicesWithMediaType(mediaType)
        var captureDevice : AVCaptureDevice = devices.firstObject as! AVCaptureDevice
        
        for device : AVCaptureDevice in devices as! [AVCaptureDevice] {
            if(device.position == position) {
                captureDevice = device
                break
            }
        }
        
        return captureDevice
    }
    
    
    
}