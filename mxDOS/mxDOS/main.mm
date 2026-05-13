#include <SDL.h>
#undef main
#include <CoreFoundation/CoreFoundation.h>

#import <Foundation/Foundation.h>
#import "TouchOverlayView.h"
#import "GameSelectionViewController.h"
#include <string>

extern int sdl_main(int argc, char *argv[]);

static UIWindow            *gSelectionWindow;
static dispatch_semaphore_t gGameSema;
static NSString            *gSelectedConf;
static volatile BOOL        gGameChosen;
static volatile BOOL        gQuitRequested = NO;

// Used only when sdl_main has already returned and we need a fresh process.
static NSString *const kQueuedConfKey = @"mxdos_queued_conf";

// ---------------------------------------------------------------------------
// Keystroke injection — lets us "type" DOSBox shell commands in-process
// ---------------------------------------------------------------------------

static void sdlPushKey(SDL_Scancode sc, BOOL down) {
    SDL_Event e; SDL_zero(e);
    e.type                = down ? SDL_KEYDOWN : SDL_KEYUP;
    e.key.state           = down ? SDL_PRESSED : SDL_RELEASED;
    e.key.keysym.scancode = sc;
    e.key.keysym.sym      = SDL_GetKeyFromScancode(sc);
    SDL_PushEvent(&e);
}

// Maps a printable ASCII character to an SDL scancode (US keyboard layout).
static void pushChar(char c) {
    SDL_Scancode sc = SDL_SCANCODE_UNKNOWN;
    BOOL shift = NO;

    if      (c >= 'a' && c <= 'z') { sc = (SDL_Scancode)(SDL_SCANCODE_A + c - 'a'); }
    else if (c >= 'A' && c <= 'Z') { sc = (SDL_Scancode)(SDL_SCANCODE_A + c - 'A'); shift = YES; }
    else if (c >= '1' && c <= '9') { sc = (SDL_Scancode)(SDL_SCANCODE_1 + c - '1'); }
    else switch (c) {
        case '0':  sc = SDL_SCANCODE_0;           break;
        case ' ':  sc = SDL_SCANCODE_SPACE;       break;
        case '.':  sc = SDL_SCANCODE_PERIOD;      break;
        case '-':  sc = SDL_SCANCODE_MINUS;       break;
        case '_':  sc = SDL_SCANCODE_MINUS;       shift = YES; break;
        case ':':  sc = SDL_SCANCODE_SEMICOLON;   shift = YES; break;
        case '"':  sc = SDL_SCANCODE_APOSTROPHE;  shift = YES; break;
        case '\'': sc = SDL_SCANCODE_APOSTROPHE;  break;
        case '/':  sc = SDL_SCANCODE_SLASH;       break;
        case '\\': sc = SDL_SCANCODE_BACKSLASH;   break;
        default:   return;
    }

    if (shift) sdlPushKey(SDL_SCANCODE_LSHIFT, YES);
    sdlPushKey(sc, YES);
    sdlPushKey(sc, NO);
    if (shift) sdlPushKey(SDL_SCANCODE_LSHIFT, NO);
}

static void pushCommand(NSString *cmd) {
    for (const char *s = cmd.UTF8String; *s; s++) pushChar(*s);
    sdlPushKey(SDL_SCANCODE_RETURN, YES);
    sdlPushKey(SDL_SCANCODE_RETURN, NO);
}

// Extracts [autoexec] lines from a dosbox.conf file.
static NSArray<NSString *> *autoexecLines(NSString *confPath) {
    NSString *text = [NSString stringWithContentsOfFile:confPath
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (!text) return @[];
    NSMutableArray *result = [NSMutableArray array];
    BOOL inSection = NO;
    for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceCharacterSet];
        if ([line isEqualToString:@"[autoexec]"]) { inSection = YES;  continue; }
        if ([line hasPrefix:@"["])                { inSection = NO;   continue; }
        if (!inSection || line.length == 0 || [line hasPrefix:@"#"]) continue;
        [result addObject:line];
    }
    return result;
}

// Switches the running DOSBox session to a new game by injecting keystrokes.
// Strategy: Ctrl+Alt+Delete triggers DOSBox's emulated BIOS warm reboot (INT 19h).
// This cannot be intercepted by the running game (unlike Ctrl+C / INT 23h).
// After the reboot, DOSBox re-runs [autoexec] from the conf already loaded in
// memory: "mount c ." picks up the new host CWD we set via chdir() above.
static void injectGameLoad(NSString *confPath) {
    chdir(confPath.stringByDeletingLastPathComponent.fileSystemRepresentation);

    // Flush any previously queued key events before injecting new ones.
    SDL_FlushEvent(SDL_KEYDOWN);
    SDL_FlushEvent(SDL_KEYUP);

    // Ctrl+Alt+Delete → INT 19h warm reboot (uninterceptable by games).
    sdlPushKey(SDL_SCANCODE_LCTRL,  YES);
    sdlPushKey(SDL_SCANCODE_LALT,   YES);
    sdlPushKey(SDL_SCANCODE_DELETE, YES);
    sdlPushKey(SDL_SCANCODE_DELETE, NO);
    sdlPushKey(SDL_SCANCODE_LALT,   NO);
    sdlPushKey(SDL_SCANCODE_LCTRL,  NO);

    // After reboot, DOSBox re-runs [autoexec] which remounts C: from the new CWD.
    // We only need to handle the D: CD image and game launch — skip mount c / c:.
    pushCommand(@"unmount d");
    for (NSString *cmd in autoexecLines(confPath)) {
        NSString *lower = cmd.lowercaseString;
        if ([lower hasPrefix:@"mount c"] || [lower isEqualToString:@"c:"]) continue;
        pushCommand(cmd);
    }
}

