#import "GameSelectionViewController.h"

// ---------------------------------------------------------------------------
// GameEntry
// ---------------------------------------------------------------------------

@interface GameEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *folderPath;
@property (nonatomic, copy) NSString *confPath;
@property (nonatomic)       BOOL      hasCustomConf;
@end

@implementation GameEntry
@end

// ---------------------------------------------------------------------------
// GameSelectionViewController
// ---------------------------------------------------------------------------

@interface GameSelectionViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy)   GameSelectedBlock       callback;
@property (nonatomic, copy)   GameCancelBlock         cancelBlock;
@property (nonatomic, strong) NSArray<GameEntry *>   *games;
@property (nonatomic, strong) UITableView            *tableView;
@property (nonatomic, strong) UILabel                *emptyLabel;
@end

@implementation GameSelectionViewController

- (instancetype)initWithCallback:(GameSelectedBlock)callback
                     cancelBlock:(nullable GameCancelBlock)cancelBlock {
    if (!(self = [super init])) return nil;
    _callback    = callback;
    _cancelBlock = cancelBlock;
    return self;
}

// -- View lifecycle ----------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];

    // Dark terminal background
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:1.0];

    // Title
    UILabel *title = [[UILabel alloc] init];
    title.text = @"mxDOS";
    title.textColor = [UIColor colorWithRed:0.10 green:0.90 blue:0.45 alpha:1.0];
    title.font = [UIFont monospacedSystemFontOfSize:30 weight:UIFontWeightBold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    // Subtitle
    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"Select a game to play";
    sub.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    sub.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sub];

    // Separator
    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [UIColor colorWithRed:0.10 green:0.90 blue:0.45 alpha:0.25];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sep];

    // Table
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    _tableView.separatorInset = UIEdgeInsetsMake(0, 20, 0, 0);
    _tableView.rowHeight = 72;
    _tableView.dataSource = self;
    _tableView.delegate   = self;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"game"];
    [self.view addSubview:_tableView];

    // Empty-state label (shown when Documents has no recognized games)
    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.text = @"No games found.\n\nCopy a game folder into this app\nvia Finder → Files.";
    _emptyLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    _emptyLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.hidden = YES;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor    constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [sub.topAnchor      constraintEqualToAnchor:title.bottomAnchor constant:4],
        [sub.centerXAnchor  constraintEqualToAnchor:self.view.centerXAnchor],

        [sep.topAnchor      constraintEqualToAnchor:sub.bottomAnchor constant:20],
        [sep.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [sep.heightAnchor   constraintEqualToConstant:1],

        [_tableView.topAnchor      constraintEqualToAnchor:sep.bottomAnchor],
        [_tableView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.widthAnchor   constraintEqualToAnchor:self.view.widthAnchor multiplier:0.7],
    ]];

    // "Continue Playing" button — only when shown as an in-game overlay
    if (_cancelBlock) {
        UIButton *cont = [UIButton buttonWithType:UIButtonTypeCustom];
        [cont setTitle:@"Continue Playing" forState:UIControlStateNormal];
        [cont setTitleColor:[UIColor colorWithRed:0.10 green:0.90 blue:0.45 alpha:1.0]
                   forState:UIControlStateNormal];
        cont.titleLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightSemibold];
        cont.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:cont];
        [cont addTarget:self action:@selector(continuePressed)
               forControlEvents:UIControlEventTouchUpInside];

        [NSLayoutConstraint activateConstraints:@[
            [cont.topAnchor    constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
            [cont.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        ]];
    }

    [self scanGames];
}

- (void)continuePressed {
    if (_cancelBlock) _cancelBlock();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self scanGames];
}

// -- Game scanning -----------------------------------------------------------

- (void)scanGames {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:docs error:nil];

    NSMutableArray<GameEntry *> *games = [NSMutableArray array];
    for (NSString *item in [items sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        NSString *dir = [docs stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;

        // Ignore hidden folders
        if ([item hasPrefix:@"."]) continue;

        NSString *conf = [dir stringByAppendingPathComponent:@"dosbox.conf"];
        if ([fm fileExistsAtPath:conf]) {
            if (!isMxDOSAutoGenConf(conf)) {
                // User-provided conf — use it as-is.
                GameEntry *e = [GameEntry new];
                e.name          = item;
                e.folderPath    = dir;
                e.confPath      = conf;
                e.hasCustomConf = YES;
                [games addObject:e];
                continue;
            }
            // mxDOS auto-gen (any version) — fall through and re-generate
            // so detection improvements and relative-path fixes are applied.
        }

        // No dosbox.conf — look for a .bat launcher, then fall back to .exe
        NSString *firstExe = [self firstLauncherInFolder:dir fm:fm];
        if (firstExe) {
            GameEntry *e = [GameEntry new];
            e.name          = item;
            e.folderPath    = dir;
            e.confPath      = [self generateConfForFolder:dir exe:firstExe];
            e.hasCustomConf = NO;
            [games addObject:e];
        }
    }

    _games = games;
    _emptyLabel.hidden  = (games.count > 0);
    _tableView.hidden   = (games.count == 0);
    [_tableView reloadData];
}

// DOS extenders / runtime helpers that should never be auto-launched.
static NSSet<NSString *> *dosRuntimes(void) {
    static NSSet *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        s = [NSSet setWithObjects:
             @"dos4gw.exe", @"dos32a.exe", @"pmode.exe", @"cwsdpmi.exe",
             @"hdpmi32i.exe", @"dpmi16bi.ovl", @"rtvdm.exe", @"dos4gw.exe",
             @"run16.exe", @"run32.exe", nil];
    });
    return s;
}

