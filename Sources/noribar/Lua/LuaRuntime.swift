import Foundation
import CLua

// MARK: - Instruction-count hook state
//
// The hook is a @convention(c) function and cannot capture Swift context, so its counter
// lives at file scope. Safe here: there is exactly one lua_State and it is only ever
// touched from one serial queue, so the hook only ever runs on that thread during a
// protected call. (A multi-state design would stash this in lua_getextraspace.)
private var gHookInstructionFires = 0
private var gHookFireLimit = 0 // 0 == disabled

private let instructionHook: lua_Hook = { L, _ in
    guard let L = L else { return }
    gHookInstructionFires += 1
    if gHookFireLimit > 0 && gHookInstructionFires > gHookFireLimit {
        lua_pushstring(L, "script exceeded its instruction budget (likely an infinite loop) — aborted")
        lua_error(L) // longjmp; unwinds to the enclosing lua_pcall
    }
}

/// Owns the single `lua_State` and the dedicated serial queue it runs on (D7).
///
/// Threading contract:
///   * The `lua_State` is touched *only* from `queue`.
///   * Lua callbacks emit `BarCommand`s via `emit`, which marshals to the main thread.
///   * Inbound events (timers, provider events) are funnelled onto `queue` first.
///   * Every entry into Lua goes through `protectedCall`, so a script error is caught and
///     surfaced — never crashes the host.
final class LuaRuntime {
    /// The one queue allowed to touch `lua_State`.
    let queue = DispatchQueue(label: "org.norikit.noribar.lua", qos: .userInitiated)

    /// State-change sink. Called on `queue`; the implementation must marshal to main.
    var emit: (BarCommand) -> Void = { _ in }
    /// Error sink (script errors, load failures). Called on `queue`.
    var onError: (String) -> Void = { msg in
        FileHandle.standardError.write(Data(("lua error: " + msg + "\n").utf8))
    }

    private var L: OpaquePointer?
    private var nextItemID = 1
    private var itemMetaRef: Int32 = LUA_NOREF

    private var timers: [DispatchSourceTimer] = []
    private var subscribers: [String: [Int32]] = [:]

    /// Fire the count hook every N VM instructions. Larger = less overhead, coarser guard.
    private let hookEveryNInstructions: Int32 = 1000
    /// Abort a single protected call after this many hook fires (≈ N×this instructions).
    private let hookFireBudget = 200_000

    // MARK: Lifecycle

    /// (Re)start the VM from a config file. Safe to call repeatedly = hot reload.
    func start(configURL: URL) {
        queue.async { [weak self] in self?._start(configURL: configURL) }
    }

    func shutdown() {
        queue.sync { [weak self] in self?._teardown() }
    }

    private func _start(configURL: URL) {
        dispatchPrecondition(condition: .onQueue(queue))
        _teardown() // idempotent: clears prior state/timers/items for hot reload

        emit(.clear)

        guard let L = luaL_newstate() else {
            onError("luaL_newstate failed (out of memory)")
            return
        }
        self.L = L
        luaL_openlibs(L)
        lua_sethook(L, instructionHook, LUA_MASKCOUNT, hookEveryNInstructions)
        installBindings(L)

        let path = configURL.path
        if luaL_loadfilex(L, path, nil) != LUA_OK {
            onError("loading config: " + popError(L))
            return
        }
        if protectedCall(L, nargs: 0, nresults: 0) != LUA_OK {
            onError("running config: " + popError(L))
            // A broken config leaves whatever items it managed to create; the app lives on.
        }
    }

    private func _teardown() {
        for t in timers { t.cancel() }
        timers.removeAll()
        subscribers.removeAll()
        nextItemID = 1
        if let L = L {
            lua_close(L) // frees everything incl. ref'd callbacks; no leak across reloads
        }
        L = nil
        itemMetaRef = LUA_NOREF
    }

    // MARK: Protected calls

    /// Wraps `lua_pcall` with a traceback message handler and resets the per-call
    /// instruction guard. Returns the Lua status code.
    func protectedCall(_ L: OpaquePointer?, nargs: Int32, nresults: Int32) -> Int32 {
        let funcBase = lua_gettop(L) - nargs
        cl_pushcfunction(L, messageHandler)
        cl_insert(L, funcBase)

        gHookInstructionFires = 0
        gHookFireLimit = hookFireBudget
        let rc = cl_pcall(L, nargs, nresults, funcBase)
        gHookFireLimit = 0

        cl_remove(L, funcBase) // drop the handler
        return rc
    }

