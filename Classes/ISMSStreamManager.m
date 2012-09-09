//
//  ISMSStreamManager.m
//  iSub
//
//  Created by Benjamin Baron on 11/10/11.
//  Copyright (c) 2011 Ben Baron. All rights reserved.
//

#import "ISMSStreamManager.h"
#import "DatabaseSingleton.h"
#import "FMDatabaseAdditions.h"
#import "Song.h"
#import "NSMutableURLRequest+SUS.h"
#import "SavedSettings.h"
#import "MusicSingleton.h"
#import "ISMSStreamHandler.h"
#import "ISMSCFNetworkStreamHandler.h"
#import "PlaylistSingleton.h"
#import "AudioEngine.h"
#import "ISMSCoverArtLoader.h"
#import "SUSLyricsDAO.h"
#import "ViewObjectsSingleton.h"
#import "iSubAppDelegate.h"
#import "ISMSCacheQueueManager.h"
#import "TBXML.h"

LOG_LEVEL_ISUB_DEFAULT
#define maxNumOfReconnects 5

@implementation ISMSStreamManager
@synthesize handlerStack, lyricsDAO, lastCachedSong, lastTempCachedSong;

- (Song *)currentStreamingSong
{
	if (!self.isQueueDownloading)
		return nil;
	
	ISMSStreamHandler *handler = [self.handlerStack firstObjectSafe];
	return handler.mySong;
}

- (ISMSStreamHandler *)handlerForSong:(Song *)aSong
{
	if (!aSong)
		return nil;
	
	for (ISMSStreamHandler *handler in self.handlerStack)
	{
		if ([handler.mySong isEqualToSong:aSong])
		{
			//DLog(@"handler.mySong: %@    aSong: %@", handler.mySong.title, aSong.title);
			return handler;
		}
	}
	return nil;
}

- (BOOL)isSongFirstInQueue:(Song *)aSong
{
	if (!aSong)
		return NO;
	
	ISMSStreamHandler *firstHandler = [self.handlerStack firstObjectSafe];
	return [aSong isEqualToSong:firstHandler.mySong];
}

- (BOOL)isSongDownloading:(Song *)aSong
{
	if (!aSong)
		return NO;
	
	return [self handlerForSong:aSong].isDownloading;
}

- (BOOL)isQueueDownloading
{
	for (ISMSStreamHandler *handler in self.handlerStack)
	{
		if (handler.isDownloading)
			return YES;
	}
	return NO;
}

// Main worker method
- (void)cancelAllStreamsExcept:(NSArray *)handlersToSkip
{
	// Cancel the handlers
	for (ISMSStreamHandler *handler in self.handlerStack)
	{
		if (![handlersToSkip containsObject:handler])
		{
			// If we're trying to resume, cancel the request
			[NSObject cancelPreviousPerformRequestsWithTarget:self 
													 selector:@selector(resumeHandler:)
													   object:handler];
			
			// Cancel the handler
			[handler cancel];
		}
	}
	
	[self saveHandlerStack];
}

// Convenience method
- (void)cancelAllStreamsExceptForSongs:(NSArray *)songsToSkip
{
	// If songsToSkip == nil, just cancel all handlers
	if (!songsToSkip)
	{
		[self cancelAllStreams];
		return;
	}
	
	// Gather the handler objects to cancel
	NSMutableArray *handlersToSkip = [NSMutableArray arrayWithCapacity:[songsToSkip count]];
	for (Song *aSong in songsToSkip)
	{
		ISMSStreamHandler *handler = [self handlerForSong:aSong];
		if (handler)
			[handlersToSkip addObject:[self handlerForSong:aSong]];
	}
	
	// Cancel the other handlers
	[self cancelAllStreamsExcept:handlersToSkip];
}

// Convenience method
- (void)cancelAllStreamsExceptForSong:(Song *)aSong
{
	// If aSong == nil, just cancel all handlers
	if (![self handlerForSong:aSong])
	{
		[self cancelAllStreams];
		return;
	}
	
	// Create the handler array with the one object
	NSArray *handlersToSkip = [NSArray arrayWithObject:[self handlerForSong:aSong]];
	
	// Cancel the other handlers
	[self cancelAllStreamsExcept:handlersToSkip];
}

// Convenience method
- (void)cancelAllStreams
{
	[self cancelAllStreamsExcept:nil];
}

