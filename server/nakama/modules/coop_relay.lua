local nk = require("nakama")

local M = {}

local OP_PACKET_RELIABLE = 1
local OP_PACKET_UNRELIABLE = 2
local OP_CONTROL = 10

local PROFILE_COLLECTION = "public_profile"
local PROFILE_KEY = "info"
local EMPTY_MATCH_TICKS_LIMIT = 300 -- 5 ticks/sec -> 60s grace before empty match auto-closes
local MAX_PACKET_BYTES = 262144
local MAX_PACKETS_PER_SEC = 1500

local function decode_i32_le(data)
    local b1, b2, b3, b4 = string.byte(data, 1, 4)
    if not b4 then
        return 0
    end
    local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    if n >= 2147483648 then
        n = n - 4294967296
    end
    return n
end

local function encode_i32_le(n)
    local v = tonumber(n) or 0
    if v < 0 then
        v = v + 4294967296
    end
    local b1 = v % 256
    v = math.floor(v / 256)
    local b2 = v % 256
    v = math.floor(v / 256)
    local b3 = v % 256
    v = math.floor(v / 256)
    local b4 = v % 256
    return string.char(b1, b2, b3, b4)
end

local LOBBY_COLLECTION = "coop_lobby"
local LOBBY_KEY = "active"
local ROOM_CODE_COLLECTION = "room_codes"
local SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000"

local function cleanup_lobby_storage(state)
    if not state or not state.host_user_id or state.host_user_id == "" then
        return
    end
    local ok_r, objs = pcall(nk.storage_read, {
        { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = state.host_user_id }
    })
    if ok_r and type(objs) == "table" and #objs > 0 and type(objs[1].value) == "table" then
        local stored_mid = tostring(objs[1].value.match_id or "")
        if state.match_id == "" or stored_mid == state.match_id then
            pcall(nk.storage_delete, {
                { collection = LOBBY_COLLECTION, key = LOBBY_KEY, user_id = state.host_user_id }
            })
            local rcode = tostring(objs[1].value.room_code or state.room_code or "")
            if rcode ~= "" then
                pcall(nk.storage_delete, {
                    { collection = ROOM_CODE_COLLECTION, key = rcode, user_id = SYSTEM_USER_ID }
                })
            end
        end
    end
end

local function load_public_profile(user_id)
    local objs = nk.storage_read({
        { collection = PROFILE_COLLECTION, key = PROFILE_KEY, user_id = user_id }
    })
    if #objs > 0 and type(objs[1].value) == "table" then
        return objs[1].value
    end
    return {}
end

local function is_accepted_friend(host_user_id, candidate_user_id)
    local ok, friends = pcall(nk.friends_list, host_user_id, 100)
    if not ok or type(friends) ~= "table" then
        return false
    end
    for _, f in ipairs(friends) do
        local u = f.user
        local fid = u and (u.user_id or u.id) or ""
        if fid == candidate_user_id and tonumber(f.state) == 0 then
            return true
        end
    end
    return false
end

local function count_peers(state)
    local count = 0
    for _, p in pairs(state.peers) do
        if p and p.presence then
            count = count + 1
        end
    end
    return count
end

local function build_peer_list(state)
    local list = {}
    for pid, p in pairs(state.peers) do
        if p and p.presence then
            table.insert(list, {
                peer_id = pid,
                user_id = p.user_id,
                uid = p.uid or "",
                role = p.role or "player",
                username = p.username or "",
                display_name = p.display_name or ""
            })
        end
    end
    table.sort(list, function(a, b)
        return a.peer_id < b.peer_id
    end)
    return list
end

local function build_match_label(state)
    return nk.json_encode({
        kind = "shadowspore_coop",
        host_user_id = state.host_user_id,
        host_uid = state.host_uid,
        world_name = state.world_name,
        room_code = state.room_code,
        join_mode = state.join_mode,
        max_players = state.max_players,
        players = count_peers(state)
    })
end

