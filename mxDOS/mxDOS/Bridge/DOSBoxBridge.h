#pragma once
#import <Foundation/Foundation.h>

// Objective-C++ interface exposed to Swift.
// Implementation in DOSBoxBridge.mm links to DOSBox C++ internals.
@interface DOSBoxBridge : NSObject

// Start the DOSBox emulator on a background thread.
// configPath: full path to the .conf file to use.
- (void)startWithConfig:(NSString *)configPath;

// Stop the emulator and clean up.
- (void)stop;

// Inject a keyboard event into the DOSBox event queue.
// sdlScancode: SDL_Scancode value for the key.
// pressed: YES for key-down, NO for key-up.
- (void)injectKey:(int)sdlScancode pressed:(BOOL)pressed;

@end
