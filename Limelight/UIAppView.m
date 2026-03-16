//
//  UIAppView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIAppView.h"
#import "AppAssetManager.h"

#if TARGET_OS_TV
#import "VLTVOSUI.h"
#endif

static const float REFRESH_CYCLE = 1.0f;

#if TARGET_OS_TV
@interface VLMarqueeLabel : UIView
@property (nonatomic, copy) NSString* text;
@property (nonatomic, strong) UIFont* font;
@property (nonatomic, strong) UIColor* textColor;
- (void)startIfNeeded;
- (void)stop;
@end

@implementation VLMarqueeLabel {
    UILabel* _label;
    BOOL _animating;
    CGFloat _lastOverflow;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;

        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.numberOfLines = 1;
        _label.lineBreakMode = NSLineBreakByClipping;
        _label.textAlignment = NSTextAlignmentLeft;
        [self addSubview:_label];
    }
    return self;
}

- (NSString *)text { return _label.text; }
- (void)setText:(NSString *)text { _label.text = text; }
- (UIFont *)font { return _label.font; }
- (void)setFont:(UIFont *)font { _label.font = font; }
- (UIColor *)textColor { return _label.textColor; }
- (void)setTextColor:(UIColor *)textColor { _label.textColor = textColor; }

- (void)layoutSubviews {
    [super layoutSubviews];

    // If our size changed while animating, restart cleanly to avoid odd offsets.
    if (_animating) {
        [self startIfNeeded];
    }
}

- (void)startIfNeeded {
    [self stop];

    if (self.bounds.size.width <= 1.0) {
        return;
    }

    // Measure single-line width.
    CGSize fit = [_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, self.bounds.size.height)];
    CGFloat overflow = fit.width - self.bounds.size.width;
    _lastOverflow = overflow;
    if (overflow <= 8.0) {
        _label.frame = self.bounds;
        _label.transform = CGAffineTransformIdentity;
        return;
    }

    _animating = YES;
    _label.frame = self.bounds;
    _label.transform = CGAffineTransformIdentity;

    // Scroll speed tuned for tvOS readability. Cap duration to avoid comically slow scroll.
    CGFloat pixelsPerSecond = 55.0;
    CGFloat duration = MAX(2.2, MIN(12.0, overflow / pixelsPerSecond));

    __weak typeof(self) weakSelf = self;
    void (^animateOnce)(void) = ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf->_animating) {
            return;
        }
        [UIView animateWithDuration:duration
                              delay:0.75
                            options:UIViewAnimationOptionCurveLinear
                         animations:^{
            strongSelf->_label.transform = CGAffineTransformMakeTranslation(-overflow, 0);
        } completion:^(BOOL finished) {
            __strong typeof(self) strongSelf2 = weakSelf;
            if (strongSelf2 == nil || !finished || !strongSelf2->_animating) {
                return;
            }
            // Reset and loop with a small pause for readability.
            strongSelf2->_label.transform = CGAffineTransformIdentity;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                animateOnce();
            });
        }];
    };

    animateOnce();
}

- (void)stop {
    _animating = NO;
    [_label.layer removeAllAnimations];
    _label.transform = CGAffineTransformIdentity;
    _label.frame = self.bounds;
}

@end
#endif

