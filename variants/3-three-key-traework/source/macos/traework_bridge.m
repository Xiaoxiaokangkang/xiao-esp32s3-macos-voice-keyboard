#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <signal.h>

static const CGKeyCode kF16KeyCode = 106;
static NSString *const kTraeWorkBundleID = @"cn.trae.solo.app";
static CFMachPortRef gEventTap;
static BOOL gWaitingLogged;
static BOOL gActionInFlight;
static BOOL gNewTaskRequested;

static void Diagnostic(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      @"xiao-traework-bridge.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSData data] writeToFile:path atomically:YES];
    }
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    [file seekToEndOfFile];
    [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static CFTypeRef CopyAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    return AXUIElementCopyAttributeValue(element, attribute, &value) == kAXErrorSuccess
        ? value : NULL;
}

static NSString *CopyStringAttribute(AXUIElementRef element,
                                     CFStringRef attribute) {
    CFTypeRef value = CopyAttribute(element, attribute);
    if (!value) return nil;
    NSString *result = CFGetTypeID(value) == CFStringGetTypeID()
        ? [(__bridge NSString *)value copy] : nil;
    CFRelease(value);
    return result;
}

static AXUIElementRef CopyFirstTextArea(AXUIElementRef root) {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:(__bridge id)root];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 5000) {
        AXUIElementRef element = (__bridge AXUIElementRef)queue.firstObject;
        // Keep the AX object alive before removing the array's strong reference.
        // Without this retain, ARC may release the object immediately and the
        // following AX call can dereference a stale pointer.
        CFRetain(element);
        [queue removeObjectAtIndex:0];
        if ([CopyStringAttribute(element, kAXRoleAttribute)
             isEqualToString:(__bridge NSString *)kAXTextAreaRole]) {
            return element;
        }
        CFTypeRef children = CopyAttribute(element, kAXChildrenAttribute);
        if (children && CFGetTypeID(children) == CFArrayGetTypeID()) {
            [queue addObjectsFromArray:(__bridge NSArray *)children];
        }
        if (children) CFRelease(children);
        CFRelease(element);
    }
    return NULL;
}

static BOOL StringIdentifiesNewTask(NSString *value) {
    if (!value.length) return NO;
    NSString *normalized = value.lowercaseString;
    NSArray<NSString *> *labels = @[
        @"new task", @"新任务", @"新建任务", @"新聊天", @"新对话"
    ];
    for (NSString *label in labels) {
        if ([normalized containsString:label]) return YES;
    }
    return NO;
}

static AXUIElementRef CopyNewTaskButton(AXUIElementRef root) {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:(__bridge id)root];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 5000) {
        AXUIElementRef element = (__bridge AXUIElementRef)queue.firstObject;
        CFRetain(element);
        [queue removeObjectAtIndex:0];

        NSString *role = CopyStringAttribute(element, kAXRoleAttribute);
        BOOL isButton = [role isEqualToString:(__bridge NSString *)kAXButtonRole];
        BOOL matches = NO;
        if (isButton) {
            matches = StringIdentifiesNewTask(
                          CopyStringAttribute(element, kAXTitleAttribute)) ||
                      StringIdentifiesNewTask(
                          CopyStringAttribute(element, kAXDescriptionAttribute)) ||
                      StringIdentifiesNewTask(
                          CopyStringAttribute(element, kAXValueAttribute)) ||
                      StringIdentifiesNewTask(
                          CopyStringAttribute(element, kAXHelpAttribute));
        }
        if (matches) return element;

        CFTypeRef children = CopyAttribute(element, kAXChildrenAttribute);
        if (children && CFGetTypeID(children) == CFArrayGetTypeID()) {
            [queue addObjectsFromArray:(__bridge NSArray *)children];
        }
        if (children) CFRelease(children);
        CFRelease(element);
    }
    return NULL;
}

static BOOL CopyPointInside(AXUIElementRef element, CGPoint *point) {
    CFTypeRef positionValue = CopyAttribute(element, kAXPositionAttribute);
    CFTypeRef sizeValue = CopyAttribute(element, kAXSizeAttribute);
    BOOL typesValid = positionValue && sizeValue &&
        CFGetTypeID(positionValue) == AXValueGetTypeID() &&
        CFGetTypeID(sizeValue) == AXValueGetTypeID();
    CGPoint position = CGPointZero;
    CGSize size = CGSizeZero;
    BOOL valid = typesValid &&
        AXValueGetValue(positionValue, kAXValueCGPointType, &position) &&
        AXValueGetValue(sizeValue, kAXValueCGSizeType, &size) &&
        size.width > 4 && size.height > 4;
    if (positionValue) CFRelease(positionValue);
    if (sizeValue) CFRelease(sizeValue);
    if (!valid) return NO;
    *point = CGPointMake(position.x + MIN(24, size.width / 2),
                         position.y + MIN(24, size.height / 2));
    return YES;
}

