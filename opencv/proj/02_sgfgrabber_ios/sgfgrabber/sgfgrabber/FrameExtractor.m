//
//  FrameExtractor.m
//  sgfgrabber
//
//  Created by Andreas Hauenstein on 2017-10-20.
//  Copyright © 2017 AHN. All rights reserved.
//  Adapted from Boris Ohayon: IOS Camera Frames Extraction

#import "FrameExtractor.h"

//==============================
@interface FrameExtractor()
@property AVCaptureDevicePosition position;
@property AVCaptureSessionPreset quality;
@property AVCaptureSession *captureSession;
@property CIContext *context;
@property bool permissionGranted;
@property dispatch_queue_t sessionQ;
@property dispatch_queue_t bufferQ;

@end

//===============================
@implementation FrameExtractor

//---------------------
- (instancetype)init
{
    self = [super init];
    if (self) {
        self.permissionGranted = false;
        self.position = AVCaptureDevicePositionFront;
        self.quality = AVCaptureSessionPresetMedium;
        self.captureSession = [AVCaptureSession new];
        self.context = [CIContext new];
        self.sessionQ = dispatch_queue_create("com.ahaux.sessionQ", DISPATCH_QUEUE_SERIAL);
        self.bufferQ  = dispatch_queue_create("com.ahaux.bufferQ",  DISPATCH_QUEUE_SERIAL);
        [self checkPermission];
        dispatch_async(self.sessionQ, ^{
            [self configureSession];
            [self.captureSession startRunning];
        });
    }
    return self;
}

#pragma mark - AVSession config
//--------------------------
- (void)checkPermission
{
    switch( [AVCaptureDevice authorizationStatusForMediaType: AVMediaTypeVideo]) {
        case AVAuthorizationStatusAuthorized:
            self.permissionGranted = true;
            break;
        case AVAuthorizationStatusNotDetermined:
            dispatch_suspend(self.sessionQ);
            [self requestPermission];
            break;
        default:
            self.permissionGranted = false;
    }
} // checkPermission()

//----------------------------
- (void)requestPermission
{
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                             completionHandler: ^(BOOL granted) {
                                 self.permissionGranted = granted;
                                 dispatch_resume(self.sessionQ);
                             }];
}

//--------------------------
- (void)configureSession
{
    if (!self.permissionGranted) return;
    [self.captureSession setSessionPreset:self.quality];
    AVCaptureDevice *captureDevice = [self selectCaptureDevice];
    AVCaptureDeviceInput *captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:nil];
    if (![self.captureSession canAddInput:captureDeviceInput]) {
        return;
    }
    [self.captureSession addInput:captureDeviceInput];
    AVCaptureVideoDataOutput *videoOutput = [AVCaptureVideoDataOutput new];
    [videoOutput setSampleBufferDelegate:self queue:self.bufferQ];
    if (![self.captureSession canAddOutput:videoOutput]) {
        return;
    }
    [self.captureSession addOutput:videoOutput];
    AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
}

//-----------------------------------------
- (AVCaptureDevice *)selectCaptureDevice
{
    AVCaptureDevice *res = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    return res;
}

//--------------------------------------------------------------------
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
    CGImageRef cgImage = [self.context createCGImage:ciImage fromRect:ciImage.extent];
    UIImage *res = [UIImage imageWithCGImage:cgImage];
    CFRelease(cgImage);
    return res;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
//------------------------------------------------------------
- (void) captureOutput:(AVCaptureOutput * ) captureOutput
 didOutputSampleBuffer:(CMSampleBufferRef ) sampleBuffer
        fromConnection:(AVCaptureConnection * ) connection
{
    UIImage *uiImage = [self imageFromSampleBuffer:sampleBuffer];
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       [self.delegate captured:uiImage];
                   });
}

@end





