import Foundation
import CLua

// MARK: - Instruction-count hook state
//
// The hook is a @convention(c) function and cannot capture Swift context, so its
// counter lives at file scope. This is safe here because there is exactly one
// lua_State and it is only ever touched from one serial queue (so the hook only
// ever runs on that one thread, during a protected call). The real project would
// stash this in `lua_getextraspace` to support multiple states.
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

/// Owns the single `lua_State` and the dedicated serial queue it runs on.
///
/// Threading contract (the whole point of this spike):
///   * The `lua_State` is touched *only* from `queue`.
///   * Lua callbacks emit `BarCommand`s via `emit`, which hops to the main thread.
///   * Inbound events (timers, simulated system events) are funnelled onto `queue`
///     before they reach `lua_State`.
///   * Every entry into Lua goes through `protectedCall`, so a script error is
///     caught and surfaced — never crashes the host.
final class LuaVM {
    /// The one queue allowed to touch `lua_State`.
    let queue = DispatchQueue(label: "org.norikit.noribar.spike-b.lua", qos: .userInitiated)

    /// State-change sink. Called on `queue`; implementations must marshal to main.
    var emit: (BarCommand) -> Void = { _ in }
    /// Error sink (script errors, load failures). Called on `queue`.
    var onError: (String) -> Void = { msg in FileHandle.standardError.write(Data(("lua error: " + msg + "\n").utf8)) }

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

        // Load + run the user's config under full protection.
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

