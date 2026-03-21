//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Utils.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"

#include <Limelight.h>

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    id<ConnectionCallbacks> _callbacks;
    Connection* _connection;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _callbacks = callbacks;
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

- (void)main {
    [CryptoManager generateKeyPairUsingSSL];

    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];

    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [_callbacks launchFailed:serverInfoResp.statusMessage];
        return;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [_callbacks launchFailed:@"Failed to connect to PC"];
        return;
    }

    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [_callbacks launchFailed:@"Device not paired to PC"];
        return;
    }

    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [_callbacks launchFailed:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return;
        }
    }

    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;

    // resumeApp and launchApp handle calling launchFailed
    NSString* sessionUrl;
    if ([serverState hasSuffix:@"_SERVER_BUSY"]) {
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }

    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;

    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self->_callbacks streamAspectRatio:(float)self->_config.width / (float)self->_config.height useFramePacing:self->_config.useFramePacing];
        self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:renderer connectionCallbacks:self->_callbacks];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) stopStream
{
    [_connection terminate];
}

- (double) currentDisplayRefreshRate
{
    if (_connection == nil) {
        return 0.0;
    }

    return [_connection getVideoDisplayRefreshRate];
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [_callbacks launchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }

    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [_callbacks launchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }

    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (NSString*) getStatsOverlayText {
    video_stats_t stats;

    if (!_connection) {
        return nil;
    }

    if (![_connection getVideoStats:&stats]) {
        return nil;
    }

    float interval = stats.endTime - stats.startTime;
    if (interval <= 0.0f) {
        return nil;
    }

    float streamFps = stats.totalFrames / interval;
    float incomingFps = stats.receivedFrames / interval;
    float droppedPercentage = stats.totalFrames > 0 ? (100.0f * stats.networkDroppedFrames / (float)stats.totalFrames) : 0.0f;
    double renderedFps = [_connection getVideoRenderedFps];
    double decodeLatencyMs = [_connection getAverageDecoderLatencyMs];

    uint32_t rtt, variance;
    BOOL hasRtt = LiGetEstimatedRttInfo(&rtt, &variance);
    NSString* latencyString = hasRtt ? [NSString stringWithFormat:@"%u ms (variance: %u ms)", rtt, variance] : @"N/A";
    NSString* hostProcessingString;
    float hostProcessingAverageMs = 0.0f;
    if (stats.framesWithHostProcessingLatency != 0) {
        hostProcessingAverageMs = (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f;
        hostProcessingString = [NSString stringWithFormat:@"\nHost processing latency min/max/avg: %.1f/%.1f/%.1f ms",
                                stats.minHostProcessingLatency / 10.f,
                                stats.maxHostProcessingLatency / 10.f,
                                hostProcessingAverageMs];
    }
    else {
        hostProcessingString = @"";
    }

#if TARGET_OS_TV
    NSString* rangeInfo = [[NSUserDefaults standardUserDefaults] boolForKey:@"fullRangeVideo"] ? @"Full" : @"Limited";
    UIScreen* screen = nil;
    if (@available(tvOS 13.0, *)) {
        screen = _renderView.window.windowScene.screen;
    }
    if (screen == nil && _renderView.window != nil) {
        screen = _renderView.window.screen;
    }
    if (screen == nil) {
        screen = [[UIScreen screens] firstObject];
    }

    NSInteger displayMaxFps = 0;
    if (screen != nil) {
        displayMaxFps = screen.maximumFramesPerSecond;
    }

    NSMutableArray<NSString*>* segments = [NSMutableArray array];
    if (_config.requestedWidth > 0 && _config.requestedHeight > 0 && _config.requestedFrameRate > 0 &&
        (_config.requestedWidth != _config.width ||
         _config.requestedHeight != _config.height ||
         _config.requestedFrameRate != _config.frameRate)) {
        [segments addObject:[NSString stringWithFormat:@"Req %dx%d@%d", _config.requestedWidth, _config.requestedHeight, _config.requestedFrameRate]];
        [segments addObject:[NSString stringWithFormat:@"Use %dx%d@%d", _config.width, _config.height, _config.frameRate]];
    }
    else {
        [segments addObject:[NSString stringWithFormat:@"%dx%d@%d", _config.width, _config.height, _config.frameRate]];
    }
    [segments addObject:[_connection getActiveCodecName]];
    [segments addObject:[NSString stringWithFormat:@"In %.1f", incomingFps]];
    [segments addObject:[NSString stringWithFormat:@"Stream %.1f", streamFps]];
    if (renderedFps > 0.0) {
        [segments addObject:[NSString stringWithFormat:@"Render %.1f", renderedFps]];
    }
    if (decodeLatencyMs > 0.0) {
        [segments addObject:[NSString stringWithFormat:@"Decode %.1f ms", decodeLatencyMs]];
    }

    double displayRefreshRate = [_connection getVideoDisplayRefreshRate];
    if (displayRefreshRate > 0.0) {
        [segments addObject:[NSString stringWithFormat:@"Output %.1f Hz", displayRefreshRate]];
    }
    else if (displayMaxFps > 0) {
        [segments addObject:[NSString stringWithFormat:@"Display %ld Hz", (long)displayMaxFps]];
    }

    if (hasRtt) {
        [segments addObject:[NSString stringWithFormat:@"RTT %u±%u ms", rtt, variance]];
    }
    else {
        [segments addObject:@"RTT N/A"];
    }

    [segments addObject:[NSString stringWithFormat:@"Drop %.1f%%", droppedPercentage]];

    if (stats.framesWithHostProcessingLatency != 0) {
        [segments addObject:[NSString stringWithFormat:@"Host %.1f ms", hostProcessingAverageMs]];
    }

    [segments addObject:[NSString stringWithFormat:@"%@ range", rangeInfo]];
    if (!_config.effectiveSops) {
        [segments addObject:@"SOPS off"];
    }

    if (LiGetCurrentHostDisplayHdrMode()) {
        [segments addObject:@"HDR"];
    }

    return [segments componentsJoinedByString:@"  •  "];
#else
    NSString* displayInfo = @"";
    return [NSString stringWithFormat:@"Video stream: %dx%d %.2f FPS (Codec: %@)\nFrames dropped by your network connection: %.2f%%\nAverage network latency: %@%@%@",
            _config.width,
            _config.height,
            averageFps,
            [_connection getActiveCodecName],
            droppedPercentage,
            latencyString,
            hostProcessingString,
            displayInfo];
#endif
}

@end
