#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_YML="${PROD_YML:-$SCRIPT_DIR/prod.yml}"
CUSTOM_NAKAMA_URL="${NAKAMA_URL:-}"
SYSTEM_USER_ID="00000000-0000-0000-0000-000000000000"

extract_yml_value() {
    local section="$1"
    local field="$2"
    if [[ ! -f "$PROD_YML" ]]; then
        echo "Fehler: $PROD_YML nicht gefunden." >&2
        exit 1
    fi
    local val
    val=$(awk -v sec="$section" -v fld="$field" '
        $0 ~ "^[[:space:]]*" sec ":[[:space:]]*$" { in_sec=1; next }
        in_sec && /^[^[:space:]]/ { in_sec=0 }
        in_sec && $0 ~ "^[[:space:]]*" fld ":[[:space:]]*" {
            sub("^[[:space:]]*" fld ":[[:space:]]*", "");
            gsub(/["'\''[:space:]]/, "");
            print;
            exit
        }
    ' "$PROD_YML")
    if [[ -z "$val" ]]; then
        echo "Fehler: ${section}.${field} nicht in $PROD_YML gefunden." >&2
        exit 1
    fi
    printf '%s' "$val"
}

extract_http_key() {
    if [[ -n "${RUNTIME_HTTP_KEY:-}" ]]; then
        printf '%s' "$RUNTIME_HTTP_KEY"
        return 0
    fi
    extract_yml_value "runtime" "http_key"
}

extract_server_key() {
    if [[ -n "${SERVER_KEY:-}" ]]; then
        printf '%s' "$SERVER_KEY"
        return 0
    fi
    extract_yml_value "socket" "server_key"
}

http_post() {
    local path="$1"
    local auth_header="$2"
    local json_payload="$3"
    if [[ -z "$CUSTOM_NAKAMA_URL" ]] && docker ps --format '{{.Names}}' | grep -qx 'shadowspore_caddy_prod'; then
        if [[ -n "$auth_header" ]]; then
            docker exec -i shadowspore_caddy_prod wget -qO- \
                --header="Content-Type: application/json" \
                --header="$auth_header" \
                --post-data="$json_payload" \
                "http://nakama:7350${path}"
        else
            docker exec -i shadowspore_caddy_prod wget -qO- \
                --header="Content-Type: application/json" \
                --post-data="$json_payload" \
                "http://nakama:7350${path}"
        fi
        echo
        return 0
    fi
    local base_url="${CUSTOM_NAKAMA_URL:-http://127.0.0.1:7350}"
    if [[ -n "$auth_header" ]]; then
        curl -fsS -X POST \
            -H "Content-Type: application/json" \
            -H "$auth_header" \
            -d "$json_payload" \
            "${base_url}${path}"
    else
        curl -fsS -X POST \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            "${base_url}${path}"
    fi
    echo
}

call_rpc() {
    local rpc_name="$1"
    local json_payload="$2"
    local http_key
    http_key="$(extract_http_key)"
    http_post "/v2/rpc/${rpc_name}?http_key=${http_key}&unwrap" "" "$json_payload"
}

detect_pg_container() {
    if [[ -n "${PG_CONTAINER:-}" ]]; then
        printf '%s' "$PG_CONTAINER"
        return 0
    fi
    if docker ps --format '{{.Names}}' | grep -qx 'shadowspore_postgres_prod'; then
        printf '%s' "shadowspore_postgres_prod"
        return 0
    fi
    if docker ps --format '{{.Names}}' | grep -qx 'shadowspore_postgres'; then
        printf '%s' "shadowspore_postgres"
        return 0
    fi
    echo "Fehler: Weder shadowspore_postgres_prod noch shadowspore_postgres laeuft." >&2
    exit 1
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null \
        || printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

url_encode() {
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1" 2>/dev/null \
        || printf '%s' "$1"
}

extract_json_string() {
    local json="$1"
    local key="$2"
    printf '%s' "$json" | tr -d '\r\n' | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

build_target_field() {
    local target="$1"
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        printf '"target_uid":"%s"' "$target"
    else
        printf '"target_user_id":%s' "$(json_escape "$target")"
    fi
}

reset_all_accounts() {
    local confirm="${1:-}"
    if [[ "$confirm" != "--yes" ]]; then
        echo "Abbruch: reset-accounts loescht ALLE Konten, Speicherstaende und Keys. Zum Bestaetigen '--yes' uebergeben." >&2
        exit 1
    fi
    local pg
    pg="$(detect_pg_container)"
    docker exec -i "$pg" psql -v ON_ERROR_STOP=1 -U nakama -d nakama <<SQL
BEGIN;
DELETE FROM user_edge;
DELETE FROM user_device;
DELETE FROM user_tombstone;
DELETE FROM notification;
DELETE FROM storage WHERE collection <> 'system_config';
DELETE FROM users WHERE id <> '${SYSTEM_USER_ID}';
INSERT INTO storage (collection, key, user_id, value, version, read, write)
VALUES ('system', 'uid_counter', '${SYSTEM_USER_ID}', '{"last_uid": 99999}'::jsonb, md5('uid_counter_99999'), 0, 0);
COMMIT;
SQL
    echo "Alle Konten & User-Daten in '$pg' geloescht. Naechste UID startet bei 100000."
}

bootstrap_admin() {
    local username="${1:?Benutzername angeben (z.B. nxye)}"
    local email="${2:?E-Mail angeben}"
    local password="${3:?Passwort angeben (mind. 8 Zeichen)}"
    if [[ "${#password}" -lt 8 ]]; then
        echo "Fehler: Passwort muss mindestens 8 Zeichen lang sein." >&2
        exit 1
    fi
    local key_resp admin_key srv_key basic_b64 enc_user auth_body auth_resp token prof_resp
    key_resp="$(call_rpc "admin_issue_license_key" "{\"count\":1,\"edition\":\"admin\",\"role_grant\":\"admin\",\"note\":$(json_escape "Bootstrap Admin ${username}")}")"
    admin_key="$(extract_json_string "$key_resp" "key")"
    if [[ -z "$admin_key" ]]; then
        echo "Fehler beim Erzeugen des Admin-Lizenzkeys: $key_resp" >&2
        exit 1
    fi
    srv_key="$(extract_server_key)"
    basic_b64="$(printf '%s:' "$srv_key" | base64 | tr -d '\r\n')"
    enc_user="$(url_encode "$username")"
    auth_body="{\"email\":$(json_escape "$email"),\"password\":$(json_escape "$password"),\"vars\":{\"license_key\":$(json_escape "$admin_key")}}"
    auth_resp="$(http_post "/v2/account/authenticate/email?create=true&username=${enc_user}" "Authorization: Basic ${basic_b64}" "$auth_body")"
    token="$(extract_json_string "$auth_resp" "token")"
    if [[ -z "$token" ]]; then
        echo "Fehler beim Anlegen des Accounts: $auth_resp" >&2
        exit 1
    fi
    prof_resp="$(http_post "/v2/rpc/get_my_profile" "Authorization: Bearer ${token}" "\"{}\"")"
    echo "Admin-Key: $admin_key"
    echo "Profil:    $prof_resp"
}

usage() {
    cat <<EOF
Shadowspore Prod Admin CLI
Verwendung:
  $0 issue-admin-key [notiz]
  $0 issue-keys [anzahl] [edition] [notiz]
  $0 list-keys [all|unused|claimed|revoked]
  $0 revoke-key <SHADOW-XXXX-XXXX-XXXX>
  $0 ban <uid_oder_user_id> [grund]
  $0 unban <uid_oder_user_id>
  $0 revoke-license <uid_oder_user_id>
  $0 register-build <sha256> [version] [--enforce]
  $0 events
  $0 reset-accounts --yes
  $0 bootstrap-admin <username> <email> <password>
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    issue-admin-key)
        note="${1:-Owner Admin Key}"
        call_rpc "admin_issue_license_key" "{\"count\":1,\"edition\":\"admin\",\"role_grant\":\"admin\",\"note\":$(json_escape "$note")}"
        ;;
    issue-keys)
        count="${1:-1}"
        edition="${2:-standard}"
        note="${3:-Release Key}"
        call_rpc "admin_issue_license_key" "{\"count\":${count},\"edition\":$(json_escape "$edition"),\"role_grant\":\"player\",\"note\":$(json_escape "$note")}"
        ;;
    list-keys)
        status="${1:-all}"
        call_rpc "admin_list_license_keys" "{\"status\":$(json_escape "$status")}"
        ;;
    revoke-key)
        key="${1:?Lizenzkey angeben}"
        call_rpc "admin_set_license" "{\"license_key\":$(json_escape "$key"),\"key_status\":\"revoked\",\"active\":false}"
        ;;
    ban)
        target="${1:?UID oder User-ID angeben}"
        reason="${2:-Verstoss gegen die Nutzungsbedingungen}"
        call_rpc "admin_set_ban" "{$(build_target_field "$target"),\"banned\":true,\"reason\":$(json_escape "$reason")}"
        ;;
    unban)
        target="${1:?UID oder User-ID angeben}"
        call_rpc "admin_set_ban" "{$(build_target_field "$target"),\"banned\":false}"
        ;;
    revoke-license)
        target="${1:?UID oder User-ID angeben}"
        call_rpc "admin_set_license" "{$(build_target_field "$target"),\"active\":false}"
        ;;
    register-build)
        sha="${1:?SHA-256 angeben}"
        ver="${2:-0.1.0}"
        enforce="false"
        if [[ "${3:-}" == "--enforce" ]]; then
            enforce="true"
        fi
        call_rpc "admin_register_build" "{\"exe_sha256\":$(json_escape "$sha"),\"version\":$(json_escape "$ver"),\"enforce\":${enforce}}"
        ;;
    events)
        call_rpc "admin_list_security_events" "{}"
        ;;
    reset-accounts)
        reset_all_accounts "${1:-}"
        ;;
    bootstrap-admin)
        bootstrap_admin "${1:-}" "${2:-}" "${3:-}"
        ;;
    *)
        usage
        exit 1
        ;;
esac
