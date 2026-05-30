/// The boundary that contains the bar's on-screen surface (D3). Everything private
/// (SkyLight/SLS, `dlsym`, per-OS forks) lives *behind* this protocol so the rest of the
/// app talks only to a small, public-shaped API and a future public-only fallback could be
/// slotted in.
protocol WindowBackend: AnyObject {
    /// The AppKit/CALayer host the renderer populates (D2 — must be an AppKit view tree so
    /// native SF Symbol effects work).
    var barView: BarView { get }

    /// Put the bar on screen without activating the app.
    func show()

    /// Diagnostics for findings/self-test (window id, spaces count, missing SLS symbols).
    func diagnostics() -> [String: String]
}
