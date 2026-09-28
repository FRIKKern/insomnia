// Renders AppIcon.icns: dark rounded square, moon with a cross above it.
#import <Cocoa/Cocoa.h>
int main(void) { @autoreleasepool {
    NSString *dir = @"build/AppIcon.iconset";
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    int sizes[] = {16,32,64,128,256,512,1024};
    for (int i = 0; i < 7; i++) {
        CGFloat s = sizes[i];
        NSImage *img = [NSImage imageWithSize:NSMakeSize(s, s) flipped:NO drawingHandler:^BOOL(NSRect r) {
            CGFloat inset = s * 0.05, rad = s * 0.22;
            NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, inset, inset) xRadius:rad yRadius:rad];
            NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:0.16 green:0.18 blue:0.32 alpha:1]
                                                          endingColor:[NSColor colorWithRed:0.05 green:0.06 blue:0.12 alpha:1]];
            [g drawInBezierPath:bg angle:-90];
            NSImageSymbolConfiguration *mc = [NSImageSymbolConfiguration configurationWithPointSize:s*0.5 weight:NSFontWeightRegular];
            NSImageSymbolConfiguration *xc = [NSImageSymbolConfiguration configurationWithPointSize:s*0.22 weight:NSFontWeightHeavy];
            NSImage *moon = [[[NSImage imageWithSystemSymbolName:@"moon.fill" accessibilityDescription:nil] imageWithSymbolConfiguration:mc]
                             imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor colorWithRed:1 green:0.85 blue:0.45 alpha:1]]];
            NSImage *x = [[[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:nil] imageWithSymbolConfiguration:xc]
                          imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor colorWithRed:1 green:0.35 blue:0.35 alpha:1]]];
            [moon drawInRect:NSMakeRect(s*0.18, s*0.16, s*0.52, s*0.52)];
            [x    drawInRect:NSMakeRect(s*0.60, s*0.62, s*0.22, s*0.22)];
            return YES;
        }];
        // Rasterize at exact pixel size (bypass HiDPI backing scale).
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:s pixelsHigh:s bitsPerSample:8
            samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [img drawInRect:NSMakeRect(0,0,s,s) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        int base = sizes[i] == 16 ? 16 : sizes[i] / 2;
        NSString *name = sizes[i] == 16 ? @"icon_16x16.png" : [NSString stringWithFormat:@"icon_%dx%d@2x.png", base, base];
        [png writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
        if (sizes[i] >= 32 && sizes[i] <= 512)
            [png writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%dx%d.png", sizes[i], sizes[i]]] atomically:YES];
    }
    return 0;
}}
