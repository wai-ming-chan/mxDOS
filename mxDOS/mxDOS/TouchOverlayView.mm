#import "TouchOverlayView.h"
#include <SDL.h>
#undef main
#include <unistd.h>
#include "mxDOSAudio.h"

extern "C" void mxdos_request_quit(void);
extern "C" void mxdos_cycle_discs(void);

// ---------------------------------------------------------------------------
// SDL key injection
// ---------------------------------------------------------------------------

static void pushKey(SDL_Scancode sc, BOOL down) {
    SDL_Event e;
    SDL_zero(e);
    e.type                = down ? SDL_KEYDOWN : SDL_KEYUP;
    e.key.state           = down ? SDL_PRESSED : SDL_RELEASED;
    e.key.keysym.scancode = sc;
    e.key.keysym.sym      = SDL_GetKeyFromScancode(sc);
    SDL_PushEvent(&e);
}

// ---------------------------------------------------------------------------
// KBKey — keyboard key: KEYDOWN on touch-begin, KEYUP on touch-end
// ---------------------------------------------------------------------------

@interface KBKey : UIButton
@property SDL_Scancode sc;
@property BOOL         shifted;     // inject LSHIFT around this key
@property (nonatomic, copy) NSString *lowLabel;
@property (nonatomic, copy) NSString *hiLabel;
@end

@implementation KBKey
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesBegan:t withEvent:e];
    self.alpha = 0.55;
    if (self.shifted) pushKey(SDL_SCANCODE_LSHIFT, YES);
    pushKey(self.sc, YES);
}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesEnded:t withEvent:e];
    self.alpha = 1.0;
    pushKey(self.sc, NO);
    if (self.shifted) pushKey(SDL_SCANCODE_LSHIFT, NO);
}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesCancelled:t withEvent:e];
    self.alpha = 1.0;
    pushKey(self.sc, NO);
    if (self.shifted) pushKey(SDL_SCANCODE_LSHIFT, NO);
}
@end

// ---------------------------------------------------------------------------
// KeyButton — game-control button
// ---------------------------------------------------------------------------

@interface KeyButton : UIButton
@property (nonatomic) SDL_Scancode sc;
@property (nonatomic, strong) UIColor *normalColor;
@end

static UIColor *kBtnNormal(void) { return [UIColor colorWithWhite:0.08 alpha:0.60]; }
static UIColor *kBtnPressed(void){ return [UIColor colorWithWhite:0.55 alpha:0.85]; }

@implementation KeyButton
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesBegan:t withEvent:e];
    self.backgroundColor = kBtnPressed();
    pushKey(self.sc, YES);
}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesEnded:t withEvent:e];
    self.backgroundColor = self.normalColor;
    pushKey(self.sc, NO);
}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesCancelled:t withEvent:e];
    self.backgroundColor = self.normalColor;
    pushKey(self.sc, NO);
}
@end

// ---------------------------------------------------------------------------
// DPadView — virtual D-pad translating thumb position to directional input
// ---------------------------------------------------------------------------

typedef NS_OPTIONS(NSUInteger, DPadDir) {
    DPadNone  = 0,
    DPadUp    = 1 << 0,
    DPadDown  = 1 << 1,
    DPadLeft  = 1 << 2,
    DPadRight = 1 << 3,
};

@interface DPadView : UIView
@property (nonatomic) BOOL wasdMode;
@end

@implementation DPadView {
    DPadDir  _active;
    UITouch *_touch;
}

