#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreAudio/CoreAudio.h>
#import <signal.h>

static const CGKeyCode kF13KeyCode = 105;
static const CGKeyCode kFnKeyCode = 63;
static CFMachPortRef gEventTap;
static BOOL gXiaoWasConnected;
static BOOL gLoggedWaitingForAccessibility;
static AudioDeviceID gXiaoDevice = kAudioObjectUnknown;
static CFStringRef gPreviousInputUID;

static void Diagnostic(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"xiao-fn-bridge.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSData data] writeToFile:path atomically:YES];
    }
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    [file seekToEndOfFile];
    [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static CFStringRef CopyStringProperty(AudioObjectID object, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = {
        selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value) != noErr) {
        return NULL;
    }
    return value;
}

static NSArray<NSNumber *> *AllAudioDevices(void) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr || !size) {
        return @[];
    }
    NSUInteger count = size / sizeof(AudioDeviceID);
    AudioDeviceID *ids = calloc(count, sizeof(AudioDeviceID));
    if (!ids) return @[];
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, ids);
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:count];
    if (status == noErr) {
        for (NSUInteger i = 0; i < count; i++) [result addObject:@(ids[i])];
    }
    free(ids);
    return result;
}

static AudioDeviceID DefaultInput(void) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device) != noErr) {
        return kAudioObjectUnknown;
    }
    return device;
}

static AudioDeviceID FindDeviceByUID(CFStringRef wantedUID) {
    if (!wantedUID) return kAudioObjectUnknown;
    for (NSNumber *number in AllAudioDevices()) {
        AudioDeviceID device = number.unsignedIntValue;
        CFStringRef uid = CopyStringProperty(device, kAudioDevicePropertyDeviceUID);
        BOOL matches = uid && CFEqual(uid, wantedUID);
        if (uid) CFRelease(uid);
        if (matches) return device;
    }
    return kAudioObjectUnknown;
}

static AudioDeviceID FindXiaoMicrophone(void) {
    CFStringRef wantedName = CFSTR("XIAO Voice Keyboard Microphone");
    CFStringRef wantedMaker = CFSTR("Seeed Studio");
    for (NSNumber *number in AllAudioDevices()) {
        AudioDeviceID device = number.unsignedIntValue;
        CFStringRef name = CopyStringProperty(device, kAudioObjectPropertyName);
        CFStringRef maker = CopyStringProperty(device, kAudioObjectPropertyManufacturer);
        BOOL matches = name && maker && CFEqual(name, wantedName) && CFEqual(maker, wantedMaker);
        if (name) CFRelease(name);
        if (maker) CFRelease(maker);
        if (matches) return device;
    }
    return kAudioObjectUnknown;
}

static BOOL DeviceHasInput(AudioDeviceID device) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeInput,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) != noErr || !size) return NO;
    AudioBufferList *buffers = calloc(1, size);
    if (!buffers) return NO;
    BOOL hasInput = NO;
    if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, buffers) == noErr) {
        for (UInt32 i = 0; i < buffers->mNumberBuffers; i++) {
            if (buffers->mBuffers[i].mNumberChannels > 0) {
                hasInput = YES;
                break;
            }
        }
    }
    free(buffers);
    return hasInput;
}

static BOOL SelectDefaultInput(AudioDeviceID device, NSString *reason) {
    if (device == kAudioObjectUnknown) return NO;
    if (DefaultInput() == device) return YES;
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = sizeof(device);
    OSStatus status = AudioObjectSetPropertyData(
        kAudioObjectSystemObject, &address, 0, NULL, size, &device
    );
    Diagnostic([NSString stringWithFormat:@"select input id=%u reason=%@ status=%d",
                device, reason, (int)status]);
    return status == noErr;
}

static void RefreshAudioInput(NSString *reason) {
    AudioDeviceID xiao = FindXiaoMicrophone();
    if (xiao != kAudioObjectUnknown) {
        if (!gXiaoWasConnected) {
            AudioDeviceID current = DefaultInput();
            if (current != kAudioObjectUnknown && current != xiao) {
                if (gPreviousInputUID) CFRelease(gPreviousInputUID);
                gPreviousInputUID = CopyStringProperty(current, kAudioDevicePropertyDeviceUID);
                Diagnostic(@"saved previous default input");
            }
            gXiaoWasConnected = YES;
            Diagnostic([NSString stringWithFormat:@"XIAO microphone connected id=%u", xiao]);
        }
        gXiaoDevice = xiao;
        SelectDefaultInput(xiao, reason);
        return;
    }

    gXiaoDevice = kAudioObjectUnknown;
    if (gXiaoWasConnected) {
        gXiaoWasConnected = NO;
        AudioDeviceID previous = FindDeviceByUID(gPreviousInputUID);
        if (previous != kAudioObjectUnknown) SelectDefaultInput(previous, @"restore after unplug");
        if (gPreviousInputUID) {
            CFRelease(gPreviousInputUID);
            gPreviousInputUID = NULL;
        }
        Diagnostic(@"XIAO microphone disconnected");
    }
}

static OSStatus AudioDevicesChanged(__unused AudioObjectID object,
                                    __unused UInt32 count,
                                    __unused const AudioObjectPropertyAddress addresses[],
                                    __unused void *context) {
    dispatch_async(dispatch_get_main_queue(), ^{ RefreshAudioInput(@"device list changed"); });
    return noErr;
}

