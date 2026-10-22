import Foundation

/// Phone apps that are really just a website in an app wrapper. Time in them counts
/// toward the website, so escaping from bsky.app on the Mac to Bluesky on the phone
/// doesn't hide anything.
enum AppDomains {
    private static let byBundleID: [String: String] = [
        "xyz.blueskyweb.app": "bsky.app",
        "com.burbn.instagram": "instagram.com",
        "com.burbn.barcelona": "threads.net",
        "com.atebits.Tweetie2": "x.com",
        "com.facebook.Facebook": "facebook.com",
        "com.facebook.Messenger": "messenger.com",
        "com.google.ios.youtube": "youtube.com",
        "com.reddit.Reddit": "reddit.com",
        "com.zhiliaoapp.musically": "tiktok.com",
        "com.google.Gmail": "mail.google.com",
        "com.linkedin.LinkedIn": "linkedin.com",
        "com.hammerandchisel.discord": "discord.com",
        "com.netflix.Netflix": "netflix.com",
        "com.substack.Substack": "substack.com",
        "net.whatsapp.WhatsApp": "whatsapp.com",
        "com.tinyspeck.chatlyio": "app.slack.com",
    ]

    static func domain(forBundleID id: String?) -> String? {
        id.flatMap { byBundleID[$0] }
    }

    static func normalize(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