static BOOL ClickAndFocus(AXUIElementRef element) {
    AXError status = AXUIElementSetAttributeValue(
        element, kAXFocusedAttribute, kCFBooleanTrue);
    CGPoint point;
    BOOL hasPoint = CopyPointInside(element, &point);
    if (hasPoint) {
        CGWarpMouseCursorPosition(point);
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        CGEventRef down = source ? CGEventCreateMouseEvent(
            source, kCGEventLeftMouseDown, point, kCGMouseButtonLeft) : NULL;
        CGEventRef up = source ? CGEventCreateMouseEvent(
            source, kCGEventLeftMouseUp, point, kCGMouseButtonLeft) : NULL;
        if (down) CGEventPost(kCGHIDEventTap, down);
        if (up) CGEventPost(kCGHIDEventTap, up);
        if (down) CFRelease(down);
        if (up) CFRelease(up);
        if (source) CFRelease(source);
    }
    return status == kAXErrorSuccess || hasPoint;
}

static void Finish(NSString *message) {
    Diagnostic(message);
    gActionInFlight = NO;
    gNewTaskRequested = NO;
}

static void FocusInput(NSUInteger attempt);
static void OpenNewTask(NSUInteger attempt);

static void Retry(NSUInteger attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ FocusInput(attempt + 1); });
}

static void RetryNewTask(NSUInteger attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ OpenNewTask(attempt + 1); });
}

static void RaiseFirstWindow(AXUIElementRef applicationElement) {
    CFTypeRef windowsValue = CopyAttribute(applicationElement, kAXWindowsAttribute);
    if (windowsValue && CFGetTypeID(windowsValue) == CFArrayGetTypeID()) {
        NSArray *windows = (__bridge NSArray *)windowsValue;
        if (windows.count) {
            AXUIElementRef window = (__bridge AXUIElementRef)windows.firstObject;
            AXUIElementPerformAction(window, kAXRaiseAction);
            AXUIElementSetAttributeValue(window, kAXMainAttribute, kCFBooleanTrue);
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute, kCFBooleanTrue);
        }
    }
    if (windowsValue) CFRelease(windowsValue);
}

static void FocusInput(NSUInteger attempt) {
    NSRunningApplication *app =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:
         kTraeWorkBundleID].firstObject;
    if (!app) {
        if (attempt < 50) Retry(attempt);
        else Finish(@"TraeWork launch timeout");
        return;
    }

    [app unhide];
    [app activateWithOptions:NSApplicationActivateAllWindows];
    AXUIElementRef applicationElement = AXUIElementCreateApplication(app.processIdentifier);
    RaiseFirstWindow(applicationElement);
    BOOL frontmost = [[[NSWorkspace sharedWorkspace].frontmostApplication bundleIdentifier]
                      isEqualToString:kTraeWorkBundleID];
    if (!frontmost) {
        CFRelease(applicationElement);
        if (attempt < 50) Retry(attempt);
        else Finish(@"TraeWork foreground activation timeout");
        return;
    }

    AXUIElementRef input = CopyFirstTextArea(applicationElement);
    if (input && ClickAndFocus(input)) {
        CFRetain(applicationElement);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            NSString *role = @"unknown";
            CFTypeRef focused = CopyAttribute(applicationElement,
                                              kAXFocusedUIElementAttribute);
            if (focused && CFGetTypeID(focused) == AXUIElementGetTypeID()) {
                role = CopyStringAttribute((AXUIElementRef)focused,
                                           kAXRoleAttribute) ?: @"unknown";
            }
            if (focused) CFRelease(focused);
            BOOL stillFrontmost = [[[NSWorkspace sharedWorkspace]
                .frontmostApplication bundleIdentifier]
                isEqualToString:kTraeWorkBundleID];
            if (stillFrontmost &&
                [role isEqualToString:(__bridge NSString *)kAXTextAreaRole]) {
                Finish([NSString stringWithFormat:
                        @"input verified role=%@ attempt=%lu", role,
                        (unsigned long)attempt]);
            } else if (attempt < 50) {
                Diagnostic([NSString stringWithFormat:
                            @"verification retry frontmost=%d role=%@ attempt=%lu",
                            stillFrontmost, role, (unsigned long)attempt]);
                Retry(attempt);
            } else {
                Finish(@"TraeWork input verification timeout");
            }
            CFRelease(applicationElement);
        });
        CFRelease(input);
        CFRelease(applicationElement);
        return;
    }
    if (input) CFRelease(input);
    CFRelease(applicationElement);
    NSUInteger retryLimit = gNewTaskRequested ? 50 : 15;
    if (attempt < retryLimit) {
        Retry(attempt);
    } else if (!gNewTaskRequested) {
        Diagnostic(@"current input unavailable; falling back to New task");
        OpenNewTask(0);
    } else {
        Finish(@"TraeWork input focus timeout after New task");
    }
}

