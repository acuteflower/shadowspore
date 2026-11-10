# Laedt die Rohclips der Higgsfield-Sounds nach tools\sfx_raw und verarbeitet sie.
# Aufruf im Projektordner:  powershell -ExecutionPolicy Bypass -File tools\sfx_download.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$raw = Join-Path $PSScriptRoot "sfx_raw"
New-Item -ItemType Directory -Force -Path $raw | Out-Null
$base = "https://d8j0ntlcm91z4.cloudfront.net/user_3LvBOoo57JfOhErfjKLiVBV8rJZ/"
$clips = [ordered]@{
  "item_take"         = "hf_20261110_193406_611d46a6-6829-4e33-a07f-6556abf5e541.wav"
  "pack_ui1"          = "hf_20261110_194432_122b0853-dea6-4a45-9b17-cefa66bc83cb.wav"
  "pack_ui2"          = "hf_20261110_195827_039f5622-3895-427c-a68f-34abd0d2b010.wav"
  "pack_small"        = "hf_20261110_200753_5addabae-2ba7-495a-a5a5-ff83b5b0216c.wav"
  "pack_deerfox"      = "hf_20261110_201924_db99513f-14fe-495f-a963-1d9b40c8a916.wav"
  "pack_bear"         = "hf_20261110_202835_4845922d-d75b-4a88-9fbe-4edfe81203aa.wav"
  "pack_crow"         = "hf_20261110_203932_21cbb485-a7a9-4ef2-9487-ca34bfe8e281.wav"
  "pack_raven"        = "hf_20261110_204915_23b74b1a-6aa2-4be6-b4ab-af8489316f79.wav"
  "pack_birds2"       = "hf_20261110_210032_21e1827d-ff31-4b04-b955-9e2e3c789850.wav"
  "pack_build"        = "hf_20261110_211248_b9755724-89f3-44d6-86c6-0b84a2501d20.wav"
  "pack_misc"         = "hf_20261110_212534_d7e374c0-438f-45c1-8e4b-d82b62b79b13.wav"
  "cricket_night"     = "hf_20261110_213750_56698077-aefb-4fa9-8c74-019b66a3e1b2.wav"
  "wind_day_loop"     = "hf_20261110_215006_a94aa471-e8bb-4d57-a11a-02224c946f48.wav"
  "wind_night_loop"   = "hf_20261110_220222_d901c2ff-c982-47d2-841b-cdfb3714d39f.wav"
  "river_loop"        = "hf_20261110_221438_78c3f941-ce23-49ea-a586-fddcfa19e40d.wav"
  "fire_crackle_loop" = "hf_20261110_222654_ff5fc39b-2d09-42b2-b3a8-5381e8ec3d66.wav"
}
foreach ($name in $clips.Keys) {
  $out = Join-Path $raw ($name + ".wav")
  Write-Host "Lade $name ..."
  Invoke-WebRequest -Uri ($base + $clips[$name]) -OutFile $out
}
Write-Host "Verarbeite ..."
Push-Location $root
py -3 tools/sfx_process.py tools/sfx_raw
Pop-Location
Write-Host "Fertig. Danach: Godot --headless --path . --import"
