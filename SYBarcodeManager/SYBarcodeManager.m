//
//  SYBarcodeManager.m
//  zhangshaoyu
//
//  Created by zhangshaoyu on 16/1/19.
//  Copyright © 2016年 zhangshaoyu. All rights reserved.
//

#import "SYBarcodeManager.h"
#import <AVFoundation/AVFoundation.h>
#import "SYBarcodeView.h"

typedef void (^ScanningComplete)(BOOL isValid, NSString *scanResult);

typedef void (^SaveToPhotosAlbumComplete)(BOOL isSuccess);
static SaveToPhotosAlbumComplete saveToPhotosAlbumComplete;

@interface SYBarcodeManager () <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, assign) BOOL isValidCamera;

@property (nonatomic, strong) AVCaptureDevice *captureDevice;

@property (nonatomic, strong) UIView *superview;
@property (nonatomic, assign) CGRect superFrame;
@property (nonatomic, strong) SYBarcodeView *scanView;

@property (nonatomic, strong) AVCaptureSession *avSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *avLayer;
    
@property (nonatomic, copy) ScanningComplete scanningComplete;

@end

@implementation SYBarcodeManager

- (instancetype)initWithFrame:(CGRect)frame view:(UIView *)superView
{
    self = [super init];
    if (self) {
        //
        _message = @"将二维码放入框内，即可自动扫描.";
        _messagePosition = 0;
        _messageFont = [UIFont systemFontOfSize:15.0];
        _messageColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
        //
        self.superFrame = frame;
        self.superview = superView;
        CGFloat size = ((frame.size.width > frame.size.height ? frame.size.height : frame.size.width) * 0.6);
        self.scanFrame = CGRectMake((frame.size.width - size) / 2, (frame.size.width - size) / 2, size, size);
        //
        [self addNotification];
    }
    return self;
}
    
- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    NSLog(@"%@ 被释放了...", self.class);
}
    
#pragma mark - 扫描二维码

/// 退出扫描
- (void)QrcodeScanningCancel
{
    if (self.isValidCamera) {
        if (self.avSession.isRunning) {
            [self.avSession stopRunning];
        }
        
        self.scanningComplete = nil;
        [self.scanView scanLineStop];
        [self resetZoomFactor];
        [self closeFlashLight];
    }
}

/// 开始扫描
- (void)QrcodeScanningStart
{
    if (self.isValidCamera) {
        if (!self.avSession.isRunning) {
            [self.avSession startRunning];
            [self.scanView scanLineStart];
        }
    }
}

/// 开始扫描，初始化及立即开始，及扫描结果回调
- (void)QrcodeScanningStart:(void (^)(BOOL isEnable, NSString *result))complete
{
    [self QrcodeScanningStart:YES complete:complete];
}
/// 开始扫描，初始化未开始
- (void)QrcodeScanningComplete:(void (^)(BOOL isEnable, NSString *result))complete
{
    [self QrcodeScanningStart:NO complete:complete];
}

/// 开始扫描初始化及是否立即开始
- (void)QrcodeScanningStart:(BOOL)isStart complete:(void (^)(BOOL isEnable, NSString *result))complete
{
    if (self.isValidCamera) {
        // 视图
        if (self.superview) {
            [self.superview addSubview:self.scanView];
        }
        self.scanView.label.text = self.message;
        self.scanView.label.textColor = self.messageColor;
        self.scanView.label.font = self.messageFont;
        
        // 回调
        self.scanningComplete = [complete copy];
        
        // 显示扫描相机
        if (self.avLayer.superlayer == nil) {
            // 扫描框的位置和大小
            self.avLayer.frame = self.scanView.superview.bounds;
            [self.scanView.superview.layer insertSublayer:self.avLayer above:0];
            [self.scanView.superview bringSubviewToFront:self.scanView];
            
            self.scanView.superview.clipsToBounds = YES;
            self.scanView.superview.layer.masksToBounds = YES;
        }
        
        if (isStart) {
            [self QrcodeScanningStart];
        }
    } else {
        if (complete) {
            complete(NO, nil);
        }
    }
}

#pragma mark - 长按识别二维码

/**
 长按等识别图片二维码

 @param image 二维码图片
 @return 识别结果
 */