// ---------------------------------------------------------------------------
// Window / selection helpers
// ---------------------------------------------------------------------------

static void showSelectionWindow(GameSelectedBlock onPick, GameCancelBlock onCancel) {
    gSelectionWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    gSelectionWindow.windowLevel = UIWindowLevelNormal + 1;
    GameSelectionViewController *vc = [[GameSelectionViewController alloc]
        initWithCallback:onPick cancelBlock:onCancel];
    gSelectionWindow.rootViewController = vc;
    [gSelectionWindow makeKeyAndVisible];
}

// Saves confPath to UserDefaults and terminates the process.
// Only used after sdl_main has returned — sdl_main cannot be called twice.
static void queueConfAndExit(NSString *confPath) {
    [NSUserDefaults.standardUserDefaults setObject:confPath forKey:kQueuedConfKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    _exit(0);
}

// ---------------------------------------------------------------------------
// In-game overlay (home button)
// ---------------------------------------------------------------------------

// Called by TouchOverlayView when ⌂ is tapped.
// The game keeps running. "Continue Playing" dismisses with no side-effect.
// Picking a game injects DOSBox shell commands in-process (z: / unmount / mount /
// run) so the switch happens immediately without restarting the process.
extern "C" void mxdos_show_game_selection_overlay(void) {
    if (gSelectionWindow) return;

    GameSelectedBlock onPick = ^(NSString *conf) {
        gSelectionWindow.hidden = YES;
        gSelectionWindow = nil;
        injectGameLoad(conf);
    };

    GameCancelBlock onCancel = ^{
        gSelectionWindow.hidden = YES;
        gSelectionWindow = nil;
    };

    if (NSThread.isMainThread) {
        showSelectionWindow(onPick, onCancel);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ showSelectionWindow(onPick, onCancel); });
    }
}

// ---------------------------------------------------------------------------
// Misc helpers
// ---------------------------------------------------------------------------

static void spinRunLoop(CFTimeInterval seconds) {
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + seconds;
    while (CFAbsoluteTimeGetCurrent() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.016, YES);
}

// Blocks until the user picks a game; result in gSelectedConf.
static void runSelectionScreen(void) {
    gGameChosen = NO; gSelectedConf = nil;
    GameSelectedBlock onPick = ^(NSString *conf) {
        gSelectedConf = conf;
        gSelectionWindow.hidden = YES; gSelectionWindow = nil;
        gGameChosen = YES;
        if (gGameSema) dispatch_semaphore_signal(gGameSema);
    };
    if (NSThread.isMainThread) {
        showSelectionWindow(onPick, nil);
        while (!gGameChosen) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.016, YES);
    } else {
        gGameSema = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{ showSelectionWindow(onPick, nil); });
        dispatch_semaphore_wait(gGameSema, DISPATCH_TIME_FOREVER);
    }
}

// ---------------------------------------------------------------------------
// Clean quit — called by the Home button in TouchOverlayView
// ---------------------------------------------------------------------------

extern "C" void mxdos_request_quit(void) {
    gQuitRequested = YES;
    SDL_Event quit;
    quit.type = SDL_QUIT;
    SDL_PushEvent(&quit);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

static int dosbox_sdl_main([[maybe_unused]] int argc, [[maybe_unused]] char *argv[]) {
    @autoreleasepool {
        // Recover a game queued from the previous process run (post-game picker).
        NSString *queued = [NSUserDefaults.standardUserDefaults stringForKey:kQueuedConfKey];
        if (queued) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:kQueuedConfKey];
            [NSUserDefaults.standardUserDefaults synchronize];
            gSelectedConf = queued;
        } else {
            runSelectionScreen();
        }

        // Launch DOSBox — called exactly once per process lifetime.
        // (sdl_main tears down all C++ globals on exit; calling it again would crash.)
        NSString *confPath = gSelectedConf;
        chdir(confPath.stringByDeletingLastPathComponent.fileSystemRepresentation);

        __block BOOL installPending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (installPending) [TouchOverlayView installOnKeyWindow];
        });

        std::string cp(confPath.UTF8String);
        char *args[] = { (char *)"dosbox", (char *)"--conf", (char *)cp.c_str(), nullptr };
        sdl_main(3, args);

        // DOSBox exited — either via the Home button (gQuitRequested) or natural game exit.
        installPending = NO;
        if (NSThread.isMainThread) {
            [TouchOverlayView removeOverlay];
            spinRunLoop(0.3);
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{ [TouchOverlayView removeOverlay]; });
        }

        if (gQuitRequested) {
            // Home button: DOSBox already flushed disk and tore down SDL. Exit cleanly.
            exit(0);
        }

        // sdl_main cannot be called again. Show the picker so the user can choose
        // the next game, then queue it and restart — the fresh process skips the picker.
        runSelectionScreen();
        queueConfAndExit(gSelectedConf);
    }
    return 0;
}

int main(int argc, char *argv[]) {
    return SDL_UIKitRunApp(argc, argv, dosbox_sdl_main);
}
