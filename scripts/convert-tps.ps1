param(
    [string]$SourceDir = "C:\Users\Lemmy\OneDrive\Lemmy\Lemmy Madelein Investments\Label Pro Analysis\Database",
    [string]$OutputDir = "C:\Users\Lemmy\OneDrive\Lemmy\Lemmy Madelein Investments\Label Pro Analysis\Database\csv-output",
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot),
    [string]$JavaExe = "C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot\bin\java.exe",
    [string]$MavenCmd = "$env:USERPROFILE\tools\apache-maven-3.9.9\bin\mvn.cmd",
    [string]$Encoding = "UTF-8",
    [string]$JavaHeap = "4g",
    # A .tps file larger than this that yields a header-only CSV is flagged as suspect (likely lost data).
    [long]$SuspectEmptyBytes = 65536,
    [string]$FailedReportPath,
    [string]$Password,
    [string]$PasswordFile,
    [string[]]$PasswordCandidates,
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
$ReportPath = Join-Path $OutputDir "conversion-report.csv"

$candidatePasswords = New-Object System.Collections.Generic.List[string]
if ($Password) {
    $candidatePasswords.Add($Password)
}
if ($PasswordCandidates) {
    foreach ($item in $PasswordCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($item) -and -not $candidatePasswords.Contains($item)) {
            $candidatePasswords.Add($item)
        }
    }
}
if ($PasswordFile) {
    if (-not (Test-Path $PasswordFile)) {
        throw "Password file not found: $PasswordFile"
    }
    foreach ($line in (Get-Content -Path $PasswordFile -Encoding UTF8)) {
        $value = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not $candidatePasswords.Contains($value)) {
            $candidatePasswords.Add($value)
        }
    }
}

