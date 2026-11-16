param(
    [string]$Version = "",
    [string]$GodotExe = "",
    [string]$BaseDownloadUrl = "https://shadowspore.com/updates",
    [string]$ServerKey = "",
    [string]$CustomReleaseTemplate = "",
    [string]$PckEncryptionKey = "",
    [string]$SignPfx = "",
    [string]$SignPassword = "",
    [string]$SignThumbprint = "",
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [string]$RegisterServerUrl = "",
    [string]$RuntimeHttpKey = "",
    [switch]$EnforceBuildGate,
    [switch]$SkipGame,
    [switch]$SkipLauncher,
    [switch]$Deploy
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Load-DotEnvFile([string]$Path) {
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($raw in Get-Content $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { continue }
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
        $map[$k] = $v
    }
    return $map
}

function Find-Godot {
    if ($GodotExe -and (Test-Path $GodotExe)) { return $GodotExe }
    $cmd = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $dlDir = Join-Path $env:USERPROFILE "Downloads"
    if (Test-Path $dlDir) {
        $console = Get-ChildItem -Path $dlDir -Recurse -Filter "*Godot*console*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($console) { return $console.FullName }
        $gui = Get-ChildItem -Path $dlDir -Recurse -Filter "Godot*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gui) { return $gui.FullName }
    }
    return $null
}

function Find-SignTool {
    $cmd = Get-Command signtool -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $kits = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path $kits) {
        $found = Get-ChildItem -Path $kits -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\x64\\" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Invoke-CodeSign([string]$TargetFile) {
    if (-not $SignPfx -and -not $SignThumbprint) { return }
    if (-not (Test-Path $TargetFile)) { return }
    $signtool = Find-SignTool
    if (-not $signtool) {
        throw "Code Signing requested, aber signtool.exe (Windows 10/11 SDK) wurde nicht gefunden."
    }
    $argsList = @("sign", "/fd", "SHA256", "/tr", $TimestampUrl, "/td", "SHA256")
    if ($SignPfx) {
        if (-not (Test-Path $SignPfx)) { throw "SignPfx nicht gefunden: $SignPfx" }
        $argsList += @("/f", (Resolve-Path $SignPfx).Path)
        if ($SignPassword) { $argsList += @("/p", $SignPassword) }
    } elseif ($SignThumbprint) {
        $argsList += @("/sha1", $SignThumbprint)
    }
    $argsList += $TargetFile
    Write-Host "Signiere $TargetFile ..." -ForegroundColor Cyan
    & $signtool @argsList
    if ($LASTEXITCODE -ne 0) {
        throw "signtool fehlgeschlagen fuer $TargetFile (EC=$LASTEXITCODE)"
    }
}

function Read-ProjectVersion {
    $cfg = Join-Path $Root "project.godot"
    foreach ($line in Get-Content $cfg) {
        if ($line -match '^config/version="([^"]+)"') {
            return $Matches[1]
        }
    }
    return "0.1.0"
}

$envSecrets = Load-DotEnvFile (Join-Path $Root ".env.release")
if (-not $PckEncryptionKey -and $envSecrets.ContainsKey("PCK_ENCRYPTION_KEY")) {
    $PckEncryptionKey = $envSecrets["PCK_ENCRYPTION_KEY"]
}
if (-not $CustomReleaseTemplate -and $envSecrets.ContainsKey("CUSTOM_RELEASE_TEMPLATE")) {
    $CustomReleaseTemplate = $envSecrets["CUSTOM_RELEASE_TEMPLATE"]
}
if (-not $ServerKey -and $envSecrets.ContainsKey("SHADOWSPORE_LIVE_SERVER_KEY")) {
    $ServerKey = $envSecrets["SHADOWSPORE_LIVE_SERVER_KEY"]
}
if (-not $SignPfx -and $envSecrets.ContainsKey("SIGN_PFX")) {
    $SignPfx = $envSecrets["SIGN_PFX"]
}
if (-not $SignPassword -and $envSecrets.ContainsKey("SIGN_PASSWORD")) {
    $SignPassword = $envSecrets["SIGN_PASSWORD"]
}
if (-not $SignThumbprint -and $envSecrets.ContainsKey("SIGN_THUMBPRINT")) {
    $SignThumbprint = $envSecrets["SIGN_THUMBPRINT"]
}

$effectiveServerKey = $ServerKey.Trim()
if (-not $effectiveServerKey) {
    $prodYml = Join-Path $Root "server\prod\prod.yml"
    if (Test-Path $prodYml) {
        foreach ($line in Get-Content $prodYml) {
            if ($line -match '^\s*server_key:\s*"([^"]+)"') {
                $effectiveServerKey = $Matches[1].Trim()
                break
            }
        }
    }
}
if (-not $effectiveServerKey) {
    $effectiveServerKey = "shadowspore_live_client_v1"
}

if (-not $Version) {
    $Version = Read-ProjectVersion
}

Write-Host "== Shadowspore Release Build v$Version ==" -ForegroundColor Cyan

$exeHash = ""

if (-not $SkipGame) {
    $godot = Find-Godot
    if (-not $godot) {
        throw "Godot 4.7 Binary nicht gefunden. Bitte mit -GodotExe angeben."
    }

    $tplBase = Join-Path $env:APPDATA "Godot\export_templates"
    $hasWinTpl = $false
    if (Test-Path $tplBase) {
        $hasWinTpl = [bool](Get-ChildItem -Path $tplBase -Recurse -Filter "windows_release_x86_64.exe" -ErrorAction SilentlyContinue)
    }
    $useEncryptedPck = $false
    if ($PckEncryptionKey) {
        if ($PckEncryptionKey -notmatch '^[0-9a-fA-F]{64}$') {
            throw "PckEncryptionKey muss exakt 64 Hex-Zeichen (256-Bit AES Key) enthalten."
        }
        if (-not $CustomReleaseTemplate -or -not (Test-Path $CustomReleaseTemplate)) {
            throw "Fuer verschluesselten PCK-Export wird ein passendes Custom Release Template (-CustomReleaseTemplate, kompiliert mit SCRIPT_AES256_ENCRYPTION_KEY) benoetigt. Siehe ./tools/build_encrypted_templates.ps1"
        }
        $useEncryptedPck = $true
        $CustomReleaseTemplate = (Resolve-Path $CustomReleaseTemplate).Path
    } elseif (-not $hasWinTpl -and -not ($CustomReleaseTemplate -and (Test-Path $CustomReleaseTemplate))) {
        Write-Warning "Godot Export-Templates fehlen unter '$tplBase'."
        Write-Host "Bitte im Godot Editor unter 'Editor -> Exportvorlagen verwalten -> Herunterladen' fuer 4.7.2.stable installieren." -ForegroundColor Yellow
        throw "Export-Templates nicht installiert."
    }

    $buildDir = Join-Path $Root "build"
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    $exeOut = Join-Path $buildDir "Shadowspore.exe"

    $buildAuthPath = Join-Path $Root "data\build_auth.json"
    $origBuildAuth = if (Test-Path $buildAuthPath) { [System.IO.File]::ReadAllText($buildAuthPath, [System.Text.UTF8Encoding]::new($false)) } else { $null }
    $presetsPath = Join-Path $Root "export_presets.cfg"
    $origPresets = [System.IO.File]::ReadAllText($presetsPath, [System.Text.UTF8Encoding]::new($false))
    $credPath = Join-Path $Root ".godot\export_credentials.cfg"
    $hadCred = Test-Path $credPath
    $origCred = if ($hadCred) { [System.IO.File]::ReadAllText($credPath, [System.Text.UTF8Encoding]::new($false)) } else { $null }

    try {
        $authObj = [ordered]@{
            server_url = "https://s.shadowspore.com"
            server_key = $effectiveServerKey
            version    = $Version
        }
        [System.IO.File]::WriteAllText($buildAuthPath, ($authObj | ConvertTo-Json -Depth 2) + "`n", [System.Text.UTF8Encoding]::new($false))

        if ($useEncryptedPck) {
            $presetText = $origPresets
            $presetText = [regex]::Replace($presetText, '(?m)^encrypt_pck=.*$', 'encrypt_pck=true')
            $presetText = [regex]::Replace($presetText, '(?m)^encrypt_directory=.*$', 'encrypt_directory=true')
            $escapedTpl = $CustomReleaseTemplate.Replace('\', '/')
            $presetText = [regex]::Replace($presetText, '(?m)^custom_template/release=.*$', "custom_template/release=`"$escapedTpl`"")
            [System.IO.File]::WriteAllText($presetsPath, $presetText, [System.Text.UTF8Encoding]::new($false))

            New-Item -ItemType Directory -Path (Split-Path $credPath -Parent) -Force | Out-Null
            $credText = "[preset.0]`n`nscript_encryption_key=`"$($PckEncryptionKey.ToLowerInvariant())`"`n"
            [System.IO.File]::WriteAllText($credPath, $credText, [System.Text.UTF8Encoding]::new($false))
            Write-Host "PCK AES-256 Verschluesselung aktiviert (Custom Template)." -ForegroundColor Green
        } elseif ($CustomReleaseTemplate -and (Test-Path $CustomReleaseTemplate)) {
            $escapedTpl = (Resolve-Path $CustomReleaseTemplate).Path.Replace('\', '/')
            $presetText = [regex]::Replace($origPresets, '(?m)^custom_template/release=.*$', "custom_template/release=`"$escapedTpl`"")
            [System.IO.File]::WriteAllText($presetsPath, $presetText, [System.Text.UTF8Encoding]::new($false))
        }

        Write-Host "1/4 Exportiere Shadowspore.exe via $godot ..."
        & $godot --headless --path $Root --export-release "Windows Desktop" $exeOut
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exeOut)) {
            throw "Godot Windows Export fehlgeschlagen (EC=$LASTEXITCODE)."
        }
    } finally {
        if ($null -ne $origBuildAuth) {
            [System.IO.File]::WriteAllText($buildAuthPath, $origBuildAuth, [System.Text.UTF8Encoding]::new($false))
        }
        [System.IO.File]::WriteAllText($presetsPath, $origPresets, [System.Text.UTF8Encoding]::new($false))
        if ($hadCred -and $null -ne $origCred) {
            [System.IO.File]::WriteAllText($credPath, $origCred, [System.Text.UTF8Encoding]::new($false))
        } elseif (-not $hadCred -and (Test-Path $credPath)) {
            Remove-Item $credPath -Force
        }
    }

    Invoke-CodeSign $exeOut

    Set-Content -Path (Join-Path $buildDir "version.txt") -Value $Version -Encoding ASCII

    $zipName = "Shadowspore-$Version-win64.zip"
    $zipPath = Join-Path $buildDir $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path $exeOut, (Join-Path $buildDir "version.txt") -DestinationPath $zipPath -CompressionLevel Optimal

    $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $exeHash = (Get-FileHash -Path $exeOut -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $zipPath).Length

    $updatesDir = Join-Path $Root "firebase\public\updates"
    New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
    Copy-Item -Path $zipPath -Destination (Join-Path $updatesDir $zipName) -Force

    $manifestObj = [ordered]@{
        version      = $Version
        download_url = "$($BaseDownloadUrl.TrimEnd('/'))/$zipName"
        sha256       = $hash
        exe_sha256   = $exeHash
        size_bytes   = $size
        changelog    = "https://shadowspore.com/"
    }
    $manifestJson = ($manifestObj | ConvertTo-Json -Depth 4).Replace("`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText((Join-Path $updatesDir "manifest.json"), $manifestJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "2/4 Paket erstellt: $zipPath ($size Bytes, ZIP-SHA256=$hash, EXE-SHA256=$exeHash)" -ForegroundColor Green
}

if (-not $SkipLauncher) {
    $launcherDir = Join-Path $Root "launcher"
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
    $prevServerKey = $env:SHADOWSPORE_LIVE_SERVER_KEY
    $env:SHADOWSPORE_LIVE_SERVER_KEY = $effectiveServerKey
    Push-Location $launcherDir
    try {
        Write-Host "3/4 Baue Frontend (Vite) ..."
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "npm run build fehlgeschlagen." }

        Write-Host "4/4 Baue Tauri Launcher Installer (Windows) ..."
        npm run tauri build
        if ($LASTEXITCODE -ne 0) { throw "npm run tauri build fehlgeschlagen." }

        $nsisDir = Join-Path $launcherDir "src-tauri\target\release\bundle\nsis"
        $setupExe = Get-ChildItem -Path $nsisDir -Filter "*-setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($setupExe) {
            Invoke-CodeSign $setupExe.FullName
            $dlDir = Join-Path $Root "firebase\public\downloads"
            New-Item -ItemType Directory -Path $dlDir -Force | Out-Null
            $destSetup = Join-Path $dlDir "Shadowspore-Launcher-Setup.exe"
            Copy-Item -Path $setupExe.FullName -Destination $destSetup -Force
            $setupHash = (Get-FileHash -Path $destSetup -Algorithm SHA256).Hash.ToLowerInvariant()
            $indexHtml = Join-Path $Root "firebase\public\index.html"
            if (Test-Path $indexHtml) {
                $html = [System.IO.File]::ReadAllText($indexHtml, [System.Text.Encoding]::UTF8)
                $html = [regex]::Replace(
                    $html,
                    '(<span id="installer-sha256" class="hash-code"\s*>)[0-9a-fA-F]{64}(</span>)',
                    "`${1}$setupHash`${2}"
                )
                [System.IO.File]::WriteAllText($indexHtml, $html, [System.Text.UTF8Encoding]::new($false))
            }
            Write-Host "Launcher-Setup kopiert nach firebase/public/downloads/Shadowspore-Launcher-Setup.exe (SHA-256=$setupHash)" -ForegroundColor Green
        }
    } finally {
        $env:SHADOWSPORE_LIVE_SERVER_KEY = $prevServerKey
        Pop-Location
    }
}

