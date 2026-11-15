local nk = require("nakama")

local SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000"
local UID_COLLECTION = "system"
local UID_COUNTER_KEY = "uid_counter"
local PROFILE_COLLECTION = "public_profile"
local PROFILE_KEY = "info"
local START_UID = 100000

-- Vergibt atomar die naechste fortlaufende Genshin-aehnliche UID (z.B. 100001).
local function allocate_next_uid()
    for _ = 1, 5 do
        local objects = nk.storage_read({
            { collection = UID_COLLECTION, key = UID_COUNTER_KEY, user_id = SYSTEM_USER_ID }
        })
        local current = START_UID
        local version = nil
        if #objects > 0 then
            current = tonumber(objects[1].value.last_uid) or START_UID
            version = objects[1].version
        end
        local next_uid = current + 1
        local ok = pcall(nk.storage_write, {
            {
                collection = UID_COLLECTION,
                key = UID_COUNTER_KEY,
                user_id = SYSTEM_USER_ID,
                value = { last_uid = next_uid },
                version = version,
                permission_read = 0,
                permission_write = 0
            }
        })
        if ok then
            return tostring(next_uid)
        end
    end
    error("Konnte keine eindeutige UID vergeben")
end

-- Stellt sicher, dass der eingeloggte Account eine feste UID hat.
local VALID_ROLES = {
    player = true,
    tester = true,
    moderator = true,
    admin = true
}

local function normalize_role(raw)
    local r = string.lower(tostring(raw or ""))
    if VALID_ROLES[r] then
        return r
    end
    return "player"
end

local function ensure_user_uid(user_id)
    local existing = nk.storage_read({
        { collection = PROFILE_COLLECTION, key = PROFILE_KEY, user_id = user_id }
    })
    if #existing > 0 and existing[1].value.uid then
        local prof = existing[1].value
        local raw_role = string.lower(tostring(prof.role or ""))
        if not VALID_ROLES[raw_role] then
            prof.role = "player"
            nk.storage_write({
                {
                    collection = PROFILE_COLLECTION,
                    key = PROFILE_KEY,
                    user_id = user_id,
                    value = prof,
                    version = existing[1].version,
                    permission_read = existing[1].permission_read or 2,
                    permission_write = 0
                }
            })
        end
        return prof
    end

    local uid = allocate_next_uid()
    local profile = {
        uid = uid,
        world_join_mode = "ask", -- "private" | "ask" | "open"
        role = "player" -- "player" | "tester" | "moderator" | "admin" (nur serverseitig beschreibbar)
    }

    nk.storage_write({
        {
            collection = PROFILE_COLLECTION,
            key = PROFILE_KEY,
            user_id = user_id,
            value = profile,
            permission_read = 2, -- oeffentlich lesbar (fuer Freunde/Suche)
            permission_write = 0 -- nur Server darf UID schreiben
        }
    })

    -- Index fuer schnelle Suche nach UID -> user_id
    nk.storage_write({
        {
            collection = "uid_index",
            key = uid,
            user_id = SYSTEM_USER_ID,
            value = { owner_id = user_id },
            permission_read = 0,
            permission_write = 0
        }
    })

    return profile
end

-- RPC: Liefert eigenes Profil inkl. fester UID (erstellt UID beim allerersten Aufruf).
local function rpc_get_my_profile(context, _payload)
    local profile = ensure_user_uid(context.user_id)
    local account = nk.account_get_id(context.user_id)
    return nk.json_encode({
        user_id = context.user_id,
        username = account.user.username,
        display_name = account.user.display_name,
        uid = profile.uid,
        world_join_mode = profile.world_join_mode,
        role = normalize_role(profile.role)
    })
end

