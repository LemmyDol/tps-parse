param(
    [string]$CsvDir = "D:\OneDrive\Label Pro Analysis\Database\csv-output",
    [string]$OutputCsv = "D:\Label Pro\tps-parse\out-test\recno-analysis.csv",
    [string]$OutputSummary = "D:\Label Pro\tps-parse\out-test\recno-summary.txt"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (!(Test-Path $CsvDir)) {
    throw "CSV folder not found: $CsvDir"
}

$rows = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem -Path $CsvDir -Filter "*.csv" -File | Sort-Object Name

foreach ($file in $files) {
    $reader = [System.IO.File]::OpenText($file.FullName)
    try {
        $headerLine = $reader.ReadLine()
        if ($null -eq $headerLine) {
            continue
        }

        $firstHeader = ($headerLine -split ',', 2)[0].Trim('"')
        if ($firstHeader.ToLower() -ne "rec no" -and $firstHeader.ToLower() -ne "rec_no") {
            continue
        }

        $lineCount = 0
        $numericCount = 0
        $min = [int]::MaxValue
        $max = [int]::MinValue
        $odd = 0
        $even = 0
        $distinct = New-Object 'System.Collections.Generic.HashSet[int]'

        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $lineCount++

            $firstField = ($line -split ',', 2)[0].Trim('"')
            $value = 0
            if ([int]::TryParse($firstField, [ref]$value)) {
                $numericCount++
                [void]$distinct.Add($value)
                if ($value -lt $min) { $min = $value }
                if ($value -gt $max) { $max = $value }
                if (($value % 2) -eq 0) { $even++ } else { $odd++ }
            }
        }

        if ($numericCount -eq 0) {
            continue
        }

        $rangeSize = $max - $min + 1
        $distinctCount = $distinct.Count
        $estimatedGaps = [Math]::Max(0, $rangeSize - $distinctCount)
        $parity = if ($odd -eq 0) { "even-only" } elseif ($even -eq 0) { "odd-only" } else { "mixed" }

        $rows.Add([pscustomobject]@{
            File = $file.Name
            DataRows = $lineCount
            NumericRecNoRows = $numericCount
            DistinctRecNo = $distinctCount
            MinRecNo = $min
            MaxRecNo = $max
            RangeSize = $rangeSize
            EstimatedMissingRecNo = $estimatedGaps
            EvenCount = $even
            OddCount = $odd
            Parity = $parity
        }) | Out-Null
    }
    finally {
        $reader.Close()
    }
}

$rows | Sort-Object File | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

$totalTables = $rows.Count
$tablesWithGaps = ($rows | Where-Object { $_.EstimatedMissingRecNo -gt 0 }).Count
$evenOnly = ($rows | Where-Object { $_.Parity -eq "even-only" }).Count
$oddOnly = ($rows | Where-Object { $_.Parity -eq "odd-only" }).Count
$mixed = ($rows | Where-Object { $_.Parity -eq "mixed" }).Count

$summary = @(
    "Tables analyzed: $totalTables",
    "Tables with rec_no gaps: $tablesWithGaps",
    "Parity even-only: $evenOnly",
    "Parity odd-only: $oddOnly",
    "Parity mixed: $mixed",
    "Analysis CSV: $OutputCsv"
)

$summary | Set-Content -Path $OutputSummary -Encoding UTF8
$summary | ForEach-Object { Write-Host $_ }
