// Insomnia — a menu bar toggle that keeps your Mac awake.
// Left-click the moon to toggle. Right-click for options.
#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <ServiceManagement/ServiceManagement.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

static NSString *const kStateKey      = @"insomnia.awake";
static NSString *const kLidKey        = @"insomnia.lid";
static NSString *const kThresholdKey  = @"insomnia.lid.minBattery";    // percent, default 20
static NSString *const kGraceKey      = @"insomnia.lid.graceMinutes";  // minutes, 0 = never, default 120
static NSString *const kUnpluggedKey  = @"insomnia.unpluggedAt";
static NSString *const kThermalKey    = @"insomnia.lid.thermalGuard";  // default YES
static NSString *const kOfflineKey    = @"insomnia.lid.offlineMinutes"; // minutes, 0 = ignore network, default 15
static NSString *const kOfflineAtKey  = @"insomnia.offlineAt";
static NSString *const kSudoers       = @"/etc/sudoers.d/insomnia";
static NSString *const kAutoUpdateKey = @"insomnia.autoUpdateCheck";   // default YES
static NSString *const kUpdateAtKey   = @"insomnia.updateCheckedAt";
static NSString *const kRepo          = @"FRIKKern/insomnia";

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

/// Moon with a cross above it: sleep is blocked. With `lid`, a dot marks a live lid override.
static NSImage *AwakeIcon(BOOL lid) {
    NSImage *moon  = Symbol(@"moon.fill", 13, NSFontWeightRegular);
    NSImage *cross = Symbol(@"xmark", 7, NSFontWeightHeavy);
    NSImage *img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        // Moon sits bottom-left, cross sits top-right above it, dot bottom-right.
        [moon  drawInRect:NSMakeRect(0, 0, 13, 13)];
        [cross drawInRect:NSMakeRect(10.5, 10.5, 7, 7)];
        if (lid) {
            [NSColor.blackColor set];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(13.5, 1, 4, 4)] fill];
        }
        return YES;
    }];
    img.template = YES;
    return img;
}

#pragma mark - Shell and power helpers

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

/// Power source snapshot. percent is -1 when no battery is present (desktop).
/// Test hook: `defaults write no.guerrilla.insomnia insomnia.debug.power battery:15` fakes a state.
static void PowerState(BOOL *onAC, int *percent) {
    NSString *fake = [NSUserDefaults.standardUserDefaults stringForKey:@"insomnia.debug.power"];
    if (fake.length) {
        NSArray *p = [fake componentsSeparatedByString:@":"];
        *onAC = ![p[0] isEqualToString:@"battery"];
        *percent = p.count > 1 ? [p[1] intValue] : 100;
        return;
    }
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    CFStringRef type = info ? IOPSGetProvidingPowerSourceType(info) : NULL;
    *onAC = !type || CFStringCompare(type, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo;
    *percent = -1;
    CFArrayRef list = info ? IOPSCopyPowerSourcesList(info) : NULL;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        NSDictionary *d = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i));
        if (![d[@(kIOPSTypeKey)] isEqual:@(kIOPSInternalBatteryType)]) continue;
        double cur = [d[@(kIOPSCurrentCapacityKey)] doubleValue], max = [d[@(kIOPSMaxCapacityKey)] doubleValue];
        if (max > 0) *percent = (int)(100.0 * cur / max + 0.5);
    }
    if (list) CFRelease(list);
    if (info) CFRelease(info);
}

static NSString *FormatDuration(NSTimeInterval s) {
    int m = (int)(s / 60);
    return m < 60 ? [NSString stringWithFormat:@"%d min", m]
                  : [NSString stringWithFormat:@"%d h %02d min", m / 60, m % 60];
}


/// Kernel clamshell flag. Test hook: `insomnia.debug.lid` = closed | open.
static BOOL LidClosed(void) {
    NSString *fake = [NSUserDefaults.standardUserDefaults stringForKey:@"insomnia.debug.lid"];
    if (fake.length) return [fake isEqualToString:@"closed"];
    io_service_t rd = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!rd) return NO;
    CFTypeRef v = IORegistryEntryCreateCFProperty(rd, CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
    IOObjectRelease(rd);
    BOOL closed = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return closed;
}

static NSString *const kThermalNames[] = { @"nominal", @"fair", @"serious", @"critical" };

/// System thermal pressure, the signal macOS itself throttles on.
/// Test hook: `insomnia.debug.thermal` = nominal | fair | serious | critical.
static NSProcessInfoThermalState Thermal(void) {
    NSString *fake = [NSUserDefaults.standardUserDefaults stringForKey:@"insomnia.debug.thermal"];
    for (int i = 0; fake.length && i < 4; i++) if ([fake isEqualToString:kThermalNames[i]]) return i;
    return NSProcessInfo.processInfo.thermalState;
}

