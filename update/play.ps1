$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Test-Path 'server.jar') -or -not (Test-Path 'client-profile\mmc-pack.json')) { throw 'Extract the entire archive first.' }
$candidates = @($env:EVENT_PRISM, "$env:LOCALAPPDATA\Programs\PrismLauncher\prismlauncher.exe", "$env:ProgramFiles\PrismLauncher\prismlauncher.exe", "$env:ProgramFiles\Prism Launcher\prismlauncher.exe")
$found = Get-Command prismlauncher.exe -ErrorAction SilentlyContinue
if ($found) { $candidates += $found.Source }
$prism = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $prism) {
    Write-Host 'Starting local server. Open Minecraft Java 1.21.11 and join localhost:25565.'
    & (Join-Path $PSScriptRoot 'start.ps1')
    exit $LASTEXITCODE
}
$prismData = if ($env:EVENT_PRISM_DATA) { $env:EVENT_PRISM_DATA } else { Join-Path $env:APPDATA 'PrismLauncher' }
$player = if ($env:EVENT_PLAYER) { $env:EVENT_PLAYER } else { (Get-Content 'player-name.txt' -Raw).Trim() }
if ($player -notmatch '^[A-Za-z0-9_]{3,16}$') { throw 'Invalid Minecraft name in player-name.txt.' }
$instance = 'servobsh-local'
$target = Join-Path $prismData "instances\$instance"
if (-not (Test-Path (Join-Path $target 'instance.cfg'))) {
    New-Item $target -ItemType Directory -Force | Out-Null
    Copy-Item 'client-profile\*' $target -Recurse -Force
}
$portLine = Get-Content 'server.properties' | Where-Object { $_ -match '^server-port=' } | Select-Object -Last 1
$port = if ($portLine) { [int]($portLine -split '=',2)[1] } else { 25565 }
if ($port -lt 1 -or $port -gt 65535) { throw 'Invalid server-port.' }
function Test-LocalPort {
    $socket = New-Object Net.Sockets.TcpClient
    try { $task = $socket.ConnectAsync('127.0.0.1', $port); if ($task.Wait(500)) { return $socket.Connected }; return $false }
    catch { return $false } finally { $socket.Dispose() }
}
New-Item '.local-session' -ItemType Directory -Force | Out-Null
$lock = $null
try { $lock = [IO.File]::Open((Join-Path $PSScriptRoot '.local-session\launch.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { Write-Host 'Launch already in progress. Please wait for Minecraft.'; exit 0 }
try {
    if (Test-LocalPort) {
        $listener = Get-NetTCPConnection -LocalPort $port -State Listen | Select-Object -First 1
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
        $jar = Join-Path $PSScriptRoot 'server.jar'
        if (-not $process.CommandLine -or -not $process.CommandLine.Contains($jar)) { throw "Port $port is used by another server. Stop that copy first." }
        Write-Host 'Your server is already running.'
    } else {
        if (-not ((Test-Path 'eula.txt') -and (Select-String -Path 'eula.txt' -Pattern '^eula=true' -Quiet))) {
            Write-Host 'Read Minecraft EULA: https://aka.ms/MinecraftEULA'
            if ((Read-Host 'Type yes if you accept') -cne 'yes') { exit 1 }
            [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'eula.txt'), "eula=true`n")
        }
        $script = Join-Path $PSScriptRoot 'start.ps1'
        $serverProcess = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $script + '"') -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Normal
        Write-Host 'Starting server. First launch may take several minutes...'
    }
    $ready = $false
    for ($i=0; $i -lt 600; $i++) {
        if ($serverProcess -and $serverProcess.HasExited) { throw 'Server exited. See logs\latest.log or run start.bat to see the startup error.' }
        if ((Test-LocalPort) -and (Test-Path 'logs\latest.log') -and (Select-String -Path 'logs\latest.log' -Pattern 'Done \(.*\)!' -Quiet)) { $ready=$true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Server did not become ready in 10 minutes. See the server console and logs\latest.log.' }
    Write-Host "Starting Minecraft as $player on localhost:$port"
    Start-Process $prism -ArgumentList @('--dir', ('"'+$prismData+'"'), '--launch', $instance, '--profile', $player, '--server', "127.0.0.1:$port")
    Write-Host 'First login: /event auth local-test, then /event menu.'
} finally { if ($lock) { $lock.Dispose() } }
