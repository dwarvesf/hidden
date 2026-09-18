//
//  HBNativeVisibilityShim.h
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The only boundary to macOS 27's private MenuBarClientCore framework, used by
// the direct (non-App Store) build. Objective-C so that exceptions a changed
// private API raises can be caught instead of crashing the app. In builds
// without HIDDENBAR_NATIVE_VISIBILITY these report the API as unavailable.

// Whether the framework, both classes and every selector used below resolve.
BOOL HBNativeVisibilityIsAvailable(void);

// Keeps only the given system items and apps visible; macOS hides every other
// status item and reflows the bar. The completion runs on the main queue with
// the assertion to hold (hiding lasts until it is invalidated or this process
// exits) or with an error.
void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error));

void HBNativeVisibilityInvalidate(id assertion);

NS_ASSUME_NONNULL_END