static const CGFloat kDPadDeadFraction = 0.18;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = NO;
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGFloat W = rect.size.width, H = rect.size.height;
    CGFloat cx = W/2, cy = H/2;
    CGFloat r  = MIN(W, H)/2.0 - 4;
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    // Background circle
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.22 alpha:0.58].CGColor);
    CGContextAddEllipseInRect(ctx, CGRectMake(cx-r, cy-r, 2*r, 2*r));
    CGContextFillPath(ctx);

    // Cross arms
    CGFloat armW = r * 0.36, armL = r * 0.88;
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.38 alpha:0.50].CGColor);
    CGContextFillRect(ctx, CGRectMake(cx - armW/2, cy - armL, armW, 2*armL));
    CGContextFillRect(ctx, CGRectMake(cx - armL, cy - armW/2, 2*armL, armW));

    // Center nub
    CGFloat nr = r * 0.18;
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.12 alpha:0.85].CGColor);
    CGContextAddEllipseInRect(ctx, CGRectMake(cx-nr, cy-nr, 2*nr, 2*nr));
    CGContextFillPath(ctx);

    // Directional arrows (blue when active)
    CGFloat ao = r * 0.60, as_ = r * 0.15;
    UIColor *norm = [UIColor colorWithWhite:0.88 alpha:0.60];
    UIColor *actv = [UIColor colorWithRed:0.35 green:0.78 blue:1.0 alpha:1.0];

    CGContextSetFillColorWithColor(ctx, (_active & DPadUp)    ? actv.CGColor : norm.CGColor);
    CGContextMoveToPoint(ctx, cx, cy - ao - as_);
    CGContextAddLineToPoint(ctx, cx - as_, cy - ao + as_);
    CGContextAddLineToPoint(ctx, cx + as_, cy - ao + as_);
    CGContextFillPath(ctx);

    CGContextSetFillColorWithColor(ctx, (_active & DPadDown)  ? actv.CGColor : norm.CGColor);
    CGContextMoveToPoint(ctx, cx, cy + ao + as_);
    CGContextAddLineToPoint(ctx, cx - as_, cy + ao - as_);
    CGContextAddLineToPoint(ctx, cx + as_, cy + ao - as_);
    CGContextFillPath(ctx);

    CGContextSetFillColorWithColor(ctx, (_active & DPadLeft)  ? actv.CGColor : norm.CGColor);
    CGContextMoveToPoint(ctx, cx - ao - as_, cy);
    CGContextAddLineToPoint(ctx, cx - ao + as_, cy - as_);
    CGContextAddLineToPoint(ctx, cx - ao + as_, cy + as_);
    CGContextFillPath(ctx);

    CGContextSetFillColorWithColor(ctx, (_active & DPadRight) ? actv.CGColor : norm.CGColor);
    CGContextMoveToPoint(ctx, cx + ao + as_, cy);
    CGContextAddLineToPoint(ctx, cx + ao - as_, cy - as_);
    CGContextAddLineToPoint(ctx, cx + ao - as_, cy + as_);
    CGContextFillPath(ctx);
}

- (DPadDir)dirForPoint:(CGPoint)p {
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    CGFloat dx = p.x - W/2, dy = p.y - H/2;
    if (hypot(dx, dy) < MIN(W,H)/2.0 * kDPadDeadFraction) return DPadNone;
    double a = atan2(dy, dx) * 180.0 / M_PI; // 0=right, 90=down, -90=up
    if      (a > -22.5  && a <=  22.5)  return DPadRight;
    else if (a >  22.5  && a <=  67.5)  return DPadRight | DPadDown;
    else if (a >  67.5  && a <= 112.5)  return DPadDown;
    else if (a > 112.5  && a <= 157.5)  return DPadLeft  | DPadDown;
    else if (a > 157.5  || a <= -157.5) return DPadLeft;
    else if (a > -157.5 && a <= -112.5) return DPadLeft  | DPadUp;
    else if (a > -112.5 && a <=  -67.5) return DPadUp;
    else                                 return DPadRight | DPadUp;
}

- (void)setActive:(DPadDir)n {
    DPadDir diff = _active ^ n;
    if (!diff) return;
    SDL_Scancode scUp    = _wasdMode ? SDL_SCANCODE_W : SDL_SCANCODE_UP;
    SDL_Scancode scDown  = _wasdMode ? SDL_SCANCODE_S : SDL_SCANCODE_DOWN;
    SDL_Scancode scLeft  = _wasdMode ? SDL_SCANCODE_A : SDL_SCANCODE_LEFT;
    SDL_Scancode scRight = _wasdMode ? SDL_SCANCODE_D : SDL_SCANCODE_RIGHT;
    if ((diff & DPadUp)    && (_active & DPadUp))    pushKey(scUp,    NO);
    if ((diff & DPadDown)  && (_active & DPadDown))  pushKey(scDown,  NO);
    if ((diff & DPadLeft)  && (_active & DPadLeft))  pushKey(scLeft,  NO);
    if ((diff & DPadRight) && (_active & DPadRight)) pushKey(scRight, NO);
    if ((diff & DPadUp)    && (n & DPadUp))          pushKey(scUp,    YES);
    if ((diff & DPadDown)  && (n & DPadDown))        pushKey(scDown,  YES);
    if ((diff & DPadLeft)  && (n & DPadLeft))        pushKey(scLeft,  YES);
    if ((diff & DPadRight) && (n & DPadRight))       pushKey(scRight, YES);
    _active = n;
    [self setNeedsDisplay];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch) return;
    _touch = touches.anyObject;
    [self setActive:[self dirForPoint:[_touch locationInView:self]]];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (![touches containsObject:_touch]) return;
    [self setActive:[self dirForPoint:[_touch locationInView:self]]];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (![touches containsObject:_touch]) return;
    _touch = nil; [self setActive:DPadNone];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touch = nil; [self setActive:DPadNone];
}

@end

// ---------------------------------------------------------------------------
// Button tags
// ---------------------------------------------------------------------------

