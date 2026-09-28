// Insomnia — a menu bar toggle that keeps your Mac awake.
// Left-click the moon to toggle. Right-click for options.
#import <Cocoa/Cocoa.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <ServiceManagement/ServiceManagement.h>

static NSString *const kStateKey = @"insomnia.awake";

#pragma mark - Icons

static NSImage *Symbol(NSString *name, CGFloat pointSize, NSFontWeight weight) {
    NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    NSImage *img = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:name] imageWithSymbolConfiguration:cfg];
    img.template = YES;
    return img;
}

/// Plain moon: the Mac is allowed to sleep.
static NSImage *AsleepIcon(void) {
    return Symbol(@"moon.fill", 15, NSFontWeightRegular);
}

/// Moon with a cross above it: sleep is blocked.
static NSImage *AwakeIcon(void) {
    NSImage *moon  = Symbol(@"moon.fill", 13, NSFontWeightRegular);
    NSImage *cross = Symbol(@"xmark", 7, NSFontWeightHeavy);
    NSImage *img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        // Moon sits bottom-left, cross sits top-right above it.
        [moon  drawInRect:NSMakeRect(0, 0, 13, 13)];
        [cross drawInRect:NSMakeRect(10.5, 10.5, 7, 7)];
        return YES;
    }];
    img.template = YES;
    return img;
}

#pragma mark - App

@interface Insomnia : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSImage *awakeIcon;
@property (strong) NSImage *asleepIcon;
@end

@implementation Insomnia {
    IOPMAssertionID _assertions[2];
    int _assertionCount;
}

- (BOOL)isAwake {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:kStateKey];
    return v ? [v boolValue] : YES;   // default: on
}

- (void)setAwake:(BOOL)awake {
    [NSUserDefaults.standardUserDefaults setBool:awake forKey:kStateKey];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.awakeIcon  = AwakeIcon();
    self.asleepIcon = AsleepIcon();
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.target = self;
    button.action = @selector(handleClick:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    [self apply:self.isAwake];
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [self releaseAssertions];
}

#pragma mark Clicks

- (void)handleClick:(id)sender {
    NSEvent *e = NSApp.currentEvent;
    if (e.type == NSEventTypeRightMouseUp || (e.modifierFlags & NSEventModifierFlagControl)) {
        [self showMenu];
    } else {
        [self apply:!self.isAwake];
    }
}

- (void)toggle { [self apply:!self.isAwake]; }

- (void)toggleLaunchAtLogin {
    SMAppService *svc = SMAppService.mainAppService;
    NSError *err = nil;
    if (svc.status == SMAppServiceStatusEnabled) [svc unregisterAndReturnError:&err];
    else                                          [svc registerAndReturnError:&err];
    if (err) NSBeep();
}

- (void)quit { [NSApp terminate:nil]; }

- (void)showMenu {
    BOOL awake = self.isAwake;
    NSMenu *menu = [NSMenu new];

    NSMenuItem *state = [[NSMenuItem alloc] initWithTitle:awake ? @"Insomnia is on — Mac stays awake"
                                                                : @"Insomnia is off — Mac may sleep"
                                                   action:nil keyEquivalent:@""];
    state.enabled = NO;
    [menu addItem:state];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *t = [[NSMenuItem alloc] initWithTitle:@"Prevent Sleep" action:@selector(toggle) keyEquivalent:@""];
    t.state = awake ? NSControlStateValueOn : NSControlStateValueOff;
    t.target = self;
    [menu addItem:t];

    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"Launch at Login" action:@selector(toggleLaunchAtLogin) keyEquivalent:@""];
    login.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    login.target = self;
    [menu addItem:login];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *q = [[NSMenuItem alloc] initWithTitle:@"Quit Insomnia" action:@selector(quit) keyEquivalent:@"q"];
    q.target = self;
    [menu addItem:q];

    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = nil;   // restore click-to-toggle
}

#pragma mark Power assertions

- (void)apply:(BOOL)awake {
    self.awake = awake;
    if (awake) [self acquireAssertions]; else [self releaseAssertions];
    self.statusItem.button.image = awake ? self.awakeIcon : self.asleepIcon;
    self.statusItem.button.toolTip = awake ? @"Insomnia: Mac stays awake (click to allow sleep)"
                                           : @"Insomnia: Mac may sleep (click to keep awake)";
}

- (void)acquireAssertions {
    if (_assertionCount > 0) return;
    // Same pair caffeinate -i -s uses: idle sleep always, system sleep on AC.
    CFStringRef types[2] = { kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventSystemSleep };
    for (int i = 0; i < 2; i++) {
        IOPMAssertionID id = 0;
        IOReturn r = IOPMAssertionCreateWithName(types[i], kIOPMAssertionLevelOn,
                                                 CFSTR("Insomnia keeps the Mac awake"), &id);
        if (r == kIOReturnSuccess) _assertions[_assertionCount++] = id;
    }
}

- (void)releaseAssertions {
    for (int i = 0; i < _assertionCount; i++) IOPMAssertionRelease(_assertions[i]);
    _assertionCount = 0;
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        Insomnia *delegate = [Insomnia new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];   // menu bar only, no Dock icon
        [app run];
    }
    return 0;
}
