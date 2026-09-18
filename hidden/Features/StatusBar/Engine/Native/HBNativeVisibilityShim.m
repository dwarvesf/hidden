//
//  HBNativeVisibilityShim.m
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#import "HBNativeVisibilityShim.h"

static NSString *const HBNativeVisibilityErrorDomain = @"HBNativeVisibility";

static NSError *HBNativeVisibilityError(NSString *reason) {
    return [NSError errorWithDomain:HBNativeVisibilityErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

#if HIDDENBAR_NATIVE_VISIBILITY

#import <dlfcn.h>
#import <objc/message.h>

// MenuBarClientCore is the private framework behind macOS 27's assessment
// (exam lockdown) mode, which can restrict the menu bar to an allow-list. It is
// resolved at runtime so a macOS release that changes or removes it turns into
// "unavailable" rather than a launch failure. Names are spelled out on purpose.
static NSString *const HBFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const HBConfigurationClassName = @"MBAssessmentModeConfiguration";
static NSString *const HBAssertionClassName = @"MBAssessmentModeAssertion";

static SEL HBConfigurationInit(void) { return @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:); }
static SEL HBActivate(void) { return @selector(activateWithConfiguration:completionHandler:); }
static SEL HBInvalidate(void) { return @selector(invalidate); }

BOOL HBNativeVisibilityIsAvailable(void) {
    if (!dlopen(HBFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
        return NO;
    }
    Class configuration = NSClassFromString(HBConfigurationClassName);
    Class assertion = NSClassFromString(HBAssertionClassName);
    return configuration && assertion
        && [configuration instancesRespondToSelector:HBConfigurationInit()]
        && [assertion instancesRespondToSelector:HBActivate()]
        && [assertion instancesRespondToSelector:HBInvalidate()];
}

void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!HBNativeVisibilityIsAvailable()) {
        finish(nil, HBNativeVisibilityError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    @try {
        // Both lists must be NSArrays: the framework indexes into them, and an
        // NSSet raises -objectAtIndex: unrecognized.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(HBConfigurationClassName) alloc], HBConfigurationInit(),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(HBAssertionClassName) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, HBNativeVisibilityError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, HBActivate(), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, HBNativeVisibilityError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void HBNativeVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:HBInvalidate()]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, HBInvalidate());
        }
    } @catch (NSException *exception) {
        NSLog(@"NativeVisibility: invalidate raised %@: %@", exception.name, exception.reason);
    }
}

#else

BOOL HBNativeVisibilityIsAvailable(void) {
    return NO;
}

void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, HBNativeVisibilityError(@"Native visibility is not part of this build"));
    });
}

void HBNativeVisibilityInvalidate(id assertion) {
}

#endif
