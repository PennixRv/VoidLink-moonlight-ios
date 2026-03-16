//
//  UIComputerView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIComputerView.h"

#if TARGET_OS_TV
#import "VLTVOSUI.h"
#endif

@implementation UIComputerView {
    TemporaryHost* _host;
    UIVisualEffectView* _cardBackground;
    UIView* _selectedHighlightView;
    UIImageView* _hostIcon;
    UILabel* _hostLabel;
    UIImageView* _hostOverlay;
    UIActivityIndicatorView* _hostSpinner;
    id<HostCallback> _callback;
    CGSize _labelSize;
#if TARGET_OS_TV
    UIInterpolatingMotionEffect* _motionEffectH;
    UIInterpolatingMotionEffect* _motionEffectV;
    UIView* _statusBadgeContainer;
    UILabel* _statusBadgeLabel;
#endif
}
static const float REFRESH_CYCLE = 2.0f;

#if TARGET_OS_TV
static const int ITEM_PADDING = 50;
static const int LABEL_DY = 40;
#else
static const int ITEM_PADDING = 0;
static const int LABEL_DY = 20;
#endif

- (id) init {
    self = [super init];
        
#if TARGET_OS_TV
    self.frame = CGRectMake(0, 0, 400, 400);
#else
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        self.frame = CGRectMake(0, 0, 200, 200);
    } else {
        self.frame = CGRectMake(0, 0, 100, 100);
    }
#endif
    
    _hostIcon = [[UIImageView alloc] initWithFrame:self.frame];
    _hostIcon.contentMode = UIViewContentModeScaleAspectFit;
#if TARGET_OS_TV
    // Use template rendering so we can invert tint colors on focus, similar to modern tvOS apps.
    [_hostIcon setImage:[[UIImage imageNamed:@"Computer"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _hostIcon.tintColor = [UIColor whiteColor];
#else
    [_hostIcon setImage:[UIImage imageNamed:@"Computer"]];
#endif
    
    self.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.layer.shadowOffset = CGSizeMake(0, 10);
    self.layer.shadowOpacity = 0.0;
    self.layer.shadowRadius = 16.0;
    self.clipsToBounds = NO;

    [self addTarget:self action:@selector(hostButtonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(hostButtonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    
    _hostLabel = [[UILabel alloc] init];
#if TARGET_OS_TV
    _hostLabel.textColor = VLTVOSCardForegroundColor(self.traitCollection, NO);
    _hostLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightSemibold];
#else
    _hostLabel.textColor = [UIColor whiteColor];
#endif
    
    _hostOverlay = [[UIImageView alloc] initWithFrame:CGRectMake(self.frame.size.width / 3, _hostIcon.frame.size.height / 4, _hostIcon.frame.size.width / 3, self.frame.size.height / 3)];
    _hostSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [_hostSpinner setFrame:_hostOverlay.frame];
    _hostSpinner.userInteractionEnabled = NO;
    _hostSpinner.hidesWhenStopped = YES;

#if TARGET_OS_TV
    // tvOS-style "material" card behind the host icon.
    _cardBackground = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:VLTVOSCardBlurStyle(self.traitCollection)]];
    _cardBackground.frame = _hostIcon.frame;
    _cardBackground.userInteractionEnabled = NO;
    _cardBackground.alpha = 0.7;
    _cardBackground.clipsToBounds = YES;
    _cardBackground.layer.cornerRadius = VLTVOSCardCornerRadius;
    VLTVOSSetContinuousCornerIfAvailable(_cardBackground.layer);
    
    _selectedHighlightView = [[UIView alloc] initWithFrame:_cardBackground.bounds];
    _selectedHighlightView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _selectedHighlightView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    _selectedHighlightView.hidden = YES;
    [_cardBackground.contentView addSubview:_selectedHighlightView];
    
    _motionEffectH = VLTVOSCreateMotionEffect(@"center.x", UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis);
    _motionEffectV = VLTVOSCreateMotionEffect(@"center.y", UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis);

    // A small corner badge for quick status scanning (online/offline/pairing).
    _statusBadgeContainer = [[UIView alloc] initWithFrame:CGRectZero];
    _statusBadgeContainer.userInteractionEnabled = NO;
    _statusBadgeContainer.hidden = YES;
    _statusBadgeContainer.backgroundColor = [UIColor colorWithRed:0.98 green:0.31 blue:0.55 alpha:0.95];
    _statusBadgeContainer.layer.cornerRadius = 12.0;
    if (@available(tvOS 11.0, *)) {
        _statusBadgeContainer.layer.maskedCorners = kCALayerMinXMaxYCorner;
    }
    _statusBadgeContainer.layer.masksToBounds = YES;
    [_cardBackground.contentView addSubview:_statusBadgeContainer];

    _statusBadgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusBadgeLabel.userInteractionEnabled = NO;
    _statusBadgeLabel.textColor = [UIColor whiteColor];
    _statusBadgeLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    [_statusBadgeContainer addSubview:_statusBadgeLabel];
#endif
    
#if TARGET_OS_TV
    [self addSubview:_cardBackground];
#endif
    [self addSubview:_hostLabel];
    [self addSubview:_hostIcon];
    
#if TARGET_OS_TV
    _hostIcon.clipsToBounds = NO;
    _hostIcon.adjustsImageWhenAncestorFocused = YES;
    _hostIcon.masksFocusEffectToContents = YES;
    
    self.adjustsImageWhenHighlighted = NO;
    
    _hostOverlay.masksFocusEffectToContents = YES;
    _hostOverlay.adjustsImageWhenAncestorFocused = NO;
    
    [_hostIcon.overlayContentView addSubview:_hostOverlay];
    [_hostIcon.overlayContentView addSubview:_hostSpinner];
#else
    [self addSubview:_hostOverlay];
    [self addSubview:_hostSpinner];
    
    if (@available(iOS 13.4.1, *)) {
        // Allow the button style to change when moused over
        self.pointerInteractionEnabled = YES;
    }
#endif
    
    return self;
}

#if TARGET_OS_TV
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    if (@available(tvOS 13.0, *)) {
        if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
            // Keep card blur and text colors consistent with the system appearance.
            _cardBackground.effect = [UIBlurEffect effectWithStyle:VLTVOSCardBlurStyle(self.traitCollection)];
            UIColor* fg = VLTVOSCardForegroundColor(self.traitCollection, self.isFocused);
            _hostLabel.textColor = fg;
            _hostIcon.tintColor = fg;
            _hostOverlay.tintColor = fg;
        }
    }
}