// Main worker method
- (void)cancelStreamAtIndex:(NSUInteger)index
{
	if (index < [self.handlerStack count])
	{
		// Find the handler object and cancel it
		ISMSStreamHandler *handler = [self.handlerStack objectAtIndexSafe:index];
		
		[handler cancel];
		
		// If we're trying to resume, cancel the request
		[NSObject cancelPreviousPerformRequestsWithTarget:self 
												 selector:@selector(resumeHandler:)
												   object:handler];
	}
	
	[self saveHandlerStack];
}

// Convenience method
- (void)cancelStream:(ISMSStreamHandler *)handler
{
	// If handler == nil, do nothing
	if (!handler)
		return;
	
	// Get the handler index
	NSUInteger index = [self.handlerStack indexOfObject:handler];
	
	// Cancel the handler
	[self cancelStreamAtIndex:index];
}

// Convenience method
- (void)cancelStreamForSong:(Song *)aSong
{
	// If aSong == nil, do nothing
	if (!aSong)
		return;
	
	// Cancel the handler
	[self cancelStream:[self handlerForSong:aSong]];
}

// Main worker method
- (void)removeAllStreamsExcept:(NSArray *)handlersToSkip
{
	// Remove the handlers
	NSArray *handlers = [NSArray arrayWithArray:self.handlerStack];
	for (ISMSStreamHandler *handler in handlers)
	{
		if (![handlersToSkip containsObject:handler])
		{
            [self cancelStream:handler];
            [self.handlerStack removeObject:handler];
            
            if (!handler.mySong.isFullyCached && !handler.mySong.isTempCached && !([cacheQueueManagerS.currentQueuedSong isEqualToSong:handler.mySong] && cacheQueueManagerS.isQueueDownloading))
            {
                DLog(@"Removing song from cached songs table: %@", handler.mySong);
                [handler.mySong removeFromCachedSongsTableDbQueue];
            }
			//[handler.mySong removeFromCachedSongsTableDbQueue];
		}
	}
	
	// Start the next handler
	if ([self.handlerStack count] > 0)
	{
		// Get the first handler
		ISMSStreamHandler *handler = [self.handlerStack firstObject];
		
		// If it's not already downloading, start downloading
		if (!handler.isDownloading)
		{
			[handler start];
		}
	}
	
	[self saveHandlerStack];
}

// Convenience method
- (void)removeAllStreamsExceptForSongs:(NSArray *)songsToSkip
{
	// If songsToSkip == nil, remove all handlers
	if (!songsToSkip)
	{
		[self removeAllStreams];
		return;
	}
	
	// Gather the handler objects to skip
	NSMutableArray *handlersToSkip = [NSMutableArray arrayWithCapacity:[songsToSkip count]];
	for (Song *aSong in songsToSkip)
	{
		ISMSStreamHandler *handler = [self handlerForSong:aSong];
		if (handler) 
			[handlersToSkip addObject:[self handlerForSong:aSong]];
	}
	
	// Remove the other handlers
	[self removeAllStreamsExcept:handlersToSkip];
}

// Convenience method
- (void)removeAllStreamsExceptForSong:(Song *)aSong
{
	// If aSong == nil, remove all handlers
	if (![self handlerForSong:aSong])
	{
		[self removeAllStreams];
		return;
	}
	
	// Get the handler to skip
	NSArray *handlersToSkip = [NSArray arrayWithObject:[self handlerForSong:aSong]];
	
	// Remove the other handlers
	[self removeAllStreamsExcept:handlersToSkip];
}

// Convenience method
- (void)removeAllStreams
{
	[self cancelAllStreams];
	[self removeAllStreamsExcept:nil];
}

// Main worker method
- (void)removeStreamAtIndex:(NSUInteger)index
{
	if (index < [self.handlerStack count])
	{
		[self cancelStreamAtIndex:index];
		
		ISMSStreamHandler *handler = [self.handlerStack objectAtIndex:index];
		if (!handler.mySong.isFullyCached && !handler.mySong.isTempCached && !([cacheQueueManagerS.currentQueuedSong isEqualToSong:handler.mySong] && cacheQueueManagerS.isQueueDownloading))
        {
            DLog(@"Removing song from cached songs table: %@", handler.mySong);
            [handler.mySong removeFromCachedSongsTableDbQueue];
        }
        [self.handlerStack removeObjectAtIndexSafe:index];
	}
	
	[self saveHandlerStack];
}

// Convenience method
- (void)removeStream:(ISMSStreamHandler *)handler
{
	// If handler == nil, do nothing
	if (!handler)
		return;
	
	// Remove the handler
	[self removeStreamAtIndex:[self.handlerStack indexOfObject:handler]];
}