static void OpenNewTask(NSUInteger attempt) {
    NSRunningApplication *app =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:
         kTraeWorkBundleID].firstObject;
    if (!app) {
        if (attempt < 80) RetryNewTask(attempt);
        else Finish(@"cold launch timeout waiting for TraeWork process");
        return;
    }

    [app unhide];
    [app activateWithOptions:NSApplicationActivateAllWindows];
    AXUIElementRef applicationElement =
        AXUIElementCreateApplication(app.processIdentifier);
    RaiseFirstWindow(applicationElement);

    BOOL frontmost = [[[NSWorkspace sharedWorkspace].frontmostApplication
                       bundleIdentifier] isEqualToString:kTraeWorkBundleID];
    if (!frontmost) {
        CFRelease(applicationElement);
        if (attempt < 80) RetryNewTask(attempt);
        else Finish(@"cold launch timeout waiting for foreground window");
        return;
    }

    AXUIElementRef newTask = CopyNewTaskButton(applicationElement);
    if (!newTask) {
        CFRelease(applicationElement);
        if (attempt < 80) RetryNewTask(attempt);
        else Finish(@"cold launch timeout waiting for New task button");
        return;
    }

    AXError pressStatus = AXUIElementPerformAction(newTask, kAXPressAction);
    BOOL activated = pressStatus == kAXErrorSuccess;
    if (!activated) activated = ClickAndFocus(newTask);
    CFRelease(newTask);
    CFRelease(applicationElement);

    if (!activated) {
        if (attempt < 80) RetryNewTask(attempt);
        else Finish(@"unable to activate New task button");
        return;
    }

    Diagnostic([NSString stringWithFormat:
                @"cold launch New task activated attempt=%lu",
                (unsigned long)attempt]);
    gNewTaskRequested = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ FocusInput(0); });
}

static void OpenTraeWork(void) {
    if (gActionInFlight) {
        Diagnostic(@"action ignored while previous action is running");
        return;
    }
    gActionInFlight = YES;
    gNewTaskRequested = NO;
    Diagnostic(@"F16 action started");
    BOOL wasRunning = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:kTraeWorkBundleID].count > 0;
    if (wasRunning) {
        Diagnostic(@"TraeWork already running; focusing current input");
        FocusInput(0);
        return;
    }
    Diagnostic(@"TraeWork not running; starting cold-launch New task flow");
    NSURL *url = [[NSWorkspace sharedWorkspace]
                  URLForApplicationWithBundleIdentifier:kTraeWorkBundleID];
    if (!url) {
        Finish(@"TraeWork application not installed");
        return;
    }
    NSWorkspaceOpenConfiguration *configuration =
        [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:url
        configuration:configuration completionHandler:
        ^(__unused NSRunningApplication *openedApp, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) Finish([NSString stringWithFormat:
                               @"TraeWork launch failed: %@", error]);
            else OpenNewTask(0);
        });
    }];
}

static CGEventRef EventCallback(__unused CGEventTapProxy proxy,
                                CGEventType type, CGEventRef event,
                                __unused void *context) {
    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        Diagnostic(@"event tap disabled; re-enabling");
        if (gEventTap) CGEventTapEnable(gEventTap, true);
        return event;
    }
    if ((type != kCGEventKeyDown && type != kCGEventKeyUp) ||
        CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) != kF16KeyCode) {
        return event;
    }
    if (CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat)) return NULL;
    if (type == kCGEventKeyDown) {
        Diagnostic(@"F16 down");
        dispatch_async(dispatch_get_main_queue(), ^{ OpenTraeWork(); });
    }
    return NULL;
}

static BOOL StartIfAuthorized(void) {
    if (gEventTap) return YES;
    if (!AXIsProcessTrusted()) {
        if (!gWaitingLogged) Diagnostic(@"waiting for Accessibility permission");
        gWaitingLogged = YES;
        return NO;
    }
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) |
                       CGEventMaskBit(kCGEventKeyUp);
    gEventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault, mask,
                                 EventCallback, NULL);
    if (!gEventTap) {
        gEventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault, mask,
                                     EventCallback, NULL);
    }
    if (!gEventTap) return NO;
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault, gEventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(gEventTap, true);
    CFRelease(source);
    gWaitingLogged = NO;
    Diagnostic(@"Accessibility ready; K1/F16 bridge active");
    return YES;
}

static void PermissionTimer(__unused CFRunLoopTimerRef timer,
                            __unused void *context) {
    StartIfAuthorized();
}

static void Stop(__unused int signalNumber) { exit(0); }

int main(void) {
    @autoreleasepool {
        Diagnostic(@"TraeWork Bridge 1.1 started");
        NSDictionary *options = @{
            (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES
        };
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        StartIfAuthorized();
        CFRunLoopTimerContext context = {0, NULL, NULL, NULL, NULL};
        CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0,
            PermissionTimer, &context);
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
        CFRelease(timer);
        signal(SIGINT, Stop);
        signal(SIGTERM, Stop);
        CFRunLoopRun();
    }
    return 0;
}
