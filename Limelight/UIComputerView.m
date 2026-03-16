//
//  UIComputerView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIComputerView.h"

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
    _hostLabel.textColor = [UIColor whiteColor];
    if (@available(tvOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
            _hostLabel.textColor = [UIColor blackColor];
        }
    }
    _hostLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightMedium];
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
    _cardBackground = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _cardBackground.frame = _hostIcon.frame;
    _cardBackground.userInteractionEnabled = NO;
    _cardBackground.alpha = 0.7;
    _cardBackground.clipsToBounds = YES;
    _cardBackground.layer.cornerRadius = 16.0;
    if (@available(tvOS 13.0, *)) {
        _cardBackground.layer.cornerCurve = kCACornerCurveContinuous;
    }
    
    _selectedHighlightView = [[UIView alloc] initWithFrame:_cardBackground.bounds];
    _selectedHighlightView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _selectedHighlightView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:1.0];
    _selectedHighlightView.hidden = YES;
    [_cardBackground.contentView addSubview:_selectedHighlightView];
    
    _motionEffectH = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    _motionEffectH.minimumRelativeValue = @(-8);
    _motionEffectH.maximumRelativeValue = @(8);
    _motionEffectV = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    _motionEffectV.minimumRelativeValue = @(-8);
    _motionEffectV.maximumRelativeValue = @(8);
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
        self.layer.shadowOpacity = focused ? 0.15 : 0.0;
        self.layer.shadowRadius = focused ? 18.0 : 16.0;
        self->_cardBackground.alpha = focused ? 0.9 : 0.7;
    } completion:nil];
    
    _selectedHighlightView.hidden = !focused;
    
    // Match Bilibili-style focus: white card when focused, dark card when not.
    UIColor* focusedForeground = [UIColor blackColor];
    UIColor* unfocusedForeground = [UIColor whiteColor];
    if (@available(tvOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
            unfocusedForeground = [UIColor blackColor];
        }
    }
    _hostIcon.tintColor = focused ? focusedForeground : unfocusedForeground;
    _hostOverlay.tintColor = focused ? focusedForeground : unfocusedForeground;
    _hostLabel.textColor = focused ? focusedForeground : unfocusedForeground;
    
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
    
    [_hostLabel setText:@"Add Host Manually"];
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