- (NSString *)QRCodeFromImage:(UIImage *)image
{
    NSData *data = UIImagePNGRepresentation(image);
    CIImage *ciimage = [CIImage imageWithData:data];
    if (ciimage) {
        CIDetector *qrDetector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@(YES)}] options:@{CIDetectorAccuracy : CIDetectorAccuracyHigh}];
        NSArray *resultArr = [qrDetector featuresInImage:ciimage];
        if (resultArr.count > 0) {
            CIFeature *feature = resultArr[0];
            CIQRCodeFeature *qrFeature = (CIQRCodeFeature *)feature;
            NSString *result = qrFeature.messageString;
            return result;
        } else {
            return nil;
        }
    } else {
        return nil;
    }
}

#pragma mark - getter

#pragma mark 窗口
    
- (SYBarcodeView *)scanView
{
    if (_scanView == nil) {
        _scanView = [[SYBarcodeView alloc] initWithFrame:self.superFrame];
        //
        [self addGesture:_scanView];
    }
    return _scanView;
}

#pragma mark 扫描器

- (BOOL)isValidCamera
{
    /// 先判断摄像头硬件是否好用
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        // 用户是否允许摄像头使用
        AVAuthorizationStatus authorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        // 不允许弹出提示框
        if (authorizationStatus == AVAuthorizationStatusRestricted || authorizationStatus == AVAuthorizationStatusDenied) {
            return NO;
        } else {
            return YES;
        }
    } else {
        // 硬件问题提示
        return NO;
    }
}

- (AVCaptureDevice *)captureDevice
{
    if (_captureDevice == nil) {
        _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    return _captureDevice;
}
    

- (AVCaptureSession *)avSession
{
    if (_avSession == nil) {

        // 创建输入流
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:self.captureDevice error:nil];

        // 创建输出流
        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        // 设置代理 在主线程里刷新
        [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];

        // 初始化链接对象
        _avSession = [[AVCaptureSession alloc] init];
        // 高质量采集率
        [_avSession setSessionPreset:AVCaptureSessionPresetHigh];

        if ([_avSession canAddInput:input]) {
            [_avSession addInput:input];
        }
        if ([_avSession canAddOutput:output]) {
            [_avSession addOutput:output];
            
            // 设置扫码支持的编码格式(如下设置条形码和二维码兼容)
            // output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code, AVMetadataObjectTypeUPCECode, AVMetadataObjectTypeCode39Code, AVMetadataObjectTypeCode39Mod43Code, AVMetadataObjectTypeCode93Code, AVMetadataObjectTypeCode128Code, AVMetadataObjectTypePDF417Code];
            // 仅条形码
            // output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
            // 条形码和二维码
            // output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code, AVMetadataObjectTypeCode128Code];
            if ([output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode] &&
                        [output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeCode128Code] &&
                        [output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeEAN13Code]) {
                        output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode, AVMetadataObjectTypeCode128Code, AVMetadataObjectTypeEAN13Code];
            }
        }
        
        // 光线
        [self lightOutput:_avSession];
        
        // ??
        [self.captureDevice lockForConfiguration:nil];
        if (self.captureDevice.isFocusPointOfInterestSupported && [self.captureDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            self.captureDevice.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        }
        [self.captureDevice unlockForConfiguration];
        
        // 调整扫描位置（取值范围{0,0,1,1}，且取反{y,x,height,width}）
        CGSize size = [UIScreen mainScreen].bounds.size;
        output.rectOfInterest = CGRectMake(_scanFrame.origin.y / size.height, _scanFrame.origin.x / size.width, _scanFrame.size.height / size.height, _scanFrame.size.width / size.width);
    }

    return _avSession;
}

- (AVCaptureVideoPreviewLayer *)avLayer
{
    if (_avLayer == nil) {
        _avLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.avSession];
        _avLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        
        //
        [_avLayer setAffineTransform:CGAffineTransformMakeScale(1.5, 1.5)];
    }
    
    return _avLayer;
}
    
#pragma mark - setter
    
- (void)setScanFrame:(CGRect)scanFrame
{
    _scanFrame = scanFrame;
    self.scanView.scanFrame = _scanFrame;
    [self.scanView reloadBarcodeView];
}
    
- (void)setMaskColor:(UIColor *)maskColor
{
    _maskColor = maskColor;
    self.scanView.backgroundColor = _maskColor;
    [self.scanView reloadBarcodeView];
}
    