// Convenience method
- (void)removeStreamForSong:(Song *)aSong
{
	// If aSong == nil, do nothing
	if (!aSong)
		return;
	
	// Remove the handler
	[self removeStream:[self handlerForSong:aSong]];
}

- (void)resumeQueue
{
	[self resumeHandler:[self.handlerStack firstObjectSafe]];
}

- (void)resumeHandler:(ISMSStreamHandler *)handler
{
	if (!handler)
		return; 
	
	// As an added check, verify that this handler is still in the stack
	if ([self isSongInQueue:handler.mySong])
	{
		if (cacheQueueManagerS.isQueueDownloading && [cacheQueueManagerS.currentQueuedSong isEqualToSong:handler.mySong])
		{
			// This song is already being downloaded by the cache queue, so just start the player
			[self ISMSStreamHandlerStartPlayback:handler];
			
			// Remove the handler from the stack
			[self removeStream:handler];
			
			// Start the next handler which is now the first object
			if ([self.handlerStack count] > 0)
			{
				ISMSStreamHandler *handler = [self.handlerStack firstObjectSafe];
				[self startHandler:handler];
			}
		}
		else
		{
			[handler start:YES];
		}
	}
}

- (void)startHandler:(ISMSStreamHandler *)handler resume:(BOOL)resume
{
	if (!handler)
		return;
	
	if (cacheQueueManagerS.isQueueDownloading && [cacheQueueManagerS.currentQueuedSong isEqualToSong:handler.mySong])
	{
		// This song is already being downloaded by the cache queue, so just start the player
		[self ISMSStreamHandlerStartPlayback:handler];
		
		// Remove the handler from the stack
		[self removeStream:handler];
		
		// Start the next handler which is now the first object
		if ([self.handlerStack count] > 0)
		{
			ISMSStreamHandler *handler = [self.handlerStack firstObjectSafe];
			[self startHandler:handler];
		}
	}
	else
	{
		[handler start:resume];
		[lyricsDAO loadLyricsForArtist:handler.mySong.artist andTitle:handler.mySong.title];
	}
}

- (void)startHandler:(ISMSStreamHandler *)handler
{
	if (!handler)
		return;
	
	DDLogVerbose(@"starting handler, handlerStack: %@", self.handlerStack);
	
	[self startHandler:handler resume:NO];
}

- (void)saveHandlerStack
{
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.handlerStack];
	if (data)
	{
		[[NSUserDefaults standardUserDefaults] setObject:data forKey:@"handlerStack"];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
}

- (void)loadHandlerStack
{	
	NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"handlerStack"];
	if (data) 
		self.handlerStack = [NSKeyedUnarchiver unarchiveObjectWithData:data];

	for (ISMSStreamHandler *handler in self.handlerStack)
	{
		handler.delegate = self;
	}
	
	DDLogVerbose(@"load handler stack, handlerStack: %@", self.handlerStack);

}

#pragma mark - Handler Stealing

// Hand of handler to cache queue
- (void)stealHandlerForCacheQueue:(ISMSStreamHandler *)handler
{
	DDLogInfo(@"cache queue manager stole handler for: %@", handler.mySong.title);
	handler.partialPrecacheSleep = NO;
	[self.handlerStack removeObject:handler];
	[self saveHandlerStack];
	[self fillStreamQueue];
}

#pragma mark Download

- (void)queueStreamForSong:(Song *)song byteOffset:(unsigned long long)byteOffset secondsOffset:(double)secondsOffset atIndex:(NSUInteger)index isTempCache:(BOOL)isTemp isStartDownload:(BOOL)isStartDownload
{
	if (!song)
		return;
	
	ISMSStreamHandler *handler = [[ISMSCFNetworkStreamHandler alloc] initWithSong:song 
															byteOffset:byteOffset
														 secondsOffset:secondsOffset
																isTemp:isTemp
															  delegate:self];
	if (![self.handlerStack containsObject:handler])
	{
		[self.handlerStack insertObject:handler atIndex:index];
		
		if ([self.handlerStack count] == 1 && isStartDownload)
		{
			[self startHandler:handler];
		}
		
		// Also download the album art
		if (song.coverArtId)
		{
			ISMSCoverArtLoader *playerArt = [[ISMSCoverArtLoader alloc] initWithDelegate:self coverArtId:song.coverArtId isLarge:YES];
			[playerArt downloadArtIfNotExists];
			//if (![playerArt downloadArtIfNotExists])
			//	;
			
			ISMSCoverArtLoader *tableArt = [[ISMSCoverArtLoader alloc] initWithDelegate:self coverArtId:song.coverArtId isLarge:NO];
			[tableArt downloadArtIfNotExists];
			//if (![tableArt downloadArtIfNotExists])
			//	;
		}
	}
	
	[self saveHandlerStack];
}