@implementation UIAppView {
    TemporaryApp* _app;
 #if !TARGET_OS_TV
    UILabel* _appLabel;
 #endif
    UIImageView* _appOverlay;
    UIImageView* _appImage;
    NSCache* _artCache;
    id<AppCallback> _callback;
#if TARGET_OS_TV
    UIInterpolatingMotionEffect* _motionEffectH;
    UIInterpolatingMotionEffect* _motionEffectV;
    UIView* _titleOverlayContainer;
    CAGradientLayer* _titleGradientLayer;
    VLMarqueeLabel* _titleLabel;
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
    // Match the tvOS storyboard cell size (Main.storyboard: AppCell itemSize=300x400)
    // so we don't need to scale the whole view (which makes fonts and corner radii harder to tune).
    self.frame = CGRectMake(0, 0, 300, 400);
#else
    self.frame = CGRectMake(0, 0, 150, 200);
#endif
    
    [self setAlpha:app.hidden ? 0.4 : 1.0];

    _appImage = [[UIImageView alloc] initWithFrame:self.bounds];
    _appImage.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
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
    _appImage.layer.cornerRadius = VLTVOSCardCornerRadius;
    VLTVOSSetContinuousCornerIfAvailable(_appImage.layer);
    _appImage.clipsToBounds = YES;
    
    self.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.layer.shadowOffset = CGSizeMake(0, 0);
    self.layer.shadowOpacity = 0.0;
    self.layer.shadowRadius = 18.0;
    self.clipsToBounds = NO;
    
    _motionEffectH = VLTVOSCreateMotionEffect(@"center.x", UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis);
    _motionEffectV = VLTVOSCreateMotionEffect(@"center.y", UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis);

    // Bottom title overlay (gradient + marquee on focus), inspired by modern tvOS clients.
    _titleOverlayContainer = [[UIView alloc] initWithFrame:CGRectZero];
    _titleOverlayContainer.userInteractionEnabled = NO;
    _titleOverlayContainer.clipsToBounds = YES;
    _titleOverlayContainer.layer.cornerRadius = VLTVOSCardCornerRadius;
    VLTVOSSetContinuousCornerIfAvailable(_titleOverlayContainer.layer);
    if (@available(tvOS 11.0, *)) {
        _titleOverlayContainer.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }

    _titleGradientLayer = [CAGradientLayer layer];
    _titleGradientLayer.startPoint = CGPointMake(0.5, 0.0);
    _titleGradientLayer.endPoint = CGPointMake(0.5, 1.0);
    _titleGradientLayer.locations = @[ @0.0, @1.0 ];
    _titleGradientLayer.colors = @[
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.68].CGColor,
    ];
    [_titleOverlayContainer.layer insertSublayer:_titleGradientLayer atIndex:0];

    _titleLabel = [[VLMarqueeLabel alloc] initWithFrame:CGRectZero];
    _titleLabel.userInteractionEnabled = NO;
    _titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor whiteColor];
    [_titleOverlayContainer addSubview:_titleLabel];

    [_appImage.overlayContentView addSubview:_titleOverlayContainer];
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
    CGAffineTransform targetTransform = VLTVOSFocusTransformForBounds(self.bounds, focused);
    
    [coordinator addCoordinatedAnimations:^{
        self.transform = targetTransform;
        self.layer.shadowOffset = focused ? CGSizeMake(0, VLTVOSCardShadowOffsetYFocused) : CGSizeMake(0, 0);
        self.layer.shadowOpacity = focused ? 0.20 : 0.0;
        self.layer.shadowRadius = VLTVOSCardShadowRadiusFocused;
    } completion:nil];

    VLTVOSUpdateMotionEffectsForFocus(self, _motionEffectH, _motionEffectV, focused);

    // Marquee only when focused to keep the screen calm.
    if (_titleLabel != nil) {
        if (focused) {
            [_titleLabel startIfNeeded];
        }
        else {
            [_titleLabel stop];
        }
    }
}

- (void)tvosSetAncestorFocused:(BOOL)focused
{
    if (_titleLabel == nil) {
        return;
    }
    if (focused) {
        [_titleLabel startIfNeeded];
    }
    else {
        [_titleLabel stop];
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
#if !TARGET_OS_TV
    if (_appLabel != nil) {
        [_appLabel removeFromSuperview];
        _appLabel = nil;
    }
#endif
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
    
    // Always show the title overlay for fast scanning on tvOS.
#if TARGET_OS_TV
    if (_titleLabel != nil) {
        _titleLabel.text = _app.name ?: @"";
        // If we're already focused, restart the marquee in case the title changed.
        if (self.isFocused) {
            [_titleLabel startIfNeeded];
        }
    }
#else
    // Keep the old fallback label behavior on iOS where the UI layout differs.
    if (noAppImage) {
        _appLabel = [[UILabel alloc] init];
        [_appLabel setTextColor:[UIColor whiteColor]];
        [_appLabel setText:_app.name];
        [_appLabel setFont:[UIFont systemFontOfSize:24]];
        [_appLabel setBaselineAdjustment:UIBaselineAdjustmentAlignCenters];
        [_appLabel setTextAlignment:NSTextAlignmentCenter];
        [_appLabel setLineBreakMode:NSLineBreakByWordWrapping];
        [_appLabel setNumberOfLines:0];
    }
#endif

    [self positionSubviews];
    
#if TARGET_OS_TV
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

#if !TARGET_OS_TV
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
    return;
#endif

    if (_appOverlay != nil) {
        // Small corner overlay looks cleaner than a giant centered play icon.
        CGFloat overlaySize = MIN(frameSize.width, frameSize.height) * 0.22;
        CGFloat inset = 14.0;
        _appOverlay.frame = CGRectMake(frameSize.width - overlaySize - inset,
                                       inset,
                                       overlaySize,
                                       overlaySize);
    }

#if TARGET_OS_TV
    if (_titleOverlayContainer != nil && _titleGradientLayer != nil && _titleLabel != nil) {
        CGFloat overlayHeight = 96.0;
        _titleOverlayContainer.frame = CGRectMake(0,
                                                  frameSize.height - overlayHeight,
                                                  frameSize.width,
                                                  overlayHeight);
        _titleGradientLayer.frame = _titleOverlayContainer.bounds;

        // Insets tuned to keep Chinese readable without covering too much box art.
        CGFloat insetX = 18.0;
        CGFloat insetY = 12.0;
        _titleLabel.frame = CGRectMake(insetX,
                                       insetY,
                                       _titleOverlayContainer.bounds.size.width - insetX * 2,
                                       _titleOverlayContainer.bounds.size.height - insetY * 2);
    }
#endif
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
    
    // Update opacity if neccessary
    [self setAlpha:_app.hidden ? 0.4 : 1.0];
    
    // Queue the next refresh cycle
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

@end
