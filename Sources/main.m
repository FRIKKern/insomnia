// Insomnia — a menu bar toggle that keeps your Mac awake.
// Left-click the moon to toggle. Right-click for options.
#import <Cocoa/Cocoa.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <ServiceManagement/ServiceManagement.h>

static NSString *const kStateKey   = @"insomnia.awake";
static NSString *const kLidKey     = @"insomnia.lid";
static NSString *const kSudoers    = @"/etc/sudoers.d/insomnia";

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

#pragma mark - Shell helpers

/// Runs a program synchronously. Returns exit status; stdout in *out if given.
static int Run(NSString *path, NSArray<NSString *> *args, NSString **out) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args;
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = [NSPipe pipe];
    NSError *err = nil;
    if (![t launchAndReturnError:&err]) return -1;
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    if (out) *out = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
    return t.terminationStatus;
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

#pragma mark Preferences

- (BOOL)isAwake {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:kStateKey];
    return v ? [v boolValue] : YES;   // default: on
}
- (void)setAwake:(BOOL)awake { [NSUserDefaults.standardUserDefaults setBool:awake forKey:kStateKey]; }

- (BOOL)lidPref { return [NSUserDefaults.standardUserDefaults boolForKey:kLidKey]; }   // default: off
- (void)setLidPref:(BOOL)on { [NSUserDefaults.standardUserDefaults setBool:on forKey:kLidKey]; }

#pragma mark Lifecycle

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
    // Never leave the lid override behind when we are not running to own it.
    if ([self lidSleepDisabled]) [self setLidSleepDisabled:NO];
}

/// Scriptable: open insomnia://on|off|toggle|lid-on|lid-off
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) {
        NSString *cmd = u.host.lowercaseString ?: @"";
        if      ([cmd isEqualToString:@"on"])      [self apply:YES];
        else if ([cmd isEqualToString:@"off"])     [self apply:NO];
        else if ([cmd isEqualToString:@"toggle"])  [self apply:!self.isAwake];
        else if ([cmd isEqualToString:@"lid-on"])  [self enableLid:NO];
        else if ([cmd isEqualToString:@"lid-off"]) { self.lidPref = NO; [self syncLid]; }
    }
}

#pragma mark Clicks and menu

- (void)handleClick:(id)sender {
    NSEvent *e = NSApp.currentEvent;
    if (e.type == NSEventTypeRightMouseUp || (e.modifierFlags & NSEventModifierFlagControl)) {
        [self showMenu];
    } else {
        [self apply:!self.isAwake];
    }
}

- (void)toggle { [self apply:!self.isAwake]; }

- (void)toggleLid {
    if (self.lidPref) { self.lidPref = NO; [self syncLid]; }
    else              [self enableLid:YES];
}

- (void)toggleLaunchAtLogin {
    SMAppService *svc = SMAppService.mainAppService;
    NSError *err = nil;
    if (svc.status == SMAppServiceStatusEnabled) [svc unregisterAndReturnError:&err];
    else                                          [svc registerAndReturnError:&err];
    if (err) NSBeep();
}

- (void)quit { [NSApp terminate:nil]; }

- (void)showMenu {
    BOOL awake = self.isAwake, lid = self.lidPref;
    NSMenu *menu = [NSMenu new];

    NSString *title = !awake ? @"Insomnia is off — Mac may sleep"
                    : lid    ? @"Insomnia is on — awake even with lid closed"
                             : @"Insomnia is on — Mac stays awake";
    NSMenuItem *state = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    state.enabled = NO;
    [menu addItem:state];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *t = [[NSMenuItem alloc] initWithTitle:@"Prevent Sleep" action:@selector(toggle) keyEquivalent:@""];
    t.state = awake ? NSControlStateValueOn : NSControlStateValueOff;
    t.target = self;
    [menu addItem:t];

    NSMenuItem *l = [[NSMenuItem alloc] initWithTitle:@"Keep Awake With Lid Closed" action:@selector(toggleLid) keyEquivalent:@""];
    l.state = lid ? NSControlStateValueOn : NSControlStateValueOff;
    l.target = self;
    [menu addItem:l];

    [menu addItem:NSMenuItem.separatorItem];
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
    [self syncLid];
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

#pragma mark Lid (pmset disablesleep, root-only)

/// The lid override is active only while Insomnia is on AND the lid preference is on.
- (void)syncLid {
    BOOL want = self.isAwake && self.lidPref;
    if (want != [self lidSleepDisabled]) [self setLidSleepDisabled:want];
}

- (BOOL)lidSleepDisabled {
    NSString *out = nil;
    Run(@"/usr/bin/pmset", @[@"-g"], &out);
    for (NSString *line in [out componentsSeparatedByString:@"\n"])
        if ([line containsString:@"SleepDisabled"]) return [line hasSuffix:@"1"];
    return NO;
}

- (BOOL)setLidSleepDisabled:(BOOL)on {
    int rc = Run(@"/usr/bin/sudo", @[@"-n", @"/usr/bin/pmset", @"-a", @"disablesleep", on ? @"1" : @"0"], NULL);
    if (rc != 0) NSBeep();
    return rc == 0;
}

/// True once the one-time sudo rule lets us run pmset without a password.
- (BOOL)canSetLid {
    return Run(@"/usr/bin/sudo", @[@"-n", @"-l", @"/usr/bin/pmset", @"-a", @"disablesleep", @"1"], NULL) == 0;
}

/// Installs a sudoers rule that allows exactly two commands: pmset -a disablesleep 1 / 0.
- (BOOL)installSudoRule {
    NSString *rule = [NSString stringWithFormat:
        @"%@ ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0", NSUserName()];
    NSString *sh = [NSString stringWithFormat:
        @"printf '%%s\\n' '%@' > %@ && chmod 0440 %@ && visudo -cf %@ || { rm -f %@; exit 1; }",
        rule, kSudoers, kSudoers, kSudoers, kSudoers];
    NSString *script = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",
        [sh stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    NSDictionary *err = nil;
    [NSApp activateIgnoringOtherApps:YES];
    [[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&err];
    return err == nil && [self canSetLid];
}

- (void)enableLid:(BOOL)confirm {
    if (confirm) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Keep the Mac awake with the lid closed?";
        a.informativeText = @"It will keep running with the lid shut, also inside a bag, and can get warm.\n\n"
                             "Insomnia turns this off again when you switch it off or quit. "
                             "The first time, macOS asks for your password to allow the change.";
        [a addButtonWithTitle:@"Keep Awake"];
        [a addButtonWithTitle:@"Cancel"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
    }
    if (![self canSetLid] && ![self installSudoRule]) { NSBeep(); return; }
    self.lidPref = YES;
    [self syncLid];
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