enum : NSInteger {
    kUp = 1, kDown, kLeft, kRight,
    kBtnLP, kBtnMP, kBtnHP,
    kBtnLK, kBtnMK, kBtnHK,
    kToggle     = 20,
    kHome       = 21,
    kModeSwitch = 23,
    kKeyboard   = 24,
    kVolume     = 25,
    kSwapCD     = 26,
};

// ---------------------------------------------------------------------------
// TouchOverlayView
// ---------------------------------------------------------------------------

@interface TouchOverlayView ()
@property (nonatomic, strong) UIView                    *pad;
@property (nonatomic)         BOOL                       padHidden;
@property (nonatomic)         BOOL                       altMode;
@property (nonatomic, weak)   UIView                    *sdlView;
// Custom keyboard
@property (nonatomic, strong) UIView                    *keyboardView;
@property (nonatomic)         BOOL                       keyboardActive;
@property (nonatomic)         BOOL                       shiftActive;
@property (nonatomic)         BOOL                       padWasHidden;
@property (nonatomic, strong) NSArray<KBKey *>          *kbDigits;
@property (nonatomic, strong) NSArray<KBKey *>          *kbRow1;
@property (nonatomic, strong) NSArray<KBKey *>          *kbRow2;
@property (nonatomic, strong) NSArray<KBKey *>          *kbRow3;
@property (nonatomic, strong) NSMutableArray<KBKey *>   *kbLetters;
@property (nonatomic, weak)   UIButton                  *kbShiftBtn;
@property (nonatomic, weak)   KBKey                     *kbBkspKey;
@property (nonatomic, weak)   KBKey                     *kbEscKey;
@property (nonatomic, weak)   KBKey                     *kbTabKey;
@property (nonatomic, weak)   KBKey                     *kbSpaceKey;
@property (nonatomic, weak)   KBKey                     *kbEntKey;
@property (nonatomic, strong) NSArray<KBKey *>          *kbArrows;  // ◀ ▲ ▼ ▶
@property (nonatomic, strong) NSArray<KBKey *>          *kbNav;     // Home End Del PgUp PgDn
@property (nonatomic, strong) DPadView                   *dpad;
@property (nonatomic)         NSInteger                   volumeIndex; // 0-4: 0/25/50/75/100%
@end

@implementation TouchOverlayView

// -- Installation / removal --------------------------------------------------

static NSArray<UIWindow *> *allWindows(void) {
    NSMutableArray<UIWindow *> *result = [NSMutableArray array];
    if (@available(iOS 13, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class])
                [result addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (result.count == 0)
        [result addObjectsFromArray:UIApplication.sharedApplication.windows];
    return result;
}

+ (void)installOnKeyWindow {
    NSAssert(NSThread.isMainThread, @"must be called on the main thread");
    UIWindow *window = nil;
    UIWindowLevel lowestLevel = UIWindowLevelNormal + 100;
    for (UIWindow *w in allWindows()) {
        if (w.isHidden) continue;
        if (w.windowLevel < lowestLevel) { lowestLevel = w.windowLevel; window = w; }
    }
    if (!window) return;
    for (UIView *v in window.subviews)
        if ([v isKindOfClass:[TouchOverlayView class]]) return;

    UIView *sdlView = window.rootViewController.view;
    if (!sdlView) sdlView = window.subviews.firstObject;

    TouchOverlayView *ov = [[TouchOverlayView alloc] initWithFrame:window.bounds];
    ov.sdlView = sdlView;
    ov.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:ov];
}

+ (void)removeOverlay {
    NSAssert(NSThread.isMainThread, @"must be called on the main thread");
    for (UIWindow *w in allWindows())
        for (UIView *v in w.subviews.copy)
            if ([v isKindOfClass:[TouchOverlayView class]]) [v removeFromSuperview];
}

