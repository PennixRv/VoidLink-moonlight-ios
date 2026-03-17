//
//  VLTVOSUI.h
//  Moonlight
//
//  Shared tvOS UI helpers for focus style + lightweight zh-Hans strings.
//  Header-only by design to avoid touching the Xcode project file.
//

#pragma once

#import <UIKit/UIKit.h>

#if TARGET_OS_TV

// tvOS 26: prefer system-driven focus and materials. Keep our custom transforms subtle
// so the app feels "standard tvOS" instead of a bespoke focus system.
static const CGFloat VLTVOSCardScaleFactor = 1.06;
static const CGFloat VLTVOSCardShadowOpacityFocused = 0.14;
static const CGFloat VLTVOSCardShadowOpacityUnfocused = 0.0;
static const CGFloat VLTVOSCardShadowRadiusFocused = 16.0;
static const CGFloat VLTVOSCardShadowOffsetYFocused = 14.0;
static const CGFloat VLTVOSCardMotionAmplitude = 0.0;
static const CGFloat VLTVOSCardCornerRadius = 16.0;

static inline BOOL VLTVOSIsZhHans(void)
{
    static BOOL cached = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* lang = [NSLocale preferredLanguages].firstObject ?: @"";
        cached = [lang hasPrefix:@"zh"];
    });
    return cached;
}

static inline NSString* VLTVOSLocalized(NSString* en, NSString* zhHans)
{
    return VLTVOSIsZhHans() ? zhHans : en;
}

#define VLTVOS_STR(en, zhHans) VLTVOSLocalized((en), (zhHans))

static inline void VLTVOSSetContinuousCornerIfAvailable(CALayer* layer)
{
    if (@available(tvOS 13.0, *)) {
        layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static inline CGFloat VLTVOSScaleDiffForBounds(CGRect bounds, CGFloat scale)
{
    return (bounds.size.height * scale - bounds.size.height) / 2.0;
}

static inline CGAffineTransform VLTVOSFocusTransformForBounds(CGRect bounds, BOOL focused)
{
    if (!focused) {
        return CGAffineTransformIdentity;
    }

    CGFloat scale = VLTVOSCardScaleFactor;
    CGFloat scaleDiff = VLTVOSScaleDiffForBounds(bounds, scale);
    return CGAffineTransformTranslate(CGAffineTransformMakeScale(scale, scale), 0, -scaleDiff);
}

static inline UIInterpolatingMotionEffect* VLTVOSCreateMotionEffect(NSString* keyPath, UIInterpolatingMotionEffectType type)
{
    UIInterpolatingMotionEffect* effect = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:keyPath type:type];
    effect.minimumRelativeValue = @(-VLTVOSCardMotionAmplitude);
    effect.maximumRelativeValue = @(VLTVOSCardMotionAmplitude);
    return effect;
}

static inline void VLTVOSUpdateMotionEffectsForFocus(UIView* view,
                                                     UIInterpolatingMotionEffect* motionH,
                                                     UIInterpolatingMotionEffect* motionV,
                                                     BOOL focused)
{
    if (focused) {
        if (motionH != nil) {
            [view addMotionEffect:motionH];
        }
        if (motionV != nil) {
            [view addMotionEffect:motionV];
        }
    }
    else {
        if (motionH != nil) {
            [view removeMotionEffect:motionH];
        }
        if (motionV != nil) {
            [view removeMotionEffect:motionV];
        }
    }
}

static inline UIColor* VLTVOSCardForegroundColor(UITraitCollection* traits, BOOL focused)
{
    (void)traits;
    (void)focused;

    if (@available(tvOS 13.0, *)) {
        return [UIColor labelColor];
    }
    return [UIColor whiteColor];
}

static inline UIColor* VLTVOSBackgroundBaseColor(UITraitCollection* traits)
{
    if (@available(tvOS 13.0, *)) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleLight) {
            return [UIColor colorWithWhite:0.95 alpha:1.0];
        }
        return [UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:1.0];
    }
    return [UIColor blackColor];
}

static inline UIBlurEffectStyle VLTVOSCardBlurStyle(UITraitCollection* traits)
{
    if (@available(tvOS 13.0, *)) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleLight) {
            return UIBlurEffectStyleExtraLight;
        }
    }
    return UIBlurEffectStyleDark;
}

static inline BOOL VLTVOSReduceTransparencyEnabled(void)
{
    return UIAccessibilityIsReduceTransparencyEnabled();
}

static inline BOOL VLTVOSDarkerSystemColorsEnabled(void)
{
    return UIAccessibilityDarkerSystemColorsEnabled();
}

static inline UIColor* VLTVOSSolidCardBackgroundColor(UITraitCollection* traits, BOOL focused)
{
    // When Reduce Transparency is enabled, tvOS expects more opaque surfaces.
    // Use a subtle, system-like fill that still reads as "standard" without relying
    // on iOS-only dynamic system background colors.
    CGFloat alpha = focused ? 0.94 : 0.88;
    if (VLTVOSDarkerSystemColorsEnabled()) {
        alpha = focused ? 0.98 : 0.94;
    }

    if (@available(tvOS 13.0, *)) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleLight) {
            return [UIColor colorWithWhite:1.0 alpha:alpha];
        }
        return [UIColor colorWithWhite:0.12 alpha:alpha];
    }

    return [UIColor colorWithWhite:0.0 alpha:alpha];
}

static inline UIVisualEffect* VLTVOSCardMaterialEffect(UITraitCollection* traits, BOOL focused)
{
    (void)traits;

    // Liquid Glass (UIKit) is available on tvOS 26+. This gives the most "standard tvOS 26" look.
    if (@available(tvOS 26.0, *)) {
        UIGlassEffectStyle style = focused ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular;
        UIGlassEffect* effect = [UIGlassEffect effectWithStyle:style];
        effect.interactive = YES;
        return effect;
    }

    return [UIBlurEffect effectWithStyle:VLTVOSCardBlurStyle(traits)];
}

static inline void VLTVOSApplyCardMaterialToEffectView(UIVisualEffectView* effectView,
                                                       UITraitCollection* traits,
                                                       BOOL focused)
{
    if (effectView == nil) {
        return;
    }

    // Default: let the system material do the work.
    effectView.backgroundColor = [UIColor clearColor];
    effectView.contentView.backgroundColor = [UIColor clearColor];

    // Accessibility: honor Reduce Transparency by switching to an opaque-ish fill.
    if (VLTVOSReduceTransparencyEnabled()) {
        effectView.effect = nil;
        effectView.contentView.backgroundColor = VLTVOSSolidCardBackgroundColor(traits, focused);
        return;
    }

    effectView.effect = VLTVOSCardMaterialEffect(traits, focused);

    // Accessibility: a small contrast boost without abandoning the system material.
    if (VLTVOSDarkerSystemColorsEnabled()) {
        if (@available(tvOS 13.0, *)) {
            CGFloat overlayAlpha = (traits.userInterfaceStyle == UIUserInterfaceStyleLight) ? 0.06 : 0.16;
            effectView.contentView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:overlayAlpha];
        }
    }
}

#else

#define VLTVOS_STR(en, zhHans) (en)

#endif
