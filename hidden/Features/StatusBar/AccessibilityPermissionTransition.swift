// Accessibility notifications describe changes across all apps. Only restoring
// this app's own permission should retry its previously blocked collapse.
struct AccessibilityPermissionTransition {
    private var wasTrusted: Bool

    init(isTrusted: Bool) {
        wasTrusted = isTrusted
    }

    mutating func permissionWasRestored(isTrusted: Bool) -> Bool {
        defer { wasTrusted = isTrusted }
        return !wasTrusted && isTrusted
    }
}