// -- Init --------------------------------------------------------------------

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor      = UIColor.clearColor;
    self.userInteractionEnabled = YES;

    _pad = [[UIView alloc] init];
    _pad.backgroundColor = UIColor.clearColor;
    [self addSubview:_pad];
    [self buildGameButtons];
    [self buildKeyboardView];

    // Show/hide game controls
    UIButton *tog = [UIButton buttonWithType:UIButtonTypeCustom];
    tog.tag = kToggle;
    tog.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    tog.layer.cornerRadius = 8;
    tog.titleLabel.font = [UIFont systemFontOfSize:18];
    [tog setTitle:@"⌨" forState:UIControlStateNormal];
    [tog addTarget:self action:@selector(togglePad)
          forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:tog];

    // Home
    UIButton *home = [UIButton buttonWithType:UIButtonTypeCustom];
    home.tag = kHome;
    home.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    home.layer.cornerRadius = 8;
    home.titleLabel.font = [UIFont systemFontOfSize:18];
    [home setTitle:@"⌂" forState:UIControlStateNormal];
    [home addTarget:self action:@selector(homePressed)
           forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:home];

    // Mode switch
    UIButton *modeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    modeBtn.tag = kModeSwitch;
    modeBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    modeBtn.layer.cornerRadius = 8;
    modeBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [modeBtn setTitle:@"FGT" forState:UIControlStateNormal];
    [modeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [modeBtn addTarget:self action:@selector(switchMode)
              forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:modeBtn];

    // Keyboard toggle (portrait only)
    UIButton *kbBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    kbBtn.tag = kKeyboard;
    kbBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    kbBtn.layer.cornerRadius = 8;
    kbBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [kbBtn setTitle:@"ABC" forState:UIControlStateNormal];
    [kbBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [kbBtn addTarget:self action:@selector(toggleKeyboard)
            forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:kbBtn];

    // CD swap (Ctrl+F4 — cycles DOSBox imgmount disc)
    UIButton *cdBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cdBtn.tag = kSwapCD;
    cdBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    cdBtn.layer.cornerRadius = 8;
    cdBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [cdBtn setTitle:@"CD\nSWAP" forState:UIControlStateNormal];
    [cdBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    cdBtn.titleLabel.numberOfLines = 2;
    cdBtn.titleLabel.textAlignment = NSTextAlignmentCenter;
    [cdBtn addTarget:self action:@selector(swapCDPressed)
            forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:cdBtn];

    // Volume
    UIButton *volBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    volBtn.tag = kVolume;
    volBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    volBtn.layer.cornerRadius = 8;
    volBtn.titleLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    volBtn.titleLabel.numberOfLines = 2;
    volBtn.titleLabel.textAlignment = NSTextAlignmentCenter;
    [volBtn setTitle:@"VOL\n100%" forState:UIControlStateNormal];
    [volBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [volBtn addTarget:self action:@selector(volumePressed)
             forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:volBtn];
    _volumeIndex = 4; // start at 100%

    return self;
}

// -- Game button factory -----------------------------------------------------

- (KeyButton *)btn:(NSString *)title sc:(SDL_Scancode)sc tag:(NSInteger)tag color:(UIColor *)color {
    KeyButton *b      = [KeyButton buttonWithType:UIButtonTypeCustom];
    b.sc              = sc;
    b.tag             = tag;
    b.normalColor     = color;
    b.backgroundColor = color;
    b.layer.cornerRadius = 10;
    b.layer.borderWidth  = 1;
    b.layer.borderColor  = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    b.titleLabel.numberOfLines = 2;
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_pad addSubview:b];
    return b;
}

- (void)buildGameButtons {
    UIColor *lightBlue = [UIColor colorWithRed:0.45 green:0.75 blue:1.00 alpha:0.80];
    UIColor *yellow    = [UIColor colorWithRed:1.00 green:0.85 blue:0.10 alpha:0.80];
    UIColor *green     = [UIColor colorWithRed:0.10 green:0.72 blue:0.20 alpha:0.80];
    UIColor *red       = [UIColor colorWithRed:0.85 green:0.10 blue:0.10 alpha:0.85];
    UIColor *dark      = [UIColor colorWithWhite:0.10 alpha:1.00];

    _dpad = [[DPadView alloc] init];
    [_pad addSubview:_dpad];

    KeyButton *b1 = [self btn:@"F1"    sc:SDL_SCANCODE_F1     tag:kBtnLP color:lightBlue];
              [self btn:@"F2"    sc:SDL_SCANCODE_F2     tag:kBtnMP color:red];
              [self btn:@"Esc"   sc:SDL_SCANCODE_ESCAPE tag:kBtnLK color:green];
    KeyButton *b5 = [self btn:@"Space" sc:SDL_SCANCODE_SPACE  tag:kBtnMK color:yellow];
    [b1 setTitleColor:dark forState:UIControlStateNormal];
    [b5 setTitleColor:dark forState:UIControlStateNormal];
}

// -- Keyboard view builder ---------------------------------------------------

- (KBKey *)makeKBKey:(NSString *)label sc:(SDL_Scancode)sc bg:(UIColor *)bg {
    KBKey *k = [KBKey buttonWithType:UIButtonTypeCustom];
    k.sc           = sc;
    k.shifted      = NO;
    k.lowLabel     = label;
    k.hiLabel      = label.uppercaseString;
    k.backgroundColor = bg;
    k.layer.cornerRadius = 5;
    k.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [k setTitle:label forState:UIControlStateNormal];
    [k setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_keyboardView addSubview:k];
    return k;
}

- (void)buildKeyboardView {
    _kbLetters    = [NSMutableArray array];
    _keyboardView = [[UIView alloc] init];
    _keyboardView.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.97];
    _keyboardView.hidden = YES;
    [self addSubview:_keyboardView];

    UIColor *keyBg  = [UIColor colorWithWhite:0.32 alpha:1.0];
    UIColor *specBg = [UIColor colorWithWhite:0.18 alpha:1.0];

    // Row 0: digits
    typedef struct { const char *lbl; SDL_Scancode sc; } KD;
    KD digs[] = {
        {"1",SDL_SCANCODE_1},{"2",SDL_SCANCODE_2},{"3",SDL_SCANCODE_3},
        {"4",SDL_SCANCODE_4},{"5",SDL_SCANCODE_5},{"6",SDL_SCANCODE_6},
        {"7",SDL_SCANCODE_7},{"8",SDL_SCANCODE_8},{"9",SDL_SCANCODE_9},
        {"0",SDL_SCANCODE_0}
    };
    NSMutableArray<KBKey *> *r0 = [NSMutableArray array];
    for (int i = 0; i < 10; i++)
        [r0 addObject:[self makeKBKey:@(digs[i].lbl) sc:digs[i].sc bg:keyBg]];
    _kbDigits = [r0 copy];

    // Row 1: QWERTYUIOP
    KD r1d[] = {
        {"q",SDL_SCANCODE_Q},{"w",SDL_SCANCODE_W},{"e",SDL_SCANCODE_E},{"r",SDL_SCANCODE_R},
        {"t",SDL_SCANCODE_T},{"y",SDL_SCANCODE_Y},{"u",SDL_SCANCODE_U},{"i",SDL_SCANCODE_I},
        {"o",SDL_SCANCODE_O},{"p",SDL_SCANCODE_P}
    };
    NSMutableArray<KBKey *> *r1 = [NSMutableArray array];
    for (int i = 0; i < 10; i++) {
        KBKey *k = [self makeKBKey:@(r1d[i].lbl) sc:r1d[i].sc bg:keyBg];
        [r1 addObject:k]; [_kbLetters addObject:k];
    }
    _kbRow1 = [r1 copy];

    // Row 2: ASDFGHJKL
    KD r2d[] = {
        {"a",SDL_SCANCODE_A},{"s",SDL_SCANCODE_S},{"d",SDL_SCANCODE_D},{"f",SDL_SCANCODE_F},
        {"g",SDL_SCANCODE_G},{"h",SDL_SCANCODE_H},{"j",SDL_SCANCODE_J},{"k",SDL_SCANCODE_K},
        {"l",SDL_SCANCODE_L}
    };
    NSMutableArray<KBKey *> *r2 = [NSMutableArray array];
    for (int i = 0; i < 9; i++) {
        KBKey *k = [self makeKBKey:@(r2d[i].lbl) sc:r2d[i].sc bg:keyBg];
        [r2 addObject:k]; [_kbLetters addObject:k];
    }
    _kbRow2 = [r2 copy];

    // Row 3: ⇧  ZXCVBNM  ⌫
    UIButton *shiftBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    shiftBtn.backgroundColor = specBg;
    shiftBtn.layer.cornerRadius = 5;
    shiftBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [shiftBtn setTitle:@"⇧" forState:UIControlStateNormal];
    [shiftBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [shiftBtn addTarget:self action:@selector(toggleShift)
              forControlEvents:UIControlEventTouchUpInside];
    [_keyboardView addSubview:shiftBtn];
    _kbShiftBtn = shiftBtn;

    KD r3d[] = {
        {"z",SDL_SCANCODE_Z},{"x",SDL_SCANCODE_X},{"c",SDL_SCANCODE_C},{"v",SDL_SCANCODE_V},
        {"b",SDL_SCANCODE_B},{"n",SDL_SCANCODE_N},{"m",SDL_SCANCODE_M}
    };
    NSMutableArray<KBKey *> *r3 = [NSMutableArray array];
    for (int i = 0; i < 7; i++) {
        KBKey *k = [self makeKBKey:@(r3d[i].lbl) sc:r3d[i].sc bg:keyBg];
        [r3 addObject:k]; [_kbLetters addObject:k];
    }
    _kbRow3 = [r3 copy];

    KBKey *bksp = [self makeKBKey:@"⌫" sc:SDL_SCANCODE_BACKSPACE bg:specBg];
    _kbBkspKey = bksp;

    // Row 4: Esc  Tab  Space  Ent
    _kbEscKey   = [self makeKBKey:@"Esc"   sc:SDL_SCANCODE_ESCAPE bg:specBg];
    _kbTabKey   = [self makeKBKey:@"Tab"   sc:SDL_SCANCODE_TAB    bg:specBg];
    _kbSpaceKey = [self makeKBKey:@"Space" sc:SDL_SCANCODE_SPACE  bg:specBg];
    _kbEntKey   = [self makeKBKey:@"Ent"   sc:SDL_SCANCODE_RETURN bg:specBg];

    // Row 5: arrow keys
    _kbArrows = @[
        [self makeKBKey:@"◀" sc:SDL_SCANCODE_LEFT  bg:specBg],
        [self makeKBKey:@"▲" sc:SDL_SCANCODE_UP    bg:specBg],
        [self makeKBKey:@"▼" sc:SDL_SCANCODE_DOWN  bg:specBg],
        [self makeKBKey:@"▶" sc:SDL_SCANCODE_RIGHT bg:specBg],
    ];

    // Row 6: navigation keys
    _kbNav = @[
        [self makeKBKey:@"Home" sc:SDL_SCANCODE_HOME     bg:specBg],
        [self makeKBKey:@"End"  sc:SDL_SCANCODE_END      bg:specBg],
        [self makeKBKey:@"Del"  sc:SDL_SCANCODE_DELETE   bg:specBg],
        [self makeKBKey:@"PgUp" sc:SDL_SCANCODE_PAGEUP   bg:specBg],
        [self makeKBKey:@"PgDn" sc:SDL_SCANCODE_PAGEDOWN bg:specBg],
    ];
}

// -- Keyboard layout (called from layoutSubviews in portrait) ----------------

- (void)layoutKeyboardInBounds:(CGRect)kb {
    const CGFloat W    = kb.size.width;
    const CGFloat hPad = 4, gap = 5, keyH = 42, vGap = 5, vPad = 10;
    const CGFloat keyW = floor((W - 2*hPad - 9*gap) / 10.0);
    CGFloat y = vPad;

    // Row 0: digits (10 keys)
    for (NSInteger i = 0; i < 10; i++)
        _kbDigits[i].frame = CGRectMake(hPad + i*(keyW+gap), y, keyW, keyH);
    y += keyH + vGap;

    // Row 1: QWERTYUIOP (10 keys)
    for (NSInteger i = 0; i < 10; i++)
        _kbRow1[i].frame = CGRectMake(hPad + i*(keyW+gap), y, keyW, keyH);
    y += keyH + vGap;

    // Row 2: ASDFGHJKL (9 keys, centred)
    CGFloat row2W = 9*keyW + 8*gap;
    CGFloat row2X = floor((W - row2W) / 2.0);
    for (NSInteger i = 0; i < 9; i++)
        _kbRow2[i].frame = CGRectMake(row2X + i*(keyW+gap), y, keyW, keyH);
    y += keyH + vGap;

    // Row 3: ⇧ (wider) + ZXCVBNM + ⌫ (wider)
    CGFloat letW  = 7*keyW + 6*gap;
    CGFloat sides = W - 2*hPad - letW - 2*gap;
    CGFloat shW   = floor(sides * 0.46);
    CGFloat bkW   = sides - shW;
    _kbShiftBtn.frame = CGRectMake(hPad, y, shW, keyH);
    CGFloat letX = hPad + shW + gap;
    for (NSInteger i = 0; i < 7; i++)
        _kbRow3[i].frame = CGRectMake(letX + i*(keyW+gap), y, keyW, keyH);
    _kbBkspKey.frame = CGRectMake(letX + letW + gap, y, bkW, keyH);
    y += keyH + vGap;

    // Row 4: Esc  Tab  [   Space   ]  Ent
    CGFloat specW  = floor(keyW * 1.3);
    CGFloat spaceW = W - 2*hPad - 3*specW - 3*gap;
    _kbEscKey.frame   = CGRectMake(hPad,                              y, specW,  keyH);
    _kbTabKey.frame   = CGRectMake(hPad + specW + gap,                y, specW,  keyH);
    _kbSpaceKey.frame = CGRectMake(hPad + 2*(specW+gap),              y, spaceW, keyH);
    _kbEntKey.frame   = CGRectMake(hPad + 2*(specW+gap)+spaceW+gap,   y, specW,  keyH);
    y += keyH + vGap;

    // Row 5: arrow keys (4 equal-width keys spanning full row)
    CGFloat arrW = floor((W - 2*hPad - 3*gap) / 4.0);
    for (NSInteger i = 0; i < 4; i++)
        _kbArrows[i].frame = CGRectMake(hPad + i*(arrW+gap), y, arrW, keyH);
    y += keyH + vGap;

    // Row 6: nav keys (5 equal-width keys spanning full row)
    CGFloat navW = floor((W - 2*hPad - 4*gap) / 5.0);
    for (NSInteger i = 0; i < 5; i++)
        _kbNav[i].frame = CGRectMake(hPad + i*(navW+gap), y, navW, keyH);
}

// -- SDL view alignment ------------------------------------------------------

- (void)updateSDLViewAlignment {
    if (!_sdlView) return;
    const CGFloat W = self.bounds.size.width;
    const CGFloat H = self.bounds.size.height;
    if (W >= H) { _sdlView.transform = CGAffineTransformIdentity; return; }

    const CGFloat gameH     = W * 3.0 / 4.0;
    const CGFloat topMargin = floor((H - gameH) / 2.0);
    const CGFloat safeTop   = self.safeAreaInsets.top;
    const CGFloat shift     = topMargin - safeTop;
    _sdlView.transform = (shift > 1.0)
        ? CGAffineTransformMakeTranslation(0, -shift)
        : CGAffineTransformIdentity;
}

// -- Layout ------------------------------------------------------------------

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateSDLViewAlignment];

    UIEdgeInsets safe = self.safeAreaInsets;
    const CGFloat W   = self.bounds.size.width;
    const CGFloat H   = self.bounds.size.height;
    const CGFloat sz  = 54;
    const CGFloat g   = 8;
    const CGFloat lm  = safe.left  + 16;
    const CGFloat rm  = safe.right + 16;

    _pad.frame = self.bounds;

    const CGFloat tSz  = 36;
    const CGFloat tGap = 8;
    const CGFloat controlsH = g + 3 * sz;

    CGFloat gameBottom  = 0;
    CGFloat combinedTop;
    if (W < H) {
        gameBottom  = safe.top + W * 3.0 / 4.0;
        combinedTop = gameBottom + tSz + 2 * tGap;
    } else {
        combinedTop = floor((H - controlsH) / 2.0);
    }
    const CGFloat re = W - rm;

    // D-pad
    _dpad.frame = CGRectMake(lm, combinedTop + g, 3*sz, 3*sz);

    // Action buttons (arc: right column offset up by arcOff, matching SF-style layout)
    const CGFloat arcOff   = roundf(sz * 0.30);
    const CGFloat clusterH = 2*sz + g + arcOff;
    const CGFloat arcTop   = combinedTop + floor((controlsH - clusterH) / 2.0);
    const CGFloat col0     = re - 2*sz - g;
    const CGFloat col1     = re - sz;
    [_pad viewWithTag:kBtnLP].frame = CGRectMake(col0, arcTop + arcOff,          sz, sz); // F1
    [_pad viewWithTag:kBtnMP].frame = CGRectMake(col1, arcTop,                   sz, sz); // F2
    [_pad viewWithTag:kBtnLK].frame = CGRectMake(col0, arcTop + arcOff + sz + g, sz, sz); // Esc
    [_pad viewWithTag:kBtnMK].frame = CGRectMake(col1, arcTop + sz + g,          sz, sz); // Space
    for (NSInteger tag = kBtnLP; tag <= kBtnMK; tag++)
        [_pad viewWithTag:tag].layer.cornerRadius = sz / 2.0;

    // Utility strip
    if (W < H && gameBottom > 0) {
        const CGFloat midY  = gameBottom + tGap;
        const CGFloat row4W = 6*tSz + 5*tGap;
        const CGFloat row4X = floor((W - row4W) / 2.0);
        [self viewWithTag:kHome].frame      = CGRectMake(row4X,                  midY, tSz, tSz);
        [self viewWithTag:kModeSwitch].frame= CGRectMake(row4X +   tSz + tGap,   midY, tSz, tSz);
        [self viewWithTag:kToggle].frame    = CGRectMake(row4X + 2*(tSz+tGap),   midY, tSz, tSz);
        [self viewWithTag:kKeyboard].frame  = CGRectMake(row4X + 3*(tSz+tGap),   midY, tSz, tSz);
        [self viewWithTag:kVolume].frame    = CGRectMake(row4X + 4*(tSz+tGap),   midY, tSz, tSz);
        [self viewWithTag:kSwapCD].frame    = CGRectMake(row4X + 5*(tSz+tGap),   midY, tSz, tSz);
        [self viewWithTag:kKeyboard].hidden = NO;
        [self viewWithTag:kVolume].hidden   = NO;
        [self viewWithTag:kSwapCD].hidden   = NO;

        // Keyboard view occupies the controls area
        CGFloat kbTop = combinedTop;
        CGFloat kbH   = H - safe.bottom - kbTop;
        _keyboardView.frame = CGRectMake(0, kbTop, W, kbH);
        [self layoutKeyboardInBounds:_keyboardView.bounds];
    } else {
        const CGFloat tm = safe.top + 16;
        [self viewWithTag:kHome].frame       = CGRectMake(lm,                      tm, tSz, tSz);
        [self viewWithTag:kModeSwitch].frame = CGRectMake(lm + tSz + tGap,         tm, tSz, tSz);
        [self viewWithTag:kToggle].frame     = CGRectMake(lm + 2*(tSz + tGap),     tm, tSz, tSz);
        [self viewWithTag:kVolume].frame     = CGRectMake(lm + 3*(tSz + tGap),     tm, tSz, tSz);
        [self viewWithTag:kSwapCD].frame     = CGRectMake(lm + 4*(tSz + tGap),     tm, tSz, tSz);
        [self viewWithTag:kKeyboard].hidden  = YES;
        [self viewWithTag:kVolume].hidden    = NO;
        [self viewWithTag:kSwapCD].hidden    = NO;
        if (_keyboardActive) [self dismissKeyboard];
    }
}