- (void)queueStreamForSong:(Song *)song atIndex:(NSUInteger)index isTempCache:(BOOL)isTemp isStartDownload:(BOOL)isStartDownload
{	
	[self queueStreamForSong:song byteOffset:0 secondsOffset:0.0 atIndex:index isTempCache:isTemp isStartDownload:isStartDownload];
}

- (void)queueStreamForSong:(Song *)song byteOffset:(unsigned long long)byteOffset secondsOffset:(double)secondsOffset isTempCache:(BOOL)isTemp isStartDownload:(BOOL)isStartDownload
{
	[self queueStreamForSong:song byteOffset:byteOffset secondsOffset:secondsOffset atIndex:[self.handlerStack count] isTempCache:isTemp isStartDownload:isStartDownload];
}

- (void)queueStreamForSong:(Song *)song isTempCache:(BOOL)isTemp isStartDownload:(BOOL)isStartDownload
{
	//DLog(@"queuing stream for song: %@", song.title);
	[self queueStreamForSong:song byteOffset:0 secondsOffset:0.0 atIndex:[self.handlerStack count] isTempCache:isTemp isStartDownload:isStartDownload];
}

- (BOOL)isSongInQueue:(Song *)aSong
{
	BOOL isSongInQueue = NO;
	for (ISMSStreamHandler *handler in self.handlerStack)
	{
		if ([handler.mySong isEqualToSong:aSong])
		{
			isSongInQueue = YES;
			break;
		}
	}
	return isSongInQueue;
}

- (void)fillStreamQueue:(BOOL)isStartDownload
{	
	if (settingsS.isJukeboxEnabled)
		return;
	
	NSUInteger numStreamsToQueue = 1;
	if (settingsS.isNextSongCacheEnabled)
	{
		numStreamsToQueue = ISMSNumberOfStreamsToQueue;
	}
	
	if (self.handlerStack.count < numStreamsToQueue)
	{
		for (int i = 0; i < numStreamsToQueue; i++)
		{
			Song *aSong = [playlistS songForIndex:[playlistS indexForOffsetFromCurrentIndex:i]];
			if (aSong && ![self isSongInQueue:aSong] && !aSong.isFullyCached && !viewObjectsS.isOfflineMode && ![cacheQueueManagerS.currentQueuedSong isEqualToSong:aSong])
			{
				// Queue the song for download
				[self queueStreamForSong:aSong isTempCache:!settingsS.isSongCachingEnabled isStartDownload:isStartDownload];
			}
		}
		
		DDLogVerbose(@"fill stream queue, handlerStack: %@", self.handlerStack);
	}
}

- (void)fillStreamQueue
{
	[self fillStreamQueue:YES];
}

- (void)songCachingToggled
{
	if (settingsS.isSongCachingEnabled)
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(fillStreamQueue) 
													 name:ISMSNotification_SongPlaybackEnded 
												   object:nil];
	else
		[[NSNotificationCenter defaultCenter] removeObserver:self 
														name:ISMSNotification_SongPlaybackEnded 
													  object:nil];
}

- (void)currentPlaylistIndexChanged
{
	// TODO: Fix this logic, it's wrong
	// Verify that the last song is not constantly retrying to connect, 
	// so the current song can download and play
	[self removeStreamForSong:playlistS.prevSong];
}

- (void)currentPlaylistOrderChanged
{
	Song *currentSong = playlistS.currentSong;
	Song *nextSong = playlistS.nextSong;
	NSMutableArray *songsToSkip = [NSMutableArray arrayWithCapacity:2];
	if (currentSong) [songsToSkip addObject:currentSong];
	if (nextSong) [songsToSkip addObject:nextSong];
	
	[self removeAllStreamsExceptForSongs:songsToSkip];
	[self fillStreamQueue:audioEngineS.player.isStarted];
}