static CGEventRef EventCallback(__unused CGEventTapProxy proxy, CGEventType type,
                                CGEventRef event, __unused void *userInfo) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        Diagnostic([NSString stringWithFormat:@"event tap disabled type=%u; re-enabling", (unsigned)type]);
        if (gEventTap) CGEventTapEnable(gEventTap, true);
        return event;
    }
    if ((type != kCGEventKeyDown && type != kCGEventKeyUp) ||
        CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) != kF13KeyCode) {
        return event;
    }
    if (CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat)) {
        return NULL;
    }

    BOOL down = type == kCGEventKeyDown;
    if (down) RefreshAudioInput(@"key press check");

    // Do not allocate or post a replacement event. Mutate the USB keyboard's
    // original F13 event in place so its source metadata survives downstream.
    int64_t sourceState = CGEventGetIntegerValueField(event, kCGEventSourceStateID);
    int64_t sourcePID = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
    CGEventFlags flags = CGEventGetFlags(event);
    CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, kFnKeyCode);
    CGEventSetType(event, kCGEventFlagsChanged);
    if (down) flags |= kCGEventFlagMaskSecondaryFn;
    else flags &= ~kCGEventFlagMaskSecondaryFn;
    CGEventSetFlags(event, flags);

    Diagnostic([NSString stringWithFormat:
                @"F13 %@ -> Fn flagsChanged IN_PLACE sourceState=%lld sourcePID=%lld flags=%llu",
                down ? @"down" : @"up", sourceState, sourcePID,
                (unsigned long long)flags]);
    return event;
}

static BOOL StartKeyboardBridgeIfAuthorized(void) {
    if (gEventTap) return YES;
    if (!AXIsProcessTrusted()) {
        if (!gLoggedWaitingForAccessibility) {
            Diagnostic(@"waiting for Accessibility permission");
            gLoggedWaitingForAccessibility = YES;
        }
        return NO;
    }

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
    // The HID tap is the earliest public Quartz event-tap location and keeps us
    // as close as possible to the original USB event. Fall back only if macOS
    // refuses that tap on this machine.
    gEventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault, mask, EventCallback, NULL);
    if (gEventTap) {
        Diagnostic(@"keyboard bridge active at HID event tap");
    } else {
        Diagnostic(@"HID event tap unavailable; trying session event tap");
        gEventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault, mask, EventCallback, NULL);
    }
    if (!gEventTap) {
        Diagnostic(@"Accessibility granted but event tap creation failed; will retry");
        return NO;
    }

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gEventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(gEventTap, true);
    CFRelease(source);
    gLoggedWaitingForAccessibility = NO;
    Diagnostic(@"Accessibility ready; keyboard bridge active");
    return YES;
}

static void PermissionTimerFired(__unused CFRunLoopTimerRef timer, __unused void *info) {
    StartKeyboardBridgeIfAuthorized();
}

static void StopBridge(__unused int signalNumber) {
    exit(0);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test-inplace") == 0) {
            CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
            CGEventRef original = source ? CGEventCreateKeyboardEvent(source, kF13KeyCode, false) : NULL;
            if (!original) {
                if (source) CFRelease(source);
                printf("IN_PLACE_FAIL: unable to create test event\n");
                return 20;
            }
            CGEventRef result = EventCallback(NULL, kCGEventKeyUp, original, NULL);
            BOOL valid = result == original &&
                         CGEventGetType(result) == kCGEventFlagsChanged &&
                         CGEventGetIntegerValueField(result, kCGKeyboardEventKeycode) == kFnKeyCode &&
                         !(CGEventGetFlags(result) & kCGEventFlagMaskSecondaryFn);
            printf(valid ? "IN_PLACE_OK: original CGEvent mutated and returned\n"
                         : "IN_PLACE_FAIL: event was replaced or fields are wrong\n");
            CFRelease(original);
            CFRelease(source);
            return valid ? 0 : 21;
        }

        if (argc > 1 && strcmp(argv[1], "--self-test-audio") == 0) {
            AudioDeviceID xiao = FindXiaoMicrophone();
            if (xiao == kAudioObjectUnknown) {
                printf("AUTO_INPUT_FAIL: XIAO microphone not found\n");
                return 10;
            }
            for (NSNumber *number in AllAudioDevices()) {
                AudioDeviceID candidate = number.unsignedIntValue;
                if (candidate != xiao && DeviceHasInput(candidate)) {
                    SelectDefaultInput(candidate, @"self-test setup");
                    break;
                }
            }
            gXiaoWasConnected = NO;
            RefreshAudioInput(@"self-test insertion");
            if (DefaultInput() != xiao) {
                printf("AUTO_INPUT_FAIL: unable to select XIAO\n");
                return 11;
            }
            printf("AUTO_INPUT_OK: XIAO is the default input\n");
            return 0;
        }

        AudioObjectPropertyAddress address = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        OSStatus audioStatus = AudioObjectAddPropertyListener(
            kAudioObjectSystemObject, &address, AudioDevicesChanged, NULL
        );
        Diagnostic([NSString stringWithFormat:@"bridge v2.2-inplace-test started audio-listener=%d", (int)audioStatus]);

        NSDictionary *promptOptions = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)promptOptions);
        StartKeyboardBridgeIfAuthorized();

        CFRunLoopTimerContext timerContext = {0, NULL, NULL, NULL, NULL};
        CFRunLoopTimerRef permissionTimer = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 1.0,
            1.0,
            0,
            0,
            PermissionTimerFired,
            &timerContext
        );
        CFRunLoopAddTimer(CFRunLoopGetMain(), permissionTimer, kCFRunLoopCommonModes);
        CFRelease(permissionTimer);

        signal(SIGINT, StopBridge);
        signal(SIGTERM, StopBridge);

        double delays[] = {0.0, 0.25, 0.75, 1.5, 3.0};
        for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
            double delay = delays[i];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ RefreshAudioInput(@"startup retry"); });
        }

        printf("Fn Bridge v2.2 IN_PLACE_TEST 已运行：原地将 XIAO F13 改写为 Fn。\n");
        CFRunLoopRun();
    }
    return 0;
}
