param(
    [string]$SourceDir = "C:\Users\Lemmy\OneDrive\Lemmy\Lemmy Madelein Investments\Label Pro Analysis\Database",
    [string]$OutputDir = "C:\Users\Lemmy\OneDrive\Lemmy\Lemmy Madelein Investments\Label Pro Analysis\Database\csv-output",
    [string]$ProjectDir = "C:\Users\Lemmy\tps-parse",
    [string]$JavaExe = "C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot\bin\java.exe",
    [string]$MavenCmd = "$env:USERPROFILE\tools\apache-maven-3.9.9\bin\mvn.cmd",
    [string]$Encoding = "UTF-8",
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
    $recoveredWithPassword = 0

    function Invoke-TpsToCsv {
        param(
            [string]$Jar,
            [string]$Java,
            [string]$Source,
            [string]$Target,
            [string]$OutEncoding,
            [switch]$EnableVerbose,
            [string]$OwnerPassword
        )

        $args = @(
            "-jar", $Jar,
            "-s", $Source,
            "-t", $Target,
            "-encoding", $OutEncoding
        )

        if ($EnableVerbose) {
            $args += "-verbose"
        }

        if ($OwnerPassword) {
            $args += @("-password", $OwnerPassword)
        }

        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = (& $Java @args 2>&1 | Out-String)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousEap
        }
        [pscustomobject]@{
            Success = ($exitCode -eq 0)
            Output = $output
            ExitCode = $exitCode
        }
    }

    foreach ($tpsFile in $tpsFiles) {
        $targetCsv = Join-Path $OutputDir ($tpsFile.BaseName + ".csv")
        Write-Host "Processing $($tpsFile.Name)..."

        $result = Invoke-TpsToCsv -Jar $jar -Java $JavaExe -Source $tpsFile.FullName -Target $targetCsv -OutEncoding $Encoding -EnableVerbose:$VerboseMode

        if (-not $result.Success) {
            $isLikelyEncrypted = $result.Output -match "NotATopSpeedFileException|its not a TopSpeed file or it may be 'encrypted'"

            if ($isLikelyEncrypted -and $candidatePasswords.Count -gt 0) {
                $unlocked = $false
                foreach ($candidate in $candidatePasswords) {
                    Write-Host "  Trying password candidate for $($tpsFile.Name)..."
                    $retry = Invoke-TpsToCsv -Jar $jar -Java $JavaExe -Source $tpsFile.FullName -Target $targetCsv -OutEncoding $Encoding -EnableVerbose:$VerboseMode -OwnerPassword $candidate
                    if ($retry.Success) {
                        $recoveredWithPassword++
                        Write-Host "  Recovered with password candidate."
                        $unlocked = $true
                        break
                    }
                }
                if ($unlocked) {
                    continue
                }
            }

            $reason = "unknown-error"
            if ($result.Output -match "NotATopSpeedFileException|its not a TopSpeed file or it may be 'encrypted'") {
                $reason = if ($candidatePasswords.Count -gt 0) { "encrypted-or-not-tps (password attempts failed)" } else { "encrypted-or-not-tps (no password supplied)" }
            }

            $failed.Add("$($tpsFile.FullName) | $reason")
            Write-Warning "Failed: $($tpsFile.FullName) [$reason]"
        }
    }

    if ($failed.Count -gt 0) {
        $failed | Set-Content -Path $FailedReportPath -Encoding UTF8
        Write-Warning "$($failed.Count) file(s) failed conversion."
        Write-Warning "$recoveredWithPassword file(s) recovered via password retry."
        Write-Warning "Failed report: $FailedReportPath"
        $failed | ForEach-Object { Write-Warning " - $_" }
    } else {
        if (Test-Path $FailedReportPath) {
            Remove-Item $FailedReportPath -Force
        }
        Write-Host "$recoveredWithPassword file(s) recovered via password retry."
        Write-Host "No failed files."
    }

    Write-Host "Done. Output folder: $OutputDir"
}
finally {
    Pop-Location
}
