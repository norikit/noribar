import AppKit

/// The one real provider in M1: observes the frontmost-application change and fires
/// `front_app_switched` with `{ app = <name> }`. This replaces Spike B's *simulated*
/// timer event, proving the full provider → Lua → render path end to end.
///
/// `NSWorkspace.didActivateApplicationNotification` is delivered on the main thread;
/// `emit` (→ `LuaRuntime.fire`) hops it onto the Lua queue.
final class FrontAppProvider: Provider {
    let eventName = "front_app_switched"
    private var token: NSObjectProtocol?

    func start(emit: @escaping (String, [String: String]) -> Void) {
        let nc = NSWorkspace.shared.notificationCenter
        token = nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                               object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName ?? "?"
            emit("front_app_switched", ["app": name])
        }
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        token = nil
    }
}