/// True when a route to the internet exists (Wi-Fi, Ethernet, tethering).
/// Test hook: `insomnia.debug.net` = online | offline.
static BOOL Online(void) {
    NSString *fake = [NSUserDefaults.standardUserDefaults stringForKey:@"insomnia.debug.net"];
    if (fake.length) return [fake isEqualToString:@"online"];
    struct sockaddr_in zero = { .sin_len = sizeof(zero), .sin_family = AF_INET };
    SCNetworkReachabilityRef r = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zero);
    SCNetworkReachabilityFlags f = 0;
    BOOL ok = r && SCNetworkReachabilityGetFlags(r, &f);
    if (r) CFRelease(r);
    return ok && (f & kSCNetworkReachabilityFlagsReachable) && !(f & kSCNetworkReachabilityFlagsConnectionRequired);
}

#pragma mark - App

@interface Insomnia : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSImage *awakeIcon, *awakeLidIcon, *asleepIcon;
@property (strong) NSTimer *guardTimer;
@property BOOL lidLive;        // what pmset reported at the last sync
@property BOOL thermalHold;    // tripped hot with lid closed; held until lid opens or AC returns
@property SCNetworkReachabilityRef reach;
@property (strong) NSString *availableVersion;   // newer release seen by the last check, or nil
- (void)syncLid;
@end

static void PowerChanged(void *ctx) { [(__bridge Insomnia *)ctx syncLid]; }
static void NetChanged(SCNetworkReachabilityRef r, SCNetworkReachabilityFlags f, void *ctx) { [(__bridge Insomnia *)ctx syncLid]; }

@implementation Insomnia {
    IOPMAssertionID _assertions[2];
    int _assertionCount;
}

#pragma mark Preferences

- (NSUserDefaults *)d { return NSUserDefaults.standardUserDefaults; }

- (BOOL)isAwake { id v = [self.d objectForKey:kStateKey]; return v ? [v boolValue] : YES; }   // default: on
- (void)setAwake:(BOOL)awake { [self.d setBool:awake forKey:kStateKey]; }

- (BOOL)lidPref { return [self.d boolForKey:kLidKey]; }   // default: off
- (void)setLidPref:(BOOL)on { [self.d setBool:on forKey:kLidKey]; }

- (int)minBattery { id v = [self.d objectForKey:kThresholdKey]; return v ? [v intValue] : 20; }
- (int)graceMinutes { id v = [self.d objectForKey:kGraceKey]; return v ? [v intValue] : 120; }
- (BOOL)thermalGuard { id v = [self.d objectForKey:kThermalKey]; return v ? [v boolValue] : YES; }
- (void)toggleThermalGuard { [self.d setBool:!self.thermalGuard forKey:kThermalKey]; [self syncLid]; }
- (BOOL)autoUpdate { id v = [self.d objectForKey:kAutoUpdateKey]; return v ? [v boolValue] : YES; }
- (void)toggleAutoUpdate { [self.d setBool:!self.autoUpdate forKey:kAutoUpdateKey]; }
- (NSString *)version { return NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0"; }
- (int)offlineMinutes { id v = [self.d objectForKey:kOfflineKey]; return v ? [v intValue] : 15; }
- (void)setOffline:(NSMenuItem *)item { [self.d setInteger:item.tag forKey:kOfflineKey]; [self syncLid]; }
- (NSDate *)offlineAt { return [self.d objectForKey:kOfflineAtKey]; }
- (void)setOfflineAt:(NSDate *)date {
    if (date) [self.d setObject:date forKey:kOfflineAtKey]; else [self.d removeObjectForKey:kOfflineAtKey];
}

- (NSDate *)unpluggedAt { return [self.d objectForKey:kUnpluggedKey]; }
- (void)setUnpluggedAt:(NSDate *)date {
    if (date) [self.d setObject:date forKey:kUnpluggedKey]; else [self.d removeObjectForKey:kUnpluggedKey];
}

#pragma mark Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.awakeIcon    = AwakeIcon(NO);
    self.awakeLidIcon = AwakeIcon(YES);
    self.asleepIcon   = AsleepIcon();
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.target = self;
    button.action = @selector(handleClick:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];

    // Power source changes (plug/unplug, capacity) plus a minute tick for the grace clock.
    CFRunLoopSourceRef src = IOPSNotificationCreateRunLoopSource(PowerChanged, (__bridge void *)self);
    if (src) { CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopDefaultMode); CFRelease(src); }
    self.guardTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(syncLid) userInfo:nil repeats:YES];
    self.guardTimer.tolerance = 10;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncLid)
        name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    struct sockaddr_in zero = { .sin_len = sizeof(zero), .sin_family = AF_INET };
    self.reach = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zero);
    SCNetworkReachabilityContext ctx = { 0, (__bridge void *)self, NULL, NULL, NULL };
    if (self.reach && SCNetworkReachabilitySetCallback(self.reach, NetChanged, &ctx))
        SCNetworkReachabilityScheduleWithRunLoop(self.reach, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

    [self apply:self.isAwake];   // also self-heals a stale lid override left by an unclean exit
    [self performSelector:@selector(dailyUpdateCheck) withObject:nil afterDelay:20];
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [self releaseAssertions];
    // Never leave the lid override behind when we are not running to own it.
    if ([self lidSleepDisabled]) [self setLidSleepDisabled:NO];
}

