param(
    [string]$SourceDir = "C:\Users\Lemmy\OneDrive\Lemmy\Lemmy Madelein Investments\Label Pro Analysis\Database",
    [string]$OutputDir = "C:\Users\Lemmy\OneDrive\Lemmy\Lemmy Madelein Investments\Label Pro Analysis\Database\csv-output",
    [string]$ProjectDir = "C:\Users\Lemmy\tps-parse",
    [string]$JavaExe = "C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot\bin\java.exe",
    [string]$MavenCmd = "$env:USERPROFILE\tools\apache-maven-3.9.9\bin\mvn.cmd",
    [string]$Encoding = "UTF-8",
    [string]$FailedReportPath,
    [string]$Password,
    [switch]$SkipBuild,
    [switch]$VerboseMode
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path $ProjectDir)) {
    throw "Project directory not found: $ProjectDir"
}
if (-not (Test-Path $SourceDir)) {
    throw "Source TPS folder not found: $SourceDir"
}
if (-not (Test-Path $JavaExe)) {
    throw "Java executable not found: $JavaExe"
}
if (-not (Test-Path $MavenCmd) -and -not $SkipBuild) {
    throw "Maven executable not found: $MavenCmd"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if (-not $FailedReportPath) {
    $FailedReportPath = Join-Path $OutputDir "failed-files.txt"
}

Push-Location $ProjectDir
try {
    if (-not $SkipBuild) {
        Write-Host "Building project with Maven..."
        & $MavenCmd clean package -DskipTests
    }

    $jar = Join-Path $ProjectDir "target\tps-to-csv.jar"
    if (-not (Test-Path $jar)) {
        throw "Jar not found: $jar"
    }

    $tpsFiles = @(Get-ChildItem -Path $SourceDir -File | Where-Object { $_.Name.ToLower().EndsWith(".tps") })
    if ($tpsFiles.Count -eq 0) {
        throw "No .tps files found in: $SourceDir"
    }

    Write-Host "Converting $($tpsFiles.Count) TPS file(s) to CSV..."
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($tpsFile in $tpsFiles) {
        $targetCsv = Join-Path $OutputDir ($tpsFile.BaseName + ".csv")
        $args = @(
            "-jar", $jar,
            "-s", $tpsFile.FullName,
            "-t", $targetCsv,
            "-encoding", $Encoding
        )

        if ($VerboseMode) {
            $args += "-verbose"
        }

        if ($Password) {
            $args += @("-password", $Password)
        }

        Write-Host "Processing $($tpsFile.Name)..."
        & $JavaExe @args
        if ($LASTEXITCODE -ne 0) {
            $failed.Add($tpsFile.FullName)
            Write-Warning "Failed: $($tpsFile.FullName)"
        }
    }

    if ($failed.Count -gt 0) {
        $failed | Set-Content -Path $FailedReportPath -Encoding UTF8
        Write-Warning "$($failed.Count) file(s) failed conversion."
        Write-Warning "Failed report: $FailedReportPath"
        $failed | ForEach-Object { Write-Warning " - $_" }
    } else {
        if (Test-Path $FailedReportPath) {
            Remove-Item $FailedReportPath -Force
        }
        Write-Host "No failed files."
    }

    Write-Host "Done. Output folder: $OutputDir"
}
finally {
    Pop-Location
}