// -- Actions -----------------------------------------------------------------

- (void)togglePad {
    _padHidden  = !_padHidden;
    _pad.hidden = _padHidden;
}

- (void)toggleKeyboard {
    if (_keyboardActive) {
        [self dismissKeyboard];
    } else {
        _keyboardActive  = YES;
        _padWasHidden    = _padHidden;
        _pad.hidden      = YES;
        _keyboardView.hidden = NO;
        UIButton *btn = (UIButton *)[self viewWithTag:kKeyboard];
        btn.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.30 alpha:0.75];
    }
}

- (void)dismissKeyboard {
    _keyboardActive      = NO;
    _keyboardView.hidden = YES;
    _pad.hidden          = _padWasHidden;
    // Reset shift state
    if (_shiftActive) [self applyShift:NO];
    UIButton *btn = (UIButton *)[self viewWithTag:kKeyboard];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
}

- (void)toggleShift {
    [self applyShift:!_shiftActive];
}

- (void)applyShift:(BOOL)on {
    _shiftActive = on;
    _kbShiftBtn.backgroundColor = on
        ? [UIColor colorWithRed:0.10 green:0.55 blue:0.30 alpha:0.85]
        : [UIColor colorWithWhite:0.18 alpha:1.0];
    for (KBKey *k in _kbLetters) {
        k.shifted = on;
        [k setTitle:(on ? k.hiLabel : k.lowLabel) forState:UIControlStateNormal];
    }
}