- (void)setScanCornerColor:(UIColor *)scanCornerColor
{
    _scanCornerColor = scanCornerColor;
    self.scanView.cornerColor = _scanCornerColor;
    [self.scanView reloadBarcodeView];
}

-(void)setScanlineImage:(UIImage *)scanlineImage
{
    _scanlineImage = scanlineImage;
    self.scanView.scanline.image = _scanlineImage;
    [self.scanView reloadBarcodeView];
}

- (void)setMessage:(NSString *)message
{
    _message = message;
    self.scanView.label.text = _message;
}

- (void)setMessagePosition:(NSInteger)messagePosition
{
    _messagePosition = messagePosition;
    self.scanView.position = _messagePosition;
    [self.scanView reloadBarcodeView];
}

#pragma mark AVCaptureMetadataOutputObjectsDelegate

// 通过代理方法获取扫描到的结果
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    NSLog(@"%s", __func__);
    
    if (metadataObjects.count > 0) {
        // [session stopRunning];
        AVMetadataMachineReadableCodeObject *metadataObject = [metadataObjects objectAtIndex: 0];
        // 输出扫描字符串
        NSLog(@"输出扫描字符串 = %@，value = %@", metadataObject, metadataObject.stringValue);
        
        // 停止扫描
        [self.avSession stopRunning];
        // 停止扫描线
        [self.scanView scanLineStop];
        // 大小复原
        [self resetZoomFactor];
        // 关闭灯光
        [self closeFlashLight];
        
        if (self.scanningComplete) {
            NSString *result = metadataObject.stringValue;
            self.scanningComplete(self.isValidCamera, result);
        }
    }
}

#pragma mark - 生成二维码

// 根据字符内容生成二维码图片CIImage
+ (CIImage *)QrcodeCIImageWithContent:(NSString *)content
{
    NSData *barCodeData = [content dataUsingEncoding:NSUTF8StringEncoding];
    // 创建filter
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    // 设置内容和纠错级别
    [filter setValue:barCodeData forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    // 返回CIImage
    return filter.outputImage;
}

// 二维码图片UIImage
+ (UIImage *)QrcodeImageWithCIImage:(CIImage *)ciimage size:(CGFloat)size
{
    CGRect extent = CGRectIntegral(ciimage.extent);
    CGFloat scale = MIN(size / CGRectGetWidth(extent), size / CGRectGetHeight(extent));
    // 创建bitmap;
    size_t width = CGRectGetWidth(extent) * scale;
    size_t height = CGRectGetHeight(extent) * scale;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef bitmapRef = CGBitmapContextCreate(nil, width, height, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaNone);
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef bitmapImage = [context createCGImage:ciimage fromRect:extent];
    CGContextSetInterpolationQuality(bitmapRef, kCGInterpolationNone);
    CGContextScaleCTM(bitmapRef, scale, scale);
    CGContextDrawImage(bitmapRef, extent, bitmapImage);
    // 保存bitmap到图片
    CGImageRef scaledImage = CGBitmapContextCreateImage(bitmapRef);
    CGContextRelease(bitmapRef);
    CGImageRelease(bitmapImage);
    return [UIImage imageWithCGImage:scaledImage];
}

// 内存管理
void ProviderReleaseCacheData (void *info, const void *data, size_t size)
{
    free((void*)data);
}

/// 黑白二维码转成指定颜色
+ (UIImage *)QrcodeImageChangeColor:(UIImage *)image colorRed:(CGFloat)red colorGreen:(CGFloat)green colorBlue:(CGFloat)blue
{
    const int imageWidth = image.size.width;
    const int imageHeight = image.size.height;
    size_t bytesPerRow = imageWidth * 4;
    uint32_t *rgbImageBuf = (uint32_t *)malloc(bytesPerRow * imageHeight);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgbImageBuf, imageWidth, imageHeight, 8, bytesPerRow, colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipLast);
    CGContextDrawImage(context, CGRectMake(0, 0, imageWidth, imageHeight), image.CGImage);
    // 遍历像素
    int pixelNum = imageWidth * imageHeight;
    uint32_t *pCurPtr = rgbImageBuf;
    for (int i = 0; i < pixelNum; i++, pCurPtr++) {
        if ((*pCurPtr & 0xFFFFFF00) < 0x99999900) {
            // 将白色变成透明
            // 改成下面的代码，会将图片转成想要的颜色
            uint8_t* ptr = (uint8_t*)pCurPtr;
            ptr[3] = red; //0~255
            ptr[2] = green;
            ptr[1] = blue;
        } else {
            uint8_t *ptr = (uint8_t *)pCurPtr;
            ptr[0] = 0;
        }
    }
    
    // 输出图片
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, rgbImageBuf, bytesPerRow * imageHeight, ProviderReleaseCacheData);
    CGImageRef imageRef = CGImageCreate(imageWidth, imageHeight, 8, 32, bytesPerRow, colorSpace,
                                        kCGImageAlphaLast | kCGBitmapByteOrder32Little, dataProvider,
                                        NULL, true, kCGRenderingIntentDefault);
    CGDataProviderRelease(dataProvider);
    UIImage *resultUIImage = [UIImage imageWithCGImage:imageRef];
    
    // 清理空间
    CGImageRelease(imageRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    return resultUIImage;
}