-- Loest eine UID (oder einen Benutzernamen) auf eine Nakama user_id auf.
local function resolve_target_user(raw_query)
    local query = tostring(raw_query or ""):match("^%s*(.-)%s*$")
    if query == "" then
        return nil, "UID oder Benutzername fehlt"
    end
    if query:match("^%d+$") then
        local idx = nk.storage_read({
            { collection = "uid_index", key = query, user_id = SYSTEM_USER_ID }
        })
        if #idx == 0 then
            return nil, "Kein Spieler mit UID " .. query .. " gefunden"
        end
        return idx[1].value.owner_id, nil
    end
    local ok, users = pcall(nk.users_get_username, { query })
    if ok and users and #users > 0 then
        local found_id = users[1].user_id or users[1].id
        if found_id and found_id ~= "" then
            return found_id, nil
        end
    end
    return nil, "Kein Spieler mit Namen '" .. query .. "' gefunden"
end

-- Laedt oeffentliche Profile (UID, world_join_mode) fuer eine Liste von user_ids.
local function load_public_profiles(user_ids)
    local out = {}
    if #user_ids == 0 then
        return out
    end
    local keys = {}
    for _, id in ipairs(user_ids) do
        table.insert(keys, { collection = PROFILE_COLLECTION, key = PROFILE_KEY, user_id = id })
    end
    local objects = nk.storage_read(keys)
    for _, obj in ipairs(objects) do
        out[obj.user_id] = obj.value
    end
    return out
end

-- RPC: Findet einen anderen Spieler anhand seiner UID oder seines Namens.
local function rpc_find_by_uid(_context, payload)
    local req = nk.json_decode(payload or "{}")
    local query = tostring(req.uid or req.query or "")
    if query == "" then
        error("uid fehlt")
    end
    local owner_id, err = resolve_target_user(query)
    if not owner_id then
        return nk.json_encode({ found = false, error = err })
    end
    local profile = ensure_user_uid(owner_id)
    local account = nk.account_get_id(owner_id)
    return nk.json_encode({
        found = true,
        user_id = owner_id,
        uid = profile.uid,
        username = account.user.username,
        display_name = account.user.display_name,
        world_join_mode = profile.world_join_mode,
        role = normalize_role(profile.role)
    })
end

-- RPC: Sendet eine Freundesanfrage per UID/Name oder nimmt eine bestehende Anfrage an.
local function rpc_add_friend_by_uid(context, payload)
    local req = nk.json_decode(payload or "{}")
    local query = tostring(req.uid or req.query or "")
    local target_id, err = resolve_target_user(query)
    if not target_id then
        return nk.json_encode({ ok = false, error = err })
    end
    if target_id == context.user_id then
        return nk.json_encode({ ok = false, error = "Du kannst dich nicht selbst hinzufuegen" })
    end
    nk.friends_add(context.user_id, context.username, { target_id })
    local profile = ensure_user_uid(target_id)
    local account = nk.account_get_id(target_id)
    return nk.json_encode({
        ok = true,
        target = {
            user_id = target_id,
            uid = profile.uid,
            username = account.user.username,
            display_name = account.user.display_name,
            role = normalize_role(profile.role)
        }
    })
end

-- RPC: Nimmt eine eingehende Freundesanfrage per user_id an.
local function rpc_accept_friend(context, payload)
    local req = nk.json_decode(payload or "{}")
    local target_id = tostring(req.user_id or "")
    if target_id == "" or target_id == context.user_id then
        return nk.json_encode({ ok = false, error = "Ungueltige Ziel-ID" })
    end
    nk.friends_add(context.user_id, context.username, { target_id })
    return nk.json_encode({ ok = true })
end

-- RPC: Entfernt einen Freund oder lehnt/zieht eine Anfrage zurueck.
local function rpc_remove_friend(context, payload)
    local req = nk.json_decode(payload or "{}")
    local target_id = tostring(req.user_id or "")
    if target_id == "" then
        return nk.json_encode({ ok = false, error = "Ungueltige Ziel-ID" })
    end
    nk.friends_delete(context.user_id, context.username, { target_id })
    return nk.json_encode({ ok = true })
end

