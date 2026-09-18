#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <signal.h>

static BOOL gXiaoWasConnected;
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

static CFStringRef CopyStringProperty(AudioObjectID object,
                                      AudioObjectPropertySelector selector) {
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
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address,
                                       0, NULL, &size) != noErr || !size) {
        return @[];
    }
    NSUInteger count = size / sizeof(AudioDeviceID);
    AudioDeviceID *ids = calloc(count, sizeof(AudioDeviceID));
    if (!ids) return @[];
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                  &address, 0, NULL, &size, ids);
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
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address,
                                   0, NULL, &size, &device) != noErr) {
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
    for (NSNumber *number in AllAudioDevices()) {
        AudioDeviceID device = number.unsignedIntValue;
        CFStringRef name = CopyStringProperty(device, kAudioObjectPropertyName);
        CFStringRef maker = CopyStringProperty(device, kAudioObjectPropertyManufacturer);
        BOOL matches = name && maker &&
            CFEqual(name, CFSTR("XIAO Voice Keyboard Microphone")) &&
            CFEqual(maker, CFSTR("Seeed Studio"));
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
    if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) != noErr || !size) {
        return NO;
    }
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
    OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject,
                                                  &address, 0, NULL, size, &device);
    Diagnostic([NSString stringWithFormat:@"select input id=%u reason=%@ status=%d",
                device, reason, (int)status]);
    return status == noErr;
}

static BOOL ApplyFnMapping(NSString *reason) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/hidutil"];
    task.arguments = @[
        @"property",
        @"--matching", @"{\"VendorID\":0x2886,\"ProductID\":0x5d}",
        @"--set", @"{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x700000068,\"HIDKeyboardModifierMappingDst\":0xFF00000003}]}"
    ];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        Diagnostic([NSString stringWithFormat:@"Fn mapping launch failed reason=%@ error=%@",
                    reason, error]);
        return NO;
    }
    [task waitUntilExit];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    Diagnostic([NSString stringWithFormat:@"Fn mapping reason=%@ status=%d output=%@",
                reason, task.terminationStatus,
                [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]);
    return task.terminationStatus == 0;
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
        SelectDefaultInput(xiao, reason);
        ApplyFnMapping(reason);
        return;
    }

    if (gXiaoWasConnected) {
        gXiaoWasConnected = NO;
        AudioDeviceID previous = FindDeviceByUID(gPreviousInputUID);
        if (previous != kAudioObjectUnknown) {
            SelectDefaultInput(previous, @"restore after unplug");
        }
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
    dispatch_async(dispatch_get_main_queue(), ^{
        RefreshAudioInput(@"device list changed");
    });
    return noErr;
}

static void StopBridge(__unused int signalNumber) { exit(0); }

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test-mapping") == 0) {
            BOOL ok = ApplyFnMapping(@"self-test");
            printf(ok ? "FN_MAPPING_OK: device F13 mapped to Apple Fn\n"
                      : "FN_MAPPING_FAIL: hidutil returned an error\n");
            return ok ? 0 : 20;
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
            kAudioObjectSystemObject, &address, AudioDevicesChanged, NULL);
        Diagnostic([NSString stringWithFormat:
                    @"Fn Bridge 3.0 started audio-listener=%d", (int)audioStatus]);

        signal(SIGINT, StopBridge);
        signal(SIGTERM, StopBridge);

        double delays[] = {0.0, 0.25, 0.75, 1.5, 3.0};
        for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
            double delay = delays[i];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                           (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                RefreshAudioInput(@"startup retry");
            });
        }

        printf("Fn Bridge 3.0 已运行：XIAO F13 映射为 Fn，并自动选择 XIAO 麦克风。\n");
        CFRunLoopRun();
    }
    return 0;
}