- (void)tvosUpdateStatusBadge {
    if (_statusBadgeContainer == nil || _statusBadgeLabel == nil) {
        return;
    }

    NSString* text = nil;
    UIColor* color = [UIColor colorWithRed:0.98 green:0.31 blue:0.55 alpha:0.95];

    if (_host == nil) {
        // Add-host tile doesn't need a badge.
        text = nil;
    }
    else if (_host.state == StateOnline) {
        if (_host.pairState == PairStateUnpaired) {
            text = VLTVOS_STR(@"Pair", @"需配对");
            color = [UIColor colorWithRed:0.98 green:0.62 blue:0.15 alpha:0.95];
        }
        else {
            text = VLTVOS_STR(@"Online", @"在线");
            color = [UIColor colorWithRed:0.23 green:0.78 blue:0.35 alpha:0.95];
        }
    }
    else if (_host.state == StateOffline) {
        text = VLTVOS_STR(@"Offline", @"离线");
        color = [UIColor colorWithRed:0.95 green:0.23 blue:0.23 alpha:0.95];
    }
    else {
        text = VLTVOS_STR(@"Connecting", @"连接中");
        color = [UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:0.95];
    }

    _statusBadgeContainer.hidden = (text == nil || text.length == 0);
    _statusBadgeContainer.backgroundColor = color;
    _statusBadgeLabel.text = text;
    [_statusBadgeLabel sizeToFit];

    // Layout: pin to top-right, with internal padding.
    CGFloat paddingX = 10.0;
    CGFloat paddingY = 6.0;
    CGFloat w = _statusBadgeLabel.bounds.size.width + paddingX * 2;
    CGFloat h = _statusBadgeLabel.bounds.size.height + paddingY * 2;
    _statusBadgeContainer.frame = CGRectMake(_cardBackground.bounds.size.width - w, 0, w, h);
    _statusBadgeLabel.frame = CGRectMake(paddingX, paddingY,
                                        _statusBadgeContainer.bounds.size.width - paddingX * 2,
                                        _statusBadgeContainer.bounds.size.height - paddingY * 2);
}

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
        self.layer.shadowOpacity = focused ? VLTVOSCardShadowOpacityFocused : VLTVOSCardShadowOpacityUnfocused;
        self.layer.shadowRadius = focused ? VLTVOSCardShadowRadiusFocused : 16.0;
        self->_cardBackground.alpha = focused ? 0.92 : 0.74;
    } completion:nil];
    
    _selectedHighlightView.hidden = !focused;
    
    UIColor* fg = VLTVOSCardForegroundColor(self.traitCollection, focused);
    _hostIcon.tintColor = fg;
    _hostOverlay.tintColor = fg;
    _hostLabel.textColor = fg;

    VLTVOSUpdateMotionEffectsForFocus(self, _motionEffectH, _motionEffectV, focused);
}
#endif

