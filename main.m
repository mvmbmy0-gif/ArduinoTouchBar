#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

// ==============================================================================
//  LANGUAGE / LOCALIZATION CONFIGURATION
//  ------------------------------------------------------------------------------
//  - Set FORCE_LANGUAGE to nil for automatic system language detection (en/uk),
//    or explicitly set to @"en", @"uk", @"es", @"de", etc.
//  - To add a new language, simply add a new key dictionary to kI18n below!
// ==============================================================================

#define FORCE_LANGUAGE nil

static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *kI18n = @{
    @"en": @{
        @"verify":          @"Verify",
        @"upload":          @"Upload",
        @"serial":          @"Monitor",
        @"sketches":        @"Sketches",
        @"libraries":       @"Libraries",
        @"sketch_fallback": @"Sketch",
        @"menu_toggle":     @"Show / Hide Arduino Bar",
        @"menu_quit":       @"Quit ArduinoTouchBar"
    },
    @"uk": @{
        @"verify":          @"Перевірити",
        @"upload":          @"Зашити",
        @"serial":          @"Монітор",
        @"sketches":        @"Скетчі",
        @"libraries":       @"Бібліотеки",
        @"sketch_fallback": @"Скетч",
        @"menu_toggle":     @"Показати / Сховати панель Arduino",
        @"menu_quit":       @"Вийти з ArduinoTouchBar"
    }
};

static NSString *Localized(NSString *key) {
    NSString *lang = FORCE_LANGUAGE;
    if (!lang) {
        NSString *preferred = [NSLocale preferredLanguages].firstObject ?: @"en";
        if ([preferred hasPrefix:@"uk"]) {
            lang = @"uk";
        } else {
            lang = @"en";
        }
    }
    NSDictionary *dict = kI18n[lang] ?: kI18n[@"en"];
    return dict[key] ?: kI18n[@"en"][key] ?: key;
}

// --- Private Touch Bar and DFR APIs ---
@interface NSTouchBarItem (Private)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (Private)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier identifier, BOOL present);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL shows);

@interface ArduinoBarController : NSObject <NSApplicationDelegate, NSTouchBarDelegate>
@property (strong) NSCustomTouchBarItem *trayItem;
@property (copy) NSString *currentTrayId;
@property (assign) NSInteger trayCounter;

@property (strong) NSTouchBar *arduinoTouchBar;
@property (strong) NSArray<NSTouchBarItemIdentifier> *mainIdentifiers;
@property (strong) NSArray<NSTouchBarItemIdentifier> *mainIdentifiersWithWindows;
@property (strong) NSStatusItem *statusItem;
@property (strong) NSTimer *windowPollTimer;

@property (strong) NSArray<NSDictionary *> *openWindows;
@property (assign) BOOL isShowingWindows;
@property (assign) BOOL isBarVisible;
@property (assign) BOOL isTrayVisible;
@property (assign) BOOL userDismissedManually;
@end

@implementation ArduinoBarController

- (NSImage *)sfSymbol:(NSString *)name {
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        if (img) {
            [img setTemplate:YES];
            return img;
        }
    }
    return nil;
}

