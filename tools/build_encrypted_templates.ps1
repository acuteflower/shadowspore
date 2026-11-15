param(
    [string]$GodotSourceDir = "",
    [string]$EncryptionKey = "",
    [string]$ServerKey = "",
    [switch]$InitSecretsOnly,
    [int]$Jobs = 0
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SecretsFile = Join-Path $Root ".env.release"
$OutTemplate = Join-Path $Root "custom_templates\windows_release_x86_64.exe"

function New-RandomHex([int]$Bytes = 32) {
    $buf = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buf)
    } finally {
        $rng.Dispose()
    }
    return ($buf | ForEach-Object { $_.ToString("x2") }) -join ""
}

if (-not $EncryptionKey) {
    if (Test-Path $SecretsFile) {
        foreach ($line in Get-Content $SecretsFile) {
            if ($line -match '^PCK_ENCRYPTION_KEY=(.+)$') {
                $EncryptionKey = $Matches[1].Trim()
                break
            }
        }
    }
    if (-not $EncryptionKey) {
        $EncryptionKey = New-RandomHex 32
    }
}

if ($EncryptionKey -notmatch '^[0-9a-fA-F]{64}$') {
    throw "EncryptionKey muss exakt 64 Hex-Zeichen (256-Bit AES) lang sein."
}
$EncryptionKey = $EncryptionKey.ToLowerInvariant()

if (-not $ServerKey) {
    if (Test-Path $SecretsFile) {
        foreach ($line in Get-Content $SecretsFile) {
            if ($line -match '^SHADOWSPORE_LIVE_SERVER_KEY=(.+)$') {
                $ServerKey = $Matches[1].Trim()
                break
            }
        }
    }
    if (-not $ServerKey) {
        $ServerKey = "ssp_live_" + (New-RandomHex 18)
    }
}

$envLines = @(
    "# Lokale Release-Geheimnisse (per .gitignore ausgeschlossen)",
    "PCK_ENCRYPTION_KEY=$EncryptionKey",
    "CUSTOM_RELEASE_TEMPLATE=$OutTemplate",
    "SHADOWSPORE_LIVE_SERVER_KEY=$ServerKey"
)
[System.IO.File]::WriteAllText($SecretsFile, ($envLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "Lokale Release-Keys gespeichert in: $SecretsFile (gitignored)" -ForegroundColor Green

if ($InitSecretsOnly) {
    Write-Host "Nutzung nach Kompilierung des Godot Custom-Templates:" -ForegroundColor Cyan
    Write-Host "  ./tools/build_release.ps1 -Version `"0.9.2`"" -ForegroundColor Cyan
    exit 0
}

if (-not $GodotSourceDir -or -not (Test-Path (Join-Path $GodotSourceDir "SConstruct"))) {
    throw @"
Bitte Godot 4.7.2 Source-Code angeben (-GodotSourceDir C:\...\godot-4.7.2-stable).
Beispiel:
  git clone --branch 4.7.2-stable --depth 1 https://github.com/godotengine/godot.git C:\src\godot-4.7.2
  ./tools/build_encrypted_templates.ps1 -GodotSourceDir C:\src\godot-4.7.2
"@
}

function Import-MsvcEnv {
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) { return }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return }
    $vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if (-not $vsPath) {
        $vsPath = (& $vswhere -all -products * -property installationPath | Select-Object -First 1)
    }
    if (-not $vsPath) { return }
    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) { return }
    Write-Host "Lade MSVC x64 Build-Umgebung aus '$vcvars' ..." -ForegroundColor Cyan
    $lines = cmd.exe /d /c "`"$vcvars`" >nul && set"
    foreach ($line in $lines) {
        $eq = $line.IndexOf("=")
        if ($eq -gt 0) {
            $name = $line.Substring(0, $eq)
            $val = $line.Substring($eq + 1)
            [Environment]::SetEnvironmentVariable($name, $val, "Process")
        }
    }
}

$scons = Get-Command scons -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $scons) {
    throw "SCons nicht gefunden. Bitte 'pip install scons' in einer Python/VS Developer Shell ausfuehren."
}
Import-MsvcEnv

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
}

New-Item -ItemType Directory -Path (Split-Path $OutTemplate -Parent) -Force | Out-Null

