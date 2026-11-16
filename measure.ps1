# SlipDPI : speed / latency measurement  (no administrator needed, changes nothing)
# Run it with the engine off and on, then compare the results; output goes to local\measure-<Etiket>.json.
# Usage:  powershell -ExecutionPolicy Bypass -File measure.ps1 -Etiket once
# Note: the download test is short (50 MB) and noisy; the test server may reject with 429 on many requests.
param([string]$Etiket = 'olcum')

$out = [ordered]@{ etiket = $Etiket; zaman = (Get-Date).ToString('s'); motorCalisiyor = [bool](Get-Process winws -ErrorAction SilentlyContinue) }

# --- ping (20 packets) ---
$out.ping = [ordered]@{}
foreach ($t in '1.1.1.1', '8.8.8.8', '162.159.138.232') {
    $r = @(Test-Connection -ComputerName $t -Count 20 -ErrorAction SilentlyContinue)
    if ($r.Count -gt 0) {
        $m = $r | Measure-Object ResponseTime -Average -Minimum -Maximum
        $out.ping[$t] = [ordered]@{ ort = [math]::Round($m.Average, 1); min = $m.Minimum; max = $m.Maximum; kayip = 20 - $r.Count }
    } else { $out.ping[$t] = 'cevap yok' }
}

# --- TLS handshake time (443, the port the engine watches; sites NOT on the list) ---
$out.tls_ms = [ordered]@{}
foreach ($u in 'https://www.google.com/generate_204', 'https://github.com/', 'https://www.cloudflare.com/cdn-cgi/trace') {
    $v = @()
    for ($i = 0; $i -lt 5; $i++) {
        $o = & curl.exe -s -o NUL -w '%{time_appconnect}' --ssl-no-revoke --max-time 8 $u
        $d = 0.0; if ([double]::TryParse("$o", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) -and $d -gt 0) { $v += $d * 1000 }
    }
    if ($v.Count -gt 0) { $out.tls_ms[$u] = [math]::Round(($v | Sort-Object)[[int][math]::Floor($v.Count / 2)], 1) } else { $out.tls_ms[$u] = 'basarisiz' }
}

# --- download / upload (over 443; upload is the direction that passes through the engine) ---
function Mbps($bytesPerSec) { [math]::Round(($bytesPerSec * 8) / 1e6, 1) }
function Num($s) { $d = 0.0; [void][double]::TryParse("$s", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d); $d }

$dl = @()
for ($i = 0; $i -lt 5; $i++) {
    # 50 MB: the largest size this endpoint accepts (100 MB and above returns 403)
    $o = & curl.exe -s -o NUL -w '%{http_code}|%{speed_download}' --ssl-no-revoke --max-time 25 'https://speed.cloudflare.com/__down?bytes=50000000'
    $p = "$o".Split('|')
    if ($p[0] -eq '200') { $dl += Mbps (Num $p[1]) } else { $dl += "http $($p[0])" }
}
$out.indirme_mbps = $dl

$tmp = Join-Path $env:TEMP 'SlipDPI-upload.bin'
$buf = New-Object byte[] (40MB); (New-Object Random).NextBytes($buf); [IO.File]::WriteAllBytes($tmp, $buf)
$ul = @()
for ($i = 0; $i -lt 3; $i++) {
    $o = & curl.exe -s -o NUL -w '%{speed_upload}' --ssl-no-revoke --max-time 40 -X POST -H 'Content-Type: application/octet-stream' --data-binary "@$tmp" 'https://speed.cloudflare.com/__up'
    $ul += Mbps (Num $o)
}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
$out.yukleme_mbps = $ul

$json = [pscustomobject]$out | ConvertTo-Json -Depth 5
# If the package is installed under Program Files it cannot write there; the result goes to the user folder.
$yerel = Join-Path $PSScriptRoot 'local'
try {
    New-Item -ItemType Directory -Force $yerel -ErrorAction Stop | Out-Null
    $json | Set-Content -Path (Join-Path $yerel "measure-$Etiket.json") -Encoding UTF8 -ErrorAction Stop
} catch {
    $yerel = Join-Path $env:LOCALAPPDATA 'SlipDPI'
    New-Item -ItemType Directory -Force $yerel | Out-Null
    $json | Set-Content -Path (Join-Path $yerel "measure-$Etiket.json") -Encoding UTF8
}
Write-Host "Sonuc dosyasi: $(Join-Path $yerel "measure-$Etiket.json")"
$json