/// 生成二维码（指定内容，指定大小，指定颜色）
+ (UIImage *)QrcodeImageWithContent:(NSString *)content size:(CGFloat)size colorRed:(CGFloat)red colorGreen:(CGFloat)green colorBlue:(CGFloat)blue
{
    CIImage *ciimage = [self QrcodeCIImageWithContent:content];
    UIImage *image = [self QrcodeImageWithCIImage:ciimage size:size];
    image = [self QrcodeImageChangeColor:image colorRed:red colorGreen:green colorBlue:blue];
    return image;
}

/// 生成二维码（指定内容，指定大小，透明色）
+ (UIImage *)QrcodeImageWithContent:(NSString *)content size:(CGFloat)size
{
    UIImage *image = [self QrcodeImageWithContent:content size:size colorRed:0.0 colorGreen:0.0 colorBlue:0.0];
    return image;
}

#pragma mark - 条形码

/// 生成条形码 条形码尺寸大小
+ (UIImage *)BarcodeImageWithContent:(NSString *)content size:(CGSize)size
{
    CIFilter *qrFilter = [CIFilter filterWithName:@"CICode128BarcodeGenerator"];
    NSData *contentData = [content dataUsingEncoding:NSUTF8StringEncoding];
    [qrFilter setValue:contentData forKey:@"inputMessage"];
    [qrFilter setValue:@(0.00) forKey:@"inputQuietSpace"];
    CIImage *image = qrFilter.outputImage;
    
    CGRect integralRect = CGRectIntegral(image.extent);
    CGFloat scale = MIN(size.width / CGRectGetWidth(integralRect), size.height / CGRectGetHeight(integralRect));
    
    size_t width = CGRectGetWidth(integralRect)*scale;
    size_t height = CGRectGetHeight(integralRect)*scale;
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceGray();
    CGContextRef bitmapRef = CGBitmapContextCreate(nil, width, height, 8, 0, colorSpaceRef, (CGBitmapInfo)kCGImageAlphaNone);
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef bitmapImage = [context createCGImage:image fromRect:integralRect];
    CGContextSetInterpolationQuality(bitmapRef, kCGInterpolationNone);
    CGContextScaleCTM(bitmapRef, scale, scale);
    CGContextDrawImage(bitmapRef, integralRect, bitmapImage);
    
    CGImageRef scaledImage = CGBitmapContextCreateImage(bitmapRef);
    CGContextRelease(bitmapRef);
    CGImageRelease(bitmapImage);
    return [UIImage imageWithCGImage:scaledImage];
}

#pragma mark - 闪光灯

- (void)openFlashLightComplete:(void (^)(BOOL hasFlash, BOOL isOpen))complete
{
    BOOL enable = NO;
    BOOL open = NO;
    
    if (self.isValidCamera) {
        if ([self.captureDevice hasTorch] && [self.captureDevice hasFlash]) {
            enable = YES;
            
            if (self.captureDevice.torchMode == AVCaptureTorchModeOff) {
                [self.captureDevice lockForConfiguration:nil];
                [self.captureDevice setTorchMode: AVCaptureTorchModeOn];
                [self.captureDevice unlockForConfiguration];
                
                open = YES;
            } else {
                [self.captureDevice lockForConfiguration:nil];
                [self.captureDevice setTorchMode: AVCaptureTorchModeOff];
                [self.captureDevice unlockForConfiguration];
                
                open = NO;
            }
        } else {
            enable = NO;
            open = NO;
        }
    }
    
    if (complete) {
        complete(enable, open);
    }
}

