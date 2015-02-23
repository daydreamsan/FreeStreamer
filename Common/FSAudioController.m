/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2015 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSAudioController.h"
#import "FSAudioStream.h"
#import "FSPlaylistItem.h"
#import "FSCheckContentTypeRequest.h"
#import "FSParsePlaylistRequest.h"
#import "FSParseRssPodcastFeedRequest.h"

@interface FSAudioController ()
@property (readonly) FSAudioStream *audioStream;
@property (readonly) FSCheckContentTypeRequest *checkContentTypeRequest;
@property (readonly) FSParsePlaylistRequest *parsePlaylistRequest;
@property (readonly) FSParseRssPodcastFeedRequest *parseRssPodcastFeedRequest;
@property (nonatomic,assign) BOOL readyToPlay;
@property (nonatomic,assign) NSUInteger currentPlaylistItemIndex;
@property (nonatomic,strong) NSMutableArray *playlistItems;
@end

@implementation FSAudioController

-(id)init
{
    if (self = [super init]) {
        _url = nil;
        _audioStream = nil;
        _checkContentTypeRequest = nil;
        _parsePlaylistRequest = nil;
        _readyToPlay = NO;
    }
    return self;
}

- (id)initWithUrl:(NSURL *)url
{
    if (self = [self init]) {
        self.url = url;
    }
    return self;
}