-- RPC: Listet Freunde (0), gesendete (1) und erhaltene (2) Anfragen inkl. UID & Online-Status.
local function rpc_list_friends(context, _payload)
    local collected = {}
    local user_ids = {}
    local seen_ids = {}
    local res = nk.friends_list(context.user_id, 100)
    local friends = (type(res) == "table" and res.friends) or res or {}
    for _, f in ipairs(friends) do
        local u = f.user
        local fid = u and (u.user_id or u.id) or ""
        if fid ~= "" then
            local st = tonumber(f.state) or 0
            if st == 0 or st == 1 or st == 2 then
                table.insert(collected, { f = f, fid = fid, state = st })
                if not seen_ids[fid] then
                    seen_ids[fid] = true
                    table.insert(user_ids, fid)
                end
            end
        end
    end

    local profiles = load_public_profiles(user_ids)
    local out = {}
    for _, entry in ipairs(collected) do
        local u = entry.f.user
        local prof = profiles[entry.fid] or {}
        table.insert(out, {
            user_id = entry.fid,
            uid = tostring(prof.uid or ""),
            username = tostring(u.username or ""),
            display_name = tostring(u.display_name or ""),
            online = (u.online == true),
            state = entry.state,
            world_join_mode = tostring(prof.world_join_mode or "ask"),
            role = normalize_role(prof.role)
        })
    end
    return nk.json_encode({ ok = true, friends = out })
end

-- RPC: Setzt die Rolle eines Benutzers (nur Server HTTP-Key oder bestehende Admins).
local function rpc_admin_set_role(context, payload)
    local is_server_call = (not context.user_id) or (context.user_id == "")
    if not is_server_call then
        local caller_profile = ensure_user_uid(context.user_id)
        if normalize_role(caller_profile.role) ~= "admin" then
            return nk.json_encode({ ok = false, error = "Nur Admins duerfen Rollen aendern." })
        end
    end

    local req = nk.json_decode(payload or "{}")
    local raw_role = string.lower(tostring(req.role or ""):gsub("^%s*(.-)%s*$", "%1"))
    if not VALID_ROLES[raw_role] then
        return nk.json_encode({ ok = false, error = "Ungueltige Rolle (erlaubt: player, tester, moderator, admin)." })
    end

    local target_query = tostring(req.uid or req.user_id or req.query or "")
    if target_query == "" then
        return nk.json_encode({ ok = false, error = "Ziel-UID oder user_id fehlt." })
    end

    local owner_id = resolve_target_user(target_query)
    if (not owner_id) and req.user_id and tostring(req.user_id) ~= "" then
        local candidate = tostring(req.user_id)
        local ok_acc, acc = pcall(nk.account_get_id, candidate)
        if ok_acc and acc and acc.user then
            owner_id = candidate
        end
    end
    if not owner_id then
        return nk.json_encode({ ok = false, error = "Spieler nicht gefunden." })
    end

    local prof = ensure_user_uid(owner_id)
    local existing = nk.storage_read({
        { collection = PROFILE_COLLECTION, key = PROFILE_KEY, user_id = owner_id }
    })
    local version = (#existing > 0 and existing[1].version) or nil
    local perm_read = (#existing > 0 and existing[1].permission_read) or 2
    prof.role = raw_role
    nk.storage_write({
        {
            collection = PROFILE_COLLECTION,
            key = PROFILE_KEY,
            user_id = owner_id,
            value = prof,
            version = version,
            permission_read = perm_read,
            permission_write = 0
        }
    })

    local account = nk.account_get_id(owner_id)
    return nk.json_encode({
        ok = true,
        user_id = owner_id,
        uid = tostring(prof.uid or ""),
        username = account.user.username,
        display_name = account.user.display_name,
        role = raw_role
    })
end

nk.register_rpc(rpc_get_my_profile, "get_my_profile")
nk.register_rpc(rpc_find_by_uid, "find_by_uid")
nk.register_rpc(rpc_add_friend_by_uid, "add_friend_by_uid")
nk.register_rpc(rpc_accept_friend, "accept_friend")
nk.register_rpc(rpc_remove_friend, "remove_friend")
nk.register_rpc(rpc_list_friends, "list_friends")
nk.register_rpc(rpc_admin_set_role, "admin_set_role")
nk.logger_info("Shadowspore Nakama-Modul geladen.")
