//
//  PreviewView.swift
//  AVCamSample
//
//  Created by Masanori Kuze on 2016/04/17.
//  Copyright © 2016年 Masanori Kuze. All rights reserved.
//

import UIKit
import AVFoundation

class Preview : UIView {
    
    var session : AVCaptureSession {
        get {
            let previewlayer : AVCaptureVideoPreviewLayer = self.layer as! AVCaptureVideoPreviewLayer
            return previewlayer.session
        }
        set {
            let previewlayer : AVCaptureVideoPreviewLayer = self.layer as! AVCaptureVideoPreviewLayer
            previewlayer.session = newValue
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
//        fatalError("init(coder:) has not been implemented")
    }
    
    override class func layerClass() -> AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}
