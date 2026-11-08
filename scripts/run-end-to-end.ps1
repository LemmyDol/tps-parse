param(
    [string]$SourceDir = "D:\OneDrive\Label Pro Analysis\Database",
    [string]$OutputDir = "D:\OneDrive\Label Pro Analysis\Database\csv-output",
    [string]$ProjectDir = "D:\Label Pro\tps-parse",
    [string]$MysqlPackageDir = "D:\Label Pro\Label Pro Database\mysql_package",
    [string]$JavaExe = "C:\Program Files\Microsoft\jdk-21.0.10.7-hotspot\bin\java.exe",
    [string]$JarPath = "D:\Label Pro\tps-parse\target\tps-to-csv.jar",
    [string]$FailureLog = "D:\Label Pro\tps-parse\out-test\conversion-log.txt",
    [string]$MysqlHost = "127.0.0.1",
    [int]$MysqlPort = 0,
    [string]$MysqlUser = "root",
    [string]$MysqlPassword = "",
    [string]$MysqlDatabase = "labelpro_restored",
    [switch]$SkipConvert,
    [switch]$SkipImport,
    [switch]$SkipRecNoCheck
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-Path([string]$pathValue, [string]$label) {
    if (!(Test-Path $pathValue)) {
        throw "$label not found: $pathValue"
    }
}

function Resolve-MysqlPort([int]$requestedPort) {
    if ($requestedPort -gt 0) {
        return $requestedPort
    }

    $xamppIni = "C:\xampp\mysql\bin\my.ini"
    if (Test-Path $xamppIni) {
        $portLine = Get-Content $xamppIni | Where-Object { $_ -match '^\s*port\s*=\s*\d+' } | Select-Object -First 1
        if ($portLine) {
            $value = ($portLine -replace '.*=','').Trim()
            $parsed = 0
            if ([int]::TryParse($value, [ref]$parsed) -and $parsed -gt 0) {
                return $parsed
            }
        }
    }

    return 3306
}

Require-Path $ProjectDir "Project directory"
Require-Path $SourceDir "Source directory"
Require-Path $MysqlPackageDir "MySQL package directory"
Require-Path $JavaExe "Java executable"
Require-Path $JarPath "Converter jar"

$MysqlPort = Resolve-MysqlPort $MysqlPort
Write-Host "MySQL endpoint: $MysqlHost`:$MysqlPort"

if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

if (-not $SkipConvert) {
    Write-Host "Step 1/3: TPS to CSV conversion"
    "" | Set-Content $FailureLog -Encoding UTF8

    $files = Get-ChildItem -Path $SourceDir -Filter "*.tps" -File | Sort-Object Name
    $total = $files.Count
    $ok = 0
    $fail = 0
    $idx = 0

    foreach ($f in $files) {
        $idx++
        $target = Join-Path $OutputDir ($f.BaseName + ".csv")
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $JavaExe -jar $JarPath -s $f.FullName -t $target *> $null
        }
        finally {
            $ErrorActionPreference = $prevEap
        }

        if ($LASTEXITCODE -eq 0) {
            $ok++
        }
        else {
            $fail++
            "FAILED: $($f.Name)" | Add-Content $FailureLog
        }

        if (($idx % 50) -eq 0 -or $idx -eq $total) {
            Write-Host "  Progress $idx/$total | OK=$ok FAIL=$fail"
        }
    }

    Write-Host "  Conversion done. Success=$ok Failed=$fail"
    Write-Host "  Failure log: $FailureLog"
}
else {
    Write-Host "Step 1/3: skipped conversion"
}

if (-not $SkipImport) {
    Write-Host "Step 2/3: Build SQL and import into MySQL"

    if (!(Get-Command node -ErrorAction SilentlyContinue)) {
        throw "Node.js is required but was not found in PATH."
    }

    Push-Location $MysqlPackageDir
    try {
        $env:SOURCE_DIR = $OutputDir
        $env:OUTPUT_DIR = $MysqlPackageDir
        $env:MYSQL_HOST = $MysqlHost
        $env:MYSQL_PORT = "$MysqlPort"
        $env:MYSQL_USER = $MysqlUser
        $env:MYSQL_PASSWORD = $MysqlPassword
        $env:MYSQL_DATABASE = $MysqlDatabase

        & node build_mysql_from_csv_stream.js
        if ($LASTEXITCODE -ne 0) {
            throw "build_mysql_from_csv_stream.js failed"
        }

        & node run_mysql_build.js
        if ($LASTEXITCODE -ne 0) {
            throw "run_mysql_build.js failed"
        }

        Write-Host "  MySQL import completed."
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "Step 2/3: skipped import"
}

if (-not $SkipRecNoCheck) {
    Write-Host "Step 3/3: rec_no analysis"
    $recNoScript = Join-Path $ProjectDir "scripts\check-recno-gaps.ps1"
    Require-Path $recNoScript "rec_no analysis script"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $recNoScript -CsvDir $OutputDir
    if ($LASTEXITCODE -ne 0) {
        throw "rec_no analysis failed"
    }
}
else {
    Write-Host "Step 3/3: skipped rec_no analysis"
}

Write-Host "End-to-end run complete."