- (void)switchMode {
    _altMode = !_altMode;
    KeyButton *lp = (KeyButton *)[_pad viewWithTag:kBtnLP];
    KeyButton *mp = (KeyButton *)[_pad viewWithTag:kBtnMP];
    KeyButton *lk = (KeyButton *)[_pad viewWithTag:kBtnLK];
    KeyButton *mk = (KeyButton *)[_pad viewWithTag:kBtnMK];
    if (_altMode) {
        lp.sc = SDL_SCANCODE_T; [lp setTitle:@"LP" forState:UIControlStateNormal];
        mp.sc = SDL_SCANCODE_Y; [mp setTitle:@"MP" forState:UIControlStateNormal];
        lk.sc = SDL_SCANCODE_G; [lk setTitle:@"LK" forState:UIControlStateNormal];
        mk.sc = SDL_SCANCODE_H; [mk setTitle:@"MK" forState:UIControlStateNormal];
    } else {
        lp.sc = SDL_SCANCODE_F1;     [lp setTitle:@"F1"    forState:UIControlStateNormal];
        mp.sc = SDL_SCANCODE_F2;     [mp setTitle:@"F2"    forState:UIControlStateNormal];
        lk.sc = SDL_SCANCODE_ESCAPE; [lk setTitle:@"Esc"   forState:UIControlStateNormal];
        mk.sc = SDL_SCANCODE_SPACE;  [mk setTitle:@"Space" forState:UIControlStateNormal];
    }
    _dpad.wasdMode = _altMode;
    UIButton *modeBtn = (UIButton *)[self viewWithTag:kModeSwitch];
    [modeBtn setTitle:_altMode ? @"STD" : @"FGT" forState:UIControlStateNormal];
}