$prevKey = $env:SCRIPT_AES256_ENCRYPTION_KEY
$env:SCRIPT_AES256_ENCRYPTION_KEY = $EncryptionKey
Push-Location $GodotSourceDir
try {
    $depsDir = Join-Path $env:LOCALAPPDATA "Godot\build_deps"
    $accesskitScript = Join-Path $GodotSourceDir "misc\scripts\install_accesskit.py"
    $d3d12Script = Join-Path $GodotSourceDir "misc\scripts\install_d3d12_sdk_windows.py"
    $angleScript = Join-Path $GodotSourceDir "misc\scripts\install_angle.py"
    if ((Test-Path $accesskitScript) -and -not (Test-Path (Join-Path $depsDir "accesskit"))) {
        Write-Host "Installiere AccessKit Build-Dependency ..." -ForegroundColor Cyan
        & python $accesskitScript
        if ($LASTEXITCODE -ne 0) { throw "install_accesskit.py fehlgeschlagen (EC=$LASTEXITCODE)." }
    }
    if ((Test-Path $d3d12Script) -and (-not (Test-Path (Join-Path $depsDir "agility_sdk")) -or -not (Test-Path (Join-Path $depsDir "mesa")))) {
        Write-Host "Installiere D3D12 Build-Dependencies (Mesa NIR / PIX / Agility SDK) ..." -ForegroundColor Cyan
        & python $d3d12Script
        if ($LASTEXITCODE -ne 0) { throw "install_d3d12_sdk_windows.py fehlgeschlagen (EC=$LASTEXITCODE)." }
    }
    if ((Test-Path $angleScript) -and -not (Test-Path (Join-Path $depsDir "angle"))) {
        Write-Host "Installiere ANGLE Build-Dependency ..." -ForegroundColor Cyan
        & python $angleScript
        if ($LASTEXITCODE -ne 0) { throw "install_angle.py fehlgeschlagen (EC=$LASTEXITCODE)." }
    }
    $selfListPath = Join-Path $GodotSourceDir "core\templates\self_list.h"
    if (Test-Path $selfListPath) {
        $sl = [System.IO.File]::ReadAllText($selfListPath, [System.Text.UTF8Encoding]::new($false))
        $inlineBlock = "`t`ttemplate <typename C>`n`t`tvoid sort_custom() {`n`t`t`tif (_first == _last) {`n`t`t`t`treturn;`n`t`t`t}`n`n`t`t`tstruct PtrComparator {`n`t`t`t`tC compare;`n`t`t`t`t_FORCE_INLINE_ bool operator()(const T *p_a, const T *p_b) const { return compare(*p_a, *p_b); }`n`t`t`t};`n`t`t`tusing Element = SelfList<T>;`n`t`t`tSortList<Element, T *, &Element::_self, &Element::_prev, &Element::_next, PtrComparator> sorter;`n`t`t`tsorter.sort(_first, _last);`n`t`t}"
        $slNorm = $sl.Replace("`r`n", "`n")
        if ($slNorm.Contains($inlineBlock) -and -not $slNorm.Contains("void SelfList<T>::List::sort_custom()")) {
            $slNorm = $slNorm.Replace($inlineBlock, "`t`ttemplate <typename C>`n`t`tvoid sort_custom();")
            $outOfLine = "`n`ntemplate <typename T>`ntemplate <typename C>`nvoid SelfList<T>::List::sort_custom() {`n`tif (_first == _last) { return; }`n`tstruct Sorter {`n`t`tC compare;`n`t`t_FORCE_INLINE_ void connect(SelfList<T> *p_a, SelfList<T> *p_b) { p_a->_next = p_b; p_b->_prev = p_a; }`n`t`t_FORCE_INLINE_ void split(SelfList<T> *p_a, SelfList<T> *p_b) { p_a->_next = nullptr; p_b->_prev = nullptr; }`n`t`tSelfList<T> *get_mid(SelfList<T> *p_head) { SelfList<T> *end = p_head, *mid = p_head; while (end->_next && end->_next->_next) { end = end->_next->_next; mid = mid->_next; } return mid; }`n`t`tbool is_sorted(SelfList<T> *p_head, SelfList<T> *p_tail, SelfList<T> *&r_sorted_until) { r_sorted_until = p_head; while (r_sorted_until != p_tail) { if (compare(*r_sorted_until->_next->_self, *r_sorted_until->_self)) { return false; } r_sorted_until = r_sorted_until->_next; } return true; }`n`t`tvoid merge(SelfList<T> *p_head1, SelfList<T> *p_tail1, SelfList<T> *p_head2, SelfList<T> *p_tail2, SelfList<T> *&r_head, SelfList<T> *&r_tail) {`n`t`t`tif (compare(*p_head2->_self, *p_head1->_self)) { r_head = p_head2; p_head2 = p_head2->_next; } else { r_head = p_head1; p_head1 = p_head1->_next; }`n`t`t`tSelfList<T> *curr = r_head;`n`t`t`twhile (p_head1 && p_head2) { if (compare(*p_head2->_self, *p_head1->_self)) { connect(curr, p_head2); p_head2 = p_head2->_next; } else { connect(curr, p_head1); p_head1 = p_head1->_next; } curr = curr->_next; }`n`t`t`tif (p_head1) { connect(curr, p_head1); r_tail = p_tail1; } else { connect(curr, p_head2); r_tail = p_tail2; }`n`t`t}`n`t`tvoid merge_sort(SelfList<T> *&r_head, SelfList<T> *&r_tail) { if (r_head == r_tail) { return; } SelfList<T> *tail1 = get_mid(r_head), *head2 = tail1->_next; split(tail1, head2); merge_sort(r_head, tail1); merge_sort(head2, r_tail); merge(r_head, tail1, head2, r_tail, r_head, r_tail); }`n`t`tvoid sort(SelfList<T> *&r_head, SelfList<T> *&r_tail) { SelfList<T> *sorted_until = nullptr; if (is_sorted(r_head, r_tail, sorted_until)) { return; } SelfList<T> *head_prev = r_head->_prev; r_head->_prev = nullptr; SelfList<T> *tail_next = r_tail->_next; r_tail->_next = nullptr; SelfList<T> *head2 = sorted_until->_next; split(sorted_until, head2); merge_sort(head2, r_tail); merge(r_head, sorted_until, head2, r_tail, r_head, r_tail); if (head_prev) { connect(head_prev, r_head); } if (tail_next) { connect(r_tail, tail_next); } }`n`t};`n`tSorter sorter;`n`tsorter.sort(_first, _last);`n}"
            $slNorm = $slNorm.TrimEnd() + $outOfLine + "`n"
            [System.IO.File]::WriteAllText($selfListPath, $slNorm, [System.Text.UTF8Encoding]::new($false))
            Write-Host "MSVC self_list.h C2327 Workaround angewendet." -ForegroundColor Cyan
        }
    }
    Write-Host "Kompiliere verschluesseltes Godot Release Export-Template (-j$Jobs) ..." -ForegroundColor Cyan
    & scons platform=windows target=template_release arch=x86_64 production=yes use_lto=yes "-j$Jobs"
    if ($LASTEXITCODE -ne 0) {
        throw "SCons Build fehlgeschlagen (EC=$LASTEXITCODE)."
    }
    $builtExe = Get-ChildItem -Path (Join-Path $GodotSourceDir "bin") -Filter "godot.windows.template_release*.exe" |
        Where-Object { $_.Name -notlike "*.console.exe" } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if (-not $builtExe) {
        throw "Kein gebautes Template unter '$(Join-Path $GodotSourceDir "bin")' gefunden."
    }
    Copy-Item -Path $builtExe.FullName -Destination $OutTemplate -Force
    $builtConsole = Get-ChildItem -Path (Join-Path $GodotSourceDir "bin") -Filter "godot.windows.template_release*.console.exe" | Select-Object -First 1
    if ($builtConsole) {
        $outConsole = Join-Path (Split-Path $OutTemplate -Parent) "windows_release_x86_64_console.exe"
        Copy-Item -Path $builtConsole.FullName -Destination $outConsole -Force
    }
    Write-Host "Verschluesseltes Export-Template bereit: $OutTemplate" -ForegroundColor Green
    Write-Host "Release bauen mit: ./tools/build_release.ps1 -Version `"0.9.2`"" -ForegroundColor Green
} finally {
    $env:SCRIPT_AES256_ENCRYPTION_KEY = $prevKey
    Pop-Location
}
