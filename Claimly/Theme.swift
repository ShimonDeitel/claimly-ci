import SwiftUI

/// Claimly's visual identity: a "ticking clock" urgency theme distinct from every
/// sibling app's palette (not cream/ink/amber luxury, not forest-green/paper,
/// not warm-clay/terracotta). Cool slate-blue "calm" base that visibly reddens
/// as a rebate's deadline approaches -- the whole point of the app's gimmick.
enum Theme {
    // Base surfaces: cool slate, almost-navy -- feels like a ledger/clipboard, not luxury.
    static let backdrop = Color(red: 0.098, green: 0.129, blue: 0.169)      // deep slate-navy
    static let surface = Color(red: 0.149, green: 0.184, blue: 0.227)       // raised card slate
    static let surfaceLight = Color(red: 0.196, green: 0.235, blue: 0.278)  // hairline-raised
    static let textPrimary = Color(red: 0.945, green: 0.957, blue: 0.965)   // near-white
    static let textSecondary = Color(red: 0.658, green: 0.706, blue: 0.745) // muted slate-grey

    // Accent: cool cyan-blue for "safe / plenty of time".
    static let safeBlue = Color(red: 0.318, green: 0.667, blue: 0.847)
    // Mid-urgency amber (a warning step between safe and critical).
    static let warnAmber = Color(red: 0.925, green: 0.686, blue: 0.259)
    // Critical: the "clock is ticking" red the whole app is built around.
    static let criticalRed = Color(red: 0.878, green: 0.243, blue: 0.243)
    static let criticalRedBright = Color(red: 0.976, green: 0.318, blue: 0.318)

    // Cashed-in stamp green (satisfying "received" confirmation).
    static let stampGreen = Color(red: 0.243, green: 0.702, blue: 0.463)
    // Expired/missed muted charcoal-red.
    static let expiredMuted = Color(red: 0.545, green: 0.318, blue: 0.318)

    static let divider = Color.white.opacity(0.08)

    /// Urgency color ramp driven by days remaining until deadline.
    /// >14 days: safe blue. 4-14: amber. 0-3: red. Overdue/expired: muted.
    static func urgencyColor(daysRemaining: Int, isExpired: Bool) -> Color {
        if isExpired { return expiredMuted }
        if daysRemaining <= 3 { return criticalRed }
        if daysRemaining <= 14 { return warnAmber }
        return safeBlue
    }

    static let cardCorner: CGFloat = 18
    static let cardShadow = Color.black.opacity(0.35)
}

/// Real tap-anywhere-to-dismiss-keyboard gesture. `.scrollDismissesKeyboard` alone
/// only fires on an actual scroll drag and does nothing for a plain tap on empty
/// space, so every screen with a text field must layer this on top via
/// `simultaneousGesture` so it never swallows taps on rows/buttons underneath.
extension View {
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}
