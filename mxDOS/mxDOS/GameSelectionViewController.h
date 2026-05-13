#pragma once
#import <UIKit/UIKit.h>

typedef void (^GameSelectedBlock)(NSString *confPath);
typedef void (^GameCancelBlock)(void);

/// Full-screen game picker.
/// When |cancelBlock| is non-nil the screen is shown as an overlay while a game
/// runs — a "Continue Playing" button is displayed and calls |cancelBlock|.
/// When |cancelBlock| is nil (startup) no dismiss option is shown.
@interface GameSelectionViewController : UIViewController
- (instancetype)initWithCallback:(GameSelectedBlock)callback
                     cancelBlock:(nullable GameCancelBlock)cancelBlock;
@end