function Invoke-TpsToCsv {
    param(
        [string]$Jar,
        [string]$Java,
        [string]$Source,
        [string]$Target,
        [string]$OutEncoding,
        [string]$Heap,
        [switch]$Direct,
        [switch]$EnableVerbose,
        [string]$OwnerPassword
    )

    $javaArgs = @("-Xmx$Heap", "-jar", $Jar, "-s", $Source, "-t", $Target, "-encoding", $OutEncoding)
    if ($Direct) { $javaArgs += "-direct" }
    if ($EnableVerbose) { $javaArgs += "-verbose" }
    if ($OwnerPassword) { $javaArgs += @("-password", $OwnerPassword) }

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = (& $Java @javaArgs 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
    # Belt and braces: older jars exit 0 even when a file aborts, so also look at the output.
    $crashed = $output -match "(?m)^FAILED:|OutOfMemoryError|Exception in thread|Exception:"
    [pscustomobject]@{
        Success  = ($exitCode -eq 0 -and -not $crashed)
        Output   = $output
        ExitCode = $exitCode
    }
}

# Returns the CSV file(s) produced for a .tps file (multi-table files produce Base.Table.csv).
function Get-OutputCsvs([string]$Dir, [string]$BaseName) {
    @(Get-ChildItem -LiteralPath $Dir -File | Where-Object {
        $_.Name -ieq "$BaseName.csv" -or ($_.Name -like "$BaseName.*.csv" -and $_.Name -notlike "*.direct.csv")
    })
}

# True when the CSV holds a header row and nothing else.
function Test-HeaderOnly([System.IO.FileInfo]$Csv) {
    $reader = New-Object System.IO.StreamReader($Csv.FullName)
    try {
        [void]$reader.ReadLine()
        while (($line = $reader.ReadLine()) -ne $null) {
            if ($line.Trim().Length -gt 0) { return $false }
        }
        return $true
    }
    finally {
        $reader.Dispose()
    }
}

Push-Location $ProjectDir
try {
    if (-not $SkipBuild) {
        Write-Host "Building project with Maven..."
        & $MavenCmd -q clean package -DskipTests
        if ($LASTEXITCODE -ne 0) { throw "Maven build failed." }
    }

    $jar = Join-Path $ProjectDir "target\tps-to-csv.jar"
    if (-not (Test-Path $jar)) {
        throw "Jar not found: $jar"
    }

    $tpsFiles = @(Get-ChildItem -Path $SourceDir -File | Where-Object { $_.Name.ToLower().EndsWith(".tps") } | Sort-Object Name)
    if ($tpsFiles.Count -eq 0) {
        throw "No .tps files found in: $SourceDir"
    }

    Write-Host "Converting $($tpsFiles.Count) TPS file(s) to CSV..."
    $failed = New-Object System.Collections.Generic.List[string]
    $suspect = New-Object System.Collections.Generic.List[string]
    $report = New-Object System.Collections.Generic.List[object]
    $recoveredWithPassword = 0
    $recoveredWithDirect = 0
    $idx = 0

    foreach ($tpsFile in $tpsFiles) {
        $idx++
        $targetCsv = Join-Path $OutputDir ($tpsFile.BaseName + ".csv")
        Write-Host "[$idx/$($tpsFiles.Count)] $($tpsFile.Name) ($([math]::Round($tpsFile.Length / 1MB, 1)) MB)"

        # Remove CSVs from earlier runs so a failure can never leave a stale or partial file looking valid.
        Get-OutputCsvs $OutputDir $tpsFile.BaseName | Remove-Item -Force

        $mode = "buffered"
        $usedPassword = $null
        $result = Invoke-TpsToCsv -Jar $jar -Java $JavaExe -Source $tpsFile.FullName -Target $targetCsv -OutEncoding $Encoding -Heap $JavaHeap -EnableVerbose:$VerboseMode

        $isLikelyEncrypted = $result.Output -match "NotATopSpeedFileException|its not a TopSpeed file or it may be 'encrypted'"

        if (-not $result.Success -and $isLikelyEncrypted -and $candidatePasswords.Count -gt 0) {
            foreach ($candidate in $candidatePasswords) {
                Write-Host "  Trying password candidate..."
                $retry = Invoke-TpsToCsv -Jar $jar -Java $JavaExe -Source $tpsFile.FullName -Target $targetCsv -OutEncoding $Encoding -Heap $JavaHeap -EnableVerbose:$VerboseMode -OwnerPassword $candidate
                if ($retry.Success) {
                    $recoveredWithPassword++
                    $usedPassword = $candidate
                    $result = $retry
                    Write-Host "  Recovered with password candidate."
                    break
                }
            }
        }

        # Out-of-memory or other crash: retry streaming straight to disk (handles very large files).
        if (-not $result.Success -and -not $isLikelyEncrypted) {
            Write-Warning "  Failed in buffered mode, retrying with -direct (streaming)..."
            Get-OutputCsvs $OutputDir $tpsFile.BaseName | Remove-Item -Force
            $mode = "direct"
            $result = Invoke-TpsToCsv -Jar $jar -Java $JavaExe -Source $tpsFile.FullName -Target $targetCsv -OutEncoding $Encoding -Heap $JavaHeap -Direct -EnableVerbose:$VerboseMode -OwnerPassword $usedPassword
            if ($result.Success) {
                $recoveredWithDirect++
                Write-Host "  Recovered with -direct."
            }
        }

        $invalidValues = ([regex]::Matches($result.Output, "WARNING: invalid (date|time)")).Count
        $incompletePages = ([regex]::Matches($result.Output, "Incomplete Page")).Count
        $csvs = @(Get-OutputCsvs $OutputDir $tpsFile.BaseName)
        [long]$csvBytes = 0
        foreach ($c in $csvs) { $csvBytes += $c.Length }
        $status = "OK"
        $note = ""

        if (-not $result.Success) {
            $status = "FAILED"
            $note = "unknown-error"
            if ($isLikelyEncrypted) {
                $note = if ($candidatePasswords.Count -gt 0) { "encrypted-or-not-tps (password attempts failed)" } else { "encrypted-or-not-tps (no password supplied)" }
            } else {
                $firstError = ($result.Output -split "`r?`n" | Where-Object { $_ -match "FAILED:|Exception|Error" } | Select-Object -First 1)
                if ($firstError) { $note = "unknown-error: $($firstError.Trim())" }
            }
            Get-OutputCsvs $OutputDir $tpsFile.BaseName | Remove-Item -Force
            $failed.Add("$($tpsFile.FullName) | $note")
            Write-Warning "  FAILED: $note"
        } elseif ($csvs.Count -eq 0) {
            $status = "FAILED"
            $note = "converter reported success but produced no CSV"
            $failed.Add("$($tpsFile.FullName) | $note")
            Write-Warning "  FAILED: $note"
        } elseif ($tpsFile.Length -gt $SuspectEmptyBytes -and @($csvs | Where-Object { Test-HeaderOnly $_ }).Count -eq $csvs.Count) {
            $status = "SUSPECT"
            $note = "header-only CSV from a $([math]::Round($tpsFile.Length / 1KB)) KB .tps file - data may be missing"
            $suspect.Add("$($tpsFile.FullName) | $note")
            Write-Warning "  SUSPECT: $note"
        }

        if ($status -eq "OK" -and $incompletePages -gt 0) {
            $note = "$incompletePages incomplete page(s) in source - some records may be unreadable"
        }

        $report.Add([pscustomobject]@{
            File            = $tpsFile.Name
            Status          = $status
            Mode            = $mode
            TpsBytes        = $tpsFile.Length
            CsvFiles        = $csvs.Count
            CsvBytes        = $csvBytes
            InvalidValues   = $invalidValues
            IncompletePages = $incompletePages
            Note            = $note
        })
    }

    $report | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

    $problems = @($failed) + @($suspect)
    if ($problems.Count -gt 0) {
        $problems | Set-Content -Path $FailedReportPath -Encoding UTF8
    } elseif (Test-Path $FailedReportPath) {
        Remove-Item $FailedReportPath -Force
    }

    $okCount = @($report | Where-Object { $_.Status -eq "OK" }).Count
    Write-Host ""
    Write-Host "================ SUMMARY ================"
    Write-Host "TPS files:           $($tpsFiles.Count)"
    Write-Host "Converted OK:        $okCount"
    Write-Host "Recovered (-direct): $recoveredWithDirect"
    Write-Host "Recovered (password):$recoveredWithPassword"
    if ($failed.Count -gt 0) {
        Write-Host "FAILED:              $($failed.Count)" -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    if ($suspect.Count -gt 0) {
        Write-Host "SUSPECT (check!):    $($suspect.Count)" -ForegroundColor Yellow
        $suspect | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    $withPages = @($report | Where-Object { $_.Status -eq "OK" -and $_.IncompletePages -gt 0 })
    if ($withPages.Count -gt 0) {
        Write-Host "Converted with incomplete pages in source: $($withPages.Count) (see report)" -ForegroundColor Yellow
    }
    Write-Host "Per-file report:     $ReportPath"
    if ($problems.Count -gt 0) { Write-Host "Problem list:        $FailedReportPath" }
    Write-Host "Output folder:       $OutputDir"
    Write-Host "========================================="

    if ($problems.Count -gt 0) { exit 1 }
}
finally {
    Pop-Location
}
