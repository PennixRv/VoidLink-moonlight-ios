//
//  UIAppView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIAppView.h"
#import "AppAssetManager.h"

static const float REFRESH_CYCLE = 1.0f;

@implementation UIAppView {
    TemporaryApp* _app;
    UILabel* _appLabel;
    UIImageView* _appOverlay;
    UIImageView* _appImage;
    NSCache* _artCache;
    id<AppCallback> _callback;
#if TARGET_OS_TV
    UIInterpolatingMotionEffect* _motionEffectH;
    UIInterpolatingMotionEffect* _motionEffectV;
#endif
}

static UIImage* noImage;

- (id) initWithApp:(TemporaryApp*)app cache:(NSCache*)cache andCallback:(id<AppCallback>)callback {
    self = [super init];
    _app = app;
    _callback = callback;
    _artCache = cache;
    
    // Cache the NoAppImage ourselves to avoid
    // having to load it each time
    if (noImage == nil) {
        noImage = [UIImage imageNamed:@"NoAppImage"];
    }
        
#if TARGET_OS_TV
    self.frame = CGRectMake(0, 0, 200, 265);
#else
    self.frame = CGRectMake(0, 0, 150, 200);
#endif
    
    [self setAlpha:app.hidden ? 0.4 : 1.0];

    _appImage = [[UIImageView alloc] initWithFrame:self.frame];
    _appImage.contentMode = UIViewContentModeScaleAspectFill;
    [_appImage setImage:noImage];
    [self addSubview:_appImage];
    
    // Use UIContextMenuInteraction on iOS 13.0+ and a standard UILongPressGestureRecognizer
    // for tvOS devices and iOS prior to 13.0.
#if !TARGET_OS_TV
    if (@available(iOS 13.0, *)) {
        UIContextMenuInteraction* rightClickInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:rightClickInteraction];
    }
    else