- (void)volumePressed {
    static const float kVolLevels[] = {0.0f, 0.05f, 0.1f, 0.2f, 1.0f};
    static NSString * const kVolLabels[] = {@"VOL\n 0%", @"VOL\n 5%", @"VOL\n10%", @"VOL\n20%", @"VOL\n100%"};
    _volumeIndex = (_volumeIndex + 1) % 5;
    mxDOS_setAudioVolume(kVolLevels[_volumeIndex]);
    UIButton *btn = (UIButton *)[self viewWithTag:kVolume];
    [btn setTitle:kVolLabels[_volumeIndex] forState:UIControlStateNormal];
    btn.backgroundColor = (_volumeIndex == 0)
        ? [UIColor colorWithRed:0.55 green:0.10 blue:0.10 alpha:0.65]
        : [UIColor colorWithWhite:0.0 alpha:0.45];
}

- (void)swapCDPressed {
    // 4 images: FDPS1.cue, FDPS1.iso, FDPS2.cue, FDPS2.iso — call twice to land on FDPS2.cue
    mxdos_cycle_discs();
    mxdos_cycle_discs();
}

- (void)homePressed {
    if (_keyboardActive) [self dismissKeyboard];
    mxdos_request_quit();
}

// -- Hit testing -------------------------------------------------------------

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == _pad) ? nil : hit;
}

@end