/// Scriptable: open insomnia://on|off|toggle|lid-on|lid-off|login-on|login-off|quit
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) {
        NSString *cmd = u.host.lowercaseString ?: @"";
        if      ([cmd isEqualToString:@"on"])      [self apply:YES];
        else if ([cmd isEqualToString:@"off"])     [self apply:NO];
        else if ([cmd isEqualToString:@"toggle"])  [self apply:!self.isAwake];
        else if ([cmd isEqualToString:@"lid-on"])  [self enableLid:NO];
        else if ([cmd isEqualToString:@"lid-off"]) { self.lidPref = NO; [self syncLid]; }
        else if ([cmd isEqualToString:@"login-on"] || [cmd isEqualToString:@"login-off"]) {
            BOOL want = [cmd isEqualToString:@"login-on"];
            if ((SMAppService.mainAppService.status == SMAppServiceStatusEnabled) != want) [self toggleLaunchAtLogin];
        }
        else if ([cmd isEqualToString:@"quit"])    [NSApp terminate:nil];
        else if ([cmd isEqualToString:@"update"])  [self checkForUpdates:YES];
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

- (void)setMinBattery:(NSMenuItem *)item { [self.d setInteger:item.tag forKey:kThresholdKey]; [self syncLid]; }
- (void)setGrace:(NSMenuItem *)item      { [self.d setInteger:item.tag forKey:kGraceKey];     [self syncLid]; }

- (void)toggleLaunchAtLogin {
    SMAppService *svc = SMAppService.mainAppService;
    NSError *err = nil;
    if (svc.status == SMAppServiceStatusEnabled) [svc unregisterAndReturnError:&err];
    else                                          [svc registerAndReturnError:&err];
    if (err) NSBeep();
}

- (void)quit { [NSApp terminate:nil]; }

static NSMenuItem *Item(NSMenu *menu, NSString *title, SEL action, id target, BOOL on) {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    i.target = target;
    i.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:i];
    return i;
}

