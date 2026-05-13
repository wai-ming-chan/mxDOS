#import "DOSBoxBridge.h"

// DOSBox / SDL headers
#include "dosbox.h"
#include <SDL.h>
#include <SDL_events.h>

// SDL renames main to SDL_main via macro; we declare sdl_main with C++ linkage.
#undef main
extern int sdl_main(int argc, char *argv[]);

@implementation DOSBoxBridge

- (void)startWithConfig:(NSString *)configPath {
    // Copy the path out of NSString so the C++ lambda can capture it safely.
    const char *rawPath = [configPath fileSystemRepresentation];
    std::string confPath(rawPath ? rawPath : "");

    // SDL_SetMainReady tells SDL we are managing the iOS run loop ourselves
    // (instead of SDL_UIKitRunApp) so SDL_Init() won't fail.
    SDL_SetMainReady();

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Build a minimal argv: dosbox --conf <path>
        std::string arg0 = "dosbox";
        std::string arg1 = "--conf";
        // confPath is captured by value above

        char *argv[4];
        argv[0] = const_cast<char *>(arg0.c_str());
        argv[1] = const_cast<char *>(arg1.c_str());
        argv[2] = const_cast<char *>(confPath.c_str());
        argv[3] = nullptr;

        int argc = (confPath.empty()) ? 1 : 3;

        sdl_main(argc, argv);
    });
}

- (void)stop {
    // Push SDL_QUIT to request a clean DOSBox shutdown.
    SDL_Event quit;
    quit.type = SDL_QUIT;
    SDL_PushEvent(&quit);
}

- (void)injectKey:(int)sdlScancode pressed:(BOOL)pressed {
    SDL_Event event;
    SDL_zero(event);
    event.type          = pressed ? SDL_KEYDOWN : SDL_KEYUP;
    event.key.state     = pressed ? SDL_PRESSED : SDL_RELEASED;
    event.key.keysym.scancode = static_cast<SDL_Scancode>(sdlScancode);
    event.key.keysym.sym      = SDL_GetKeyFromScancode(static_cast<SDL_Scancode>(sdlScancode));
    SDL_PushEvent(&event);
}

@end