- (NSString *)firstLauncherInFolder:(NSString *)dir fm:(NSFileManager *)fm {
    NSArray<NSString *> *contents = [[fm contentsOfDirectoryAtPath:dir error:nil]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    // Prefer .bat files — they're explicit launch scripts set up by the game publisher.
    for (NSString *f in contents) {
        if ([f.pathExtension.lowercaseString isEqualToString:@"bat"]) return f;
    }
    NSSet *runtimes = dosRuntimes();
    for (NSString *f in contents) {
        if (![f.pathExtension.lowercaseString isEqualToString:@"exe"]) continue;
        if ([runtimes containsObject:f.lowercaseString]) continue;
        return f;
    }
    return nil;
}

static NSString *const kAutoGenMarker = @"# mxDOS auto-generated";

// Returns YES for confs written by mxDOS (any version) so we can re-generate them.
// Old v1 format started with "[cpu]"; new format starts with kAutoGenMarker.
// Confs containing an absolute iOS container path are also stale (UUID may have changed).
static BOOL isMxDOSAutoGenConf(NSString *confPath) {
    NSString *content = [NSString stringWithContentsOfFile:confPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    if (!content) return NO;
    NSString *first = [content componentsSeparatedByString:@"\n"].firstObject ?: @"";
    if ([first hasPrefix:kAutoGenMarker]) return YES;
    if ([first isEqualToString:@"[cpu]"])  return YES;          // old v1 format
    if ([content containsString:@"/var/mobile/Containers/"]) return YES; // stale absolute path
    return NO;
}

- (NSString *)generateConfForFolder:(NSString *)folder exe:(NSString *)exe {
    NSFileManager *fm = NSFileManager.defaultManager;

    // Use paths RELATIVE to the game folder (CWD = game folder when DOSBox starts).
    // This avoids baking in the iOS container UUID which changes on clean reinstall.
    NSMutableString *autoexec = [NSMutableString stringWithString:@"mount c .\n"];

    // Detect CD images in a CD/ subfolder and add imgmount with relative paths.
    NSString *cdDir = [folder stringByAppendingPathComponent:@"CD"];
    NSArray<NSString *> *cdContents = [[fm contentsOfDirectoryAtPath:cdDir error:nil]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<NSString *> *images = [NSMutableArray array];
    for (NSString *f in cdContents) {
        NSString *ext = f.pathExtension.lowercaseString;
        if ([@[@"cue", @"iso", @"img"] containsObject:ext])
            [images addObject:[@"CD" stringByAppendingPathComponent:f]];
    }
    if (images.count > 0) {
        [autoexec appendString:@"imgmount d"];
        for (NSString *rel in images)
            [autoexec appendFormat:@" \"%@\"", rel];
        [autoexec appendString:@" -t cdrom\n"];
    }

    [autoexec appendFormat:@"c:\n%@\n", exe.uppercaseString];

    NSString *body = [NSString stringWithFormat:
        @"%@\n[cpu]\ncore=normal\ncycles=auto\n\n[autoexec]\n%@",
        kAutoGenMarker, autoexec];

    NSString *path = [folder stringByAppendingPathComponent:@"dosbox.conf"];
    [body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

// -- UITableViewDataSource ---------------------------------------------------

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)_games.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"game" forIndexPath:ip];
    GameEntry *g = _games[(NSUInteger)ip.row];

    cell.backgroundColor = UIColor.clearColor;

    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = g.name;
    cfg.secondaryText = g.hasCustomConf ? @"dosbox.conf  ·  custom config" : @"auto-detected";
    cfg.textProperties.color = UIColor.whiteColor;
    cfg.textProperties.font  = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightSemibold];
    cfg.secondaryTextProperties.color = [UIColor colorWithWhite:0.45 alpha:1.0];
    cfg.secondaryTextProperties.font  = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(14, 20, 14, 20);
    cell.contentConfiguration = cfg;

    UIView *bg = [UIView new];
    bg.backgroundColor = [UIColor colorWithRed:0.12 green:0.55 blue:0.30 alpha:0.18];
    cell.selectedBackgroundView = bg;

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}

// -- UITableViewDelegate -----------------------------------------------------

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    GameEntry *g = _games[(NSUInteger)ip.row];
    // Callback hides the window directly — no dismissal needed since this VC
    // is the window's root, not a modally presented controller.
    if (_callback) _callback(g.confPath);
}

@end
