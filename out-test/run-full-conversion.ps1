$ErrorActionPreference = "Stop"

$java = "C:\Program Files\Microsoft\jdk-21.0.10.7-hotspot\bin\java.exe"
$jar = "D:\Label Pro\tps-parse\target\tps-to-csv.jar"
$srcDir = "D:\OneDrive\Label Pro Analysis\Database"
$outDir = "D:\OneDrive\Label Pro Analysis\Database\csv-output"
$logFile = "D:\Label Pro\tps-parse\out-test\conversion-log.txt"

if (!(Test-Path $java)) { throw "Java not found: $java" }
if (!(Test-Path $jar)) { throw "Jar not found: $jar" }
if (!(Test-Path $srcDir)) { throw "Source folder not found: $srcDir" }
if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

"" | Set-Content $logFile -Encoding UTF8

$files = Get-ChildItem $srcDir -Filter "*.tps" -File | Sort-Object Name
$total = $files.Count
$ok = 0
$fail = 0
$idx = 0

Write-Host "Starting conversion of $total files..."
foreach ($f in $files) {
    $idx++
    $target = Join-Path $outDir ($f.BaseName + ".csv")
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $java -jar $jar -s $f.FullName -t $target *> $null
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
    if ($LASTEXITCODE -eq 0) {
        $ok++
    }
    else {
        $fail++
        "FAILED: $($f.Name)" | Add-Content $logFile
    }

    if (($idx % 50) -eq 0 -or $idx -eq $total) {
        Write-Host "Progress $idx/$total | OK=$ok FAIL=$fail"
    }
}

$csvCount = (Get-ChildItem $outDir -Filter "*.csv" -File | Measure-Object).Count
Write-Host "Done. Success: $ok  Failed: $fail"
Write-Host "CSV files present: $csvCount"
Write-Host "Failure log: $logFile"
