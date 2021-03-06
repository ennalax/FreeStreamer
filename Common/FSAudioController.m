/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
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

@synthesize readyToPlay;
@synthesize currentPlaylistItemIndex;
@synthesize playlistItems;

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

- (id)initWithUrl:(NSString *)url
{
    if (self = [self init]) {
        self.url = url;
    }
    return self;
}

- (void)dealloc
{
    [_audioStream stop];
    
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
    @synchronized (self) {
        if (self.readyToPlay) {
            if ([self.playlistItems count] > 0) {
                FSPlaylistItem *playlistItem = (self.playlistItems)[self.currentPlaylistItemIndex];
                
                self.audioStream.url = playlistItem.nsURL;
            }
            
            [self.audioStream play];
            return;
        }
        
        [self.checkContentTypeRequest start];
        
        NSDictionary *userInfo = @{FSAudioStreamNotificationKey_State: @(kFsAudioStreamRetrievingURL)};
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
}

- (void)playFromURL:(NSString*)url
{
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

/*
 * =======================================
 * Properties
 * =======================================
 */

- (void)setUrl:(NSString *)url
{
    @synchronized (self) {
        if (!url) {
            [self.audioStream stop];
            _url = nil;
            return;
        }
        
        self.currentPlaylistItemIndex = 0;
        
        if (![url isEqual:_url]) {
            [self.audioStream stop];
            
            [self.checkContentTypeRequest cancel];
            [self.parsePlaylistRequest cancel];
            [self.parseRssPodcastFeedRequest cancel];
            
            self.checkContentTypeRequest.url = url;
            self.parsePlaylistRequest.url = url;
            self.parseRssPodcastFeedRequest.url = url;
            
            NSString *copyOfURL = [url copy];
            _url = copyOfURL;
            /* Since the stream URL changed, the content may have changed */
            self.readyToPlay = NO;
            self.playlistItems = [[NSMutableArray alloc] init];
        }
    
        self.audioStream.url = [NSURL URLWithString:_url];
    }
}

- (NSString*)url
{
    if (!_url) {
        return nil;
    }
    
    NSString *copyOfURL = [_url copy];
    return copyOfURL;
}

- (FSAudioStream *)stream
{
    return self.audioStream;
}

@end