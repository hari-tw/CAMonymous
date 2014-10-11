//
//  CaptureManager.m
//  CAMonymous
//
//  Created by Andrew K. on 10/11/14.
//  Copyright (c) 2014 CAMonymous_team. All rights reserved.
//

@import AVFoundation;
@import CoreVideo;
@import Metal;

#import "CaptureManager.h"

@interface CaptureManager()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate>

@end

@implementation CaptureManager
{
  CVMetalTextureCacheRef _textureCache;
  AVCaptureDevice *_captureDevice;
  AVCaptureSession *_captureSession;
  dispatch_queue_t _captureQueue;
}

#pragma mark Singleton Methods

+ (CaptureManager *)sharedManager {
  static CaptureManager *sharedMyManager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedMyManager = [[self alloc] init];
  });
  return sharedMyManager;
}

- (id)init {
  if (self = [super init]) {
  }
  return self;
}

- (void)setupCaptureWithDevice:(id <MTLDevice>)device
{
  self.device = device;
  
  CVMetalTextureCacheCreate(NULL, NULL, device, NULL, &_textureCache);
  
  _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  
  _captureSession = [[AVCaptureSession alloc] init];
  
  AVCaptureInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:_captureDevice error:nil];
  [_captureSession addInput:input];
  
  _captureQueue = dispatch_queue_create("captureQueue", DISPATCH_QUEUE_SERIAL);
  
  AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
  videoOutput.videoSettings = @{
                                (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
                                };
  [videoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
  [_captureSession addOutput:videoOutput];
  
  AVCaptureMetadataOutput *metaOutput = [[AVCaptureMetadataOutput alloc] init];
  [metaOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
  [_captureSession addOutput:metaOutput];
  [metaOutput setMetadataObjectTypes:@[AVMetadataObjectTypeFace]];
  
  
  [_captureSession startRunning];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
  CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  
  id<MTLTexture> textureY = nil;
  
  {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    CVMetalTextureRef texture = NULL;
    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, _textureCache, pixelBuffer, NULL, pixelFormat, width, height, 0, &texture);
    if(status == kCVReturnSuccess)
    {
      textureY = CVMetalTextureGetTexture(texture);
      if (self.delegate){
        [self.delegate textureUpdated:textureY];
      }
      CFRelease(texture);
    }
  }
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection{
  
  NSUInteger numberOfFaces = metadataObjects.count;
  
  if (numberOfFaces > 0){
    
    if (self.device != nil){
      
      
      NSUInteger numberOfFaceObjects = 4;
      NSUInteger numberOfComponents = 6;
      float buffer[numberOfComponents*numberOfFaceObjects];
      if (numberOfFaces < numberOfFaceObjects){
        numberOfFaceObjects = numberOfFaces;
      }
      
      for (int i = 0; i < numberOfFaceObjects; i++){
        AVMetadataFaceObject *face = (AVMetadataFaceObject *)metadataObjects[i];
        
        buffer[0 + i*numberOfComponents] = face.bounds.origin.x;
        buffer[1 + i*numberOfComponents] = face.bounds.origin.y;
        buffer[2 + i*numberOfComponents] = face.bounds.size.width;
        buffer[3 + i*numberOfComponents] = face.bounds.size.height;
        buffer[4 + i*numberOfComponents] = face.rollAngle;
        buffer[5 + i*numberOfComponents] = face.yawAngle;
      }
      
      
      
      id <MTLBuffer> metalBuffer = [self.device newBufferWithBytes:&buffer length:sizeof(buffer)*numberOfFaces options:MTLResourceOptionCPUCacheModeDefault];
      if (self.delegate != nil){
        [self.delegate facesUpdated:metalBuffer numberOfFaces:numberOfFaces];
      }
      
    }else{
      NSLog(@"device == nil =(");
    }
  }else{
    if (self.delegate != nil){
      [self.delegate facesUpdated:nil numberOfFaces:numberOfFaces];
    }
  }
}

@end
