import CLua

// The Lua-facing API surface: `bar.add`, `bar.every`, `bar.subscribe`, and `item:set`.
//
// Each is a file-scope `@convention(c)` function. They run on the Lua `queue` because they
// are only ever invoked from inside a protected call there, and they retrieve their owning
// `LuaRuntime` from upvalue(1) (light userdata).
//
// NOTE on robustness (carried from Spike B's findings): these readers default missing or
// mistyped fields rather than erroring. A production hardening pass should add a typed
// table-field reader + `luaL_argerror` validation; tracked as a follow-up, not done in M1.

func vm(from L: OpaquePointer?) -> LuaRuntime {
    guard let raw = lua_touserdata(L, cl_upvalueindex(1)) else {
        fatalError("noribar: LuaRuntime context upvalue missing from a binding call")
    }
    return Unmanaged<LuaRuntime>.fromOpaque(raw).takeUnretainedValue()
}

func stringField(_ L: OpaquePointer?, _ tableIdx: Int32, _ key: String) -> String? {
    lua_getfield(L, tableIdx, key)
    defer { cl_pop(L, 1) }
    guard cl_isstring(L, -1) != 0, let c = cl_tostring(L, -1) else { return nil }
    return String(cString: c)
}

/// bar.add({ position=, icon=, label= }) -> item
let barAdd: lua_CFunction = { L in
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

/// item:set({ icon=, label=, effect= })
///
/// `effect` is the M1 addition that lets a Lua callback fire a native symbol animation.
/// An unknown effect string is ignored (logged-free) rather than fatal.
let itemSet: lua_CFunction = { L in
    let vm = vm(from: L)
    lua_getfield(L, 1, "_id")
    let id = Int(cl_tointeger(L, -1))
    cl_pop(L, 1)
    let icon = stringField(L, 2, "icon")
    let label = stringField(L, 2, "label")
    let effect = stringField(L, 2, "effect").flatMap { SymbolEffect(rawValue: $0) }
    vm.emit(.set(id: id, icon: icon, label: label, effect: effect))
    return 0
}

/// bar.every(seconds, function)
let barEvery: lua_CFunction = { L in
    let vm = vm(from: L)
    let interval = Double(cl_tonumber(L, 1))
    lua_pushvalue(L, 2)            // copy the function to the top
    let ref = cl_ref(L)           // pop + store in registry
    vm.addTimer(interval: interval, callbackRef: ref)
    return 0
}

/// bar.subscribe("event_name", function)
let barSubscribe: lua_CFunction = { L in
    let vm = vm(from: L)
    guard let c = cl_tostring(L, 1) else { return 0 }
    let name = String(cString: c)
    lua_pushvalue(L, 2)
    let ref = cl_ref(L)
    vm.subscribe(event: name, callbackRef: ref)
    return 0
}

/// Message handler installed as the pcall errfunc: appends a Lua traceback.
let messageHandler: lua_CFunction = { L in
    let msg = cl_tostring(L, 1)
    luaL_traceback(L, L, msg, 1)
    return 1
}
