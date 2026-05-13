#pragma once
#import <UIKit/UIKit.h>

/// Full-screen transparent UIView that renders a d-pad + action buttons
/// and injects SDL keyboard events into DOSBox.
/// Call +installOnKeyWindow from the main queue after SDL has initialised.
@interface TouchOverlayView : UIView
+ (void)installOnKeyWindow;
+ (void)removeOverlay;
@end