if ($exeHash -and $RegisterServerUrl -and $RuntimeHttpKey) {
    $regEndpoint = "$($RegisterServerUrl.TrimEnd('/'))/v2/rpc/admin_register_build?http_key=$([uri]::EscapeDataString($RuntimeHttpKey))&unwrap"
    $regPayload = @{
        exe_sha256 = $exeHash
        version    = $Version
        enforce    = [bool]$EnforceBuildGate
    } | ConvertTo-Json -Compress
    $regRes = Invoke-RestMethod -Uri $regEndpoint -Method Post -ContentType "application/json" -Body $regPayload
    Write-Host "Build-Gate auf Server registriert: $($regRes | ConvertTo-Json -Compress)" -ForegroundColor Green
} elseif ($exeHash) {
    Write-Host "Naechster Schritt fuer Build-Gate (im Launcher Admin-Tab -> Sicherheit & Builds):" -ForegroundColor Yellow
    Write-Host "  EXE SHA-256: $exeHash  (Version: $Version)" -ForegroundColor Yellow
}

Write-Host "Release-Artefakte bereit in 'build/', 'firebase/public/updates/' und 'launcher/src-tauri/target/release/bundle/'." -ForegroundColor Green

if ($Deploy) {
    $fbDir = Join-Path $Root "firebase"
    $accountMjsPath = Join-Path $fbDir "public\account.mjs"
    $origAccountMjs = if (Test-Path $accountMjsPath) { [System.IO.File]::ReadAllText($accountMjsPath, [System.Text.UTF8Encoding]::new($false)) } else { $null }
    Push-Location $fbDir
    try {
        $rootChangelog = Join-Path $Root "CHANGELOG.md"
        if (Test-Path $rootChangelog) {
            Copy-Item -Path $rootChangelog -Destination (Join-Path $fbDir "public\CHANGELOG.md") -Force
        }
        if ($null -ne $origAccountMjs -and $effectiveServerKey) {
            $safeKey = $effectiveServerKey.Replace("\", "").Replace("'", "")
            $updatedAccountMjs = [regex]::Replace(
                $origAccountMjs,
                "(?m)^const CLIENT_KEY = '[^']*';",
                { param($m) "const CLIENT_KEY = '$safeKey';" }
            )
            [System.IO.File]::WriteAllText($accountMjsPath, $updatedAccountMjs, [System.Text.UTF8Encoding]::new($false))
        }
        Write-Host "5/5 Deploye Firebase Hosting (--only hosting) ..." -ForegroundColor Cyan
        & firebase deploy --only hosting --project shadowspore
        if ($LASTEXITCODE -ne 0) {
            throw "firebase deploy fehlgeschlagen (EC=$LASTEXITCODE)."
        }
    } finally {
        if ($null -ne $origAccountMjs) {
            [System.IO.File]::WriteAllText($accountMjsPath, $origAccountMjs, [System.Text.UTF8Encoding]::new($false))
        }
        Pop-Location
    }
}