- (void) hostButtonSelected:(id)sender {
    _hostIcon.layer.opacity = 0.5f;
    _hostSpinner.layer.opacity = 0.5f;
    _hostOverlay.layer.opacity = 0.5f;
}
- (void) hostButtonDeselected:(id)sender {
    _hostIcon.layer.opacity = 1.0f;
    _hostSpinner.layer.opacity = 1.0f;
    _hostOverlay.layer.opacity = 1.0f;
}

- (id) initForAddWithCallback:(id<HostCallback>)callback {
    self = [self init];
    _callback = callback;
    
    [self addTarget:self action:@selector(addClicked) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    [_hostLabel setText:VLTVOS_STR(@"Add Host Manually", @"手动添加主机")];
    [_hostLabel sizeToFit];
    
    [_hostOverlay setImage:[UIImage imageNamed:@"AddOverlayIcon"]];
    
    [self updateBounds];
        
    return self;
}

- (id) initWithComputer:(TemporaryHost*)host andCallback:(id<HostCallback>)callback {
    self = [self init];
    _host = host;
    _callback = callback;
    
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
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hostLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }
    
    [self addTarget:self action:@selector(hostClicked) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    [self updateContentsForHost:host];

    return self;
}

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil && _host != nil) {
        [self updateLoop];
    }
}

- (void) updateBounds {
    float x = FLT_MAX;
    float y = FLT_MAX;
    float width = 0;
    float height;
    
    float iconX = _hostIcon.frame.origin.x + _hostIcon.frame.size.width / 2;
    _hostLabel.center = CGPointMake(iconX, _hostIcon.frame.origin.y + _hostIcon.frame.size.height + LABEL_DY);
    
    x = MIN(x, _hostIcon.frame.origin.x);
    x = MIN(x, _hostLabel.frame.origin.x);
    
    y = MIN(y, _hostIcon.frame.origin.y);
    y = MIN(y, _hostLabel.frame.origin.y);

    width = MAX(width, _hostIcon.frame.size.width);
    width = MAX(width, _hostLabel.frame.size.width);
    
    height = _hostIcon.frame.size.height +
        _hostLabel.frame.size.height +
        LABEL_DY / 2;
    
    self.bounds = CGRectMake(x - ITEM_PADDING, y - ITEM_PADDING, width + 2 * ITEM_PADDING, height + 2 * ITEM_PADDING);
    
#if TARGET_OS_TV
    // Keep the material card pinned to the icon region (not the label).
    _cardBackground.frame = _hostIcon.frame;
    [self tvosUpdateStatusBadge];
#endif
}

- (void) updateContentsForHost:(TemporaryHost*)host {
    _hostLabel.text = _host.name;
    [_hostLabel sizeToFit];
    
    if (host.state == StateOnline) {
        [_hostSpinner stopAnimating];

        if (host.pairState == PairStateUnpaired) {
            UIImage* img = [UIImage imageNamed:@"LockedOverlayIcon"];
#if TARGET_OS_TV
            img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
#endif
            [_hostOverlay setImage:img];
        }
        else {
            [_hostOverlay setImage:nil];
        }
    }
    else if (host.state == StateOffline) {
        [_hostSpinner stopAnimating];
        UIImage* img = [UIImage imageNamed:@"ErrorOverlayIcon"];
#if TARGET_OS_TV
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
#endif
        [_hostOverlay setImage:img];
    }
    else {
        [_hostSpinner startAnimating];
    }
    
    [self updateBounds];
}

- (void) updateLoop {
    // Stop immediately if the view has been detached
    if (self.superview == nil) {
        return;
    }
    
    [self updateContentsForHost:_host];
    
    // Queue the next refresh cycle
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

- (void) hostLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback hostLongClicked:_host view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    // We don't want to trigger the primary action at this point, so cancel
    // tracking touch on this view now. This will also have the (intended)
    // effect of removing the touch highlight on this view.
    [self cancelTrackingWithEvent:nil];
    
    [_callback hostLongClicked:_host view:self];
    return nil;
}
#endif

- (void) hostClicked {
    [_callback hostClicked:_host view:self];
}

- (void) addClicked {
    [_callback addHostClicked];
}

@end
