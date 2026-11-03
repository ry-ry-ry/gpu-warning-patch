# Suppresses the "Resource usage exceeds GPU memory capacity" toast in MSFS 2024
# by dropping that one notification in the UI's NotificationsManager.
# The in-game notifications page loads Global/lib.js; lib.bundle.js holds the same code for
# other pages, so both are patched. All other notifications are untouched.
# Re-run after every sim update (updates replace the files).
#   .\Patch-GpuMemWarning.ps1            apply
#   .\Patch-GpuMemWarning.ps1 -Revert    restore the backups
#   .\Patch-GpuMemWarning.ps1 -GameDir <install folder>   skip auto-detection
param(
    [string]$GameDir = "",
    [switch]$Revert
)
$ErrorActionPreference = "Stop"

# Microsoft Store / Xbox app install first (following the WindowsApps junction
# if the game was moved to another drive), then any Steam library.
function Find-GameDir {
    $pkg = Get-AppxPackage -Name Microsoft.Limitless -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        $item = Get-Item $pkg.InstallLocation -Force
        if ($item.LinkType -and $item.Target) { return @($item.Target)[0] }
        return $pkg.InstallLocation
    }
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        $libs = @($steam) + @(Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' })
        foreach ($lib in $libs | Select-Object -Unique) {
            foreach ($m in Get-ChildItem (Join-Path $lib 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
                $acf = Get-Content $m.FullName -Raw
                if ($acf -match '"name"\s+"Microsoft Flight Simulator 2024"' -and $acf -match '"installdir"\s+"([^"]+)"') {
                    return (Join-Path $lib "steamapps\common\$($Matches[1])")
                }
            }
        }
    }
    throw "MSFS 2024 not found. Pass its install folder with -GameDir."
}

if (-not $GameDir) { $GameDir = Find-GameDir }
$globalDir = Join-Path $GameDir "Packages\fs-base-ui\html_ui\Global"
if (-not (Test-Path (Join-Path $globalDir "lib.js"))) { throw "No UI files under $globalDir. Pass the install folder with -GameDir." }
Write-Host "MSFS 2024: $GameDir"
$files  = @("lib.js", "lib.bundle.js") | ForEach-Object { Join-Path $globalDir $_ }
$marker = "/*nogpuwarn*/"
# Payload carries params.title "@fs-base,TT:SYSTEM.NOTIF_LOW_GPU_MEMORY_CAPACITY_DESC" plus the resolved text.
$guard  = "${marker}if(/LOW_GPU_MEMORY|exceeds GPU memory/i.test(JSON.stringify(t)))return;"
$anchors = @(
    "async NewNotification(t){",
    "UpdateNotificationData(t){"
)

foreach ($file in $files) {
    $backup = "$file.orig"

    if ($Revert) {
        if (Test-Path $backup) { Copy-Item $backup $file -Force; Write-Host "Restored $file" }
        else { Write-Host "No backup for $file, skipped" }
        continue
    }

    $src = [IO.File]::ReadAllText($file)
    if ($src.Contains($marker)) { Write-Host "Already patched: $file"; continue }

    foreach ($a in $anchors) {
        $n = ([regex]::Matches($src, [regex]::Escape($a))).Count
        if ($n -ne 1) { throw "Anchor '$a' found $n times in $file (expected 1); UI code changed, patch needs updating." }
    }

    Copy-Item $file $backup -Force
    foreach ($a in $anchors) { $src = $src.Replace($a, $a + $guard) }
    [IO.File]::WriteAllText($file, $src, (New-Object Text.UTF8Encoding $false))
    Write-Host "Patched $file (backup: $backup)"
}