- (void)dealloc
{
    [_audioStream stop];
    
    _audioStream.delegate = nil;
    _audioStream = nil;
    
    [_checkContentTypeRequest cancel];
    [_parsePlaylistRequest cancel];
    [_parseRssPodcastFeedRequest cancel];
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (FSAudioStream *)audioStream
{
    if (!_audioStream) {
        _audioStream = [[FSAudioStream alloc] init];
    }
    return _audioStream;
}

- (FSCheckContentTypeRequest *)checkContentTypeRequest
{
    if (!_checkContentTypeRequest) {
        __weak FSAudioController *weakSelf = self;
        
        _checkContentTypeRequest = [[FSCheckContentTypeRequest alloc] init];
        _checkContentTypeRequest.url = self.url;
        _checkContentTypeRequest.onCompletion = ^() {
            if (weakSelf.checkContentTypeRequest.playlist) {
                // The URL is a playlist; retrieve the contents
                [weakSelf.parsePlaylistRequest start];
            } else if (weakSelf.checkContentTypeRequest.xml) {
                // The URL may be an RSS feed, check the contents
                [weakSelf.parseRssPodcastFeedRequest start];
            } else {
                // Not a playlist; try directly playing the URL
                
                weakSelf.readyToPlay = YES;
                [weakSelf.audioStream play];
            }
        };
        _checkContentTypeRequest.onFailure = ^() {
            // Failed to check the format; try playing anyway
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioController: Failed to check the format, trying to play anyway, URL: %@", weakSelf.audioStream.url);
#endif
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
    }
    return _checkContentTypeRequest;
}

- (FSParsePlaylistRequest *)parsePlaylistRequest
{
    if (!_parsePlaylistRequest) {
        __weak FSAudioController *weakSelf = self;
        
        _parsePlaylistRequest = [[FSParsePlaylistRequest alloc] init];
        _parsePlaylistRequest.onCompletion = ^() {
            if ([weakSelf.parsePlaylistRequest.playlistItems count] > 0) {
                weakSelf.playlistItems = weakSelf.parsePlaylistRequest.playlistItems;
                
                weakSelf.readyToPlay = YES;
                
                weakSelf.audioStream.onCompletion = ^() {
                    if (weakSelf.currentPlaylistItemIndex + 1 < [weakSelf.playlistItems count]) {
                        weakSelf.currentPlaylistItemIndex = weakSelf.currentPlaylistItemIndex + 1;
                        
                        [weakSelf play];
                    }
                };
                
                [weakSelf play];
            }
        };
        _parsePlaylistRequest.onFailure = ^() {
            // Failed to parse the playlist; try playing anyway

#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioController: Playlist parsing failed, trying to play anyway, URL: %@", weakSelf.audioStream.url);
#endif
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
    }
    return _parsePlaylistRequest;
}

- (FSParseRssPodcastFeedRequest *)parseRssPodcastFeedRequest
{
    if (!_parseRssPodcastFeedRequest) {
        __weak FSAudioController *weakSelf = self;
        
        _parseRssPodcastFeedRequest = [[FSParseRssPodcastFeedRequest alloc] init];
        _parseRssPodcastFeedRequest.onCompletion = ^() {
            if ([weakSelf.parseRssPodcastFeedRequest.playlistItems count] > 0) {
                weakSelf.playlistItems = weakSelf.parseRssPodcastFeedRequest.playlistItems;
                
                weakSelf.readyToPlay = YES;
                
                weakSelf.audioStream.onCompletion = ^() {
                    if (weakSelf.currentPlaylistItemIndex + 1 < [weakSelf.playlistItems count]) {
                        weakSelf.currentPlaylistItemIndex = weakSelf.currentPlaylistItemIndex + 1;
                        
                        [weakSelf play];
                    }
                };
                
                [weakSelf play];
            }
        };
        _parseRssPodcastFeedRequest.onFailure = ^() {
            // Failed to parse the XML file; try playing anyway
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioController: Failed to parse the RSS feed, trying to play anyway, URL: %@", weakSelf.audioStream.url);
#endif
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
    }
    return _parseRssPodcastFeedRequest;
}

- (BOOL)isPlaying
{
    return [self.audioStream isPlaying];
}

/*
 * =======================================
 * Public interface
 * =======================================
 */

- (void)play
{
    if (!self.readyToPlay) {
        /*
         * Not ready to play; start by checking the content type of the given
         * URL.
         */
        [self.checkContentTypeRequest start];
        
        NSDictionary *userInfo = @{FSAudioStreamNotificationKey_State: @(kFsAudioStreamRetrievingURL)};
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
        [[NSNotificationCenter defaultCenter] postNotification:notification];
        
        return;
    }
    
    if ([self.playlistItems count] > 0) {
        self.audioStream.url = self.currentPlaylistItem.nsURL;
    }
    
    [self.audioStream play];
}

- (void)playFromURL:(NSURL*)url
{
    if (!url) {
        return;
    }
    
    [self stop];
    
    self.url = url;
        
    [self play];
}

- (void)stop
{
    [self.audioStream stop];
    
    self.readyToPlay = NO;
}

- (void)pause
{
    [self.audioStream pause];
}

-(BOOL)hasMultiplePlaylistItems
{
    return ([self.playlistItems count] > 1);
}

-(BOOL)hasNextItem
{
    return [self hasMultiplePlaylistItems] && (self.currentPlaylistItemIndex + 1 < [self.playlistItems count]);
}

-(BOOL)hasPreviousItem
{
    return ([self hasMultiplePlaylistItems] && (self.currentPlaylistItemIndex != 0));
}

-(void)playNextItem
{
    if ([self hasNextItem]) {
        self.currentPlaylistItemIndex = self.currentPlaylistItemIndex + 1;
        
        [self stop];
        
        [self play];
    }
}

-(void)playPreviousItem
{
    if ([self hasPreviousItem]) {
        self.currentPlaylistItemIndex = self.currentPlaylistItemIndex - 1;
        
        [self stop];
        
        [self play];
    }
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (void)setVolume:(float)volume
{
    self.audioStream.volume = volume;
}

- (float)volume
{
    return self.audioStream.volume;
}

- (void)setUrl:(NSURL *)url
{
    [self.audioStream stop];
    
    [self.checkContentTypeRequest cancel];
    [self.parsePlaylistRequest cancel];
    [self.parseRssPodcastFeedRequest cancel];
    
    self.playlistItems = [[NSMutableArray alloc] init];
    
    self.currentPlaylistItemIndex = 0;
    
    self.readyToPlay = NO;
    
    if (url) {
        NSURL *copyOfURL = [url copy];
        _url = copyOfURL;
        
        self.audioStream.url = _url;
    
        self.checkContentTypeRequest.url = _url;
        self.parsePlaylistRequest.url = _url;
        self.parseRssPodcastFeedRequest.url = _url;
        
        if ([_url isFileURL]) {
            /*
             * Local file URLs can be directly played
             */
            self.readyToPlay = YES;
        }
    } else {
        _url = nil;
    }
}

- (NSURL* )url
{
    if (!_url) {
        return nil;
    }
    
    NSURL *copyOfURL = [_url copy];
    return copyOfURL;
}

- (FSAudioStream *)stream
{
    return self.audioStream;
}

- (FSPlaylistItem *)currentPlaylistItem
{
    if (self.readyToPlay) {
        if ([self.playlistItems count] > 0) {
            FSPlaylistItem *playlistItem = (self.playlistItems)[self.currentPlaylistItemIndex];
            return playlistItem;
        }
    }
    return nil;
}

@end