#endif
    {
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(appLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }
    
    [self addTarget:self action:@selector(appClicked:) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    [self addTarget:self action:@selector(buttonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(buttonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    
#if TARGET_OS_TV
    _appImage.adjustsImageWhenAncestorFocused = YES;
    _appImage.layer.cornerRadius = 16.0;
    if (@available(tvOS 13.0, *)) {
        _appImage.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _appImage.clipsToBounds = YES;
    
    self.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.layer.shadowOffset = CGSizeMake(0, 0);
    self.layer.shadowOpacity = 0.0;
    self.layer.shadowRadius = 18.0;
    self.clipsToBounds = NO;
    
    _motionEffectH = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    _motionEffectH.minimumRelativeValue = @(-8);
    _motionEffectH.maximumRelativeValue = @(8);
    _motionEffectV = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    _motionEffectV.minimumRelativeValue = @(-8);
    _motionEffectV.maximumRelativeValue = @(8);
#else
    // Rasterizing the cell layer increases rendering performance by quite a bit
    // but we want it unrasterized for tvOS where it must be scaled.
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    
    if (@available(iOS 13.4.1, *)) {
        // Allow the button style to change when moused over
        self.pointerInteractionEnabled = YES;
    }
#endif
    
    [self updateAppImage];
    
    return self;
}

#if TARGET_OS_TV
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    
    BOOL nextIsSelf = (context.nextFocusedView == self);
    BOOL prevIsSelf = (context.previouslyFocusedView == self);
    if (!nextIsSelf && !prevIsSelf) {
        return;
    }
    
    BOOL focused = nextIsSelf;
    CGFloat targetScale = focused ? 1.1 : 1.0;
    CGFloat scaleDiff = (self.bounds.size.height * targetScale - self.bounds.size.height) / 2.0;
    CGAffineTransform targetTransform = focused ? CGAffineTransformTranslate(CGAffineTransformMakeScale(targetScale, targetScale), 0, -scaleDiff) : CGAffineTransformIdentity;
    
    [coordinator addCoordinatedAnimations:^{
        self.transform = targetTransform;
        self.layer.shadowOffset = focused ? CGSizeMake(0, 16) : CGSizeMake(0, 0);
        self.layer.shadowOpacity = focused ? 0.20 : 0.0;
        self.layer.shadowRadius = 18.0;
    } completion:nil];
    
    if (focused) {
        if (_motionEffectH != nil) {
            [self addMotionEffect:_motionEffectH];
        }
        if (_motionEffectV != nil) {
            [self addMotionEffect:_motionEffectV];
        }
    }
    else {
        if (_motionEffectH != nil) {
            [self removeMotionEffect:_motionEffectH];
        }
        if (_motionEffectV != nil) {
            [self removeMotionEffect:_motionEffectV];
        }
    }
}
#endif

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil) {
        [self updateLoop];
    }
}

- (void) appClicked:(UIView *)view {
    [_callback appClicked:_app view:view];
}

- (void) appLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback appLongClicked:_app view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    // We don't want to trigger the primary action at this point, so cancel
    // tracking touch on this view now. This will also have the (intended)
    // effect of removing the touch highlight on this view.
    [self cancelTrackingWithEvent:nil];
    
    [_callback appLongClicked:_app view:self];
    return nil;
}
#endif

- (void) updateAppImage {
    if (_appOverlay != nil) {
        [_appOverlay removeFromSuperview];
        _appOverlay = nil;
    }
    if (_appLabel != nil) {
        [_appLabel removeFromSuperview];
        _appLabel = nil;
    }
    
    BOOL noAppImage = false;
    
    // First check the memory cache
    UIImage* appImage = [_artCache objectForKey:_app];
    if (appImage == nil) {
        // Next try to load from the on disk cache
        appImage = [UIImage imageWithContentsOfFile:[AppAssetManager boxArtPathForApp:_app]];
        if (appImage != nil) {
            [_artCache setObject:appImage forKey:_app];
        }
    }
    
    if (appImage != nil) {
        // This size of image might be blank image received from GameStream.
        // TODO: Improve no-app image detection
        if (!(appImage.size.width == 130.f && appImage.size.height == 180.f) && // GFE 2.0
            !(appImage.size.width == 628.f && appImage.size.height == 888.f)) { // GFE 3.0
            [_appImage setImage:appImage];
        } else {
            noAppImage = true;
        }
    } else {
        noAppImage = true;
    }
    
    if ([_app.id isEqualToString:_app.host.currentGame]) {
        // Only create the app overlay if needed
        _appOverlay = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Play"]];
        _appOverlay.layer.shadowColor = [UIColor blackColor].CGColor;
        _appOverlay.layer.shadowOffset = CGSizeMake(0, 0);
        _appOverlay.layer.shadowOpacity = 1;
        _appOverlay.layer.shadowRadius = 4.0;
        _appOverlay.contentMode = UIViewContentModeScaleAspectFit;
    }
    
    if (noAppImage) {
        _appLabel = [[UILabel alloc] init];
        [_appLabel setTextColor:[UIColor whiteColor]];
        [_appLabel setText:_app.name];
#if TARGET_OS_TV
        [_appLabel setFont:[UIFont systemFontOfSize:28 weight:UIFontWeightMedium]];
#else
        [_appLabel setFont:[UIFont systemFontOfSize:24]];
#endif
        [_appLabel setBaselineAdjustment:UIBaselineAdjustmentAlignCenters];
        [_appLabel setTextAlignment:NSTextAlignmentCenter];
        [_appLabel setLineBreakMode:NSLineBreakByWordWrapping];
        [_appLabel setNumberOfLines:0];
    }
    
    [self positionSubviews];
    
#if TARGET_OS_TV
    [_appImage.overlayContentView addSubview:_appLabel];
    [_appImage.overlayContentView addSubview:_appOverlay];
#else
    [self addSubview:_appLabel];
    [self addSubview:_appOverlay];
#endif
}

- (void) buttonSelected:(id)sender {
    _appImage.layer.opacity = 0.5f;
}
- (void) buttonDeselected:(id)sender {
    _appImage.layer.opacity = 1.0f;
}

- (void) positionSubviews {
    CGFloat padding = 5.f;
    CGSize frameSize = _appImage.frame.size;
    CGPoint center = _appImage.center;
    
    if (_appLabel != nil) {
        if (_appOverlay != nil) {
            _appOverlay.frame = CGRectMake(0, 0, frameSize.width / 3, frameSize.width / 3);
            _appOverlay.center = CGPointMake(frameSize.width / 2, padding + _appOverlay.frame.size.height / 2);
            
            [_appLabel setFrame:CGRectMake(padding, _appOverlay.frame.size.height + padding, frameSize.width - 2 * padding, frameSize.height - _appOverlay.frame.size.height - 2 * padding)];
        }
        else {
            [_appLabel setFrame:CGRectMake(padding, padding, frameSize.width - 2 * padding, frameSize.height - 2 * padding)];
        }
    }
    else if (_appOverlay != nil) {
        _appOverlay.frame = CGRectMake(0, 0, frameSize.width / 2, frameSize.width / 2);
        _appOverlay.center = center;
    }
}

- (void) updateLoop {
    // Stop immediately if the view has been detached
    if (self.superview == nil) {
        return;
    }
    
    // Update the app image if neccessary
    if ((_appOverlay != nil && ![_app.id isEqualToString:_app.host.currentGame]) ||
        (_appOverlay == nil && [_app.id isEqualToString:_app.host.currentGame])) {
        [self updateAppImage];
    }
    
    // Show no shadow for hidden apps. Because we adjust the opacity of the
    // cells for hidden apps, it makes them look bad when the shadow draws
    // through the app tile.
    self.superview.layer.shadowOpacity = _app.hidden ? 0.0f : 0.5f;
    
    // Update opacity if neccessary
    [self setAlpha:_app.hidden ? 0.4 : 1.0];
    
    // Queue the next refresh cycle
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

@end
