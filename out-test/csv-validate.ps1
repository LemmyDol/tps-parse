Add-Type -AssemblyName Microsoft.VisualBasic

$outDir = "D:\OneDrive\Label Pro Analysis\Database\csv-output"
$report = "D:\Label Pro\tps-parse\out-test\csv-quality-report.txt"
$csvFiles = Get-ChildItem $outDir -Filter "*.csv" -File

$results = foreach ($file in $csvFiles) {
    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($file.FullName)
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes = $true
    $parser.TrimWhiteSpace = $false

    $headerCount = $null
    $rowNumber = 0
    $dataRows = 0
    $status = 'ok'
    $detail = ''

    try {
        if (-not $parser.EndOfData) {
            $header = $parser.ReadFields()
            $rowNumber = 1
            $headerCount = $header.Count
        }

        while (-not $parser.EndOfData) {
            $fields = $parser.ReadFields()
            $rowNumber++
            $dataRows++

            if ($headerCount -ne $null -and $fields.Count -ne $headerCount) {
                $status = 'column-mismatch'
                $detail = "row=$rowNumber header=$headerCount fields=$($fields.Count)"
                break
            }
        }
    }
    catch [Microsoft.VisualBasic.FileIO.MalformedLineException] {
        $status = 'malformed'
        $detail = "row=$rowNumber line=$($_.Exception.LineNumber) $($_.Exception.Message)"
    }
    catch {
        $status = 'error'
        $detail = $_.Exception.Message
    }
    finally {
        $parser.Close()
    }

    [pscustomobject]@{
        File = $file.Name
        HeaderColumns = $headerCount
        DataRows = $dataRows
        Status = $status
        Detail = $detail
    }
}

$headerOnly = $results | Where-Object { $_.Status -eq 'ok' -and $_.DataRows -eq 0 }
$issues = $results | Where-Object { $_.Status -ne 'ok' }
$withData = $results | Where-Object { $_.Status -eq 'ok' -and $_.DataRows -gt 0 }

$lines = @()
$lines += "Total CSVs: $($results.Count)"
$lines += "Valid with data: $($withData.Count)"
$lines += "Header-only: $($headerOnly.Count)"
$lines += "Issues: $($issues.Count)"
$lines += ""
$lines += "Issue files:"
if ($issues.Count -eq 0) {
    $lines += "None"
}
else {
    $lines += ($issues | Sort-Object File | ForEach-Object { "- $($_.File) | $($_.Status) | $($_.Detail)" })
}
$lines += ""
$lines += "Top files by row count:"
$lines += ($withData | Sort-Object DataRows -Descending | Select-Object -First 20 | ForEach-Object { "- $($_.File) | columns=$($_.HeaderColumns) | rows=$($_.DataRows)" })

$lines | Set-Content -Path $report -Encoding UTF8

Write-Host "Total CSVs: $($results.Count)"
Write-Host "Valid with data: $($withData.Count)"
Write-Host "Header-only: $($headerOnly.Count)"
Write-Host "Issues: $($issues.Count)"
Write-Host "Report: $report"