    /// Wraps `lua_pcall` with a traceback message handler and resets the
    /// per-call instruction guard. Returns the Lua status code.
    private func protectedCall(_ L: OpaquePointer?, nargs: Int32, nresults: Int32) -> Int32 {
        // Insert the traceback handler just below the function being called.
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
    private func popError(_ L: OpaquePointer?) -> String {
        defer { cl_pop(L, 1) }
        if let c = cl_tostring(L, -1) { return String(cString: c) }
        return "(non-string error object)"
    }

    // MARK: Timers (host run loop → Lua)

    /// Called from the `bar.every` binding (already on `queue`).
    fileprivate func addTimer(interval: Double, callbackRef: Int32) {
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

    // MARK: Events (simulated system events → Lua)

    fileprivate func subscribe(event: String, callbackRef: Int32) {
        subscribers[event, default: []].append(callbackRef)
    }

    /// Public entry point used by the app to inject a (simulated) system event.
    /// Hops onto `queue` first — callers may be on the main thread.
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

    // MARK: Bindings

    private func installBindings(_ L: OpaquePointer?) {
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        // Build the Item metatable: { __index = { set = <cfunc> } }, store a ref to it.
        cl_newtable(L)                 // metatable
        cl_newtable(L)                 // methods table (__index)
        pushContextClosure(L, itemSet, ctx)
        lua_setfield(L, -2, "set")
        lua_setfield(L, -2, "__index")
        itemMetaRef = cl_ref(L)        // pops metatable, stores in registry

        // Global `bar` table with add / every / subscribe.
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

    // Reaches the metatable ref from a binding (which only has `L`).
    fileprivate func pushItemMetatable(_ L: OpaquePointer?) {
        cl_rawgeti_registry(L, itemMetaRef)
    }

    fileprivate func allocateItemID() -> Int { defer { nextItemID += 1 }; return nextItemID }

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

    /// Compile a representative callback once, then invoke it `iterations` times,
    /// recording each round-trip via Metrics. This is the real per-tick path:
    /// registry fetch → pcall (with hook reset + traceback handler) → `item:set`
    /// binding → command emit → async hop to main.
    func benchmark(iterations: Int, completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let L = self.L else { completion(); return }
            let chunk = """
            local it = bar.add({ type='item', position='left', icon='gauge.with.dots.needle.bottom.50percent', label='0' })
            return function(n) it:set({ label = tostring(n) }) end
            """
            guard luaL_loadstring(L, chunk) == LUA_OK,
                  self.protectedCall(L, nargs: 0, nresults: 1) == LUA_OK else {
                self.onError("benchmark setup: " + self.popError(L)); completion(); return
            }
            let ref = cl_ref(L) // pop + store the returned function
            for i in 0..<iterations {
                let start = DispatchTime.now()
                cl_rawgeti_registry(L, ref)
                lua_pushinteger(L, lua_Integer(i))
                _ = self.protectedCall(L, nargs: 1, nresults: 0)
                Metrics.shared.recordTick(seconds: start.secondsSince())
            }
            cl_unref(L, ref)
            completion()
        }
    }

    /// Run a block on the Lua queue (used to fence reload measurements).
    func onQueue(_ block: @escaping () -> Void) { queue.async(execute: block) }
}

// MARK: - C bindings (file-scope @convention(c) functions)
//
// Each retrieves its owning LuaVM from upvalue(1) (light userdata). They run on
// `queue` because they are only ever invoked from inside a protected call there.

private func vm(from L: OpaquePointer?) -> LuaVM {
    let raw = lua_touserdata(L, cl_upvalueindex(1))!
    return Unmanaged<LuaVM>.fromOpaque(raw).takeUnretainedValue()
}

private func stringField(_ L: OpaquePointer?, _ tableIdx: Int32, _ key: String) -> String? {
    lua_getfield(L, tableIdx, key)
    defer { cl_pop(L, 1) }
    guard cl_isstring(L, -1) != 0, let c = cl_tostring(L, -1) else { return nil }
    return String(cString: c)
}

/// bar.add({ type=, position=, icon=, label= }) -> item
private let barAdd: lua_CFunction = { L in
    let vm = vm(from: L)
    let position = BarPosition(rawValue: stringField(L, 1, "position") ?? "left") ?? .left
    let icon = stringField(L, 1, "icon") ?? ""
    let label = stringField(L, 1, "label") ?? ""
    let id = vm.allocateItemID()
    vm.emit(.add(id: id, position: position, icon: icon, label: label))

    // Return an item handle: { _id = id } with the Item metatable.
    cl_newtable(L)
    lua_pushinteger(L, lua_Integer(id))
    lua_setfield(L, -2, "_id")
    vm.pushItemMetatable(L)
    lua_setmetatable(L, -2)
    return 1
}

/// item:set({ icon=, label= })
private let itemSet: lua_CFunction = { L in
    let vm = vm(from: L)
    lua_getfield(L, 1, "_id")
    let id = Int(cl_tointeger(L, -1))
    cl_pop(L, 1)
    let icon = stringField(L, 2, "icon")
    let label = stringField(L, 2, "label")
    vm.emit(.set(id: id, icon: icon, label: label))
    return 0
}

/// bar.every(seconds, function)
private let barEvery: lua_CFunction = { L in
    let vm = vm(from: L)
    let interval = Double(cl_tonumber(L, 1))
    lua_pushvalue(L, 2)            // copy the function to the top
    let ref = cl_ref(L)           // pop + store in registry
    vm.addTimer(interval: interval, callbackRef: ref)
    return 0
}

/// bar.subscribe("event_name", function)
private let barSubscribe: lua_CFunction = { L in
    let vm = vm(from: L)
    guard let c = cl_tostring(L, 1) else { return 0 }
    let name = String(cString: c)
    lua_pushvalue(L, 2)
    let ref = cl_ref(L)
    vm.subscribe(event: name, callbackRef: ref)
    return 0
}

/// Message handler installed as the pcall errfunc: appends a Lua traceback.
private let messageHandler: lua_CFunction = { L in
    let msg = cl_tostring(L, 1)
    luaL_traceback(L, L, msg, 1)
    return 1
}

// MARK: - Small timing helper

extension DispatchTime {
    func secondsSince() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - uptimeNanoseconds) / 1_000_000_000
    }
}
