param(
    [string]$Port,
    [int]$Seconds = 60
)

$ErrorActionPreference = 'Stop'
if ($Seconds -lt 1) { throw 'Seconds must be positive.' }
if (-not $Port) {
    $ports = @([System.IO.Ports.SerialPort]::GetPortNames())
    if ($ports.Count -ne 1) {
        throw "Specify -Port COM<number>. Available ports: $($ports -join ', ')"
    }
    $Port = $ports[0]
}

$logDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$logPath = Join-Path $logDirectory ('split-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$serial = New-Object System.IO.Ports.SerialPort $Port, 115200, None, 8, One
$serial.DtrEnable = $true
$serial.RtsEnable = $true
$writer = $null
try {
    $serial.Open()
    $writer = New-Object System.IO.StreamWriter $logPath, $false, ([System.Text.Encoding]::UTF8)
    $writer.AutoFlush = $true
    Write-Host "Reading $Port for $Seconds seconds. Press keys on each half. Log: $logPath"
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $chunk = $serial.ReadExisting()
        if ($chunk) {
            $writer.Write($chunk)
            Write-Host -NoNewline $chunk
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    if ($writer) { $writer.Dispose() }
    $serial.Dispose()
}
Write-Host "Saved: $logPath"