- (void)showMenu {
    BOOL awake = self.isAwake, lid = self.lidPref;
    BOOL onAC; int pct; PowerState(&onAC, &pct);
    NSMenu *menu = [NSMenu new];

    NSString *title;
    if (!awake)                 title = @"Insomnia is off — Mac may sleep";
    else if (!lid)              title = @"Insomnia is on — Mac stays awake";
    else if (self.lidLive)      title = @"Insomnia is on — awake even with lid closed";
    else                        title = [NSString stringWithFormat:@"Insomnia is on — lid override paused (%@)", [self pauseReason]];
    Item(menu, title, NULL, nil, NO).enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];

    Item(menu, @"Prevent Sleep", @selector(toggle), self, awake);
    Item(menu, @"Keep Awake With Lid Closed", @selector(toggleLid), self, lid);

    // On-battery guard submenu
    NSMenu *sub = [NSMenu new];
    NSString *status = onAC ? @"On charger"
                            : [NSString stringWithFormat:@"Unplugged %@ · battery %d%%",
                               FormatDuration(-[self.unpluggedAt timeIntervalSinceNow]), pct];
    status = [status stringByAppendingFormat:@" · lid %@ · thermal %@ · %@",
              LidClosed() ? @"closed" : @"open", kThermalNames[Thermal()],
              Online() ? @"online" : [NSString stringWithFormat:@"offline %@", FormatDuration(-[self.offlineAt timeIntervalSinceNow])]];
    Item(sub, status, NULL, nil, NO).enabled = NO;
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"Pause lid override when battery is below…", NULL, nil, NO).enabled = NO;
    for (NSNumber *n in @[@10, @20, @30, @40, @50])
        Item(sub, [NSString stringWithFormat:@"%@%%", n], @selector(setMinBattery:), self, self.minBattery == n.intValue).tag = n.intValue;
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"…or when unplugged longer than", NULL, nil, NO).enabled = NO;
    NSArray *graces = @[@[@30, @"30 min"], @[@60, @"1 hour"], @[@120, @"2 hours"], @[@240, @"4 hours"], @[@0, @"Never"]];
    for (NSArray *g in graces)
        Item(sub, g[1], @selector(setGrace:), self, self.graceMinutes == [g[0] intValue]).tag = [g[0] intValue];
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"…or when offline longer than (agents need network)", NULL, nil, NO).enabled = NO;
    NSArray *offs = @[@[@5, @"5 min"], @[@15, @"15 min"], @[@30, @"30 min"], @[@60, @"1 hour"], @[@0, @"Never — keep rendering while moving"]];
    for (NSArray *o in offs)
        Item(sub, o[1], @selector(setOffline:), self, self.offlineMinutes == [o[0] intValue]).tag = [o[0] intValue];
    [sub addItem:NSMenuItem.separatorItem];
    Item(sub, @"…or when hot with the lid closed", @selector(toggleThermalGuard), self, self.thermalGuard);
    NSMenuItem *subItem = [[NSMenuItem alloc] initWithTitle:@"Lid Override on Battery" action:nil keyEquivalent:@""];
    subItem.submenu = sub;
    [menu addItem:subItem];

    [menu addItem:NSMenuItem.separatorItem];
    Item(menu, @"Launch at Login", @selector(toggleLaunchAtLogin), self,
         SMAppService.mainAppService.status == SMAppServiceStatusEnabled);
    [menu addItem:NSMenuItem.separatorItem];
    NSMenu *upd = [NSMenu new];
    Item(upd, [NSString stringWithFormat:@"Insomnia %@", self.version], NULL, nil, NO).enabled = NO;
    Item(upd, self.availableVersion ? [NSString stringWithFormat:@"Update to %@…", self.availableVersion] : @"Check for Updates…",
         @selector(checkNow), self, NO);
    Item(upd, @"Check Daily", @selector(toggleAutoUpdate), self, self.autoUpdate);
    NSMenuItem *updItem = [[NSMenuItem alloc] initWithTitle:self.availableVersion ? [NSString stringWithFormat:@"Update Available: %@", self.availableVersion] : @"Updates"
                                                     action:nil keyEquivalent:@""];
    updItem.submenu = upd;
    [menu addItem:updItem];
    Item(menu, @"Quit Insomnia", @selector(quit), self, NO).keyEquivalent = @"q";

    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = nil;   // restore click-to-toggle
}

#pragma mark Power assertions

- (void)apply:(BOOL)awake {
    self.awake = awake;
    if (awake) [self acquireAssertions]; else [self releaseAssertions];
    [self syncLid];
}

- (void)refreshIcon {
    BOOL awake = self.isAwake;
    self.statusItem.button.image = !awake ? self.asleepIcon : self.lidLive ? self.awakeLidIcon : self.awakeIcon;
    self.statusItem.button.toolTip = !awake       ? @"Insomnia: Mac may sleep (click to keep awake)"
                                   : self.lidLive ? @"Insomnia: awake even with lid closed (click to allow sleep)"
                                                  : @"Insomnia: Mac stays awake (click to allow sleep)";
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

#pragma mark Updates

- (void)checkNow { [self checkForUpdates:YES]; }

/// Once a day, quietly. Only marks the menu; never interrupts.
- (void)dailyUpdateCheck {
    if (!self.autoUpdate) return;
    NSDate *last = [self.d objectForKey:kUpdateAtKey];
    if (!last || -[last timeIntervalSinceNow] > 24 * 3600) [self checkForUpdates:NO];
}

- (void)checkForUpdates:(BOOL)interactive {
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", kRepo]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    req.timeoutInterval = 15;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
        NSString *tag = nil;
        if (data) {
            id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([j isKindOfClass:NSDictionary.class] && [j[@"tag_name"] isKindOfClass:NSString.class]) tag = j[@"tag_name"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleUpdateTag:tag interactive:interactive error:err]; });
    }] resume];
}