- (void)createTrayItem {
    self.trayCounter += 1;
    self.currentTrayId = [NSString stringWithFormat:@"com.local.arduinobar.tray.%ld", (long)self.trayCounter];
    self.trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:self.currentTrayId];

    NSImage *trayImg = [self sfSymbol:@"cpu"];
    if (@available(macOS 11.0, *)) {
        if (trayImg) {
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:15.5 weight:NSFontWeightRegular];
            trayImg = [trayImg imageWithSymbolConfiguration:cfg];
            NSImage *whiteImg = [NSImage imageWithSize:trayImg.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
                [trayImg drawInRect:dstRect];
                [[NSColor whiteColor] set];
                NSRectFillUsingOperation(dstRect, NSCompositingOperationSourceAtop);
                return YES;
            }];
            [whiteImg setTemplate:NO];
            trayImg = whiteImg;
        }
    }

    NSButton *trayBtn = nil;
    if (trayImg) {
        trayBtn = [NSButton buttonWithImage:trayImg target:self action:@selector(toggleBar:)];
        trayBtn.imageScaling = NSImageScaleNone;
    } else {
        trayBtn = [NSButton buttonWithTitle:@"INO" target:self action:@selector(toggleBar:)];
    }
    [trayBtn setButtonType:NSButtonTypeMomentaryChange];
    trayBtn.bordered = NO;
    trayBtn.wantsLayer = YES;
    // Native Control Strip dark tint (#3B3B3D) and standard 38pt width
    trayBtn.layer.backgroundColor = [NSColor colorWithDisplayP3Red:54.5/255.0 green:54.5/255.0 blue:55.0/255.0 alpha:1.0].CGColor;
    trayBtn.layer.cornerRadius = 0.0;
    [trayBtn.widthAnchor constraintEqualToConstant:38].active = YES;

    self.trayItem.view = trayBtn;
    [NSTouchBarItem addSystemTrayItem:self.trayItem];
    DFRElementSetControlStripPresenceForIdentifier(self.currentTrayId, YES);
    self.isTrayVisible = YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

    self.trayCounter = 0;
    self.isShowingWindows = NO;
    self.isBarVisible = NO;
    self.isTrayVisible = NO;
    self.userDismissedManually = NO;
    self.openWindows = @[];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *menuImg = [self sfSymbol:@"cpu"];
    if (menuImg) {
        self.statusItem.button.image = menuImg;
    } else {
        self.statusItem.button.title = @"ArduinoBar";
    }
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:Localized(@"menu_toggle") action:@selector(toggleBar:) keyEquivalent:@"a"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:Localized(@"menu_quit") action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;

    DFRSystemModalShowsCloseBoxWhenFrontMost(YES);

    self.mainIdentifiers = @[
        @"com.local.ino.verify",
        @"com.local.ino.upload",
        @"com.local.ino.serial",
        @"com.local.ino.sketchbook",
        @"com.local.ino.libs"
    ];

    self.mainIdentifiersWithWindows = @[
        @"com.local.ino.verify",
        @"com.local.ino.upload",
        @"com.local.ino.serial",
        @"com.local.ino.sketchbook",
        @"com.local.ino.libs",
        @"com.local.ino.windows"
    ];

    self.arduinoTouchBar = [[NSTouchBar alloc] init];
    self.arduinoTouchBar.delegate = self;
    self.arduinoTouchBar.defaultItemIdentifiers = self.mainIdentifiers;

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(checkFrontApp)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];

    self.windowPollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(refreshArduinoWindows)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (NSRunningApplication *)findArduinoApp {
    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *name = front.localizedName ?: @"";
    NSString *bid = front.bundleIdentifier ?: @"";
    if ([name rangeOfString:@"Arduino" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [bid rangeOfString:@"arduino" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return front;
    }
    return nil;
}

- (NSString *)formatWindowTitle:(NSString *)rawTitle {
    NSString *clean = rawTitle ?: Localized(@"sketch_fallback");
    NSArray *seps = @[@" — Arduino IDE", @" - Arduino IDE", @" | Arduino IDE"];
    for (NSString *sep in seps) {
        NSRange r = [clean rangeOfString:sep];
        if (r.location != NSNotFound) {
            clean = [clean substringToIndex:r.location];
            break;
        }
    }
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return clean.length > 0 ? clean : Localized(@"sketch_fallback");
}

- (void)refreshArduinoWindows {
    if (![self findArduinoApp] || !AXIsProcessTrusted()) return;

    NSMutableArray *found = [NSMutableArray array];
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        NSString *name = app.localizedName ?: @"";
        NSString *bid = app.bundleIdentifier ?: @"";
        if ([name rangeOfString:@"Arduino" options:NSCaseInsensitiveSearch].location == NSNotFound &&
            [bid rangeOfString:@"arduino" options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        if ([bid isEqualToString:@"com.local.ArduinoTouchBar"]) continue;

        AXUIElementRef appRef = AXUIElementCreateApplication(app.processIdentifier);
        if (!appRef) continue;

        CFArrayRef winList = NULL;
        if (AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef *)&winList) == kAXErrorSuccess && winList) {
            CFIndex count = CFArrayGetCount(winList);
            for (CFIndex i = 0; i < count; i++) {
                AXUIElementRef winRef = (AXUIElementRef)CFArrayGetValueAtIndex(winList, i);
                CFTypeRef titleRef = NULL;
                AXUIElementCopyAttributeValue(winRef, kAXTitleAttribute, &titleRef);
                NSString *title = titleRef ? (__bridge_transfer NSString *)titleRef : @"";

                CFTypeRef roleRef = NULL;
                AXUIElementCopyAttributeValue(winRef, kAXRoleAttribute, &roleRef);
                NSString *role = roleRef ? (__bridge_transfer NSString *)roleRef : @"";

                if ([role isEqualToString:(__bridge NSString *)kAXWindowRole] || role.length == 0) {
                    if (title.length > 0) {
                        NSString *formatted = [self formatWindowTitle:title];
                        [found addObject:@{
                            @"title": formatted,
                            @"rawTitle": title,
                            @"pid": @(app.processIdentifier)
                        }];
                    }
                }
            }
            CFRelease(winList);
        }
        CFRelease(appRef);
    }

    self.openWindows = [found copy];

    if (!self.isShowingWindows) {
        NSArray *desired = (self.openWindows.count > 1) ? self.mainIdentifiersWithWindows : self.mainIdentifiers;
        if (![self.arduinoTouchBar.defaultItemIdentifiers isEqualToArray:desired]) {
            self.arduinoTouchBar.defaultItemIdentifiers = desired;
        }
    }
}

- (void)checkFrontApp {
    if ([self findArduinoApp]) {
        [self refreshArduinoWindows];
        if (!self.isTrayVisible) {
            [self createTrayItem];
        }
        if (!self.isBarVisible && !self.userDismissedManually) {
            [self showBar];
        }
    } else {
        if (self.isTrayVisible && self.currentTrayId) {
            DFRElementSetControlStripPresenceForIdentifier(self.currentTrayId, NO);
            self.isTrayVisible = NO;
        }
        if (self.isBarVisible) {
            [NSTouchBar dismissSystemModalTouchBar:self.arduinoTouchBar];
            self.isBarVisible = NO;
            self.isShowingWindows = NO;
        }
        self.userDismissedManually = NO;
    }
}

- (void)showBar {
    if (!self.isTrayVisible) {
        [self createTrayItem];
    }
    self.isShowingWindows = NO;
    self.arduinoTouchBar.defaultItemIdentifiers = (self.openWindows.count > 1) ? self.mainIdentifiersWithWindows : self.mainIdentifiers;
    [NSTouchBar presentSystemModalTouchBar:self.arduinoTouchBar systemTrayItemIdentifier:self.currentTrayId];
    self.isBarVisible = YES;
    self.userDismissedManually = NO;
}

- (void)toggleBar:(id)sender {
    if (self.isBarVisible) {
        [NSTouchBar dismissSystemModalTouchBar:self.arduinoTouchBar];
        self.isBarVisible = NO;
        self.isShowingWindows = NO;
        self.userDismissedManually = YES;
    } else {
        [self showBar];
    }
}

- (void)openWindowsMenu:(id)sender {
    [self refreshArduinoWindows];
    if (self.openWindows.count <= 1) return;
    self.isShowingWindows = YES;

    NSMutableArray *ids = [NSMutableArray arrayWithObject:@"com.local.ino.back"];
    for (NSInteger i = 0; i < (NSInteger)self.openWindows.count; i++) {
        [ids addObject:[NSString stringWithFormat:@"com.local.ino.win.%ld", (long)i]];
    }
    self.arduinoTouchBar.defaultItemIdentifiers = ids;
}

- (void)closeWindowsMenu:(id)sender {
    self.isShowingWindows = NO;
    self.arduinoTouchBar.defaultItemIdentifiers = (self.openWindows.count > 1) ? self.mainIdentifiersWithWindows : self.mainIdentifiers;
}

- (void)raiseWindow:(NSButton *)sender {
    NSInteger pos = sender.tag;
    if (pos >= 0 && pos < (NSInteger)self.openWindows.count) {
        NSDictionary *info = self.openWindows[pos];
        pid_t pid = [info[@"pid"] intValue];
        NSString *targetRaw = info[@"rawTitle"];

        AXUIElementRef appRef = AXUIElementCreateApplication(pid);
        CFArrayRef winList = NULL;
        if (AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef *)&winList) == kAXErrorSuccess && winList) {
            CFIndex count = CFArrayGetCount(winList);
            for (CFIndex i = 0; i < count; i++) {
                AXUIElementRef winRef = (AXUIElementRef)CFArrayGetValueAtIndex(winList, i);
                CFTypeRef titleRef = NULL;
                AXUIElementCopyAttributeValue(winRef, kAXTitleAttribute, &titleRef);
                NSString *t = titleRef ? (__bridge_transfer NSString *)titleRef : @"";
                if ([t isEqualToString:targetRaw] || (count == 1)) {
                    AXUIElementPerformAction(winRef, kAXRaiseAction);
                    AXUIElementSetAttributeValue(winRef, kAXMainAttribute, kCFBooleanTrue);
                    break;
                }
            }
            CFRelease(winList);
        }
        CFRelease(appRef);

        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        [app activateWithOptions:0];
    }
    [self closeWindowsMenu:nil];
}

