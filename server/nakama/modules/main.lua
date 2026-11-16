local nk = require("nakama")

local SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000"
local UID_COLLECTION = "system"
local UID_COUNTER_KEY = "uid_counter"
local PROFILE_COLLECTION = "public_profile"
local PROFILE_KEY = "info"
local LOBBY_COLLECTION = "coop_lobby"
local LOBBY_KEY = "active"
local ROOM_CODE_COLLECTION = "coop_room_code"
local JOIN_REQUEST_COLLECTION = "coop_join_request"
local IDENTITY_TICKET_COLLECTION = "coop_identity_ticket"
local LICENSE_KEYS_COLLECTION = "license_keys"
local LICENSE_INDEX_KEY = "recent_keys"
local ENTITLEMENTS_COLLECTION = "entitlements"
local ENTITLEMENT_KEY = "license"
local LAUNCH_TICKETS_COLLECTION = "launch_tickets"
local GAME_SESSIONS_COLLECTION = "game_sessions"
local GAME_SESSION_KEY = "active"
local SECURITY_EVENTS_COLLECTION = "security_events"
local SECURITY_INDEX_KEY = "recent_events"
local SYSTEM_CONFIG_COLLECTION = "system_config"
local BUILD_HASHES_KEY = "allowed_exe_hashes"
local LAUNCH_TICKET_TTL_SEC = 45
local START_UID = 99999

local NOTIF_COOP_INVITE = 101
local NOTIF_COOP_JOIN_REQUEST = 102
local NOTIF_COOP_JOIN_APPROVED = 103
local NOTIF_COOP_JOIN_DECLINED = 104

local VALID_JOIN_MODES = {
    private = true,
    ask = true,
    open = true
}

local PROTECTED_CLIENT_COLLECTIONS = {
    saves = true,
    public_profile = true,
    entitlements = true,
    license_keys = true,
    launch_tickets = true,
    game_sessions = true,
    security_events = true,
    system = true,
    system_config = true,
    uid_index = true,
    coop_lobby = true,
    coop_room_code = true,
    coop_join_request = true,
    coop_identity_ticket = true
}

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

    local ok_acc, acc = pcall(nk.account_get_id, user_id)
    if not ok_acc or not acc or not acc.user then
        error({ "Konto existiert nicht mehr. Bitte erneut anmelden.", 16 })
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

local function normalize_join_mode(raw)
    local m = string.lower(tostring(raw or "")):gsub("^%s*(.-)%s*$", "%1")
    if VALID_JOIN_MODES[m] then
        return m
    end
    return nil
end

