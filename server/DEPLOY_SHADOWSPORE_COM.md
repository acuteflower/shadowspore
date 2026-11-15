# Shadowspore Live-Deployment (`shadowspore.com` + `s.shadowspore.com`)

Diese Anleitung bringt Webseite/Auto-Updater (**Firebase Hosting**) und Nakama Game-Server (**Linux-VPS**) produktiv online.

## 1. Architektur

| Dienst | Hostname | Hoster | Zweck |
|---|---|---|---|
| **Webseite & Downloads** (`firebase/`) | `https://shadowspore.com` | Firebase Hosting | Landingpage, Launcher-Setup (`/downloads/Shadowspore-Launcher-Setup.exe`), Auto-Updater (`/updates/manifest.json` + Build-ZIPs) |
| **Game-Server & Koop-Relay** (`server/prod/`) | `https://s.shadowspore.com` (`wss://s.shadowspore.com/ws`) | Linux-VPS (Docker) | Konten, Cloud-Saves, Freunde, Rollen, Lobby-Codes und Echtzeit-Koop-Relay |

Release-Builds des Launchers und von `Shadowspore.exe` sind ab Werk auf `https://s.shadowspore.com` und `https://shadowspore.com/updates/manifest.json` vorkonfiguriert — Spieler müssen in den Einstellungen nichts manuell eintragen.

---

## 2. DNS bei Namecheap einrichten (`shadowspore.com`)

Im Namecheap Dashboard unter **Domain List → Manage → Advanced DNS**:

1. **Für den Game-Server (`s.shadowspore.com`):**
   - `A Record` · Host: **`s`** · Value: **`<IPv4-Adresse eures Linux-VPS>`** · TTL: `Automatic`
   - *(Optional)* `AAAA Record` · Host: **`s`** · Value: **`<IPv6-Adresse des VPS>`**
2. **Für die Webseite (`shadowspore.com` auf Firebase Hosting):**
   - In der Firebase Console unter **Hosting → Benutzerdefinierte Domain hinzufügen** `shadowspore.com` eingeben.
   - Vorhandene Namecheap-Standardeinträge für `@` / `www` (z. B. *URL Redirect* / *Parking*) löschen und stattdessen die von Firebase angezeigten `A`- und `TXT`-Records eintragen.

---

## 3. Produktiv-Server (`s.shadowspore.com`) auf Ubuntu 24.04 starten

1. Auf dem Linux-VPS Docker + Docker Compose installieren und die Firewall (UFW) setzen:
   ```bash
   sudo ufw allow OpenSSH
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw allow 443/udp
   sudo ufw enable
   ```
   *(Die internen Nakama-Ports **7349, 7350, 7351** in der Firewall geschlossen lassen — Caddy übernimmt HTTPS/WSS auf Port 443.)*

2. Repository (oder `server/`) auf den VPS kopieren und einmalig Produktions-Secrets erzeugen:
   ```bash
   cd ~/shadowspore/server/prod
   chmod +x generate-secrets.sh
   ./generate-secrets.sh
   ```
   Dadurch entstehen `server/prod/.env` und `server/prod/prod.yml` (beide per `.gitignore` ausgeschlossen).
   *Hinweis:* Das Skript erkennt automatisch ob der Server `arm64` (z. B. Hetzner `CAX11` → `NAKAMA_TAG=3.24.2-arm`) oder `amd64`/`x86_64` (`NAKAMA_TAG=3.24.2`) nutzt. Alle geheimen Keys (`POSTGRES_PASSWORD`, `encryption_key`, `refresh_encryption_key`, `console.password`, `runtime.http_key`) werden zufällig erzeugt; `socket.server_key` bleibt standardmäßig `shadowspore_live_client_v1`. Falls in `.env.release` ein eigener `SHADOWSPORE_LIVE_SERVER_KEY` gesetzt ist, exakt diesen als Parameter übergeben: `./generate-secrets.sh "<DEIN_SERVER_KEY>"`.

3. Stack starten:
   ```bash
   cd ~/shadowspore/server/prod
   docker compose -f docker-compose.prod.yml up -d
   docker compose -f docker-compose.prod.yml logs -f caddy nakama
   ```
   Sobald `s.shadowspore.com` auf die VPS-IP zeigt, holt Caddy automatisch das Let's-Encrypt-Zertifikat (`https://s.shadowspore.com` und `wss://s.shadowspore.com/ws`).

4. Nakama-Admin-Konsole sicher per SSH-Tunnel aufrufen (nie öffentlich öffnen):
   ```bash
   ssh -L 7351:127.0.0.1:7351 user@s.shadowspore.com
   ```
   Danach lokal `http://127.0.0.1:7351` im Browser öffnen (`username: shadowspore_ops`, Passwort aus `server/prod/prod.yml`).

---

## 4. Konten zurücksetzen & ersten Admin-Account anlegen (`UID 100000`)

Alle Konten werden ausschließlich mit einem `SHADOW-XXXX-XXXX-XXXX` Lizenzkey auf **shadowspore.com/#register** (bzw. per `admin-cli.sh`) angelegt.

1. Auf dem VPS mit [admin-cli.sh](prod/admin-cli.sh) den ersten Admin-Account anlegen (optional vorher mit `reset-accounts --yes` zurücksetzen, damit der erste Account exakt `UID 100000` erhält):
   ```bash
   cd ~/shadowspore/server/prod
   chmod +x admin-cli.sh
   ./admin-cli.sh reset-accounts --yes
   ./admin-cli.sh bootstrap-admin nxye levinadamek@outlook.de "DEIN-STARTPASSWORT"
   ```
2. Danach für Spieler normale Keys erzeugen:
   ```bash
   ./admin-cli.sh issue-keys 10 standard "Beta-Welle 1"
   ```
3. Nur Accounts mit `"role": "admin"` erhalten im Spiel Zugriff auf das Debug-/Mod-Menü und im Launcher auf das Admin-Werkzeug (abgesichert durch `coop_verify_ticket` & Server-Checks).

---

## 5. Spiel & Launcher bauen & auf Firebase deployen

1. Einmalig lokal in Godot 4.7.2: *Editor → Exportvorlagen verwalten → Herunterladen*, damit Windows-Export-Templates in `%APPDATA%\Godot\export_templates` vorhanden sind.
2. Release bauen & optional direkt deployen (erzeugt `build/Shadowspore.exe`, `Shadowspore-<Version>-win64.zip`, SHA-256 `firebase/public/updates/manifest.json` sowie `firebase/public/downloads/Shadowspore-Launcher-Setup.exe`):
   ```powershell
   ./tools/build_release.ps1 -Version "0.9.1" -Deploy
   ```
3. Bei eigenem `SHADOWSPORE_LIVE_SERVER_KEY` in `.env.release` Firebase Hosting immer über `build_release.ps1` deployen (setzt auch `firebase/public/account.mjs` beim Upload automatisch synchron, sodass `shadowspore.com` und `s.shadowspore.com` denselben Key nutzen):
   ```powershell
   ./tools/build_release.ps1 -SkipGame -SkipLauncher -Deploy
   ```
   *(Ohne abweichenden Key funktioniert auch direkt `cd firebase; firebase deploy --only hosting --project shadowspore`.)*
