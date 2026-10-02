import Foundation

/// Decides whether a store change deserves a notification. Pure apart from its own memory of
/// which pending permission requests were already announced.
///
/// One ping per transition into needs input, and again only when a *new* permission request
/// joins (a different tool key). Muted or focused sessions are remembered as announced, so the
/// same pending state never pings later.
public struct NotificationPolicy: Sendable {
    /// Pending permission keys already announced (or deliberately skipped), per session.
    private var announced: [SessionKey: Set<String>] = [:]

    public init() {}

    /// - Parameters:
    ///   - session: the session after the change, nil when it was removed (end or clear).
    ///   - muted: the session's space is muted, or notifications are off.
    ///   - focused: the user is looking at this session in Kohai's window right now.
    /// - Returns: true when a notification should be posted.
    public mutating func shouldNotify(key: SessionKey, after session: Session?, muted: Bool, focused: Bool) -> Bool {
        guard let session, session.status == .needsInput else {
            announced[key] = nil
            return false
        }
        // A permission request without a tool key is stored as "" and still counts as one.
        let pending = session.pendingPermissions.isEmpty ? [""] : session.pendingPermissions
        let fresh = pending.subtracting(announced[key] ?? [])
        // Forget answered requests so a repeat of the same tool later is new again.
        announced[key] = pending
        return !fresh.isEmpty && !muted && !focused
    }
}