function M.match_init(context, setupstate)
    local params = type(setupstate) == "table" and setupstate or {}
    local host_uid = tostring(params.host_uid or "")
    local host_user_id = tostring(params.host_user_id or "")
    local join_mode = tostring(params.join_mode or "ask")
    if join_mode ~= "private" and join_mode ~= "ask" and join_mode ~= "open" then
        join_mode = "ask"
    end
    local max_players = math.max(1, math.min(4, tonumber(params.max_players) or 4))
    local state = {
        match_id = context and context.match_id or "",
        host_user_id = host_user_id,
        host_uid = host_uid,
        world_name = tostring(params.world_name or "KOOP-WELT"),
        room_code = string.upper(tostring(params.room_code or "")),
        join_mode = join_mode,
        max_players = max_players,
        approved = {},
        force_approved = {},
        kicked = {},
        peers = {},
        user_to_peer = {},
        next_peer_id = 2,
        idle_ticks = 0,
        rate_tick = 0,
        peer_pkt_count = {},
        pending_kicks = {},
        closing_ticks = nil,
        host_joined_once = false,
        closed = false
    }
    return state, 5, build_match_label(state)
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
    if state.closed then
        return state, false, "Welt geschlossen."
    end
    local uid_str = presence.user_id
    local ent_objs = nk.storage_read({
        { collection = "entitlements", key = "license", user_id = uid_str }
    })
    local ent = (#ent_objs > 0 and type(ent_objs[1].value) == "table") and ent_objs[1].value or {}
    if ent.banned == true then
        return state, false, "Konto gesperrt: " .. tostring(ent.ban_reason or "Verstoss")
    end
    local now = os.time()
    local force_until = state.force_approved and state.force_approved[uid_str]
    if force_until and force_until >= now then
        state.kicked[uid_str] = nil
        return state, true
    end
    if ent.active ~= true then
        return state, false, "Keine gueltige Shadowspore-Lizenz."
    end
    local exp = tonumber(ent.expires_at or 0) or 0
    if exp > 0 and os.time() > exp then
        return state, false, "Shadowspore-Lizenz abgelaufen."
    end
    if state.user_to_peer[uid_str] ~= nil then
        -- Replace stale session of the same player cleanly on match_join
        return state, true
    end
    if uid_str == state.host_user_id then
        return state, true
    end
    if state.kicked[uid_str] and state.kicked[uid_str] > os.time() then
        return state, false, "Du wurdest aus dieser Sitzung entfernt."
    end
    if count_peers(state) >= state.max_players then
        return state, false, "Welt ist voll (max. " .. tostring(state.max_players) .. " Spieler)."
    end

    -- Refresh latest join_mode from active lobby (which overrides profile default) in case it changed out-of-band
    local lobby_objs = nk.storage_read({
        { collection = "coop_lobby", key = "active", user_id = state.host_user_id }
    })
    local live_mode = ""
    if #lobby_objs > 0 and type(lobby_objs[1].value) == "table" and lobby_objs[1].value.join_mode then
        live_mode = tostring(lobby_objs[1].value.join_mode)
    else
        local host_prof = load_public_profile(state.host_user_id)
        live_mode = tostring(host_prof.world_join_mode or state.join_mode)
    end
    if live_mode == "private" or live_mode == "ask" or live_mode == "open" then
        state.join_mode = live_mode
    end

    local approved_until = state.approved[uid_str]
    if approved_until and approved_until >= now then
        return state, true
    end

    if state.join_mode == "private" then
        return state, false, "Diese Welt ist privat (nur mit Einladung)."
    elseif state.join_mode == "ask" then
        return state, false, "Beitritt nur auf Anfrage oder per Einladung."
    end

    -- join_mode == "open": accepted friends can always join; non-friends require matching room code
    if is_accepted_friend(state.host_user_id, uid_str) then
        return state, true
    end
    local meta = type(metadata) == "table" and metadata or {}
    local supplied_code = string.upper(tostring(meta.room_code or ""))
    if state.room_code ~= "" and supplied_code == state.room_code then
        return state, true
    end
    return state, false, "Nur fuer Freunde oder mit gueltigem Raumcode."
end

function M.match_join(context, dispatcher, tick, state, presences)
    state.idle_ticks = 0
    for _, presence in ipairs(presences) do
        local user_id = presence.user_id
        local existing_pid = state.user_to_peer[user_id]
        if existing_pid ~= nil and state.peers[existing_pid] then
            -- Kick old connection cleanly if player reconnected quickly
            local old_p = state.peers[existing_pid].presence
            if old_p and old_p.session_id ~= presence.session_id then
                pcall(dispatcher.match_kick, { old_p })
            end
            state.peers[existing_pid] = nil
            state.user_to_peer[user_id] = nil
        end

        local peer_id
        if user_id == state.host_user_id then
            peer_id = 1
            state.host_joined_once = true
        else
            peer_id = state.next_peer_id
            state.next_peer_id = state.next_peer_id + 1
        end

        local prof = load_public_profile(user_id)
        local ok_acc, acc = pcall(nk.account_get_id, user_id)
        local dname = (ok_acc and acc and acc.user and acc.user.display_name) or ""
        local uname = presence.username or ((ok_acc and acc and acc.user and acc.user.username) or "")
        local entry = {
            peer_id = peer_id,
            user_id = user_id,
            uid = tostring(prof.uid or ""),
            role = tostring(prof.role or "player"),
            username = tostring(uname),
            display_name = tostring(dname ~= "" and dname or uname),
            presence = presence
        }
        state.peers[peer_id] = entry
        state.user_to_peer[user_id] = peer_id
        state.approved[user_id] = nil
        if state.force_approved then
            state.force_approved[user_id] = nil
        end

        -- Send welcome with full peer roster to the joining peer
        local welcome_json = nk.json_encode({
            type = "welcome",
            self_peer_id = peer_id,
            host_peer_id = 1,
            max_players = state.max_players,
            join_mode = state.join_mode,
            world_name = state.world_name,
            room_code = state.room_code,
            peers = build_peer_list(state)
        })
        dispatcher.broadcast_message(OP_CONTROL, welcome_json, { presence }, nil, true)

        -- Announce new peer to all other already-connected peers
        local others = {}
        for pid, p in pairs(state.peers) do
            if pid ~= peer_id and p and p.presence then
                table.insert(others, p.presence)
            end
        end
        if #others > 0 then
            local joined_json = nk.json_encode({
                type = "peer_joined",
                peer = {
                    peer_id = entry.peer_id,
                    user_id = entry.user_id,
                    uid = entry.uid,
                    role = entry.role,
                    username = entry.username,
                    display_name = entry.display_name
                }
            })
            dispatcher.broadcast_message(OP_CONTROL, joined_json, others, nil, true)
        end
    end
    dispatcher.match_label_update(build_match_label(state))
    return state
end

function M.match_leave(context, dispatcher, tick, state, presences)
    local host_left = false
    for _, presence in ipairs(presences) do
        local user_id = presence.user_id
        local pid = state.user_to_peer[user_id]
        if pid ~= nil then
            local current = state.peers[pid]
            if current and current.presence and current.presence.session_id == presence.session_id then
                state.peers[pid] = nil
                state.user_to_peer[user_id] = nil
                if pid == 1 then
                    host_left = true
                end
                local remaining = {}
                for _, p in pairs(state.peers) do
                    if p and p.presence then
                        table.insert(remaining, p.presence)
                    end
                end
                if #remaining > 0 then
                    local left_json = nk.json_encode({
                        type = "peer_left",
                        peer_id = pid,
                        user_id = user_id,
                        reason = host_left and "host_left" or "left"
                    })
                    dispatcher.broadcast_message(OP_CONTROL, left_json, remaining, nil, true)
                end
            end
        end
    end
    dispatcher.match_label_update(build_match_label(state))
    if host_left then
        state.closed = true
        cleanup_lobby_storage(state)
        return nil
    end
    return state
end

local function evict_peer(dispatcher, state, target_pid, reason, ban_seconds)
    local target = target_pid and state.peers[target_pid] or nil
    if not target then
        return false
    end
    local target_uid = tostring(target.user_id or "")
    if target_uid ~= "" then
        state.kicked[target_uid] = os.time() + (ban_seconds or 180)
        if state.approved then state.approved[target_uid] = nil end
        if state.force_approved then state.force_approved[target_uid] = nil end
        state.user_to_peer[target_uid] = nil
    end
    state.peers[target_pid] = nil

    if target.presence then
        pcall(dispatcher.broadcast_message, OP_CONTROL, nk.json_encode({
            type = "kicked",
            reason = reason or "kicked"
        }), { target.presence }, nil, true)
        state.pending_kicks = state.pending_kicks or {}
        table.insert(state.pending_kicks, { presence = target.presence, wait = 1 })
    end

    local remaining = {}
    for _, rem in pairs(state.peers) do
        if rem and rem.presence then
            table.insert(remaining, rem.presence)
        end
    end
    if #remaining > 0 then
        dispatcher.broadcast_message(OP_CONTROL, nk.json_encode({
            type = "peer_left",
            peer_id = target_pid,
            user_id = target_uid,
            reason = reason or "kicked"
        }), remaining, nil, true)
    end
    dispatcher.match_label_update(build_match_label(state))
    return true
end

local function handle_control_message(dispatcher, state, message)
    local ok, req = pcall(nk.json_decode, message.data or "{}")
    if not ok or type(req) ~= "table" then
        return state
    end
    local sender_user_id = message.sender.user_id
    if sender_user_id ~= state.host_user_id then
        nk.logger_warn("Koop Control-Spoof abgewehrt von user_id=" .. tostring(sender_user_id))
        return state
    end
    local action = tostring(req.type or "")
    if action == "kick" then
        local target_pid = tonumber(req.target_peer_id)
        if target_pid and target_pid ~= 1 then
            evict_peer(dispatcher, state, target_pid, "kicked", 180)
        end
    elseif action == "set_join_mode" then
        local nm = tostring(req.join_mode or "")
        if nm == "private" or nm == "ask" or nm == "open" then
            state.join_mode = nm
            dispatcher.match_label_update(build_match_label(state))
            dispatcher.broadcast_message(OP_CONTROL, nk.json_encode({
                type = "mode_changed",
                join_mode = nm
            }), nil, nil, true)
        end
    elseif action == "set_room_code" then
        state.room_code = string.upper(tostring(req.room_code or ""))
        dispatcher.match_label_update(build_match_label(state))
    elseif action == "close" then
        local guests = {}
        for pid, p in pairs(state.peers) do
            if pid ~= 1 and p and p.presence then
                table.insert(guests, p.presence)
            end
        end
        if #guests == 0 then
            state.closed = true
            return nil
        end
        pcall(dispatcher.broadcast_message, OP_CONTROL, nk.json_encode({
            type = "kicked",
            reason = "host_closed"
        }), guests, nil, true)
        state.closing_ticks = 1
        return state
    end
    return state
end

local function handle_packet_message(dispatcher, state, tick, message)
    local data = message.data
    if type(data) ~= "string" or #data < 6 or #data > MAX_PACKET_BYTES then
        return
    end
    local sender_user_id = message.sender.user_id
    local sender_pid = state.user_to_peer[sender_user_id]
    if sender_pid == nil then
        return
    end
    if tick - (state.rate_tick or 0) >= 5 then
        state.rate_tick = tick
        state.peer_pkt_count = {}
    end
    local cnt = (state.peer_pkt_count[sender_pid] or 0) + 1
    state.peer_pkt_count[sender_pid] = cnt
    if cnt > MAX_PACKETS_PER_SEC then
        return
    end
    local target_pid = decode_i32_le(data)
    if math.abs(target_pid) > 100000 then
        return
    end
    local channel_and_payload = string.sub(data, 5)
    local stamped = encode_i32_le(sender_pid) .. channel_and_payload
    local reliable = (message.op_code == OP_PACKET_RELIABLE)

    if target_pid > 0 then
        local dst = state.peers[target_pid]
        if dst and dst.presence and target_pid ~= sender_pid then
            dispatcher.broadcast_message(message.op_code, stamped, { dst.presence }, nil, reliable)
        end
        return
    end

    local excluded = (target_pid < 0) and (-target_pid) or 0
    local targets = {}
    for pid, p in pairs(state.peers) do
        if pid ~= sender_pid and pid ~= excluded and p and p.presence then
            table.insert(targets, p.presence)
        end
    end
    if #targets > 0 then
        dispatcher.broadcast_message(message.op_code, stamped, targets, nil, reliable)
    end
end

function M.match_loop(context, dispatcher, tick, state, messages)
    if state.closed then
        return nil
    end
    if state.pending_kicks and #state.pending_kicks > 0 then
        local still_pending = {}
        for _, item in ipairs(state.pending_kicks) do
            if item.wait <= 0 then
                if item.presence then
                    pcall(dispatcher.match_kick, { item.presence })
                end
            else
                item.wait = item.wait - 1
                table.insert(still_pending, item)
            end
        end
        state.pending_kicks = still_pending
    end
    if state.closing_ticks ~= nil then
        if state.closing_ticks <= 0 then
            state.closed = true
            cleanup_lobby_storage(state)
            local rem = {}
            for _, p in pairs(state.peers) do
                if p and p.presence then
                    table.insert(rem, p.presence)
                end
            end
            if #rem > 0 then
                pcall(dispatcher.match_kick, rem)
            end
            return nil
        end
        state.closing_ticks = state.closing_ticks - 1
        return state
    end
    for _, message in ipairs(messages) do
        if message.op_code == OP_CONTROL then
            state = handle_control_message(dispatcher, state, message)
            if state == nil then
                return nil
            end
        elseif message.op_code == OP_PACKET_RELIABLE or message.op_code == OP_PACKET_UNRELIABLE then
            handle_packet_message(dispatcher, state, tick, message)
        end
    end

    if count_peers(state) == 0 then
        state.idle_ticks = state.idle_ticks + 1
        if state.idle_ticks >= EMPTY_MATCH_TICKS_LIMIT then
            cleanup_lobby_storage(state)
            return nil
        end
    else
        state.idle_ticks = 0
    end
    return state
end

function M.match_terminate(context, dispatcher, tick, state, grace_seconds)
    cleanup_lobby_storage(state)
    return state
end

function M.match_signal(context, dispatcher, tick, state, data)
    local ok, req = pcall(nk.json_decode, data or "{}")
    if not ok or type(req) ~= "table" then
        return state, nk.json_encode({ ok = false, error = "Ungueltiges Match-Signal." })
    end
    local action = tostring(req.action or "")
    if action == "approve_user" then
        local target_uid = tostring(req.user_id or "")
        local ttl = tonumber(req.ttl) or 600
        if target_uid ~= "" then
            if req.force_admin == true then
                state.force_approved = state.force_approved or {}
                state.force_approved[target_uid] = os.time() + ttl
            else
                state.approved[target_uid] = os.time() + ttl
            end
            state.kicked[target_uid] = nil
        end
        return state, nk.json_encode({ ok = true })
    elseif action == "is_participant_or_approved" then
        local target_uid = tostring(req.user_id or "")
        local active = (state.user_to_peer[target_uid] ~= nil)
        local approved_until = state.approved[target_uid]
        local force_until = state.force_approved and state.force_approved[target_uid]
        local now = os.time()
        local allowed = active
            or (approved_until ~= nil and approved_until >= now)
            or (force_until ~= nil and force_until >= now)
        return state, nk.json_encode({ ok = true, allowed = allowed, active = active })
    elseif action == "set_join_mode" then
        local nm = tostring(req.join_mode or "")
        if nm == "private" or nm == "ask" or nm == "open" then
            state.join_mode = nm
            dispatcher.match_label_update(build_match_label(state))
            dispatcher.broadcast_message(OP_CONTROL, nk.json_encode({
                type = "mode_changed",
                join_mode = nm
            }), nil, nil, true)
            return state, nk.json_encode({ ok = true, join_mode = nm })
        end
        return state, nk.json_encode({ ok = false, error = "Ungueltiger Modus." })
    elseif action == "kick_banned" then
        local target_uid = tostring(req.user_id or "")
        local pid = state.user_to_peer[target_uid]
        if target_uid ~= "" then
            state.kicked[target_uid] = os.time() + 86400
        end
        if pid then
            evict_peer(dispatcher, state, pid, "banned", 86400)
        end
        return state, nk.json_encode({ ok = true })
    elseif action == "kick_user" then
        local target_uid = tostring(req.user_id or "")
        local cooldown = math.max(10, tonumber(req.cooldown) or 60)
        local pid = state.user_to_peer[target_uid]
        if target_uid == state.host_user_id or pid == 1 then
            return state, nk.json_encode({ ok = false, error = "Host kann nicht einzeln gekickt werden - schliesse stattdessen die Welt." })
        end
        if target_uid ~= "" then
            state.kicked[target_uid] = os.time() + cooldown
            if state.approved then state.approved[target_uid] = nil end
            if state.force_approved then state.force_approved[target_uid] = nil end
        end
        if pid and evict_peer(dispatcher, state, pid, "kicked_admin", cooldown) then
            return state, nk.json_encode({ ok = true, kicked = true, peer_id = pid })
        end
        return state, nk.json_encode({ ok = true, kicked = false })
    elseif action == "close" then
        local all_p = {}
        for _, p in pairs(state.peers) do
            if p and p.presence then
                table.insert(all_p, p.presence)
            end
        end
        if #all_p == 0 then
            state.closed = true
            cleanup_lobby_storage(state)
            return nil, nk.json_encode({ ok = true })
        end
        pcall(dispatcher.broadcast_message, OP_CONTROL, nk.json_encode({
            type = "kicked",
            reason = "closed"
        }), all_p, nil, true)
        state.closing_ticks = 1
        return state, nk.json_encode({ ok = true })
    elseif action == "info" then
        return state, nk.json_encode({
            ok = true,
            host_user_id = state.host_user_id,
            host_uid = state.host_uid,
            world_name = state.world_name,
            room_code = state.room_code,
            join_mode = state.join_mode,
            max_players = state.max_players,
            player_count = count_peers(state),
            peers = build_peer_list(state)
        })
    end
    return state, nk.json_encode({ ok = false, error = "Unbekanntes Signal." })
end

return M
