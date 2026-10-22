import AppKit

/// Figures out what the user is looking at right now: a website (for supported
/// browsers) or otherwise the frontmost app.
@MainActor
enum ActivityProbe {
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.operasoftware.Opera",
    ]
    static let safariBrowsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
    ]

    /// Set when a browser refused Apple Events (user hasn't granted Automation permission).
    static var deniedBrowsers: Set<String> = []

    private static var scripts: [String: NSAppleScript] = [:]

    static func currentKey() -> ActivityKey? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? (bundleID.isEmpty ? "Unknown" : bundleID)

        if chromiumBrowsers.contains(bundleID) || safariBrowsers.contains(bundleID) {
            if let urlString = activeTabURL(bundleID: bundleID, appName: name) {
                return .website(host(from: urlString))
            }
        }
        if axBrowsers.contains(bundleID) {
            if let urlString = addressBarURL(pid: app.processIdentifier) {
                return .website(host(from: urlString))
            }
        }
        return .app(name)
    }

    // MARK: Accessibility (Firefox and friends, which have no AppleScript URL API)

    static let axBrowsers: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "app.zen-browser.zen", "net.waterfox.waterfox", "io.gitlab.librewolf-community",
    ]

    /// Set when a Firefox-style browser was frontmost but we lack Accessibility permission.
    static var accessibilityMissing = false

    /// True once the user has granted Accessibility permission.
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Walks the focused window's UI tree (skipping web content) for the address bar.
    private static func addressBarURL(pid: pid_t) -> String? {
        guard accessibilityTrusted else {
            if !accessibilityMissing { requestAccessibility() }  // prompt once per launch
            accessibilityMissing = true
            return nil
        }
        accessibilityMissing = false
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window: AXUIElement = axAttr(app, kAXFocusedWindowAttribute) else { return nil }

        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let el = queue.removeFirst()
            visited += 1
            let role: String = axAttr(el, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" { continue }
            if role == "AXComboBox" || role == "AXTextField" {
                let desc: String = axAttr(el, kAXDescriptionAttribute) ?? ""
                let ident: String = axAttr(el, "AXIdentifier") ?? ""
                if desc.localizedCaseInsensitiveContains("address") || ident == "urlbar-input" {
                    // Empty, or the user is mid-typing a search: fall back to the app name.
                    guard let value: String = axAttr(el, kAXValueAttribute), !value.isEmpty,
                          !value.contains(" ") else { return nil }
                    // Firefox trims "https://" from the displayed URL.
                    return value.contains("://") || value.hasPrefix("about:") ? value : "https://" + value
                }
            }
            queue += (axAttr(el, kAXChildrenAttribute) as [AXUIElement]?) ?? []
        }
        return nil
    }

    private static func axAttr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func host(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        if let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        // chrome://newtab, about:blank, file:// etc.
        if let scheme = url.scheme { return scheme == "file" ? "local file" : "\(scheme) page" }
        return urlString
    }

    private static func activeTabURL(bundleID: String, appName: String) -> String? {
        let script: NSAppleScript
        if let cached = scripts[bundleID] {
            script = cached
        } else {
            let source = safariBrowsers.contains(bundleID)
                ? "tell application id \"\(bundleID)\" to return URL of current tab of front window"
                : "tell application id \"\(bundleID)\" to return URL of active tab of front window"
            guard let s = NSAppleScript(source: source) else { return nil }
            scripts[bundleID] = s
            script = s
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743: not authorized to send Apple Events
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                deniedBrowsers.insert(appName)
            }
            return nil
        }
        deniedBrowsers.remove(appName)
        return result.stringValue
    }
}