- (void)sendKeyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags {
    if (!AXIsProcessTrusted()) {
        NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
        return;
    }
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef down = CGEventCreateKeyboardEvent(src, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(src, keyCode, false);
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    CFRelease(src);
}

- (void)doVerify:(id)sender     { [self sendKeyCode:kVK_ANSI_R flags:kCGEventFlagMaskCommand]; }
- (void)doUpload:(id)sender     { [self sendKeyCode:kVK_ANSI_U flags:kCGEventFlagMaskCommand]; }
- (void)doSerial:(id)sender     { [self sendKeyCode:kVK_ANSI_M flags:(kCGEventFlagMaskCommand | kCGEventFlagMaskShift)]; }
- (void)doSketchbook:(id)sender { [self sendKeyCode:kVK_ANSI_B flags:(kCGEventFlagMaskCommand | kCGEventFlagMaskShift)]; }
- (void)doLibs:(id)sender       { [self sendKeyCode:kVK_ANSI_I flags:(kCGEventFlagMaskCommand | kCGEventFlagMaskShift)]; }

- (NSButton *)makeSymbolButton:(NSString *)symbolName title:(NSString *)title action:(SEL)action {
    NSImage *img = [self sfSymbol:symbolName];
    NSButton *btn;
    if (img) {
        btn = [NSButton buttonWithTitle:title image:img target:self action:action];
        btn.imagePosition = title.length > 0 ? NSImageLeft : NSImageOnly;
    } else {
        btn = [NSButton buttonWithTitle:title target:self action:action];
    }
    btn.bezelStyle = NSBezelStyleRounded;
    return btn;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    NSButton *btn = nil;

    if ([identifier isEqualToString:@"com.local.ino.verify"]) {
        btn = [self makeSymbolButton:@"checkmark.circle" title:Localized(@"verify") action:@selector(doVerify:)];
    } else if ([identifier isEqualToString:@"com.local.ino.upload"]) {
        btn = [self makeSymbolButton:@"arrow.right.circle" title:Localized(@"upload") action:@selector(doUpload:)];
    } else if ([identifier isEqualToString:@"com.local.ino.serial"]) {
        btn = [self makeSymbolButton:@"terminal" title:Localized(@"serial") action:@selector(doSerial:)];
    } else if ([identifier isEqualToString:@"com.local.ino.sketchbook"]) {
        btn = [self makeSymbolButton:@"folder" title:Localized(@"sketches") action:@selector(doSketchbook:)];
    } else if ([identifier isEqualToString:@"com.local.ino.libs"]) {
        btn = [self makeSymbolButton:@"books.vertical" title:Localized(@"libraries") action:@selector(doLibs:)];
    } else if ([identifier isEqualToString:@"com.local.ino.windows"]) {
        btn = [self makeSymbolButton:@"macwindow.on.rectangle" title:@"" action:@selector(openWindowsMenu:)];
        [btn.widthAnchor constraintEqualToConstant:48].active = YES;
    } else if ([identifier isEqualToString:@"com.local.ino.back"]) {
        btn = [self makeSymbolButton:@"chevron.left" title:@"" action:@selector(closeWindowsMenu:)];
        [btn.widthAnchor constraintEqualToConstant:64].active = YES;
    } else if ([identifier hasPrefix:@"com.local.ino.win."]) {
        NSInteger pos = [[identifier substringFromIndex:18] integerValue];
        if (pos >= 0 && pos < (NSInteger)self.openWindows.count) {
            NSDictionary *info = self.openWindows[pos];
            btn = [self makeSymbolButton:@"doc.text" title:info[@"title"] action:@selector(raiseWindow:)];
            btn.tag = pos;
        }
    }

    if (btn) {
        item.view = btn;
    }
    return item;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ArduinoBarController *controller = [[ArduinoBarController alloc] init];
        app.delegate = controller;
        [app run];
    }
    return 0;
}
