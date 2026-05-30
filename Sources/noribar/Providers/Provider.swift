/// A native Swift source of system state that emits **events** into the Lua layer
/// (replacing sketchybar's per-event script spawning). Q3 — M1 ships exactly one
/// (`FrontAppProvider`) to prove the provider → Lua → render path; the taxonomy and a
/// richer provider set are deferred.
///
/// A provider receives an `emit` closure (wired to `LuaRuntime.fire`) and is responsible
/// for getting its observations onto that closure; the runtime hops them onto the Lua
/// queue, so providers may observe on whatever thread is natural for their source.
protocol Provider: AnyObject {
    /// The event name this provider fires (what Lua `bar.subscribe`s to).
    var eventName: String { get }
    /// Begin observing. `emit(name, payload)` injects an event into the bar.
    func start(emit: @escaping (_ event: String, _ payload: [String: String]) -> Void)
    /// Stop observing.
    func stop()
}