- (void)downloadMoreOfPrecacheStream
{
	if (self.isQueueDownloading)
	{
		ISMSStreamHandler *currentHandler = [handlerStack objectAtIndexSafe:0];
		if (currentHandler.isPartialPrecacheSleeping)
		{
			// Allow 10 more seconds of audio data to download
			currentHandler.secondsToPartialPrecache += 10;
			
			// Break the wait loop, but leave partial precaching on
			currentHandler.tempBreakPartialPrecache = YES;
		}
	}
}

#pragma mark - ISMSStreamHandler delegate

- (void)ISMSStreamHandlerStarted:(ISMSStreamHandler *)handler
{
	if (handler.isTempCache)
		self.lastTempCachedSong = nil;
}

- (void)ISMSStreamHandlerStartPlayback:(ISMSStreamHandler *)handler
{	
	// Update the last cached song
	self.lastCachedSong = handler.mySong;
	
	Song *currentSong = playlistS.currentSong;
	Song *nextSong = playlistS.nextSong;
	
//DLog(@"starting playback for %@  file size: %llu", handler.mySong, handler.totalBytesTransferred);
	
	if ([handler.mySong isEqualToSong:currentSong])
	{
		[audioEngineS start];
		
		// Only for temp cached files
		if (handler.isTempCache)
		{
			// TODO: get rid of this ugly hack
			[EX2Dispatch timerInMainQueueAfterDelay:1.0 
										   withName:@"temp song set byteOffset/seconds"
                                            repeats:NO
									   performBlock:^{
				//DLog(@"byteOffset: %llu   secondsOffset: %f", handler.byteOffset, handler.secondsOffset);
				audioEngineS.player.startByteOffset = handler.byteOffset;
				audioEngineS.player.startSecondsOffset = handler.secondsOffset;
			}];
		}
	}
	else if ([handler.mySong isEqualToSong:nextSong])
	{
		//DLog(@"preparing next song stream");
		[audioEngineS.player prepareNextSongStream];
	}
	
	[self saveHandlerStack];
}

- (void)ISMSStreamHandlerConnectionFailed:(ISMSStreamHandler *)handler withError:(NSError *)error
{
	//DLog(@"stream handler failed: %@", handler);
	if (handler.numOfReconnects < maxNumOfReconnects)
	{
		//DLog(@"retrying stream handler");
		// Less than max number of reconnections, so try again 
		handler.numOfReconnects++;
		// Retry connection after a delay to prevent a tight loop
		[self performSelector:@selector(resumeHandler:) withObject:handler afterDelay:1.5];
		//[self startHandler:handler resume:YES];
	}
	else
	{
		//DLog(@"removing stream handler");
		//DLog(@"handlerStack: %@", self.handlerStack);
		// Tried max number of times so remove
		[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_StreamHandlerSongFailed];
		[self removeStream:handler];
	}
}

- (void)ISMSStreamHandlerConnectionFinished:(ISMSStreamHandler *)handler
{	
	BOOL isSuccess = YES;

	if (handler.totalBytesTransferred == 0)
	{
		// Not a trial issue, but no data was returned at all
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Uh oh!" message:@"We asked for a song, but the server didn't send anything!\n\nIt's likely that Subsonic's transcoding failed.\n\nIf you need help, please tap the Support button on the Home tab." delegate:appDelegateS cancelButtonTitle:@"OK" otherButtonTitles: nil];
		[alert show];
		[[NSFileManager defaultManager] removeItemAtPath:handler.filePath error:NULL];
		isSuccess = NO;
	}
	else if (handler.totalBytesTransferred < 1000)
	{
		BOOL isLicenseIssue = NO;
		// Verify that it's a license issue
		NSData *receivedData = [NSData dataWithContentsOfFile:handler.filePath];
		NSError *error;
		TBXML *tbxml = [[TBXML alloc] initWithXMLData:receivedData error:&error];
		if (!error)
		{
			TBXMLElement *root = tbxml.rootXMLElement;
				
			TBXMLElement *error = [TBXML childElementNamed:@"error" parentElement:root];
			if (error)
			{
				NSString *code = [TBXML valueOfAttributeNamed:@"code" forElement:error];
				//NSString *message = [TBXML valueOfAttributeNamed:@"message" forElement:error];
				if ([code isEqualToString:@"60"])
				{
					isLicenseIssue = YES;
				}
			}
		}
		
		if (isLicenseIssue)
		{
			// This is a trial period message, alert the user and stop streaming
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Subsonic API Trial Expired" message:@"You can purchase a license for Subsonic by logging in to the web interface and clicking the red Donate link on the top right.\n\nPlease remember, iSub is a 3rd party client for Subsonic, and this license and trial is for Subsonic and not iSub.\n\nIf you didn't know about the Subsonic license requirement, and do not wish to purchase it, please tap the Support button on the Home tab and contact iSub support for a refund." delegate:appDelegateS cancelButtonTitle:@"OK" otherButtonTitles: nil];
			[alert show];
			[[NSFileManager defaultManager] removeItemAtPath:handler.filePath error:NULL];
			isSuccess = NO;
		}	
	}
	
	if (isSuccess)
	{
		//DLog(@"finished downloading song: %@", handler.mySong.title);
		
		// Mark song as cached
		if (!handler.isTempCache)
        	{
            		if ([cacheQueueManagerS isSongInQueue:handler.mySong])
            		{
                		//handler.mySong.isDownloaded = YES;
                		[handler.mySong removeFromCacheQueueDbQueue];
            		}
            
           		DLog(@"Marking isFullyCached = YES for %@", handler.mySong);
			handler.mySong.isFullyCached = YES;
		}
		
		// Update the last cached song
		self.lastCachedSong = handler.mySong;
		
		if (handler.isTempCache)
			self.lastTempCachedSong = handler.mySong;
		
		// Remove the handler from the stack
		[self removeStream:handler];
		
		// Start the next handler which is now the first object
		if ([self.handlerStack count] > 0)
		{
			ISMSStreamHandler *handler = [self.handlerStack firstObjectSafe];
			[self startHandler:handler];
		}
		
		// Keep the queue filled
		[self fillStreamQueue];
		NSDictionary *userInfo = [NSDictionary dictionaryWithObject:handler.mySong.songId forKey:@"songId"];
		[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_StreamHandlerSongDownloaded 
													  userInfo:userInfo];
	}
}

