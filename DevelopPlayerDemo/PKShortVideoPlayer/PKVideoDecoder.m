//
//  PKVideoDecoder.m
//  DevelopPlayerDemo
//
//  Created by jiangxincai on 16/1/7.
//  Copyright © 2016年 1yyg. All rights reserved.
//

#import "PKVideoDecoder.h"

@import AVFoundation;

@interface PKVideoDecoder ()

@property (nonatomic, strong) AVAsset *asset;
@property (nonatomic, strong) AVAssetReader *assetReader;
@property (nonatomic, strong) AVAssetReaderTrackOutput *assetReaderOutput;

@property (nonatomic, assign) BOOL initFlag;
@property (nonatomic, assign) BOOL resetFlag;
@property (nonatomic, assign) BOOL finishFlag;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSRecursiveLock *lock;

@end

@implementation PKVideoDecoder

#pragma mark - Initialization

- (instancetype)initWithVideoURL:(NSURL *)videoURL format:(int)format {
    self = [super init];
    if (self) {
        _format = format;
        _lock = [[NSRecursiveLock alloc] init];
        _frameRate = 24;
        
        [_lock lock];
        if( _assetReader ){
            [_lock unlock];
        }
        _asset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
        [_lock unlock];
    }
    return self;
}

- (void)dealloc {
    [_lock lock];
    [_timer invalidate];
    [_lock unlock];
}



#pragma mark - Public

- (void)start {
    [self.lock lock];
    
    if( [self isRunning] ){
        [self.lock unlock];
        return;
    }
    self.initFlag = NO;
    [self preprocessForDecoding];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:(1.0/self.frameRate) target:self selector:@selector(captureLoop) userInfo:nil repeats:YES];
    [self.lock unlock];
}

- (void)pause {
    [self.lock lock];
    if( ![self isRunning] ){
        [self.lock unlock];
        return;
    }
    [self.timer invalidate];
    self.timer = nil;
    [self processForPausing];
    [self.lock unlock];
}

- (void)stop {
    [self.lock lock];
    self.currentTime  = 0;
    [self.timer invalidate];
    self.timer = nil;
    [self postprocessForDecoding];
    [self.lock unlock];
}



#pragma mark - Private

-(void)captureLoop {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self captureNext];
    });
}

- (void)captureNext {
    [self.lock lock];
    [self processForDecoding];
    [self.lock unlock];
}

- (BOOL)isRunning {
    return [self.timer isValid]? YES : NO;
}

- (void)preprocessForDecoding {
    [self initReader];
}

- (void)postprocessForDecoding {
    [self releaseReader];
}

- (void)processForDecoding {
    if( self.assetReader.status != AVAssetReaderStatusReading ){
        if( self.assetReader.status == AVAssetReaderStatusCompleted ){
            if( !self.loop ){
                [self.timer invalidate];
                self.timer = nil;
                
                self.resetFlag = YES;
                [self.delegate videoDecoderDidFinishDecoding:self];
                
                self.currentTime = 0;
                [self releaseReader];
                return;
            }else{
                [self.delegate videoDecoderDidFinishDecoding:self];
                
                self.currentTime = 0;
                [self initReader];
            }
        }
    }
    
    CMSampleBufferRef sampleBuffer = [self.assetReaderOutput copyNextSampleBuffer];
    if(!sampleBuffer ){
        return;
    }
    self.currentTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    CVImageBufferRef pixBuff = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    [self.delegate videoDecoderDidDecodeFrame:self pixelBuffer:pixBuff];
    
    CMSampleBufferInvalidate(sampleBuffer);
}

- (void)processForPausing {

}

- (BOOL)isFinished {
    return (self.assetReader.status == AVAssetReaderStatusCompleted) ? YES : NO;
}

- (void)releaseReader {
    self.assetReader = nil;
    self.assetReaderOutput = nil;
}

- (void)initReader {
    AVAssetTrack *track = [[self.asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    NSDictionary *setting = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:self.format]
                                                        forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    self.assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:setting];
    
    self.assetReader = [[AVAssetReader alloc] initWithAsset:self.asset error:nil];
    [self.assetReader addOutput:self.assetReaderOutput];
    
    CMTime tm = CMTimeMake((int64_t)(self.currentTime*30000), 30000);
    [self.assetReader setTimeRange:CMTimeRangeMake(tm,self.asset.duration)];
    
    [self.assetReader startReading];
}

@end