//
//  ISMSStreamHandler.h
//  Anghami
//
//  Created by Ben Baron on 7/4/12.
//  Copyright (c) 2012 Ben Baron. All rights reserved.
//

#import "ISMSStreamHandlerDelegate.h"

#define ISMSNumSecondsToPartialPreCacheDefault 45
#define ISMSNumBytesToPartialPreCache(bitrate) (BytesForSecondsAtBitrate(self.secondsToPartialPrecache, bitrate))

#define ISMSMinBytesToStartPlayback(bitrate) (BytesForSecondsAtBitrate(settingsS.audioEngineStartNumberOfSeconds, bitrate))

#define ISMSThrottleTimeInterval 0.1

#define ISMSMaxKilobitsPerSec3G 500
#define ISMSMaxBytesPerInterval3G BytesForSecondsAtBitrate(ISMSThrottleTimeInterval, ISMSMaxKilobitsPerSec3G)

#define ISMSMaxKilobitsPerSecWifi 8000
#define ISMSMaxBytesPerIntervalWifi BytesForSecondsAtBitrate(ISMSThrottleTimeInterval, ISMSMaxKilobitsPerSecWifi)

#define ISMSMinBytesToStartLimiting(bitrate) (BytesForSecondsAtBitrate(60, bitrate))

#define ISMSMaxContentLengthFailures 25

@class Song;
@interface ISMSStreamHandler : NSObject <NSCoding>

- (id)initWithSong:(Song *)song byteOffset:(unsigned long long)bOffset secondsOffset:(double)sOffset isTemp:(BOOL)isTemp delegate:(NSObject<ISMSStreamHandlerDelegate> *)theDelegate;
- (id)initWithSong:(Song *)song isTemp:(BOOL)isTemp delegate:(NSObject<ISMSStreamHandlerDelegate> *)theDelegate;

@property (unsafe_unretained) NSObject<ISMSStreamHandlerDelegate> *delegate;
@property (copy) Song *mySong;
@property unsigned long long byteOffset;
@property double secondsOffset;
@property unsigned long long totalBytesTransferred;
@property unsigned long long bytesTransferred;
@property BOOL isDelegateNotifiedToStartPlayback;
@property NSUInteger numOfReconnects;
@property BOOL isTempCache;
@property NSUInteger bitrate;
@property (unsafe_unretained, readonly) NSString *filePath;
@property BOOL partialPrecacheSleep;
@property BOOL isDownloading;
@property BOOL isCurrentSong;
@property BOOL shouldResume;
@property unsigned long long contentLength;
@property NSInteger maxBitrateSetting;
@property (strong) NSDate *speedLoggingDate;
@property unsigned long long speedLoggingLastSize;
@property BOOL isCanceled;
@property NSUInteger numberOfContentLengthFailures;
@property BOOL isPartialPrecacheSleeping;
@property NSUInteger secondsToPartialPrecache;
@property BOOL tempBreakPartialPrecache;
@property NSFileHandle *fileHandle;

- (void)start:(BOOL)resume;
- (void)start;
- (void)cancel;

- (void)connectionTimedOut;

- (void)startTimeOutTimer;
- (void)stopTimeOutTimer;

- (double)maxBytesPerIntervalForBitrate:(double)rate is3G:(BOOL)is3G;

@end