local function generate_room_code()
    local alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local raw = nk.uuid_v4():gsub("-", "")
    local out = {}
    for i = 1, 6 do
        local hex = string.sub(raw, (i - 1) * 2 + 1, i * 2)
        local n = tonumber(hex, 16) or i
        local idx = (n % #alphabet) + 1
        table.insert(out, string.sub(alphabet, idx, idx))
    end
    return table.concat(out)
end

local function load_active_lobbies(user_ids)
    local out = {}
    if #user_ids == 0 then
        return out
    end
    local reads = {}
    for _, uid_str in ipairs(user_ids) do
        table.insert(reads, { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = uid_str })
    end
    local objs = nk.storage_read(reads)
    local now = os.time()
    local stale = {}
    for _, obj in ipairs(objs) do
        local lobby = type(obj.value) == "table" and obj.value or nil
        if lobby and lobby.match_id and lobby.match_id ~= "" then
            local age = now - (tonumber(lobby.updated_at) or 0)
            local ok_m, match_info = pcall(nk.match_get, tostring(lobby.match_id))
            if ok_m and match_info and age <= 180 then
                lobby.player_count = tonumber(match_info.size) or tonumber(lobby.player_count) or 1
                out[obj.user_id] = lobby
            else
                table.insert(stale, { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = obj.user_id })
            end
        end
    end
    if #stale > 0 then
        pcall(nk.storage_delete, stale)
    end
    return out
end

local function read_active_lobby(user_id)
    local lobbies = load_active_lobbies({ user_id })
    return lobbies[user_id]
end

local function are_accepted_friends(user_a, user_b)
    if user_a == user_b then
        return true
    end
    local ok, friends = pcall(nk.friends_list, user_a, 100)
    if not ok or type(friends) ~= "table" then
        return false
    end
    for _, f in ipairs(friends) do
        local u = f.user
        local fid = u and (u.user_id or u.id) or ""
        if fid == user_b and tonumber(f.state) == 0 then
            return true
        end
    end
    return false
end

local function is_server_or_admin(context)
    if (not context.user_id) or (context.user_id == "") then
        return true, true
    end
    local caller_profile = ensure_user_uid(context.user_id)
    return normalize_role(caller_profile.role) == "admin", false
end

local function read_bool_flag(v)
    if type(v) == "table" then
        return v.value == true
    end
    return v == true
end

local function normalize_license_key(raw)
    local cleaned = string.upper(tostring(raw or "")):gsub("%s+", ""):gsub("[^A-Z0-9%-]", "")
    return cleaned
end

local function generate_license_key()
    local alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local entropy = nk.sha256_hash(nk.uuid_v4() .. ":" .. tostring(os.time()) .. ":" .. nk.uuid_v4())
    local parts = {}
    local pos = 1
    for _ = 1, 3 do
        local chunk = {}
        for _ = 1, 4 do
            local hex = string.sub(entropy, pos, pos + 1)
            pos = pos + 2
            local n = tonumber(hex, 16) or 0
            local idx = (n % #alphabet) + 1
            table.insert(chunk, string.sub(alphabet, idx, idx))
        end
        table.insert(parts, table.concat(chunk))
    end
    return "SHADOW-" .. table.concat(parts, "-")
end

local function read_entitlement(user_id)
    if not user_id or user_id == "" then
        return {}, nil
    end
    local objs = nk.storage_read({
        { collection = ENTITLEMENTS_COLLECTION, key = ENTITLEMENT_KEY, user_id = user_id }
    })
    if #objs > 0 and type(objs[1].value) == "table" then
        return objs[1].value, objs[1].version
    end
    return {}, nil
end

local function write_entitlement(user_id, ent, version)
    local req = {
        collection = ENTITLEMENTS_COLLECTION,
        key = ENTITLEMENT_KEY,
        user_id = user_id,
        value = ent,
        permission_read = 1,
        permission_write = 0
    }
    if version then
        req.version = version
    end
    nk.storage_write({ req })
end

local function check_entitlement_status(user_id)
    local ent = read_entitlement(user_id)
    if ent.banned == true then
        local reason = tostring(ent.ban_reason or "Verstoss gegen die Nutzungsbedingungen")
        return false, "Konto gesperrt: " .. reason, ent
    end
    if ent.active ~= true then
        return false, "Keine gueltige Shadowspore-Lizenz. Bitte Key auf shadowspore.com einloesen.", ent
    end
    local exp = tonumber(ent.expires_at or 0) or 0
    if exp > 0 and os.time() > exp then
        return false, "Deine Shadowspore-Lizenz ist abgelaufen.", ent
    end
    return true, "", ent
end

local function require_entitled(user_id)
    local ok, err, ent = check_entitlement_status(user_id)
    if not ok then
        return false, err, ent
    end
    return true, "", ent
end

local function append_bounded_index(collection, index_key, item_id, max_items)
    local objs = nk.storage_read({
        { collection = collection, key = index_key, user_id = SYSTEM_USER_ID }
    })
    local items = {}
    if #objs > 0 and type(objs[1].value) == "table" and type(objs[1].value.ids) == "table" then
        items = objs[1].value.ids
    end
    table.insert(items, 1, item_id)
    local trimmed = {}
    local removed = {}
    for i, id in ipairs(items) do
        if i <= max_items then
            table.insert(trimmed, id)
        else
            table.insert(removed, { collection = collection, key = id, user_id = SYSTEM_USER_ID })
        end
    end
    nk.storage_write({
        {
            collection = collection,
            key = index_key,
            user_id = SYSTEM_USER_ID,
            value = { ids = trimmed },
            permission_read = 0,
            permission_write = 0
        }
    })
    if #removed > 0 then
        pcall(nk.storage_delete, removed)
    end
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

local function infer_security_severity(kind)
    local k = string.upper(tostring(kind or ""))
    if k:find("BANNED", 1, true) or k:find("MISMATCH", 1, true) or k:find("TAMPER", 1, true)
        or k:find("DIRECT_STORAGE", 1, true) or k:find("INVALID_LAUNCH", 1, true)
        or k:find("REJECT", 1, true) or k:find("CHEAT", 1, true)
        or k:find("BYPASS", 1, true) or k:find("SPEEDHACK", 1, true) or k:find("HASH_DIFF", 1, true) then
        return "critical"
    end
    if k:find("FORCE_JOIN", 1, true) or k:find("KICK", 1, true) or k:find("CLOSE_WORLD", 1, true)
        or k:find("REVOKE", 1, true) or k:find("ROLE", 1, true) or k:find("LICENSE", 1, true)
        or k:find("ANOMALY", 1, true) or k:find("ROLLBACK", 1, true) then
        return "warn"
    end
    return "info"
end

local function load_user_meta_map(user_ids)
    local out = {}
    local unique = {}
    local seen = {}
    for _, raw_id in ipairs(user_ids or {}) do
        local uid = tostring(raw_id or "")
        if uid ~= "" and uid ~= SYSTEM_USER_ID and uid ~= "server" and uid:match("^[0-9a-fA-F%-]+$") and #uid == 36 and not seen[uid] then
            seen[uid] = true
            table.insert(unique, uid)
        end
    end
    if #unique == 0 then
        return out
    end
    local profs = load_public_profiles(unique)
    local ok_u, users = pcall(nk.users_get_id, unique)
    local user_map = {}
    if ok_u and type(users) == "table" then
        for _, u in ipairs(users) do
            local id = tostring(u.user_id or u.id or "")
            if id ~= "" then
                user_map[id] = u
            end
        end
    end
    for _, uid in ipairs(unique) do
        local prof = type(profs[uid]) == "table" and profs[uid] or {}
        local u = user_map[uid]
        local uname = u and tostring(u.username or "") or ""
        local dname = u and tostring(u.display_name or "") or ""
        out[uid] = {
            uid = tostring(prof.uid or ""),
            role = normalize_role(prof.role),
            username = uname,
            display_name = (dname ~= "" and dname) or uname
        }
    end
    return out
end

local function record_security_event(user_id, kind, detail, severity)
    local event_id = tostring(os.time()) .. "_" .. nk.uuid_v4():sub(1, 8)
    local uid_str = tostring(user_id or "")
    local kind_str = tostring(kind or "UNKNOWN"):sub(1, 64)
    local sev = tostring(severity or ""):lower()
    if sev ~= "info" and sev ~= "warn" and sev ~= "critical" then
        sev = infer_security_severity(kind_str)
    end
    local meta = load_user_meta_map({ uid_str })
    local m = meta[uid_str] or {}
    nk.logger_warn("[SECURITY] user=" .. uid_str .. " kind=" .. kind_str .. " detail=" .. tostring(detail))
    nk.storage_write({
        {
            collection = SECURITY_EVENTS_COLLECTION,
            key = event_id,
            user_id = SYSTEM_USER_ID,
            value = {
                id = event_id,
                user_id = uid_str,
                uid = tostring(m.uid or ""),
                username = tostring(m.username or m.display_name or ""),
                kind = kind_str,
                severity = sev,
                detail = tostring(detail or ""):sub(1, 300),
                at = os.time()
            },
            permission_read = 0,
            permission_write = 0
        }
    })
    pcall(append_bounded_index, SECURITY_EVENTS_COLLECTION, SECURITY_INDEX_KEY, event_id, 120)
end

local function invalidate_user_online_state(user_id)
    pcall(nk.storage_delete, {
        { collection = GAME_SESSIONS_COLLECTION, key = GAME_SESSION_KEY, user_id = user_id }
    })
    local existing = nk.storage_read({
        { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = user_id }
    })
    if #existing > 0 and type(existing[1].value) == "table" then
        local lobby = existing[1].value
        if lobby.match_id and lobby.match_id ~= "" then
            pcall(nk.match_signal, tostring(lobby.match_id), nk.json_encode({ action = "close" }))
        end
        if lobby.room_code and lobby.room_code ~= "" then
            pcall(nk.storage_delete, { { collection = ROOM_CODE_COLLECTION, key = tostring(lobby.room_code), user_id = SYSTEM_USER_ID } })
        end
        pcall(nk.storage_delete, { { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = user_id } })
    end
end

local function validate_license_key_record(key)
    if key == "" or #key < 12 then
        return nil, nil, "Ungueltiges Lizenzkey-Format."
    end
    local objs = nk.storage_read({
        { collection = LICENSE_KEYS_COLLECTION, key = key, user_id = SYSTEM_USER_ID }
    })
    if #objs == 0 or type(objs[1].value) ~= "table" then
        return nil, nil, "Lizenzkey existiert nicht."
    end
    local rec = objs[1].value
    if rec.status == "revoked" then
        return nil, nil, "Dieser Lizenzkey wurde gesperrt."
    end
    if rec.status ~= "unused" or (rec.claimed_by and rec.claimed_by ~= "") then
        return nil, nil, "Dieser Lizenzkey wurde bereits verwendet."
    end
    local exp = tonumber(rec.expires_at or 0) or 0
    if exp > 0 and os.time() > exp then
        return nil, nil, "Dieser Lizenzkey ist abgelaufen."
    end
    return rec, objs[1].version, ""
end

local function claim_license_key_for_user(user_id, raw_key)
    local key = normalize_license_key(raw_key)
    local rec, version, err = validate_license_key_record(key)
    if not rec then
        return false, err
    end
    local ent, ent_ver = read_entitlement(user_id)
    if ent.banned == true then
        return false, "Dieses Konto ist gesperrt."
    end
    rec.status = "claimed"
    rec.claimed_by = user_id
    rec.claimed_at = os.time()
    local ok_claim = pcall(nk.storage_write, {
        {
            collection = LICENSE_KEYS_COLLECTION,
            key = key,
            user_id = SYSTEM_USER_ID,
            value = rec,
            version = version,
            permission_read = 0,
            permission_write = 0
        }
    })
    if not ok_claim then
        return false, "Lizenzkey konnte nicht aktiviert werden (Konflikt). Bitte erneut versuchen."
    end

    local next_ent = {
        active = true,
        license_key = key,
        edition = tostring(rec.edition or "standard"),
        activated_at = os.time(),
        expires_at = tonumber(rec.user_expires_at or 0) or 0,
        banned = false,
        ban_reason = ""
    }
    write_entitlement(user_id, next_ent, ent_ver)

    local role_grant = normalize_role(rec.role_grant)
    if role_grant ~= "player" then
        local prof = ensure_user_uid(user_id)
        local p_objs = nk.storage_read({
            { collection = PROFILE_COLLECTION, key = PROFILE_KEY, user_id = user_id }
        })
        local p_ver = (#p_objs > 0 and p_objs[1].version) or nil
        prof.role = role_grant
        nk.storage_write({
            {
                collection = PROFILE_COLLECTION,
                key = PROFILE_KEY,
                user_id = user_id,
                value = prof,
                version = p_ver,
                permission_read = 2,
                permission_write = 0
            }
        })
    end
    return true, ""
end

-- RPC: Liefert eigenes Profil inkl. fester UID und Lizenz-/Sperrstatus.
local function rpc_get_my_profile(context, _payload)
    local profile = ensure_user_uid(context.user_id)
    local account = nk.account_get_id(context.user_id)
    local lobby = read_active_lobby(context.user_id)
    local lic_ok, lic_err, ent = check_entitlement_status(context.user_id)
    return nk.json_encode({
        user_id = context.user_id,
        username = account.user.username,
        display_name = account.user.display_name,
        uid = profile.uid,
        world_join_mode = profile.world_join_mode,
        role = normalize_role(profile.role),
        avatar_url = account.user.avatar_url or "",
        active_lobby = lobby,
        license_active = lic_ok,
        license_edition = tostring(ent.edition or (lic_ok and "standard" or "")),
        license_expires_at = tonumber(ent.expires_at or 0) or 0,
        license_error = lic_err,
        banned = (ent.banned == true),
        ban_reason = tostring(ent.ban_reason or "")
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
    local lobbies = load_active_lobbies(user_ids)
    local out = {}
    for _, entry in ipairs(collected) do
        local u = entry.f.user
        local prof = profiles[entry.fid] or {}
        local lobby = lobbies[entry.fid]
        local coop_active = (lobby ~= nil and entry.state == 0)
        table.insert(out, {
            user_id = entry.fid,
            uid = tostring(prof.uid or ""),
            username = tostring(u.username or ""),
            display_name = tostring(u.display_name or ""),
            online = (u.online == true),
            state = entry.state,
            world_join_mode = tostring(prof.world_join_mode or "ask"),
            role = normalize_role(prof.role),
            avatar_url = tostring(u.avatar_url or ""),
            coop_active = coop_active,
            coop_match_id = coop_active and tostring(lobby.match_id or "") or "",
            coop_world_name = coop_active and tostring(lobby.world_name or "") or "",
            coop_join_mode = coop_active and tostring(lobby.join_mode or prof.world_join_mode or "ask") or tostring(prof.world_join_mode or "ask"),
            coop_players = coop_active and tonumber(lobby.player_count or 1) or 0,
            coop_max_players = coop_active and tonumber(lobby.max_players or 4) or 4
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
    pcall(record_security_event, owner_id, "ADMIN_SET_ROLE", "role=" .. raw_role .. " by=" .. tostring(context.user_id or "server"), "warn")
    return nk.json_encode({
        ok = true,
        user_id = owner_id,
        uid = tostring(prof.uid or ""),
        username = account.user.username,
        display_name = account.user.display_name,
        role = raw_role
    })
end

-- RPC: Setzt den eigenen Welt-Beitrittsmodus ("private" | "ask" | "open") serverseitig.
local function rpc_set_world_join_mode(context, payload)
    local req = nk.json_decode(payload or "{}")
    local nm = normalize_join_mode(req.join_mode or req.world_join_mode or "")
    if not nm then
        return nk.json_encode({ ok = false, error = "Ungueltiger Modus (erlaubt: private, ask, open)." })
    end
    local prof = ensure_user_uid(context.user_id)
    local existing = nk.storage_read({
        { collection = PROFILE_COLLECTION, key = PROFILE_KEY, user_id = context.user_id }
    })
    local version = (#existing > 0 and existing[1].version) or nil
    local perm_read = (#existing > 0 and existing[1].permission_read) or 2
    prof.world_join_mode = nm
    nk.storage_write({
        {
            collection = PROFILE_COLLECTION,
            key = PROFILE_KEY,
            user_id = context.user_id,
            value = prof,
            version = version,
            permission_read = perm_read,
            permission_write = 0
        }
    })

    local lobby = read_active_lobby(context.user_id)
    if lobby and lobby.match_id and lobby.match_id ~= "" then
        lobby.join_mode = nm
        lobby.updated_at = os.time()
        nk.storage_write({
            {
                collection = LOBBY_COLLECTION,
                key = LOBBY_KEY,
                user_id = context.user_id,
                value = lobby,
                permission_read = 2,
                permission_write = 0
            }
        })
        pcall(nk.match_signal, lobby.match_id, nk.json_encode({ action = "set_join_mode", join_mode = nm }))
    end
    return nk.json_encode({ ok = true, world_join_mode = nm })
end

-- RPC: Oeffnet (oder reaktiviert) eine server-vermittelte Koop-Relay-Welt fuer den Caller.
local function rpc_coop_open_world(context, payload)
    local ent_ok, ent_err = require_entitled(context.user_id)
    if not ent_ok then
        return nk.json_encode({ ok = false, error = ent_err })
    end
    local req = nk.json_decode(payload or "{}")
    local prof = ensure_user_uid(context.user_id)
    local account = nk.account_get_id(context.user_id)
    local host_name = tostring((account.user.display_name ~= "" and account.user.display_name) or account.user.username or "Spieler")
    local world_name = tostring(req.world_name or "KOOP-WELT"):sub(1, 36)
    local join_mode = normalize_join_mode(req.join_mode) or tostring(prof.world_join_mode or "ask")
    local max_players = math.max(1, math.min(4, tonumber(req.max_players) or 4))

    local existing_lobby = read_active_lobby(context.user_id)
    if existing_lobby and existing_lobby.match_id and not req.force_new then
        existing_lobby.world_name = world_name
        existing_lobby.join_mode = join_mode
        existing_lobby.updated_at = os.time()
        nk.storage_write({
            {
                collection = LOBBY_COLLECTION,
                key = LOBBY_KEY,
                user_id = context.user_id,
                value = existing_lobby,
                permission_read = 2,
                permission_write = 0
            }
        })
        pcall(nk.match_signal, existing_lobby.match_id, nk.json_encode({ action = "set_join_mode", join_mode = join_mode }))
        return nk.json_encode({
            ok = true,
            match_id = tostring(existing_lobby.match_id),
            room_code = tostring(existing_lobby.room_code or ""),
            world_name = world_name,
            join_mode = join_mode,
            max_players = max_players
        })
    end

    if existing_lobby and existing_lobby.match_id then
        pcall(nk.match_signal, existing_lobby.match_id, nk.json_encode({ action = "close" }))
        if existing_lobby.room_code and existing_lobby.room_code ~= "" then
            pcall(nk.storage_delete, { { collection = ROOM_CODE_COLLECTION, key = existing_lobby.room_code, user_id = SYSTEM_USER_ID } })
        end
    end

    local room_code = string.upper(tostring(req.room_code or "")):gsub("[^A-Z0-9]", ""):sub(1, 8)
    if #room_code < 4 then
        room_code = generate_room_code()
    end

    local match_id = nk.match_create("coop_relay", {
        host_user_id = context.user_id,
        host_uid = prof.uid,
        world_name = world_name,
        room_code = room_code,
        join_mode = join_mode,
        max_players = max_players
    })

    local lobby_obj = {
        match_id = match_id,
        host_user_id = context.user_id,
        host_uid = prof.uid,
        host_name = host_name,
        world_name = world_name,
        room_code = room_code,
        join_mode = join_mode,
        max_players = max_players,
        player_count = 1,
        updated_at = os.time()
    }
    nk.storage_write({
        {
            collection = LOBBY_COLLECTION,
            key = LOBBY_KEY,
            user_id = context.user_id,
            value = lobby_obj,
            permission_read = 2,
            permission_write = 0
        },
        {
            collection = ROOM_CODE_COLLECTION,
            key = room_code,
            user_id = SYSTEM_USER_ID,
            value = {
                match_id = match_id,
                host_user_id = context.user_id,
                host_uid = prof.uid
            },
            permission_read = 0,
            permission_write = 0
        }
    })

    return nk.json_encode({
        ok = true,
        match_id = match_id,
        room_code = room_code,
        world_name = world_name,
        join_mode = join_mode,
        max_players = max_players
    })
end

-- RPC: Schliesst die eigene aktive Koop-Relay-Welt sauber.
local function rpc_coop_close_world(context, payload)
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local target_mid = type(req) == "table" and tostring(req.match_id or "") or ""
    local existing = nk.storage_read({
        { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = context.user_id }
    })
    if #existing > 0 then
        local lobby = type(existing[1].value) == "table" and existing[1].value or {}
        local stored_mid = tostring(lobby.match_id or "")
        if target_mid ~= "" and stored_mid ~= "" and stored_mid ~= target_mid then
            return nk.json_encode({ ok = true, skipped = true })
        end
        if stored_mid ~= "" then
            pcall(nk.match_signal, stored_mid, nk.json_encode({ action = "close" }))
        end
        if lobby.room_code and lobby.room_code ~= "" then
            pcall(nk.storage_delete, { { collection = ROOM_CODE_COLLECTION, key = tostring(lobby.room_code), user_id = SYSTEM_USER_ID } })
        end
        pcall(nk.storage_delete, { { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = context.user_id } })
    end
    return nk.json_encode({ ok = true })
end

-- RPC: Haelt die aktive Koop-Lobby am Leben und aktualisiert Spieleranzahl / Weltnamen.
local function rpc_coop_heartbeat(context, payload)
    local ent_ok, ent_err = require_entitled(context.user_id)
    if not ent_ok then
        return nk.json_encode({ ok = false, active = false, error = ent_err })
    end
    local req = nk.json_decode(payload or "{}")
    local lobby = read_active_lobby(context.user_id)
    if not lobby then
        return nk.json_encode({ ok = true, active = false })
    end
    if req.world_name and tostring(req.world_name) ~= "" then
        lobby.world_name = tostring(req.world_name):sub(1, 36)
    end
    if req.player_count then
        lobby.player_count = math.max(1, math.min(4, tonumber(req.player_count) or 1))
    end
    lobby.updated_at = os.time()
    nk.storage_write({
        {
            collection = LOBBY_COLLECTION,
            key = LOBBY_KEY,
            user_id = context.user_id,
            value = lobby,
            permission_read = 2,
            permission_write = 0
        }
    })
    return nk.json_encode({ ok = true, active = true, match_id = lobby.match_id })
end

-- RPC: Loest einen Raumcode auf Match-ID und Lobby-Daten auf.
local function rpc_coop_resolve_code(context, payload)
    local req = nk.json_decode(payload or "{}")
    local code = string.upper(tostring(req.room_code or req.code or "")):gsub("[^A-Z0-9]", "")
    if code == "" then
        return nk.json_encode({ ok = false, error = "Raumcode fehlt." })
    end
    local idx = nk.storage_read({
        { collection = ROOM_CODE_COLLECTION, key = code, user_id = SYSTEM_USER_ID }
    })
    if #idx == 0 or not idx[1].value or not idx[1].value.host_user_id then
        return nk.json_encode({ ok = false, error = "Kein aktives Spiel mit diesem Code gefunden." })
    end
    local host_id = tostring(idx[1].value.host_user_id)
    local lobby = read_active_lobby(host_id)
    if not lobby or tostring(lobby.room_code or "") ~= code then
        pcall(nk.storage_delete, { { collection = ROOM_CODE_COLLECTION, key = code, user_id = SYSTEM_USER_ID } })
        return nk.json_encode({ ok = false, error = "Die Koop-Sitzung zu diesem Code ist nicht mehr aktiv." })
    end
    return nk.json_encode({
        ok = true,
        match_id = tostring(lobby.match_id or ""),
        room_code = code,
        world_name = tostring(lobby.world_name or "KOOP-WELT"),
        join_mode = tostring(lobby.join_mode or "ask"),
        max_players = tonumber(lobby.max_players or 4),
        player_count = tonumber(lobby.player_count or 1),
        host_user_id = host_id,
        host_uid = tostring(lobby.host_uid or ""),
        host_name = tostring(lobby.host_name or "")
    })
end

-- RPC: Laedt einen akzeptierten Freund direkt in die eigene aktive Koop-Welt ein.
local function rpc_coop_invite_friend(context, payload)
    local ent_ok, ent_err = require_entitled(context.user_id)
    if not ent_ok then
        return nk.json_encode({ ok = false, error = ent_err })
    end
    local req = nk.json_decode(payload or "{}")
    local lobby = read_active_lobby(context.user_id)
    if not lobby or not lobby.match_id then
        return nk.json_encode({ ok = false, error = "Du hostest aktuell keine aktive Koop-Welt." })
    end
    local target_id = tostring(req.target_user_id or "")
    if target_id == "" then
        local resolved, err = resolve_target_user(req.uid or req.query or "")
        if not resolved then
            return nk.json_encode({ ok = false, error = err or "Freund nicht gefunden." })
        end
        target_id = resolved
    end
    if target_id == context.user_id then
        return nk.json_encode({ ok = false, error = "Du kannst dich nicht selbst einladen." })
    end
    if not are_accepted_friends(context.user_id, target_id) then
        return nk.json_encode({ ok = false, error = "Nur akzeptierte Freunde koennen eingeladen werden." })
    end

    local ok_sig = pcall(nk.match_signal, lobby.match_id, nk.json_encode({
        action = "approve_user",
        user_id = target_id,
        ttl = 600
    }))
    if not ok_sig then
        return nk.json_encode({ ok = false, error = "Koop-Match ist nicht mehr erreichbar." })
    end

    local prof = ensure_user_uid(context.user_id)
    local account = nk.account_get_id(context.user_id)
    local host_name = tostring((account.user.display_name ~= "" and account.user.display_name) or account.user.username or "Freund")
    local content = {
        kind = "coop_invite",
        match_id = tostring(lobby.match_id),
        room_code = tostring(lobby.room_code or ""),
        world_name = tostring(lobby.world_name or "KOOP-WELT"),
        host_user_id = context.user_id,
        host_uid = tostring(prof.uid or ""),
        host_name = host_name,
        join_mode = tostring(lobby.join_mode or "ask"),
        expires_at = os.time() + 600
    }
    nk.notification_send(target_id, host_name .. " laedt dich in die Koop-Welt ein", content, NOTIF_COOP_INVITE, context.user_id, true)
    return nk.json_encode({ ok = true, match_id = lobby.match_id, target_user_id = target_id })
end

-- RPC: Fragt den Beitritt zur Koop-Welt eines Freundes (oder per Code) an / gewaehrt bei "open" direkt Zutritt.
local function rpc_coop_request_join(context, payload)
    local ent_ok, ent_err = require_entitled(context.user_id)
    if not ent_ok then
        return nk.json_encode({ ok = false, error = ent_err })
    end
    local req = nk.json_decode(payload or "{}")
    local host_id = tostring(req.host_user_id or "")
    local by_code = false
    if host_id == "" and req.host_uid and tostring(req.host_uid) ~= "" then
        local resolved = resolve_target_user(tostring(req.host_uid))
        if resolved then
            host_id = resolved
        end
    end
    if host_id == "" and req.room_code and tostring(req.room_code) ~= "" then
        local code = string.upper(tostring(req.room_code)):gsub("[^A-Z0-9]", "")
        local idx = nk.storage_read({
            { collection = ROOM_CODE_COLLECTION, key = code, user_id = SYSTEM_USER_ID }
        })
        if #idx > 0 and idx[1].value and idx[1].value.host_user_id then
            host_id = tostring(idx[1].value.host_user_id)
            by_code = true
        end
    end
    if host_id == "" then
        return nk.json_encode({ ok = false, error = "Host oder Raumcode nicht gefunden." })
    end
    if host_id == context.user_id then
        return nk.json_encode({ ok = false, error = "Das ist deine eigene Koop-Welt." })
    end

    local lobby = read_active_lobby(host_id)
    if not lobby or not lobby.match_id then
        return nk.json_encode({ ok = false, error = "Dieser Spieler hostet aktuell keine Koop-Welt." })
    end

    local is_friend = are_accepted_friends(host_id, context.user_id)
    if not is_friend and not by_code then
        return nk.json_encode({ ok = false, error = "Nur akzeptierte Freunde duerfen beitreten." })
    end

    -- Prüfe zuerst, ob der Caller bereits im Match zugelassen/eingeladen ist
    local ok_chk, sig_res = pcall(nk.match_signal, lobby.match_id, nk.json_encode({
        action = "is_participant_or_approved",
        user_id = context.user_id
    }))
    local already_approved = false
    if ok_chk and sig_res then
        local decoded = nk.json_decode(sig_res)
        already_approved = (decoded and decoded.allowed == true)
    end

    local host_prof = ensure_user_uid(host_id)
    local mode = tostring(lobby.join_mode or host_prof.world_join_mode or "ask")
    if mode == "open" or already_approved then
        pcall(nk.match_signal, lobby.match_id, nk.json_encode({
            action = "approve_user",
            user_id = context.user_id,
            ttl = 600
        }))
        return nk.json_encode({
            ok = true,
            status = "approved",
            match_id = tostring(lobby.match_id),
            room_code = tostring(lobby.room_code or ""),
            world_name = tostring(lobby.world_name or "KOOP-WELT"),
            host_user_id = host_id,
            host_uid = tostring(lobby.host_uid or host_prof.uid or ""),
            host_name = tostring(lobby.host_name or "")
        })
    end

    if mode == "private" then
        return nk.json_encode({ ok = false, error = "Diese Welt ist privat (nur per Einladung)." })
    end

    -- mode == "ask": Anfrage speichern & Host benachrichtigen
    local me_prof = ensure_user_uid(context.user_id)
    local me_acc = nk.account_get_id(context.user_id)
    local me_name = tostring((me_acc.user.display_name ~= "" and me_acc.user.display_name) or me_acc.user.username or "Spieler")
    local req_id = nk.uuid_v4()
    local expires = os.time() + 180
    nk.storage_write({
        {
            collection = JOIN_REQUEST_COLLECTION,
            key = context.user_id,
            user_id = host_id,
            value = {
                request_id = req_id,
                match_id = tostring(lobby.match_id),
                requester_user_id = context.user_id,
                requester_uid = tostring(me_prof.uid or ""),
                requester_name = me_name,
                world_name = tostring(lobby.world_name or "KOOP-WELT"),
                expires_at = expires
            },
            permission_read = 0,
            permission_write = 0
        }
    })
    nk.notification_send(host_id, me_name .. " moechte deiner Welt beitreten", {
        kind = "coop_join_request",
        request_id = req_id,
        match_id = tostring(lobby.match_id),
        requester_user_id = context.user_id,
        requester_uid = tostring(me_prof.uid or ""),
        requester_name = me_name,
        world_name = tostring(lobby.world_name or "KOOP-WELT"),
        expires_at = expires
    }, NOTIF_COOP_JOIN_REQUEST, context.user_id, true)

    return nk.json_encode({
        ok = true,
        status = "requested",
        world_name = tostring(lobby.world_name or "KOOP-WELT"),
        host_user_id = host_id,
        host_uid = tostring(lobby.host_uid or host_prof.uid or ""),
        host_name = tostring(lobby.host_name or "")
    })
end

-- RPC: Host akzeptiert oder lehnt eine Beitrittsanfrage ab.
local function rpc_coop_respond_join_request(context, payload)
    local req = nk.json_decode(payload or "{}")
    local requester_id = tostring(req.requester_user_id or "")
    local accept = (req.accept == true)
    if requester_id == "" then
        return nk.json_encode({ ok = false, error = "requester_user_id fehlt." })
    end

    pcall(nk.storage_delete, {
        { collection = JOIN_REQUEST_COLLECTION, key = requester_id, user_id = context.user_id }
    })

    local prof = ensure_user_uid(context.user_id)
    local acc = nk.account_get_id(context.user_id)
    local host_name = tostring((acc.user.display_name ~= "" and acc.user.display_name) or acc.user.username or "Host")
    local lobby = read_active_lobby(context.user_id)

    if not accept then
        nk.notification_send(requester_id, host_name .. " hat deine Anfrage abgelehnt", {
            kind = "coop_join_declined",
            host_user_id = context.user_id,
            host_uid = tostring(prof.uid or ""),
            host_name = host_name,
            world_name = tostring((lobby and lobby.world_name) or "KOOP-WELT")
        }, NOTIF_COOP_JOIN_DECLINED, context.user_id, true)
        return nk.json_encode({ ok = true, accepted = false })
    end

    if not lobby or not lobby.match_id then
        return nk.json_encode({ ok = false, error = "Deine Koop-Welt ist nicht mehr aktiv." })
    end
    pcall(nk.match_signal, lobby.match_id, nk.json_encode({
        action = "approve_user",
        user_id = requester_id,
        ttl = 600
    }))
    nk.notification_send(requester_id, host_name .. " hat dich eingelassen!", {
        kind = "coop_join_approved",
        match_id = tostring(lobby.match_id),
        room_code = tostring(lobby.room_code or ""),
        world_name = tostring(lobby.world_name or "KOOP-WELT"),
        host_user_id = context.user_id,
        host_uid = tostring(prof.uid or ""),
        host_name = host_name,
        expires_at = os.time() + 600
    }, NOTIF_COOP_JOIN_APPROVED, context.user_id, true)
    return nk.json_encode({ ok = true, accepted = true, match_id = lobby.match_id })
end

-- RPC: Liest den portablen Cloud-Charakter (saves/player_profile) eines teilnehmenden Gastes fuer den Host.
local function rpc_coop_get_peer_character(context, payload)
    local req = nk.json_decode(payload or "{}")
    local target_user_id = tostring(req.target_user_id or "")
    local match_id = tostring(req.match_id or "")
    if target_user_id == "" then
        return nk.json_encode({ ok = false, error = "target_user_id fehlt." })
    end

    local authorized = false
    if match_id ~= "" then
        local lobby = read_active_lobby(context.user_id)
        if lobby and tostring(lobby.match_id or "") == match_id then
            local ok_chk, sig_res = pcall(nk.match_signal, match_id, nk.json_encode({
                action = "is_participant_or_approved",
                user_id = target_user_id
            }))
            if ok_chk and sig_res then
                local decoded = nk.json_decode(sig_res)
                if decoded and decoded.allowed == true then
                    authorized = true
                end
            end
        end
    end
    if not authorized then
        -- Fallback fuer ENet-LAN mit verifiziertem Nakama-Ticket + akzeptierter Freundschaft
        if req.ticket and tostring(req.ticket) ~= "" then
            local objs = nk.storage_read({
                { collection = IDENTITY_TICKET_COLLECTION, key = tostring(req.ticket), user_id = SYSTEM_USER_ID }
            })
            if #objs > 0 and objs[1].value and objs[1].value.user_id == target_user_id and tonumber(objs[1].value.expires_at or 0) >= os.time() then
                authorized = true
            end
        end
    end
    if not authorized and context.user_id == target_user_id then
        authorized = true
    end
    if not authorized then
        return nk.json_encode({ ok = false, error = "Nicht berechtigt, diesen Charakter zu laden." })
    end

    local prof = ensure_user_uid(target_user_id)
    local acc = nk.account_get_id(target_user_id)
    local dname = tostring((acc.user.display_name ~= "" and acc.user.display_name) or acc.user.username or "Gast")
    local objs = nk.storage_read({
        { collection = "saves", key = "player_profile", user_id = target_user_id }
    })
    if #objs == 0 or type(objs[1].value) ~= "table" then
        return nk.json_encode({
            ok = true,
            has_profile = false,
            uid = tostring(prof.uid or ""),
            display_name = dname,
            profile = {}
        })
    end
    return nk.json_encode({
        ok = true,
        has_profile = true,
        uid = tostring(prof.uid or ""),
        display_name = dname,
        profile = objs[1].value
    })
end

-- RPC: Erstellt ein kurzlebiges Einmal-Identitaetsticket (fuer LAN-ENet ohne JWT-Leak).
local function rpc_coop_issue_ticket(context, _payload)
    local ent_ok, ent_err = require_entitled(context.user_id)
    if not ent_ok then
        return nk.json_encode({ ok = false, error = ent_err })
    end
    local prof = ensure_user_uid(context.user_id)
    local acc = nk.account_get_id(context.user_id)
    local dname = tostring((acc.user.display_name ~= "" and acc.user.display_name) or acc.user.username or "Spieler")
    local ticket = nk.uuid_v4()
    nk.storage_write({
        {
            collection = IDENTITY_TICKET_COLLECTION,
            key = ticket,
            user_id = SYSTEM_USER_ID,
            value = {
                user_id = context.user_id,
                uid = tostring(prof.uid or ""),
                role = normalize_role(prof.role),
                display_name = dname,
                expires_at = os.time() + 300
            },
            permission_read = 0,
            permission_write = 0
        }
    })
    return nk.json_encode({
        ok = true,
        ticket = ticket,
        user_id = context.user_id,
        uid = tostring(prof.uid or ""),
        display_name = dname
    })
end

-- RPC: Prueft das Einmal-Identitaetsticket eines Gastes fuer den Host.
local function rpc_coop_verify_ticket(context, payload)
    local req = nk.json_decode(payload or "{}")
    local ticket = tostring(req.ticket or "")
    local claimed_user_id = tostring(req.user_id or "")
    if ticket == "" or claimed_user_id == "" then
        return nk.json_encode({ ok = false, valid = false, error = "Ticket oder user_id fehlt." })
    end
    local objs = nk.storage_read({
        { collection = IDENTITY_TICKET_COLLECTION, key = ticket, user_id = SYSTEM_USER_ID }
    })
    if #objs == 0 or not objs[1].value then
        return nk.json_encode({ ok = false, valid = false, error = "Ticket ungueltig oder abgelaufen." })
    end
    local val = objs[1].value
    if tostring(val.user_id or "") ~= claimed_user_id or tonumber(val.expires_at or 0) < os.time() then
        return nk.json_encode({ ok = false, valid = false, error = "Identitaet stimmt nicht ueberein oder Ticket abgelaufen." })
    end
    return nk.json_encode({
        ok = true,
        valid = true,
        user_id = claimed_user_id,
        uid = tostring(val.uid or ""),
        role = normalize_role(val.role),
        display_name = tostring(val.display_name or "")
    })
end

local function is_valid_sha256_hex(raw)
    local s = string.lower(tostring(raw or "")):gsub("%s+", "")
    return #s == 64 and s:match("^[0-9a-f]+$") ~= nil
end

local function verify_exe_hash_allowed(raw_sha256)
    local norm = string.lower(tostring(raw_sha256 or "")):gsub("%s+", "")
    local objs = nk.storage_read({
        { collection = SYSTEM_CONFIG_COLLECTION, key = BUILD_HASHES_KEY, user_id = SYSTEM_USER_ID }
    })
    local cfg = (#objs > 0 and type(objs[1].value) == "table") and objs[1].value or {}
    local enforce = cfg.enforce == true
    local hashes = type(cfg.hashes) == "table" and cfg.hashes or {}
    if not enforce then
        return true, ""
    end
    if not is_valid_sha256_hex(norm) then
        return false, "Fehlende oder ungueltige Spiel-Signatur (SHA-256). Bitte ueber den Launcher starten."
    end
    if hashes[norm] == nil then
        return false, "Veraltete oder manipulierte Shadowspore.exe. Bitte Launcher-Update ausfuehren."
    end
    return true, ""
end

local function resolve_target_user_id(req)
    local direct = tostring(req.target_user_id or req.user_id or ""):match("^%s*(.-)%s*$")
    if direct ~= "" then
        if direct:match("^%d+$") then
            local objs = nk.storage_read({
                { collection = "uid_index", key = direct, user_id = SYSTEM_USER_ID }
            })
            if #objs > 0 and type(objs[1].value) == "table" and objs[1].value.owner_id then
                return tostring(objs[1].value.owner_id)
            end
        elseif #direct == 36 and direct:match("^[0-9a-fA-F%-]+$") then
            return direct
        end
    end
    local target_uid = tostring(req.target_uid or req.uid or ""):match("^%s*(.-)%s*$")
    if target_uid ~= "" then
        if target_uid:match("^%d+$") then
            local objs = nk.storage_read({
                { collection = "uid_index", key = target_uid, user_id = SYSTEM_USER_ID }
            })
            if #objs > 0 and type(objs[1].value) == "table" then
                return tostring(objs[1].value.owner_id or "")
            end
        end
        local resolved_by_name = resolve_target_user(target_uid)
        if resolved_by_name and resolved_by_name ~= "" then
            return resolved_by_name
        end
    end
    local q = tostring(req.query or req.username or direct or ""):match("^%s*(.-)%s*$")
    if q ~= "" then
        if q:find("@", 1, true) and type(nk.sql_query) == "function" then
            local ok_q, rows = pcall(nk.sql_query, "SELECT id::text AS uid FROM users WHERE LOWER(email) = $1 LIMIT 1", { string.lower(q) })
            if ok_q and type(rows) == "table" and #rows > 0 and rows[1].uid then
                return tostring(rows[1].uid)
            end
        end
        local resolved_q = resolve_target_user(q)
        if resolved_q and resolved_q ~= "" then
            return resolved_q
        end
    end
    return ""
end

local function is_game_session_active(user_id, expected_nonce)
    local objs = nk.storage_read({
        { collection = GAME_SESSIONS_COLLECTION, key = GAME_SESSION_KEY, user_id = user_id }
    })
    if #objs == 0 or type(objs[1].value) ~= "table" then
        return false, nil, nil
    end
    local sess = objs[1].value
    if expected_nonce and expected_nonce ~= "" and tostring(sess.session_nonce or "") ~= expected_nonce then
        return false, sess, objs[1].version
    end
    return true, sess, objs[1].version
end

-- RPC: Loest einen Lizenzkey fuer den bereits eingeloggten Account ein.
local function rpc_redeem_license_key(context, payload)
    if not context.user_id or context.user_id == "" then
        return nk.json_encode({ ok = false, error = "Nicht angemeldet." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local ok, err = claim_license_key_for_user(context.user_id, req.license_key or req.key or "")
    if not ok then
        return nk.json_encode({ ok = false, error = err })
    end
    local lic_ok, lic_err, ent = check_entitlement_status(context.user_id)
    local prof = ensure_user_uid(context.user_id)
    return nk.json_encode({
        ok = true,
        license_active = lic_ok,
        license_edition = tostring(ent.edition or "standard"),
        license_expires_at = tonumber(ent.expires_at or 0) or 0,
        license_error = lic_err,
        role = normalize_role(prof.role)
    })
end

-- RPC: Stellt im Launcher ein kurzlebiges Einmal-Startticket fuer Shadowspore.exe aus.
local function rpc_issue_launch_ticket(context, payload)
    local lic_ok, lic_err = require_entitled(context.user_id)
    if not lic_ok then
        return nk.json_encode({ ok = false, error = lic_err })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local exe_sha256 = string.lower(tostring(req.exe_sha256 or "")):gsub("%s+", "")
    local hash_ok, hash_err = verify_exe_hash_allowed(exe_sha256)
    if not hash_ok then
        pcall(record_security_event, context.user_id, "EXE_HASH_MISMATCH", exe_sha256 .. " (launcher)")
        return nk.json_encode({ ok = false, error = hash_err })
    end

    local now = os.time()
    local ticket = "LT-" .. nk.uuid_v4():gsub("-", "")
    nk.storage_write({
        {
            collection = LAUNCH_TICKETS_COLLECTION,
            key = ticket,
            user_id = SYSTEM_USER_ID,
            value = {
                ticket = ticket,
                user_id = context.user_id,
                exe_sha256 = exe_sha256,
                build_version = tostring(req.build_version or ""):sub(1, 32),
                launcher_version = tostring(req.launcher_version or ""):sub(1, 32),
                issued_at = now,
                expires_at = now + LAUNCH_TICKET_TTL_SEC,
                used = false
            },
            permission_read = 0,
            permission_write = 0
        }
    })
    return nk.json_encode({
        ok = true,
        ticket = ticket,
        expires_in = LAUNCH_TICKET_TTL_SEC
    })
end

-- RPC: Loest ein Einmal-Launch-Ticket im Spiel ein und startet eine aktive Online-Sitzung.
local function rpc_redeem_launch_ticket(context, payload)
    local lic_ok, lic_err, ent = require_entitled(context.user_id)
    if not lic_ok then
        return nk.json_encode({ ok = false, error = lic_err })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local ticket = tostring(req.ticket or "")
    local client_exe_sha = string.lower(tostring(req.exe_sha256 or "")):gsub("%s+", "")

    if ticket == "" then
        pcall(record_security_event, context.user_id, "MISSING_LAUNCH_TICKET", "Direct launch attempt")
        return nk.json_encode({ ok = false, error = "Kein Launcher-Startticket vorhanden. Bitte ueber den Shadowspore Launcher starten." })
    end

    local objs = nk.storage_read({
        { collection = LAUNCH_TICKETS_COLLECTION, key = ticket, user_id = SYSTEM_USER_ID }
    })
    if #objs == 0 or type(objs[1].value) ~= "table" then
        return nk.json_encode({ ok = false, error = "Startticket ungueltig oder unbekannt." })
    end
    local val = objs[1].value
    if tostring(val.user_id or "") ~= context.user_id then
        pcall(record_security_event, context.user_id, "LAUNCH_TICKET_USER_MISMATCH", ticket)
        return nk.json_encode({ ok = false, error = "Startticket gehoert zu einem anderen Account." })
    end
    if val.used == true then
        pcall(record_security_event, context.user_id, "LAUNCH_TICKET_REPLAY", ticket)
        return nk.json_encode({ ok = false, error = "Startticket wurde bereits verwendet (Replay blockiert)." })
    end
    local now = os.time()
    if now > (tonumber(val.expires_at or 0) or 0) then
        return nk.json_encode({ ok = false, error = "Startticket ist abgelaufen. Bitte ueber den Launcher neu starten." })
    end

    local hash_ok, hash_err = verify_exe_hash_allowed(client_exe_sha)
    if not hash_ok then
        pcall(record_security_event, context.user_id, "EXE_HASH_MISMATCH", client_exe_sha .. " (game)")
        return nk.json_encode({ ok = false, error = hash_err })
    end
    if val.exe_sha256 and val.exe_sha256 ~= "" and val.exe_sha256 ~= client_exe_sha then
        pcall(record_security_event, context.user_id, "LAUNCHER_GAME_HASH_DIFF", val.exe_sha256 .. " != " .. client_exe_sha)
        return nk.json_encode({ ok = false, error = "Spieldatei stimmt nicht mit dem Launcher-Check ueberein." })
    end

    val.used = true
    val.used_at = now
    local ok_consume = pcall(nk.storage_write, {
        {
            collection = LAUNCH_TICKETS_COLLECTION,
            key = ticket,
            user_id = SYSTEM_USER_ID,
            value = val,
            version = objs[1].version,
            permission_read = 0,
            permission_write = 0
        }
    })
    if not ok_consume then
        return nk.json_encode({ ok = false, error = "Startticket konnte nicht atomar eingeloest werden." })
    end

    local nonce = "GS-" .. nk.uuid_v4():gsub("-", "")
    nk.storage_write({
        {
            collection = GAME_SESSIONS_COLLECTION,
            key = GAME_SESSION_KEY,
            user_id = context.user_id,
            value = {
                session_nonce = nonce,
                started_at = now,
                last_heartbeat_at = now,
                client_uptime_sec = 0,
                warnings = 0,
                exe_sha256 = client_exe_sha ~= "" and client_exe_sha or tostring(val.exe_sha256 or ""),
                build_version = tostring(val.build_version or "")
            },
            permission_read = 1,
            permission_write = 0
        }
    })
    return nk.json_encode({
        ok = true,
        session_nonce = nonce,
        heartbeat_interval = 25,
        grace_seconds = 60,
        server_time = now,
        license_edition = tostring(ent.edition or "standard")
    })
end

-- RPC: Regelmaessiger Online-Heartbeat & Speedhack-/Session-Pruefung.
local function rpc_game_heartbeat(context, payload)
    local lic_ok, lic_err = require_entitled(context.user_id)
    if not lic_ok then
        return nk.json_encode({ ok = false, kick = true, code = "NOT_ENTITLED", error = lic_err })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local nonce = tostring(req.session_nonce or "")
    local is_debug = req.debug_session == true
    local active, sess, sess_ver = is_game_session_active(context.user_id, nonce)
    local now = os.time()

    if not active then
        if is_debug and nonce ~= "" then
            local prof = ensure_user_uid(context.user_id)
            local role = normalize_role(prof.role)
            if (role == "admin" or role == "tester") and nonce:sub(1, 4) == "DEV-" then
                sess = {
                    session_nonce = nonce,
                    started_at = now,
                    last_heartbeat_at = now,
                    client_uptime_sec = tonumber(req.client_uptime_sec or 0) or 0,
                    warnings = 0,
                    role = role,
                    debug = true
                }
                sess_ver = nil
            else
                pcall(record_security_event, context.user_id, "DEBUG_SESSION_BYPASS",
                    "role=" .. role .. " nonce=" .. nonce:sub(1, 32), "critical")
                invalidate_user_online_state(context.user_id)
                return nk.json_encode({
                    ok = false,
                    kick = true,
                    code = "DEBUG_SESSION_FORBIDDEN",
                    error = "Direktstart / Debug-Modus ist nur fuer Admins und Tester erlaubt."
                })
            end
        else
            return nk.json_encode({
                ok = false,
                kick = true,
                code = "SESSION_REPLACED",
                error = "Deine Spielsitzung ist abgelaufen oder wurde an einem anderen Ort gestartet."
            })
        end
    end

    if req.tamper_flag and tostring(req.tamper_flag) ~= "" then
        pcall(record_security_event, context.user_id, "CLIENT_TAMPER", tostring(req.tamper_flag))
        invalidate_user_online_state(context.user_id)
        return nk.json_encode({
            ok = false,
            kick = true,
            code = "TAMPER_DETECTED",
            error = "Anti-Cheat: Manipulation erkannt."
        })
    end

    if not is_debug then
        local sess_sha = tostring(sess.exe_sha256 or "")
        local hash_ok, hash_err = verify_exe_hash_allowed(sess_sha)
        if not hash_ok then
            pcall(record_security_event, context.user_id, "EXE_HASH_OUTDATED_MIDGAME",
                sess_sha:sub(1, 16) .. " nonce=" .. nonce:sub(1, 16), "warn")
            invalidate_user_online_state(context.user_id)
            return nk.json_encode({
                ok = false,
                kick = true,
                code = "BUILD_OUTDATED",
                error = hash_err
            })
        end
    end

    local prev_server = tonumber(sess.last_heartbeat_at or now) or now
    local prev_uptime = tonumber(sess.client_uptime_sec or 0) or 0
    local client_uptime = tonumber(req.client_uptime_sec or prev_uptime) or prev_uptime
    local server_delta = now - prev_server
    local client_delta = client_uptime - prev_uptime
    local warnings = tonumber(sess.warnings or 0) or 0

    if client_uptime < (prev_uptime - 5.0) then
        pcall(record_security_event, context.user_id, "CLOCK_ROLLBACK",
            string.format("prev=%.1f now=%.1f", prev_uptime, client_uptime), "warn")
    end

    if server_delta >= 5 and client_delta > (server_delta * 1.65 + 8.0) then
        warnings = warnings + 1
        pcall(record_security_event, context.user_id, "SPEEDHACK_SUSPECT",
            string.format("server_dt=%.1f client_dt=%.1f warn=%d", server_delta, client_delta, warnings))
        if warnings >= 3 then
            invalidate_user_online_state(context.user_id)
            return nk.json_encode({
                ok = false,
                kick = true,
                code = "SPEEDHACK",
                error = "Anti-Cheat: Zeitmanipulation erkannt."
            })
        end
    end

    sess.last_heartbeat_at = now
    sess.client_uptime_sec = math.max(prev_uptime, client_uptime)
    sess.warnings = warnings
    local write_req = {
        collection = GAME_SESSIONS_COLLECTION,
        key = GAME_SESSION_KEY,
        user_id = context.user_id,
        value = sess,
        permission_read = 1,
        permission_write = 0
    }
    if sess_ver then
        write_req.version = sess_ver
    end
    nk.storage_write({ write_req })

    return nk.json_encode({
        ok = true,
        server_time = now,
        license_active = true
    })
end

-- RPC: Beendet die aktive Online-Spielsitzung sauber.
local function rpc_end_game_session(context, payload)
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local nonce = tostring(req.session_nonce or "")
    local active = is_game_session_active(context.user_id, nonce)
    if active or nonce == "" then
        pcall(nk.storage_delete, {
            { collection = GAME_SESSIONS_COLLECTION, key = GAME_SESSION_KEY, user_id = context.user_id }
        })
    end
    return nk.json_encode({ ok = true })
end

local CLIENT_TELEMETRY_KINDS = {
    MISSING_LAUNCH_TICKET = true,
    EXE_HASH_MISMATCH = true,
    LAUNCHER_CHEAT_TOOL = true,
    LAUNCHER_CHEAT_TOOL_RUNTIME = true,
    ENGINE_TIME_SCALE = true,
    CLIENT_CLOCK_DRIFT = true,
    STAT_CANARY_BOUNDS = true,
    HP_CANARY_BOUNDS = true,
    CLIENT_REPORT = true
}

-- RPC: Meldet Client-/Launcher-Sicherheitsereignisse an das Server-Audit-Log.
local function rpc_report_security_event(context, payload)
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local raw_kind = string.upper(tostring(req.kind or "CLIENT_REPORT"):gsub("[^%w_]", "_"):sub(1, 56))
    if raw_kind == "" then
        raw_kind = "CLIENT_REPORT"
    end
    local uid = tostring(context.user_id or "")
    local allowed_admin = false
    if uid == "" then
        allowed_admin = true
    else
        local prof = ensure_user_uid(uid)
        allowed_admin = normalize_role(prof.role) == "admin"
    end
    local kind = raw_kind
    if not allowed_admin and not CLIENT_TELEMETRY_KINDS[raw_kind] then
        kind = ("CLIENT_" .. raw_kind):sub(1, 64)
    end
    local detail = tostring(req.detail or ""):sub(1, 240)
    local sev = (req.severity == "critical" or req.severity == "warn" or req.severity == "info") and req.severity or nil

    -- Drosselung pro User fuer nicht-kritische Events gegen Log-Flooding
    local now = os.time()
    if uid ~= "" and sev ~= "critical" then
        local rl_objs = nk.storage_read({
            { collection = SECURITY_EVENTS_COLLECTION, key = "rl_" .. uid, user_id = SYSTEM_USER_ID }
        })
        local last_at = (#rl_objs > 0 and type(rl_objs[1].value) == "table") and (tonumber(rl_objs[1].value.at or 0) or 0) or 0
        if (now - last_at) < 4 then
            return nk.json_encode({ ok = true, throttled = true })
        end
        pcall(nk.storage_write, {
            {
                collection = SECURITY_EVENTS_COLLECTION,
                key = "rl_" .. uid,
                user_id = SYSTEM_USER_ID,
                value = { at = now },
                permission_read = 0,
                permission_write = 0
            }
        })
    end

    pcall(record_security_event, uid, kind, detail, sev)
    if req.severity == "critical" and uid ~= "" then
        invalidate_user_online_state(uid)
    end
    return nk.json_encode({ ok = true })
end

-- RPC: Server-validierter Cloud-Save fuer Spielerprofil (blockt direkte Storage-Writes).
local function rpc_save_cloud_player(context, payload)
    local lic_ok, lic_err = require_entitled(context.user_id)
    if not lic_ok then
        return nk.json_encode({ ok = false, error = lic_err })
    end
    if not payload or #payload > 524288 then
        return nk.json_encode({ ok = false, error = "Spielstand zu gross oder leer." })
    end
    local req = nk.json_decode(payload)
    local data = (type(req) == "table" and type(req.data) == "table") and req.data or req
    if type(data) ~= "table" then
        return nk.json_encode({ ok = false, error = "Ungueltiges Spielerprofil-Format." })
    end

    local prof = ensure_user_uid(context.user_id)
    local role = normalize_role(prof.role)
    local copper = tonumber(data.copper or 0) or 0
    local xp = tonumber(data.xp or 0) or 0
    local claimed = tonumber(data.claimed or 1) or 1
    local health = tonumber(data.health or 1) or 1

    if copper < 0 or copper > 500000000 or xp < 0 or xp > 500000000 or claimed < 1 or claimed > 150 or health < 0 or health > 50000 then
        pcall(record_security_event, context.user_id, "SAVE_BOUNDS",
            string.format("copper=%s xp=%s claimed=%s hp=%s", tostring(copper), tostring(xp), tostring(claimed), tostring(health)))
        return nk.json_encode({ ok = false, cheat_detected = true, error = "Ungueltige Spielerwerte erkannt." })
    end

    if role ~= "admin" and role ~= "tester" then
        local prev_objs = nk.storage_read({
            { collection = "saves", key = "player_profile", user_id = context.user_id }
        })
        local prev = (#prev_objs > 0 and type(prev_objs[1].value) == "table") and prev_objs[1].value or {}
        local prev_ts = tonumber(prev.server_updated_at or 0) or 0
        local now = os.time()
        local elapsed = (prev_ts > 0) and math.max(1, now - prev_ts) or 300
        local d_copper = copper - (tonumber(prev.copper or 0) or 0)
        local d_xp = xp - (tonumber(prev.xp or 0) or 0)
        local d_claimed = claimed - (tonumber(prev.claimed or 1) or 1)
        local max_copper_gain = math.max(100000, elapsed * 500)
        local max_xp_gain = math.max(50000, elapsed * 400)
        local max_level_gain = math.max(5, math.floor(elapsed / 20))

        if d_copper > max_copper_gain or d_xp > max_xp_gain or d_claimed > max_level_gain then
            pcall(record_security_event, context.user_id, "SAVE_ANOMALY",
                string.format("dt=%d d_copper=%d d_xp=%d d_claimed=%d", elapsed, d_copper, d_xp, d_claimed))
            return nk.json_encode({
                ok = false,
                cheat_detected = true,
                error = "Anti-Cheat: Unplausibler Spielfortschritt erkannt."
            })
        end
    end

    data.server_updated_at = os.time()
    nk.storage_write({
        {
            collection = "saves",
            key = "player_profile",
            user_id = context.user_id,
            value = data,
            permission_read = 1,
            permission_write = 0
        }
    })
    return nk.json_encode({ ok = true, saved_at = data.server_updated_at })
end

-- RPC: Server-validierter Cloud-Save fuer Weltzustand.
local function rpc_save_cloud_world(context, payload)
    local lic_ok, lic_err = require_entitled(context.user_id)
    if not lic_ok then
        return nk.json_encode({ ok = false, error = lic_err })
    end
    if not payload or #payload > 1572864 then
        return nk.json_encode({ ok = false, error = "Welt-Spielstand zu gross oder leer." })
    end
    local req = nk.json_decode(payload)
    local data = (type(req) == "table" and type(req.data) == "table") and req.data or req
    if type(data) ~= "table" then
        return nk.json_encode({ ok = false, error = "Ungueltiges Welt-Format." })
    end

    local version = math.floor(tonumber(data.version or 1) or -1)
    local day = math.floor(tonumber(data.day or 0) or -1)
    local time_val = tonumber(data.time or 0) or -1
    local level = math.floor(tonumber(data.level or 1) or -1)
    local saved_at = math.floor(tonumber(data.saved_at or os.time()) or os.time())
    local gz = type(data.gz) == "string" and data.gz:gsub("%s+", "") or ""

    if version < 1 or version > 100 or day < 0 or day > 100000 or time_val < 0 or time_val > 86400 or level < 1 or level > 150 then
        pcall(record_security_event, context.user_id, "WORLD_SAVE_INVALID",
            string.format("ver=%s day=%s time=%s lvl=%s", tostring(version), tostring(day), tostring(time_val), tostring(level)), "warn")
        return nk.json_encode({ ok = false, cheat_detected = true, error = "Ungueltige Welt-Metadaten erkannt." })
    end

    if gz == "" or #gz > 1400000 then
        pcall(record_security_event, context.user_id, "WORLD_SAVE_INVALID", "gz_empty_or_oversize", "warn")
        return nk.json_encode({ ok = false, cheat_detected = true, error = "Welt-Archiv ungueltig oder zu gross." })
    end

    local ok_b64, raw_gz = pcall(nk.base64_decode, gz)
    if not ok_b64 or type(raw_gz) ~= "string" or #raw_gz < 18 or #raw_gz > 1100000 then
        pcall(record_security_event, context.user_id, "WORLD_SAVE_INVALID", "invalid_base64_or_size", "warn")
        return nk.json_encode({ ok = false, cheat_detected = true, error = "Welt-Archiv beschaedigt (Base64)." })
    end
    local b1, b2 = string.byte(raw_gz, 1, 2)
    if b1 ~= 0x1f or b2 ~= 0x8b then
        pcall(record_security_event, context.user_id, "WORLD_SAVE_INVALID", "invalid_gzip_magic", "warn")
        return nk.json_encode({ ok = false, cheat_detected = true, error = "Welt-Archiv beschaedigt (Kein gueltiges GZIP-Format)." })
    end

    local prof = ensure_user_uid(context.user_id)
    local role = normalize_role(prof.role)
    local now = os.time()
    if role ~= "admin" and role ~= "tester" then
        local existing_objs = nk.storage_read({
            { collection = "saves", key = "world_state", user_id = context.user_id },
            { collection = "saves", key = "player_profile", user_id = context.user_id }
        })
        local prev_world = nil
        local prev_player = nil
        for _, obj in ipairs(existing_objs) do
            if obj.key == "world_state" and type(obj.value) == "table" then
                prev_world = obj.value
            elseif obj.key == "player_profile" and type(obj.value) == "table" then
                prev_player = obj.value
            end
        end

        local profile_claimed = prev_player and (tonumber(prev_player.claimed or 1) or 1) or 1
        if prev_player and level > (profile_claimed + 15) then
            pcall(record_security_event, context.user_id, "WORLD_LEVEL_MISMATCH",
                string.format("world_lvl=%d profile_claimed=%d", level, profile_claimed), "warn")
            return nk.json_encode({
                ok = false,
                cheat_detected = true,
                error = "Anti-Cheat: Welt-Level weicht unplausibel vom Spielerprofil ab."
            })
        end

        if prev_world then
            local prev_ts = tonumber(prev_world.server_updated_at or 0) or 0
            local elapsed = (prev_ts > 0) and math.max(1, now - prev_ts) or 300
            local prev_day = tonumber(prev_world.day or 0) or 0
            local prev_lvl = tonumber(prev_world.level or 1) or 1
            local d_day = day - prev_day
            local d_lvl = level - prev_lvl
            local max_day_gain = math.max(12, math.floor(elapsed / 5))
            local max_lvl_gain = math.max(5, math.floor(elapsed / 20))
            if d_day > max_day_gain or d_lvl > max_lvl_gain then
                pcall(record_security_event, context.user_id, "WORLD_SAVE_ANOMALY",
                    string.format("dt=%d d_day=%d d_lvl=%d", elapsed, d_day, d_lvl), "warn")
                return nk.json_encode({
                    ok = false,
                    cheat_detected = true,
                    error = "Anti-Cheat: Unplausibler Welt-Fortschritt erkannt."
                })
            end
        elseif day > 60 or (level > 15 and level > (profile_claimed + 5)) then
            pcall(record_security_event, context.user_id, "WORLD_INIT_ANOMALY",
                string.format("day=%d level=%d", day, level), "warn")
            return nk.json_encode({
                ok = false,
                cheat_detected = true,
                error = "Anti-Cheat: Unplausibler Startzustand fuer neue Cloud-Welt."
            })
        end
    end

    local sanitized = {
        version = version,
        day = day,
        time = time_val,
        level = level,
        saved_at = saved_at,
        gz = gz,
        server_updated_at = now
    }
    nk.storage_write({
        {
            collection = "saves",
            key = "world_state",
            user_id = context.user_id,
            value = sanitized,
            permission_read = 1,
            permission_write = 0
        }
    })
    return nk.json_encode({ ok = true, saved_at = sanitized.server_updated_at })
end

-- RPC: Loescht den Cloud-Spielstand sauber auf Serverseite.
local function rpc_wipe_cloud_save(context, _payload)
    local lic_ok, lic_err = require_entitled(context.user_id)
    if not lic_ok then
        return nk.json_encode({ ok = false, error = lic_err })
    end
    pcall(nk.storage_delete, {
        { collection = "saves", key = "player_profile", user_id = context.user_id },
        { collection = "saves", key = "world_state", user_id = context.user_id }
    })
    return nk.json_encode({ ok = true })
end

-- ADMIN RPC: Erzeugt neue Lizenzkeys (SHADOW-XXXX-XXXX-XXXX).
local function rpc_admin_issue_license_key(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins duerfen Lizenzkeys erzeugen." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local count = math.max(1, math.min(50, math.floor(tonumber(req.count or 1) or 1)))
    local edition = tostring(req.edition or "standard"):sub(1, 32)
    local role_grant = normalize_role(req.role_grant or req.role or "player")
    local note = tostring(req.note or ""):sub(1, 120)
    local expires_days = tonumber(req.expires_days or 0) or 0
    local user_expires_days = tonumber(req.user_expires_days or 0) or 0
    local now = os.time()
    local key_exp = (expires_days > 0) and (now + math.floor(expires_days * 86400)) or 0
    local user_exp = (user_expires_days > 0) and (now + math.floor(user_expires_days * 86400)) or 0

    local created_keys = {}
    for _ = 1, count do
        local key = generate_license_key()
        local rec = {
            key = key,
            status = "unused",
            edition = edition,
            role_grant = role_grant,
            note = note,
            created_by = tostring(context.user_id or "server"),
            created_at = now,
            expires_at = key_exp,
            user_expires_at = user_exp,
            claimed_by = "",
            claimed_at = 0
        }
        nk.storage_write({
            {
                collection = LICENSE_KEYS_COLLECTION,
                key = key,
                user_id = SYSTEM_USER_ID,
                value = rec,
                permission_read = 0,
                permission_write = 0
            }
        })
        pcall(append_bounded_index, LICENSE_KEYS_COLLECTION, LICENSE_INDEX_KEY, key, 200)
        table.insert(created_keys, rec)
    end
    return nk.json_encode({ ok = true, keys = created_keys })
end

-- ADMIN RPC: Listet kuerzlich erzeugte Lizenzkeys auf (mit UID/Namen der Einloeser).
local function rpc_admin_list_license_keys(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local status_filter = string.lower(tostring(req.status or "all"))
    local query_filter = string.lower(tostring(req.query or "")):match("^%s*(.-)%s*$")
    local idx_objs = nk.storage_read({
        { collection = LICENSE_KEYS_COLLECTION, key = LICENSE_INDEX_KEY, user_id = SYSTEM_USER_ID }
    })
    if #idx_objs == 0 or type(idx_objs[1].value) ~= "table" or type(idx_objs[1].value.ids) ~= "table" then
        return nk.json_encode({ ok = true, keys = {} })
    end
    local reads = {}
    for _, key_id in ipairs(idx_objs[1].value.ids) do
        table.insert(reads, { collection = LICENSE_KEYS_COLLECTION, key = tostring(key_id), user_id = SYSTEM_USER_ID })
    end
    local objs = (#reads > 0) and nk.storage_read(reads) or {}
    local by_key = {}
    local claimer_ids = {}
    for _, o in ipairs(objs) do
        if type(o.value) == "table" and o.value.key then
            by_key[o.value.key] = o.value
            if o.value.claimed_by and o.value.claimed_by ~= "" then
                table.insert(claimer_ids, tostring(o.value.claimed_by))
            end
        end
    end
    local meta = load_user_meta_map(claimer_ids)
    local out = {}
    for _, key_id in ipairs(idx_objs[1].value.ids) do
        local rec = by_key[key_id]
        if rec and (status_filter == "all" or status_filter == "" or rec.status == status_filter) then
            local cid = tostring(rec.claimed_by or "")
            local cm = meta[cid]
            local enriched = {
                key = tostring(rec.key or ""),
                status = tostring(rec.status or "unused"),
                edition = tostring(rec.edition or "standard"),
                role_grant = tostring(rec.role_grant or "player"),
                note = tostring(rec.note or ""),
                created_by = tostring(rec.created_by or ""),
                created_at = tonumber(rec.created_at or 0) or 0,
                expires_at = tonumber(rec.expires_at or 0) or 0,
                claimed_by = cid,
                claimed_by_uid = cm and tostring(cm.uid or "") or "",
                claimed_by_name = cm and tostring(cm.display_name or cm.username or "") or "",
                claimed_at = tonumber(rec.claimed_at or 0) or 0
            }
            if query_filter == "" then
                table.insert(out, enriched)
            else
                local hay = string.lower(
                    enriched.key .. " " .. enriched.note .. " " .. enriched.edition .. " " .. enriched.role_grant
                    .. " " .. enriched.claimed_by_uid .. " " .. enriched.claimed_by_name
                )
                if hay:find(query_filter, 1, true) then
                    table.insert(out, enriched)
                end
            end
        end
    end
    return nk.json_encode({ ok = true, keys = out })
end

-- ADMIN RPC: Widerruft einen Lizenzkey und/oder aktiviert/deaktiviert eine Account-Lizenz.
local function rpc_admin_set_license(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local key_raw = normalize_license_key(req.license_key or req.key or "")
    local target_user_id = resolve_target_user_id(req)

    if key_raw ~= "" then
        local objs = nk.storage_read({
            { collection = LICENSE_KEYS_COLLECTION, key = key_raw, user_id = SYSTEM_USER_ID }
        })
        if #objs > 0 and type(objs[1].value) == "table" then
            local rec = objs[1].value
            local new_status = tostring(req.key_status or "revoked")
            rec.status = new_status
            nk.storage_write({
                {
                    collection = LICENSE_KEYS_COLLECTION,
                    key = key_raw,
                    user_id = SYSTEM_USER_ID,
                    value = rec,
                    version = objs[1].version,
                    permission_read = 0,
                    permission_write = 0
                }
            })
            if target_user_id == "" and rec.claimed_by and rec.claimed_by ~= "" and new_status == "revoked" then
                target_user_id = rec.claimed_by
            end
        end
    end

    if target_user_id ~= "" then
        local ent, ver = read_entitlement(target_user_id)
        local active = (req.active ~= nil) and (req.active == true) or false
        ent.active = active
        if req.edition and tostring(req.edition) ~= "" then
            ent.edition = tostring(req.edition):sub(1, 32)
        end
        if active and (tonumber(ent.activated_at or 0) or 0) == 0 then
            ent.activated_at = os.time()
        end
        write_entitlement(target_user_id, ent, ver)
        if not active then
            invalidate_user_online_state(target_user_id)
        end
        pcall(record_security_event, target_user_id, "ADMIN_SET_LICENSE", "active=" .. tostring(active) .. " by=" .. tostring(context.user_id or "server"), "warn")
    elseif key_raw ~= "" then
        pcall(record_security_event, context.user_id or "server", "ADMIN_KEY_STATUS", "key=" .. key_raw .. " status=" .. tostring(req.key_status or "revoked"), "warn")
    end

    return nk.json_encode({ ok = true, target_user_id = target_user_id })
end

-- ADMIN RPC: Sperrt oder entsperrt ein Konto permanent/sofort.
local function rpc_admin_set_ban(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local target_user_id = resolve_target_user_id(req)
    if target_user_id == "" then
        return nk.json_encode({ ok = false, error = "Ziel-Account nicht gefunden." })
    end
    local banned = (req.banned == true)
    local reason = tostring(req.reason or (banned and "Verstoss gegen die Nutzungsbedingungen" or "")):sub(1, 200)
    local ent, ver = read_entitlement(target_user_id)
    ent.banned = banned
    ent.ban_reason = banned and reason or ""
    if banned then
        ent.banned_at = os.time()
        ent.banned_by = tostring(context.user_id or "server")
    end
    write_entitlement(target_user_id, ent, ver)
    if banned then
        pcall(record_security_event, target_user_id, "ACCOUNT_BANNED", reason)
        invalidate_user_online_state(target_user_id)
        local lobby = read_active_lobby(target_user_id)
        if lobby and lobby.match_id then
            pcall(nk.match_signal, tostring(lobby.match_id), nk.json_encode({ action = "close" }))
        end
    else
        pcall(record_security_event, target_user_id, "ACCOUNT_UNBANNED", "")
    end
    return nk.json_encode({ ok = true, target_user_id = target_user_id, banned = banned, reason = ent.ban_reason })
end

local function build_hashes_sorted_list(hashes)
    local list = {}
    for sha, meta in pairs(hashes or {}) do
        if type(meta) == "table" then
            table.insert(list, {
                sha256 = tostring(sha),
                version = tostring(meta.version or ""),
                added_at = tonumber(meta.added_at or 0) or 0
            })
        end
    end
    table.sort(list, function(a, b)
        if a.added_at ~= b.added_at then
            return a.added_at > b.added_at
        end
        return a.sha256 < b.sha256
    end)
    return list
end

-- ADMIN RPC: Liest die aktuelle Build-Hash-Konfiguration ohne Aenderung.
local function rpc_admin_get_build_config(context, _payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local objs = nk.storage_read({
        { collection = SYSTEM_CONFIG_COLLECTION, key = BUILD_HASHES_KEY, user_id = SYSTEM_USER_ID }
    })
    local cfg = (#objs > 0 and type(objs[1].value) == "table") and objs[1].value or { enforce = false, hashes = {} }
    local hashes = type(cfg.hashes) == "table" and cfg.hashes or {}
    return nk.json_encode({
        ok = true,
        enforce = (cfg.enforce == true),
        hashes = hashes,
        hash_list = build_hashes_sorted_list(hashes)
    })
end

-- ADMIN RPC: Registriert oder entfernt gueltige Build SHA-256 Hashes fuer Shadowspore.exe.
local function rpc_admin_register_build(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local objs = nk.storage_read({
        { collection = SYSTEM_CONFIG_COLLECTION, key = BUILD_HASHES_KEY, user_id = SYSTEM_USER_ID }
    })
    local cfg = (#objs > 0 and type(objs[1].value) == "table") and objs[1].value or { enforce = false, hashes = {} }
    if type(cfg.hashes) ~= "table" then
        cfg.hashes = {}
    end
    local dirty = false
    if req.clear == true then
        cfg.hashes = {}
        dirty = true
    end
    local rem_sha = string.lower(tostring(req.remove_sha256 or "")):gsub("%s+", "")
    if rem_sha ~= "" then
        if not is_valid_sha256_hex(rem_sha) then
            return nk.json_encode({ ok = false, error = "Ungueltiger SHA-256 Hash zum Entfernen." })
        end
        if cfg.hashes[rem_sha] ~= nil then
            cfg.hashes[rem_sha] = nil
            dirty = true
        end
    end
    local sha = string.lower(tostring(req.exe_sha256 or "")):gsub("%s+", "")
    if sha ~= "" then
        if not is_valid_sha256_hex(sha) then
            return nk.json_encode({ ok = false, error = "Ungueltiger SHA-256 Hash." })
        end
        cfg.hashes[sha] = {
            version = tostring(req.version or ""):sub(1, 32),
            added_at = os.time()
        }
        dirty = true
    end
    if req.enforce ~= nil then
        local new_enforce = (req.enforce == true)
        if cfg.enforce ~= new_enforce then
            cfg.enforce = new_enforce
            dirty = true
        end
    end
    if dirty then
        local write_req = {
            collection = SYSTEM_CONFIG_COLLECTION,
            key = BUILD_HASHES_KEY,
            user_id = SYSTEM_USER_ID,
            value = cfg,
            permission_read = 0,
            permission_write = 0
        }
        if #objs > 0 and objs[1].version then
            write_req.version = objs[1].version
        end
        nk.storage_write({ write_req })
        pcall(record_security_event, context.user_id or "server", "ADMIN_BUILD_CONFIG",
            "enforce=" .. tostring(cfg.enforce == true) .. " add=" .. sha:sub(1, 12) .. " rem=" .. rem_sha:sub(1, 12), "warn")
    end
    return nk.json_encode({
        ok = true,
        enforce = (cfg.enforce == true),
        hashes = cfg.hashes,
        hash_list = build_hashes_sorted_list(cfg.hashes)
    })
end

-- ADMIN RPC: Listet letzte Sicherheits-/Anti-Cheat-Ereignisse auf.
local function rpc_admin_list_security_events(context, _payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local idx_objs = nk.storage_read({
        { collection = SECURITY_EVENTS_COLLECTION, key = SECURITY_INDEX_KEY, user_id = SYSTEM_USER_ID }
    })
    if #idx_objs == 0 or type(idx_objs[1].value) ~= "table" or type(idx_objs[1].value.ids) ~= "table" then
        return nk.json_encode({ ok = true, events = {} })
    end
    local reads = {}
    for _, eid in ipairs(idx_objs[1].value.ids) do
        table.insert(reads, { collection = SECURITY_EVENTS_COLLECTION, key = tostring(eid), user_id = SYSTEM_USER_ID })
    end
    local objs = (#reads > 0) and nk.storage_read(reads) or {}
    local by_id = {}
    local user_ids = {}
    for _, o in ipairs(objs) do
        if type(o.value) == "table" and o.value.id then
            by_id[o.value.id] = o.value
            if o.value.user_id and o.value.user_id ~= "" then
                table.insert(user_ids, tostring(o.value.user_id))
            end
        end
    end
    local meta = load_user_meta_map(user_ids)
    local out = {}
    for _, eid in ipairs(idx_objs[1].value.ids) do
        local ev = by_id[eid]
        if ev then
            local uid_str = tostring(ev.user_id or "")
            local m = meta[uid_str]
            local sev = tostring(ev.severity or "")
            if sev == "" then
                sev = infer_security_severity(ev.kind)
            end
            local resolved_uid = tostring(ev.uid or "")
            if resolved_uid == "" and m then
                resolved_uid = tostring(m.uid or "")
            end
            local resolved_name = tostring(ev.username or "")
            if resolved_name == "" and m then
                resolved_name = tostring(m.username or m.display_name or "")
            end
            table.insert(out, {
                id = tostring(ev.id or eid),
                user_id = uid_str,
                uid = resolved_uid,
                username = resolved_name,
                kind = tostring(ev.kind or "UNKNOWN"),
                severity = sev,
                detail = tostring(ev.detail or ""),
                at = tonumber(ev.at or 0) or 0
            })
        end
    end
    return nk.json_encode({ ok = true, events = out })
end

-- Helper: Ermittelt alle aktuell laufenden Koop-Lobbys/Matches (inkl. privater Welten) fuer Admins.
local function collect_active_worlds_for_admin()
    local host_ids = {}
    if type(nk.sql_query) == "function" then
        local ok_q, rows = pcall(nk.sql_query,
            "SELECT user_id::text AS uid FROM storage WHERE collection = $1 AND key = $2",
            { LOBBY_COLLECTION, LOBBY_KEY })
        if ok_q and type(rows) == "table" then
            for _, row in ipairs(rows) do
                if row.uid and row.uid ~= "" then
                    table.insert(host_ids, tostring(row.uid))
                end
            end
        end
    end

    local lobbies = load_active_lobbies(host_ids)
    local worlds_by_match = {}
    local meta_needed = {}
    for host_id, lobby in pairs(lobbies) do
        local mid = tostring(lobby.match_id or "")
        if mid ~= "" then
            table.insert(meta_needed, host_id)
            worlds_by_match[mid] = {
                match_id = mid,
                host_user_id = host_id,
                host_uid = tostring(lobby.host_uid or ""),
                host_name = tostring(lobby.host_name or ""),
                world_name = tostring(lobby.world_name or "KOOP-WELT"),
                room_code = tostring(lobby.room_code or ""),
                join_mode = tostring(lobby.join_mode or "ask"),
                player_count = tonumber(lobby.player_count or 1) or 1,
                max_players = tonumber(lobby.max_players or 4) or 4,
                updated_at = tonumber(lobby.updated_at or 0) or 0,
                peers = {}
            }
        end
    end

    -- Fallback: Auch Live-Matches ohne frischen storage-Eintrag direkt von Nakama auflisten.
    local ok_ml, match_list = pcall(nk.match_list, 50, true, "", 0, 10, "")
    if ok_ml and type(match_list) == "table" then
        for _, m in ipairs(match_list) do
            local mid = tostring(m.match_id or "")
            if mid ~= "" and not worlds_by_match[mid] then
                local lbl_ok, lbl = pcall(nk.json_decode, tostring(m.label or "{}"))
                if lbl_ok and type(lbl) == "table" and lbl.kind == "shadowspore_coop" then
                    local h_uid = tostring(lbl.host_user_id or "")
                    if h_uid ~= "" then
                        table.insert(meta_needed, h_uid)
                    end
                    worlds_by_match[mid] = {
                        match_id = mid,
                        host_user_id = h_uid,
                        host_uid = tostring(lbl.host_uid or ""),
                        host_name = "",
                        world_name = tostring(lbl.world_name or "KOOP-WELT"),
                        room_code = tostring(lbl.room_code or ""),
                        join_mode = tostring(lbl.join_mode or "ask"),
                        player_count = tonumber(m.size or lbl.players or lbl.player_count or 1) or 1,
                        max_players = tonumber(lbl.max_players or 4) or 4,
                        updated_at = os.time(),
                        peers = {}
                    }
                end
            end
        end
    end

    local meta = load_user_meta_map(meta_needed)
    local out = {}
    for mid, w in pairs(worlds_by_match) do
        local hm = meta[w.host_user_id]
        if hm then
            if w.host_uid == "" then w.host_uid = hm.uid end
            if w.host_name == "" then w.host_name = hm.display_name end
        end
        local ok_sig, sig_raw = pcall(nk.match_signal, mid, '{"action":"info"}')
        if ok_sig and type(sig_raw) == "string" and sig_raw ~= "" then
            local ok_inf, info = pcall(nk.json_decode, sig_raw)
            if ok_inf and type(info) == "table" and info.ok == true then
                w.world_name = tostring(info.world_name or w.world_name)
                w.room_code = tostring(info.room_code or w.room_code)
                w.join_mode = tostring(info.join_mode or w.join_mode)
                w.max_players = tonumber(info.max_players or w.max_players) or 4
                w.player_count = tonumber(info.player_count or w.player_count) or 1
                if type(info.peers) == "table" then
                    for _, p in ipairs(info.peers) do
                        table.insert(w.peers, {
                            peer_id = tonumber(p.peer_id or 0) or 0,
                            user_id = tostring(p.user_id or ""),
                            uid = tostring(p.uid or ""),
                            role = tostring(p.role or "player"),
                            username = tostring(p.username or ""),
                            display_name = tostring(p.display_name or p.username or "")
                        })
                    end
                end
            end
        end
        table.insert(out, w)
    end
    table.sort(out, function(a, b)
        if a.player_count ~= b.player_count then
            return a.player_count > b.player_count
        end
        return a.updated_at > b.updated_at
    end)
    return out
end

-- ADMIN RPC: Liefert kompakte Uebersichtskennzahlen fuer das Admin-Dashboard.
local function rpc_admin_overview(context, _payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local total_accounts = 0
    local banned_accounts = 0
    local online_accounts = 0
    local unused_keys = 0
    local claimed_keys = 0
    local revoked_keys = 0
    local cutoff = os.time() - 75

    if type(nk.sql_query) == "function" then
        local ok_u, rows_u = pcall(nk.sql_query,
            "SELECT COUNT(*)::int AS cnt FROM users WHERE id <> $1::uuid",
            { SYSTEM_USER_ID })
        if ok_u and type(rows_u) == "table" and #rows_u > 0 then
            total_accounts = tonumber(rows_u[1].cnt or 0) or 0
        end

        local ok_b, rows_b = pcall(nk.sql_query,
            "SELECT COUNT(*)::int AS cnt FROM storage WHERE collection = $1 AND key = $2 AND COALESCE(value->>'banned', 'false') = 'true'",
            { ENTITLEMENTS_COLLECTION, ENTITLEMENT_KEY })
        if ok_b and type(rows_b) == "table" and #rows_b > 0 then
            banned_accounts = tonumber(rows_b[1].cnt or 0) or 0
        end

        local ok_g, rows_g = pcall(nk.sql_query,
            "SELECT COALESCE(value->>'last_seen', '0') AS ls FROM storage WHERE collection = $1 AND key = $2",
            { GAME_SESSIONS_COLLECTION, GAME_SESSION_KEY })
        if ok_g and type(rows_g) == "table" then
            for _, r in ipairs(rows_g) do
                if (tonumber(r.ls or 0) or 0) >= cutoff then
                    online_accounts = online_accounts + 1
                end
            end
        end

        local ok_k, rows_k = pcall(nk.sql_query,
            "SELECT COALESCE(value->>'status', 'unused') AS st, COUNT(*)::int AS cnt FROM storage WHERE collection = $1 AND key <> $2 GROUP BY 1",
            { LICENSE_KEYS_COLLECTION, LICENSE_INDEX_KEY })
        if ok_k and type(rows_k) == "table" then
            for _, r in ipairs(rows_k) do
                local st = tostring(r.st or "unused")
                local c = tonumber(r.cnt or 0) or 0
                if st == "unused" then unused_keys = c
                elseif st == "claimed" then claimed_keys = c
                elseif st == "revoked" then revoked_keys = c
                end
            end
        end
    end

    local worlds = collect_active_worlds_for_admin()
    local sec_idx = nk.storage_read({
        { collection = SECURITY_EVENTS_COLLECTION, key = SECURITY_INDEX_KEY, user_id = SYSTEM_USER_ID }
    })
    local sec_count = (#sec_idx > 0 and type(sec_idx[1].value) == "table" and type(sec_idx[1].value.ids) == "table")
        and #sec_idx[1].value.ids or 0

    local cfg_objs = nk.storage_read({
        { collection = SYSTEM_CONFIG_COLLECTION, key = BUILD_HASHES_KEY, user_id = SYSTEM_USER_ID }
    })
    local cfg = (#cfg_objs > 0 and type(cfg_objs[1].value) == "table") and cfg_objs[1].value or {}
    local hash_count = 0
    if type(cfg.hashes) == "table" then
        for _ in pairs(cfg.hashes) do
            hash_count = hash_count + 1
        end
    end

    return nk.json_encode({
        ok = true,
        total_accounts = total_accounts,
        banned_accounts = banned_accounts,
        online_accounts = online_accounts,
        active_worlds = #worlds,
        unused_keys = unused_keys,
        claimed_keys = claimed_keys,
        revoked_keys = revoked_keys,
        security_events = sec_count,
        build_enforce = (cfg.enforce == true),
        build_hash_count = hash_count
    })
end

-- ADMIN RPC: Listet registrierte Spielerkonten mit Rolle, Lizenz, Bannstatus, Online- & Lobby-State.
local function rpc_admin_list_accounts(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local raw_query = string.lower(tostring(req.query or "")):match("^%s*(.-)%s*$")
    local role_filter = string.lower(tostring(req.role or "all"))
    if role_filter == "all" then role_filter = "" end
    local status_filter = string.lower(tostring(req.status or "all"))
    local limit = math.max(1, math.min(200, math.floor(tonumber(req.limit or 100) or 100)))

    if type(nk.sql_query) ~= "function" then
        return nk.json_encode({ ok = false, error = "SQL-Abfrage auf diesem Server nicht verfuegbar." })
    end

    local like_pat = (raw_query ~= "") and ("%" .. raw_query .. "%") or ""
    local sql = [[
        SELECT
            u.id::text AS id,
            u.username AS username,
            COALESCE(u.display_name, '') AS display_name,
            COALESCE(u.email, '') AS email,
            COALESCE(u.avatar_url, '') AS avatar_url,
            EXTRACT(EPOCH FROM u.create_time)::bigint AS created_at,
            COALESCE(p.value->>'uid', '') AS uid,
            COALESCE(p.value->>'role', 'player') AS role,
            COALESCE(p.value->>'world_join_mode', 'ask') AS world_join_mode,
            COALESCE(e.value->>'active', 'false') AS license_active,
            COALESCE(e.value->>'edition', '') AS license_edition,
            COALESCE(e.value->>'expires_at', '0') AS license_expires_at,
            COALESCE(e.value->>'banned', 'false') AS banned,
            COALESCE(e.value->>'ban_reason', '') AS ban_reason,
            COALESCE(g.value->>'last_seen', '0') AS game_last_seen,
            COALESCE(l.value->>'match_id', '') AS raw_lobby_match_id
        FROM users u
        LEFT JOIN storage p ON p.user_id = u.id AND p.collection = 'public_profile' AND p.key = 'info'
        LEFT JOIN storage e ON e.user_id = u.id AND e.collection = 'entitlements' AND e.key = 'license'
        LEFT JOIN storage g ON g.user_id = u.id AND g.collection = 'game_sessions' AND g.key = 'active'
        LEFT JOIN storage l ON l.user_id = u.id AND l.collection = 'coop_lobby' AND l.key = 'active'
        WHERE u.id <> $1::uuid
          AND ($2 = '' OR LOWER(u.username) LIKE $2 OR LOWER(COALESCE(u.display_name, '')) LIKE $2 OR LOWER(COALESCE(u.email, '')) LIKE $2 OR COALESCE(p.value->>'uid', '') LIKE $2 OR u.id::text LIKE $2)
          AND ($3 = '' OR LOWER(COALESCE(p.value->>'role', 'player')) = $3)
        ORDER BY
          (CASE WHEN COALESCE(g.value->>'last_seen', '') ~ '^[0-9]+$' THEN (g.value->>'last_seen')::bigint ELSE 0 END) DESC,
          COALESCE(p.value->>'uid', '') DESC,
          u.create_time DESC
        LIMIT $4
    ]]
    local ok_q, rows = pcall(nk.sql_query, sql, { SYSTEM_USER_ID, like_pat, role_filter, limit })
    if not ok_q or type(rows) ~= "table" then
        return nk.json_encode({ ok = false, error = "Konten konnten nicht geladen werden." })
    end

    local lobby_hosts = {}
    for _, r in ipairs(rows) do
        if r.raw_lobby_match_id and r.raw_lobby_match_id ~= "" then
            table.insert(lobby_hosts, tostring(r.id))
        end
    end
    local lobbies = load_active_lobbies(lobby_hosts)
    local cutoff = os.time() - 75
    local out = {}
    for _, r in ipairs(rows) do
        local uid_id = tostring(r.id or "")
        local last_seen = tonumber(r.game_last_seen or 0) or 0
        local game_online = last_seen >= cutoff
        local is_banned = (tostring(r.banned or "false") == "true")
        local lic_active = (tostring(r.license_active or "false") == "true")
        local lobby = lobbies[uid_id]
        local include = true
        if status_filter == "online" then
            include = game_online or (lobby ~= nil)
        elseif status_filter == "hosting" then
            include = (lobby ~= nil)
        elseif status_filter == "banned" then
            include = is_banned
        elseif status_filter == "unlicensed" then
            include = not lic_active
        end
        if include then
            local uname = tostring(r.username or "")
            local dname = tostring(r.display_name or "")
            table.insert(out, {
                user_id = uid_id,
                uid = tostring(r.uid or ""),
                username = uname,
                display_name = (dname ~= "" and dname) or uname,
                email = tostring(r.email or ""),
                avatar_url = tostring(r.avatar_url or ""),
                role = normalize_role(r.role),
                world_join_mode = normalize_join_mode(r.world_join_mode),
                license_active = lic_active,
                license_edition = tostring(r.license_edition or ""),
                license_expires_at = tonumber(r.license_expires_at or 0) or 0,
                banned = is_banned,
                ban_reason = tostring(r.ban_reason or ""),
                created_at = tonumber(r.created_at or 0) or 0,
                game_online = game_online,
                game_last_seen = last_seen,
                coop_active = (lobby ~= nil),
                coop_match_id = lobby and tostring(lobby.match_id or "") or "",
                coop_world_name = lobby and tostring(lobby.world_name or "") or "",
                coop_room_code = lobby and tostring(lobby.room_code or "") or "",
                coop_join_mode = lobby and tostring(lobby.join_mode or "") or "",
                coop_players = lobby and (tonumber(lobby.player_count or 1) or 1) or 0,
                coop_max_players = lobby and (tonumber(lobby.max_players or 4) or 4) or 4
            })
        end
    end
    return nk.json_encode({ ok = true, accounts = out })
end

-- ADMIN RPC: Listet alle aktuell aktiven Koop-Welten (inkl. privater Sitzungen und Peers).
local function rpc_admin_list_active_worlds(context, _payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    return nk.json_encode({ ok = true, worlds = collect_active_worlds_for_admin() })
end

-- ADMIN RPC: Genehmigt einem Admin sofortigen Force-Join in eine laufende Koop-Welt (umgeht private/ask/max_players/kicked).
local function rpc_admin_force_join(context, payload)
    local allowed, is_server = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    if is_server or (not context.user_id) or context.user_id == "" then
        return nk.json_encode({ ok = false, error = "Force Join erfordert eine eingeloggte Admin-Session." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local target_match_id = tostring(req.match_id or ""):match("^%s*(.-)%s*$")
    local room_code = string.upper(tostring(req.room_code or "")):gsub("[^A-Z0-9]", "")
    local host_id = tostring(req.host_user_id or "")
    local raw_query = tostring(req.query or req.uid or req.target_uid or ""):match("^%s*(.-)%s*$")

    if target_match_id == "" and room_code ~= "" then
        local idx = nk.storage_read({
            { collection = ROOM_CODE_COLLECTION, key = room_code, user_id = SYSTEM_USER_ID }
        })
        if #idx > 0 and type(idx[1].value) == "table" and idx[1].value.host_user_id then
            host_id = tostring(idx[1].value.host_user_id)
        end
    end

    if target_match_id == "" and host_id == "" and raw_query ~= "" then
        local maybe_code = string.upper(raw_query):gsub("[^A-Z0-9]", "")
        if #maybe_code >= 4 and #maybe_code <= 10 then
            local idx = nk.storage_read({
                { collection = ROOM_CODE_COLLECTION, key = maybe_code, user_id = SYSTEM_USER_ID }
            })
            if #idx > 0 and type(idx[1].value) == "table" and idx[1].value.host_user_id then
                host_id = tostring(idx[1].value.host_user_id)
                room_code = maybe_code
            end
        end
        if host_id == "" then
            host_id = resolve_target_user_id({ query = raw_query, uid = raw_query })
        end
        if host_id == "" then
            local ok_m, m_info = pcall(nk.match_get, raw_query)
            if ok_m and m_info then
                target_match_id = raw_query
            end
        end
    end

    local lobby = nil
    if target_match_id == "" and host_id ~= "" then
        lobby = read_active_lobby(host_id)
        if not lobby or not lobby.match_id or lobby.match_id == "" then
            return nk.json_encode({ ok = false, error = "Dieser Spieler hostet aktuell keine aktive Koop-Welt." })
        end
        target_match_id = tostring(lobby.match_id)
    end

    if target_match_id == "" then
        return nk.json_encode({ ok = false, error = "Keine passende aktive Koop-Welt gefunden." })
    end

    local ok_inf, info_raw = pcall(nk.match_signal, target_match_id, '{"action":"info"}')
    if not ok_inf or type(info_raw) ~= "string" or info_raw == "" then
        return nk.json_encode({ ok = false, error = "Koop-Match ist nicht mehr erreichbar." })
    end
    local ok_dec, info = pcall(nk.json_decode, info_raw)
    if not ok_dec or type(info) ~= "table" or info.ok ~= true then
        return nk.json_encode({ ok = false, error = "Welt konnte nicht abgefragt werden." })
    end
    if tostring(info.host_user_id or host_id) == context.user_id then
        return nk.json_encode({ ok = false, error = "Du hostest diese Welt bereits selbst." })
    end

    local ok_sig, sig_res = pcall(nk.match_signal, target_match_id, nk.json_encode({
        action = "approve_user",
        user_id = context.user_id,
        force_admin = true,
        ttl = 600
    }))
    if not ok_sig then
        return nk.json_encode({ ok = false, error = "Force-Join-Freigabe fehlgeschlagen." })
    end
    local ok_sdec, sres = pcall(nk.json_decode, sig_res or "{}")
    if ok_sdec and type(sres) == "table" and sres.ok == false then
        return nk.json_encode({ ok = false, error = tostring(sres.error or "Freigabe abgelehnt.") })
    end

    local resolved_host_id = tostring(info.host_user_id or host_id or "")
    local hm_map = load_user_meta_map({ resolved_host_id })
    local hm = hm_map[resolved_host_id]
    local host_uid = tostring(info.host_uid or (lobby and lobby.host_uid) or (hm and hm.uid) or "")
    local host_name = tostring((lobby and lobby.host_name) or (hm and hm.display_name) or "")

    pcall(record_security_event, context.user_id, "ADMIN_FORCE_JOIN",
        "match=" .. target_match_id .. " host_uid=" .. host_uid .. " world=" .. tostring(info.world_name or ""), "warn")

    return nk.json_encode({
        ok = true,
        status = "approved",
        match_id = target_match_id,
        room_code = tostring(info.room_code or room_code or ""),
        world_name = tostring(info.world_name or (lobby and lobby.world_name) or "KOOP-WELT"),
        join_mode = tostring(info.join_mode or "ask"),
        host_user_id = resolved_host_id,
        host_uid = host_uid,
        host_name = host_name
    })
end

-- ADMIN RPC: Entfernt einen Spieler aus einer laufenden Koop-Welt.
local function rpc_admin_kick_match_peer(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local match_id = tostring(req.match_id or ""):match("^%s*(.-)%s*$")
    if match_id == "" then
        return nk.json_encode({ ok = false, error = "Match-ID fehlt." })
    end
    local target_user_id = resolve_target_user_id(req)
    if target_user_id == "" then
        return nk.json_encode({ ok = false, error = "Ziel-Spieler nicht gefunden." })
    end
    local cooldown = math.max(10, math.min(86400, tonumber(req.cooldown or 60) or 60))
    local ok_sig, raw = pcall(nk.match_signal, match_id, nk.json_encode({
        action = "kick_user",
        user_id = target_user_id,
        cooldown = cooldown
    }))
    if not ok_sig or type(raw) ~= "string" then
        return nk.json_encode({ ok = false, error = "Match ist nicht mehr erreichbar." })
    end
    local ok_dec, res = pcall(nk.json_decode, raw)
    if not ok_dec or type(res) ~= "table" or res.ok ~= true then
        return nk.json_encode({ ok = false, error = (res and res.error) or "Kick fehlgeschlagen." })
    end
    pcall(record_security_event, target_user_id, "ADMIN_KICK",
        "match=" .. match_id .. " by=" .. tostring(context.user_id or "server"), "warn")
    return nk.json_encode({ ok = true, match_id = match_id, target_user_id = target_user_id })
end

-- ADMIN RPC: Schliesst eine laufende Koop-Welt sofort serverseitig.
local function rpc_admin_close_world(context, payload)
    local allowed = is_server_or_admin(context)
    if not allowed then
        return nk.json_encode({ ok = false, error = "Nur Admins." })
    end
    local req = (payload and payload ~= "") and nk.json_decode(payload) or {}
    local match_id = tostring(req.match_id or ""):match("^%s*(.-)%s*$")
    local host_user_id = resolve_target_user_id(req)
    if match_id == "" and host_user_id ~= "" then
        local lobby = read_active_lobby(host_user_id)
        if lobby and lobby.match_id then
            match_id = tostring(lobby.match_id)
        end
    end
    if host_user_id == "" and match_id ~= "" then
        local ok_inf, info_raw = pcall(nk.match_signal, match_id, '{"action":"info"}')
        if ok_inf and type(info_raw) == "string" then
            local ok_dec, info = pcall(nk.json_decode, info_raw)
            if ok_dec and type(info) == "table" and info.host_user_id then
                host_user_id = tostring(info.host_user_id)
            end
        end
    end
    if match_id == "" then
        return nk.json_encode({ ok = false, error = "Aktives Match nicht gefunden." })
    end
    if host_user_id ~= "" then
        local existing = nk.storage_read({
            { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = host_user_id }
        })
        if #existing > 0 and type(existing[1].value) == "table" then
            local code = tostring(existing[1].value.room_code or "")
            if code ~= "" then
                pcall(nk.storage_delete, { { collection = ROOM_CODE_COLLECTION, key = code, user_id = SYSTEM_USER_ID } })
            end
            pcall(nk.storage_delete, { { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = host_user_id } })
        end
    end
    pcall(nk.match_signal, match_id, '{"action":"close"}')
    pcall(record_security_event, host_user_id ~= "" and host_user_id or (context.user_id or "server"),
        "ADMIN_CLOSE_WORLD", "match=" .. match_id .. " by=" .. tostring(context.user_id or "server"), "warn")
    return nk.json_encode({ ok = true, match_id = match_id })
end

-- HOOK: Blockiert direkte Device/Custom/Social-Authentifizierung oder Verknuepfung.
local function before_block_alt_auth(_context, _payload)
    error({ "Nur E-Mail-Login nach Lizenz-Aktivierung ueber shadowspore.com moeglich.", 7 })
end

-- HOOK: Blockiert direkte Client-Writes auf server-autoritative Collections (inkl. saves).
local function before_guard_storage_write(context, payload)
    if (not context.user_id) or context.user_id == "" then
        return payload
    end
    local objects = (type(payload) == "table" and payload.objects) or {}
    for _, obj in ipairs(objects) do
        local col = tostring(obj.collection or "")
        if PROTECTED_CLIENT_COLLECTIONS[col] then
            pcall(record_security_event, context.user_id, "DIRECT_STORAGE_WRITE", col .. "/" .. tostring(obj.key or ""))
            error({ "Direktes Beschreiben von '" .. col .. "' ist nicht erlaubt.", 7 })
        end
    end
    return payload
end

local function before_guard_storage_delete(context, payload)
    if (not context.user_id) or context.user_id == "" then
        return payload
    end
    local ids = (type(payload) == "table" and payload.object_ids) or {}
    for _, obj in ipairs(ids) do
        local col = tostring(obj.collection or "")
        if PROTECTED_CLIENT_COLLECTIONS[col] then
            pcall(record_security_event, context.user_id, "DIRECT_STORAGE_DELETE", col .. "/" .. tostring(obj.key or ""))
            error({ "Direktes Loeschen von '" .. col .. "' ist nicht erlaubt.", 7 })
        end
    end
    return payload
end

-- HOOK: Kontoerstellung nur mit gueltigem, unbenutztem Lizenzkey (Website) + Bann-Check beim Login.
local function before_authenticate_email(_context, payload)
    local is_create = read_bool_flag(payload and payload.create)
    if is_create then
        local vars = (payload.account and payload.account.vars) or {}
        local raw_key = vars.license_key or ""
        local rec, _, err = validate_license_key_record(normalize_license_key(raw_key))
        if not rec then
            error({ "Registrierung nur mit gueltigem Lizenzkey moeglich: " .. err, 3 })
        end
    else
        local email = string.lower(tostring((payload and payload.account and payload.account.email) or "")):gsub("^%s*(.-)%s*$", "%1")
        if email ~= "" and type(nk.sql_query) == "function" then
            local ok_q, rows = pcall(nk.sql_query, "SELECT id::text AS uid FROM users WHERE email = $1 LIMIT 1", { email })
            if ok_q and type(rows) == "table" and #rows > 0 and rows[1].uid then
                local ent = read_entitlement(tostring(rows[1].uid))
                if ent.banned == true then
                    error({ "Konto gesperrt: " .. tostring(ent.ban_reason or "Verstoss gegen die Nutzungsbedingungen"), 7 })
                end
            end
        end
    end
    return payload
end

local function decode_user_id_from_jwt(token)
    if type(token) ~= "string" or token == "" then
        return ""
    end
    local _, _, claims_b64 = string.find(token, "^[^%.]+%.([^%.]+)%.")
    if not claims_b64 or claims_b64 == "" then
        return ""
    end
    local b64 = claims_b64:gsub("%-", "+"):gsub("_", "/")
    local rem = #b64 % 4
    if rem == 2 then
        b64 = b64 .. "=="
    elseif rem == 3 then
        b64 = b64 .. "="
    end
    local ok_dec, json_str = pcall(nk.base64_decode, b64)
    if not ok_dec or not json_str or json_str == "" then
        return ""
    end
    local ok_json, claims = pcall(nk.json_decode, json_str)
    if ok_json and type(claims) == "table" and claims.uid then
        return tostring(claims.uid)
    end
    return ""
end

-- HOOK: Prueft Bann nach E-Mail-Login und loest den Lizenzkey bei Neuregistrierung atomar ein.
local function after_authenticate_email(context, arg1, arg2)
    local out = (type(arg1) == "table" and (arg1.token ~= nil or arg1.created ~= nil)) and arg1 or arg2
    local req = (out == arg1) and arg2 or arg1
    local user_id = tostring(context.user_id or "")
    if user_id == "" and type(out) == "table" then
        user_id = decode_user_id_from_jwt(out.token)
    end
    if user_id ~= "" then
        ensure_user_uid(user_id)
        local ent = read_entitlement(user_id)
        if ent.banned == true then
            error({ "Konto gesperrt: " .. tostring(ent.ban_reason or "Verstoss gegen die Nutzungsbedingungen"), 7 })
        end
        local created = read_bool_flag(out and out.created)
        if created then
            local vars = (type(req) == "table" and req.account and req.account.vars) or {}
            local raw_key = vars.license_key or ""
            local ok_claim, err_claim = claim_license_key_for_user(user_id, raw_key)
            if not ok_claim then
                pcall(nk.account_delete_id, user_id, true)
                error({ "Lizenzkey konnte nicht aktiviert werden: " .. err_claim, 3 })
            end
        end
    end
    return out
end

nk.register_rpc(rpc_get_my_profile, "get_my_profile")
nk.register_rpc(rpc_find_by_uid, "find_by_uid")
nk.register_rpc(rpc_add_friend_by_uid, "add_friend_by_uid")
nk.register_rpc(rpc_accept_friend, "accept_friend")
nk.register_rpc(rpc_remove_friend, "remove_friend")
nk.register_rpc(rpc_list_friends, "list_friends")
nk.register_rpc(rpc_admin_set_role, "admin_set_role")
nk.register_rpc(rpc_set_world_join_mode, "set_world_join_mode")
nk.register_rpc(rpc_coop_open_world, "coop_open_world")
nk.register_rpc(rpc_coop_close_world, "coop_close_world")
nk.register_rpc(rpc_coop_heartbeat, "coop_heartbeat")
nk.register_rpc(rpc_coop_resolve_code, "coop_resolve_code")
nk.register_rpc(rpc_coop_invite_friend, "coop_invite_friend")
nk.register_rpc(rpc_coop_request_join, "coop_request_join")
nk.register_rpc(rpc_coop_respond_join_request, "coop_respond_join_request")
nk.register_rpc(rpc_coop_get_peer_character, "coop_get_peer_character")
nk.register_rpc(rpc_coop_issue_ticket, "coop_issue_ticket")
nk.register_rpc(rpc_coop_verify_ticket, "coop_verify_ticket")
nk.register_rpc(rpc_redeem_license_key, "redeem_license_key")
nk.register_rpc(rpc_issue_launch_ticket, "issue_launch_ticket")
nk.register_rpc(rpc_redeem_launch_ticket, "redeem_launch_ticket")
nk.register_rpc(rpc_game_heartbeat, "game_heartbeat")
nk.register_rpc(rpc_end_game_session, "end_game_session")
nk.register_rpc(rpc_report_security_event, "report_security_event")
nk.register_rpc(rpc_save_cloud_player, "save_cloud_player")
nk.register_rpc(rpc_save_cloud_world, "save_cloud_world")
nk.register_rpc(rpc_wipe_cloud_save, "wipe_cloud_save")
nk.register_rpc(rpc_admin_issue_license_key, "admin_issue_license_key")
nk.register_rpc(rpc_admin_list_license_keys, "admin_list_license_keys")
nk.register_rpc(rpc_admin_set_license, "admin_set_license")
nk.register_rpc(rpc_admin_set_ban, "admin_set_ban")
nk.register_rpc(rpc_admin_get_build_config, "admin_get_build_config")
nk.register_rpc(rpc_admin_register_build, "admin_register_build")
nk.register_rpc(rpc_admin_list_security_events, "admin_list_security_events")
nk.register_rpc(rpc_admin_overview, "admin_overview")
nk.register_rpc(rpc_admin_list_accounts, "admin_list_accounts")
nk.register_rpc(rpc_admin_list_active_worlds, "admin_list_active_worlds")
nk.register_rpc(rpc_admin_force_join, "admin_force_join")
nk.register_rpc(rpc_admin_kick_match_peer, "admin_kick_match_peer")
nk.register_rpc(rpc_admin_close_world, "admin_close_world")

nk.register_req_before(before_authenticate_email, "AuthenticateEmail")
nk.register_req_after(after_authenticate_email, "AuthenticateEmail")
nk.register_req_before(before_block_alt_auth, "AuthenticateDevice")
nk.register_req_before(before_block_alt_auth, "AuthenticateCustom")
nk.register_req_before(before_block_alt_auth, "AuthenticateApple")
nk.register_req_before(before_block_alt_auth, "AuthenticateFacebook")
nk.register_req_before(before_block_alt_auth, "AuthenticateGameCenter")
nk.register_req_before(before_block_alt_auth, "AuthenticateGoogle")
nk.register_req_before(before_block_alt_auth, "AuthenticateSteam")
nk.register_req_before(before_block_alt_auth, "LinkDevice")
nk.register_req_before(before_block_alt_auth, "LinkCustom")
nk.register_req_before(before_guard_storage_write, "WriteStorageObjects")
nk.register_req_before(before_guard_storage_delete, "DeleteStorageObjects")

nk.logger_info("Shadowspore Nakama-Modul geladen.")