- (void)handleUpdateTag:(NSString *)tag interactive:(BOOL)interactive error:(NSError *)err {
    [self.d setObject:NSDate.date forKey:kUpdateAtKey];
    NSString *latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
    BOOL newer = latest && [latest compare:self.version options:NSNumericSearch] == NSOrderedDescending;
    self.availableVersion = newer ? latest : nil;
    // Also readable by scripts: defaults read no.guerrilla.insomnia insomnia.availableVersion
    if (newer) [self.d setObject:latest forKey:@"insomnia.availableVersion"];
    else [self.d removeObjectForKey:@"insomnia.availableVersion"];
    if (!interactive) return;

    NSAlert *a = [NSAlert new];
    if (!latest) {
        a.messageText = @"Couldn't check for updates";
        a.informativeText = err.localizedDescription ?: @"No answer from GitHub.";
        [a addButtonWithTitle:@"OK"];
    } else if (!newer) {
        a.messageText = [NSString stringWithFormat:@"Insomnia %@ is up to date", self.version];
        [a addButtonWithTitle:@"OK"];
    } else {
        a.messageText = [NSString stringWithFormat:@"Insomnia %@ is available", latest];
        a.informativeText = [NSString stringWithFormat:@"You have %@. Update builds the new version from source on this Mac "
                             "and relaunches Insomnia. It takes a few seconds and needs no password.", self.version];
        [a addButtonWithTitle:@"Update"];
        [a addButtonWithTitle:@"Release Notes"];
        [a addButtonWithTitle:@"Later"];
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse resp = [a runModal];
    if (!newer) return;
    if (resp == NSAlertFirstButtonReturn) [self runUpdate:tag];
    else if (resp == NSAlertSecondButtonReturn)
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@/releases/latest", kRepo]]];
}

/// Runs the public installer, detached: it quits this app and relaunches the new build.
- (void)runUpdate:(NSString *)tag {
    NSString *cmd = [NSString stringWithFormat:
        @"nohup /bin/sh -c 'sleep 1; curl -fsSL https://raw.githubusercontent.com/%@/main/install.sh | INSOMNIA_REF=%@ sh' >/dev/null 2>&1 &",
        kRepo, tag];
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    t.arguments = @[@"-c", cmd];
    t.currentDirectoryURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    [t launchAndReturnError:nil];
}

#pragma mark Lid (pmset disablesleep, root-only)

/// Why the battery guard is holding the lid override off right now, or nil if it is not.
- (NSString *)pauseReason {
    BOOL onAC; int pct; PowerState(&onAC, &pct);
    if (onAC) return nil;
    if (pct >= 0 && pct <= self.minBattery) return [NSString stringWithFormat:@"battery %d%%", pct];
    NSTimeInterval unplugged = -[self.unpluggedAt timeIntervalSinceNow];
    if (self.graceMinutes > 0 && unplugged > self.graceMinutes * 60)
        return [NSString stringWithFormat:@"unplugged %@", FormatDuration(unplugged)];
    if (self.thermalHold)
        return [NSString stringWithFormat:@"%@ with lid closed", kThermalNames[Thermal()]];
    NSTimeInterval offline = self.offlineAt ? -[self.offlineAt timeIntervalSinceNow] : 0;
    if (self.offlineMinutes > 0 && self.offlineAt && offline > self.offlineMinutes * 60)
        return [NSString stringWithFormat:@"offline %@", FormatDuration(offline)];
    return nil;
}

/// The lid override is live only while Insomnia is on, the lid preference is on,
/// and the battery guard is not holding it off. Also repairs a stale OS setting.
- (void)syncLid {
    BOOL onAC; int pct; PowerState(&onAC, &pct);
    if (onAC) self.unpluggedAt = nil;
    else if (!self.unpluggedAt) self.unpluggedAt = NSDate.date;
    if (Online()) self.offlineAt = nil;
    else if (!self.offlineAt) self.offlineAt = NSDate.date;

    // Bag guard: hot while shut on battery trips a hold that only lid-open or AC clears,
    // so a cooling-then-reheating laptop cannot oscillate.
    BOOL closed = LidClosed();
    if (onAC || !closed || !self.thermalGuard) self.thermalHold = NO;
    else if (Thermal() >= NSProcessInfoThermalStateSerious) self.thermalHold = YES;

    BOOL want = self.isAwake && self.lidPref && ![self pauseReason];
    BOOL have = [self lidSleepDisabled];
    if (want != have && [self setLidSleepDisabled:want]) have = want;
    self.lidLive = have;
    [self refreshIcon];
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
                             "On battery, Insomnia pauses this when the battery gets low, the charger has been "
                             "out for a while, or the Mac runs hot with the lid shut (adjustable). It also turns it off when you switch Insomnia off or quit. "
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