#pragma mark - ISMSLoader handler

- (void)loadingFailed:(ISMSLoader *)theLoader withError:(NSError *)error
{
	theLoader.delegate = nil;
}

- (void)loadingFinished:(ISMSLoader *)theLoader
{
	theLoader.delegate = nil;
}

#pragma mark - Memory management

- (void)didReceiveMemoryWarning
{
//DLog(@"received memory warning");
	
}

#pragma mark - Singleton methods

- (void)delayedSetup
{
	for (ISMSStreamHandler *handler in handlerStack)
	{
		// Resume any handlers that were downloading when iSub closed
		if (handler.isDownloading && !handler.isTempCache)
		{
			DDLogVerbose(@"resuming starting handler");
			[handler start:YES];
		}
	}
}

- (void)setup
{
	// Load the handler stack, it may have been full when iSub was closed
	[self loadHandlerStack];
	handlerStack = handlerStack ? handlerStack : [[NSMutableArray alloc] initWithCapacity:0];
	if ([handlerStack count] > 0)
	{
		if ([(ISMSStreamHandler *)[handlerStack firstObject] isTempCache])
		{
			[self removeAllStreams];
		}
		else
		{
			for (ISMSStreamHandler *handler in handlerStack)
			{
				// Resume any handlers that were downloading when iSub closed
				if (handler.isDownloading && !handler.isTempCache)
				{
					[handler start:YES];
				}
			}
		}
	}
	
	lastCachedSong = nil;
	lyricsDAO = [[SUSLyricsDAO alloc] initWithDelegate:self]; 
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(songCachingToggled) 
												 name:ISMSNotification_SongCachingEnabled object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(songCachingToggled) 
												 name:ISMSNotification_SongCachingDisabled object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(currentPlaylistIndexChanged) 
												 name:ISMSNotification_CurrentPlaylistIndexChanged object:nil];
	
	if (settingsS.isSongCachingEnabled)
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(fillStreamQueue) 
													 name:ISMSNotification_SongPlaybackEnded object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(currentPlaylistOrderChanged) 
												 name:ISMSNotification_RepeatModeChanged object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(currentPlaylistOrderChanged) 
												 name:ISMSNotification_CurrentPlaylistOrderChanged object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(currentPlaylistOrderChanged) 
												 name:ISMSNotification_CurrentPlaylistShuffleToggled object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(didReceiveMemoryWarning) 
												 name:UIApplicationDidReceiveMemoryWarningNotification 
											   object:nil];
}

+ (id)sharedInstance
{
    static ISMSStreamManager *sharedInstance = nil;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{
		sharedInstance = [[self alloc] init];
		[sharedInstance setup];
	});
    return sharedInstance;
}


@end