- (void)openFlashLight
{
    if (self.isValidCamera) {
        if (self.captureDevice.hasTorch && self.captureDevice.hasFlash) {
            [self.captureDevice lockForConfiguration:nil];
            [self.captureDevice setTorchMode: AVCaptureTorchModeOn];
            [self.captureDevice unlockForConfiguration];
        }
    }
}

- (void)closeFlashLight
{
    if (self.isValidCamera) {
        if (self.captureDevice.hasTorch && self.captureDevice.hasFlash) {
            [self.captureDevice lockForConfiguration:nil];
            [self.captureDevice setTorchMode: AVCaptureTorchModeOff];
            [self.captureDevice unlockForConfiguration];
        }
    }
}

#pragma mark - 通知

- (void)addNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self QrcodeScanningCancel];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self QrcodeScanningCancel];
}

#pragma mark - 缩放手势

- (void)addGesture:(UIView *)view
{
    // 缩放手势
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
    view.userInteractionEnabled = YES;
    [view addGestureRecognizer:pinchGesture];
}

- (void)pinch:(UIPinchGestureRecognizer *)gesture
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    CGFloat minZoomFactor = 1.0;
    CGFloat maxZoomFactor = device.activeFormat.videoMaxZoomFactor;
    
    if (@available(iOS 11.0, *)) {
        minZoomFactor = device.minAvailableVideoZoomFactor;
        maxZoomFactor = device.maxAvailableVideoZoomFactor;
    }
    
    static CGFloat lastZoomFactor = 1.0;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        lastZoomFactor = device.videoZoomFactor;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat zoomFactor = lastZoomFactor * gesture.scale;
        zoomFactor = fmaxf(fminf(zoomFactor, maxZoomFactor), minZoomFactor);
        [device lockForConfiguration:nil];
        device.videoZoomFactor = zoomFactor;
        [device unlockForConfiguration];
    }
}

// 停止扫描时，复原
- (void)resetZoomFactor
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [device lockForConfiguration:nil];
    device.videoZoomFactor = 1.0;
    [device unlockForConfiguration];
}

#pragma mark - 光线强弱

- (void)lightOutput:(AVCaptureSession *)session
{
    if (session) {
        // 创建摄像数据输出流
        AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        [videoDataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
        
        // 添加摄像输出流到会话对象，构成识了别光线强弱
        if ([session canAddOutput:videoDataOutput]) {
            [session addOutput:videoDataOutput];
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // 这个方法会时时调用，但内存很稳定
    CFDictionaryRef metadataDict = CMCopyDictionaryOfAttachments(NULL,sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    NSDictionary *metadata = [[NSMutableDictionary alloc] initWithDictionary:(__bridge NSDictionary*)metadataDict];
    CFRelease(metadataDict);
    NSDictionary *exifMetadata = [[metadata objectForKey:(NSString *)kCGImagePropertyExifDictionary] mutableCopy];
    float brightnessValue = [[exifMetadata objectForKey:(NSString *)kCGImagePropertyExifBrightnessValue] floatValue];
    if (self.brightnessComplete) {
        self.brightnessComplete(brightnessValue);
    }
}

#pragma mark - 音效

- (void)QrcodeScanningPlaySoundName:(NSString *)name
{
    if (name == nil || ([name isKindOfClass:NSString.class] && name.length < 0)) {
        return;
    }
    
    NSString *audioFile = [[NSBundle mainBundle] pathForResource:name ofType:nil];
    NSURL *fileUrl = [NSURL fileURLWithPath:audioFile];
    
    SystemSoundID soundID = 0;
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)(fileUrl), &soundID);
    AudioServicesAddSystemSoundCompletion(soundID, NULL, NULL, soundCompleteCallback, NULL);
    AudioServicesPlaySystemSound(soundID); // 播放音效
}

void soundCompleteCallback(SystemSoundID soundID, void *clientData)
{

}

@end