    /// Pops and returns the error object on the top of the stack as a String.
    func popError(_ L: OpaquePointer?) -> String {
        defer { cl_pop(L, 1) }
        if let c = cl_tostring(L, -1) { return String(cString: c) }
        return "(non-string error object)"
    }

    // MARK: Timers (host run loop → Lua)

    /// Called from the `bar.every` binding (already on `queue`).
    func addTimer(interval: Double, callbackRef: Int32) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self, let L = self.L else { return }
            let start = DispatchTime.now()
            cl_rawgeti_registry(L, callbackRef) // push the callback
            if self.protectedCall(L, nargs: 0, nresults: 0) != LUA_OK {
                self.onError("timer callback: " + self.popError(L))
            }
            Metrics.shared.recordTick(seconds: start.secondsSince())
        }
        timers.append(t)
        t.resume()
    }

    // MARK: Events (provider / system events → Lua)

    func subscribe(event: String, callbackRef: Int32) {
        subscribers[event, default: []].append(callbackRef)
    }

    /// Inject an event into the bar. Hops onto `queue` first — callers may be on any thread
    /// (e.g. `FrontAppProvider` on the main thread).
    func fire(event: String, payload: [String: String]) {
        queue.async { [weak self] in
            guard let self, let L = self.L, let refs = self.subscribers[event] else { return }
            for ref in refs {
                cl_rawgeti_registry(L, ref)          // push callback
                self.pushStringTable(L, payload)     // push payload table
                if self.protectedCall(L, nargs: 1, nresults: 0) != LUA_OK {
                    self.onError("event '\(event)' callback: " + self.popError(L))
                }
            }
        }
    }

    private func pushStringTable(_ L: OpaquePointer?, _ dict: [String: String]) {
        cl_newtable(L)
        for (k, v) in dict {
            lua_pushstring(L, v)
            lua_setfield(L, -2, k)
        }
    }

    // MARK: Binding support (used by Bindings.swift)

    func allocateItemID() -> Int { defer { nextItemID += 1 }; return nextItemID }

    /// Push the shared Item metatable (so item handles get `:set`).
    func pushItemMetatable(_ L: OpaquePointer?) {
        cl_rawgeti_registry(L, itemMetaRef)
    }

    private func installBindings(_ L: OpaquePointer?) {
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        // Item metatable: { __index = { set = <cfunc> } }, stored as a registry ref.
        cl_newtable(L)                 // metatable
        cl_newtable(L)                 // methods table (__index)
        pushContextClosure(L, itemSet, ctx)
        lua_setfield(L, -2, "set")
        lua_setfield(L, -2, "__index")
        itemMetaRef = cl_ref(L)        // pops metatable, stores in registry

        // Global `bar` table: add / every / subscribe.
        cl_newtable(L)
        pushContextClosure(L, barAdd, ctx);       lua_setfield(L, -2, "add")
        pushContextClosure(L, barEvery, ctx);     lua_setfield(L, -2, "every")
        pushContextClosure(L, barSubscribe, ctx); lua_setfield(L, -2, "subscribe")
        lua_setglobal(L, "bar")
    }

    /// Push a C closure carrying `self` as light-userdata upvalue(1).
    private func pushContextClosure(_ L: OpaquePointer?, _ fn: lua_CFunction, _ ctx: UnsafeMutableRawPointer) {
        lua_pushlightuserdata(L, ctx)
        lua_pushcclosure(L, fn, 1)
    }

    // MARK: Self-test helpers (used by --selftest only)

    /// Load + run an arbitrary chunk under full protection. For crash-isolation tests.
    func evaluate(_ source: String, name: String) {
        queue.async { [weak self] in
            guard let self, let L = self.L else { return }
            if luaL_loadstring(L, source) != LUA_OK {
                self.onError("\(name) (load): " + self.popError(L)); return
            }
            if self.protectedCall(L, nargs: 0, nresults: 0) != LUA_OK {
                self.onError("\(name): " + self.popError(L))
            }
        }
    }

    /// Run a block on the Lua queue (used to fence reload/measurement in the self-test).
    func onQueue(_ block: @escaping () -> Void) { queue.async(execute: block) }
}

// MARK: - Small timing helper

extension DispatchTime {
    func secondsSince() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - uptimeNanoseconds) / 1_000_000_000
    }
}
