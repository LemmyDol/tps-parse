#Requires -Version 5.1
<#
.SYNOPSIS
    Unified MySQL rebuild and row-count verification test runner.
    
.DESCRIPTION
    Executes the full MySQL import pipeline and validates end-to-end correctness:
    1. Rebuild database schema and load data from normalized CSV extracts
    2. Verify that imported row counts match the source CSV row counts
    3. Report pass/fail status and diagnostic summary
    
.PARAMETER MysqlHost
    MySQL server host (default: 127.0.0.1)
    
.PARAMETER MysqlPort
    MySQL server port (default: 3309 for XAMPP)
    
.PARAMETER MysqlUser
    MySQL user account (default: root)
    
.PARAMETER MysqlPassword
    MySQL password (required if not in environment)
    
.PARAMETER MysqlDatabase
    Target database name (default: labelpro_restored)
    
.EXAMPLE
    .\rebuild-and-verify-mysql.ps1 -MysqlPassword "Georgina30&19491"
    
.EXAMPLE
    $env:MYSQL_PASSWORD = "Georgina30&19491"
    .\rebuild-and-verify-mysql.ps1
#>

param(
    [string]$MysqlHost = "127.0.0.1",
    [string]$MysqlPort = "3309",
    [string]$MysqlUser = "root",
    [string]$MysqlPassword,
    [string]$MysqlDatabase = "labelpro_restored"
)

$ErrorActionPreference = "Stop"

# Resolve paths
$scriptDir = "D:\Label Pro\tps-parse\scripts"
$projectRoot = "D:\Label Pro\tps-parse"
$mysqlPackageDir = "D:\Label Pro\Label Pro Database\mysql_package"
$verifyScriptPath = Join-Path $scriptDir "verify-mysql-row-counts.js"
$reportDir = Join-Path $projectRoot "out-test"

Write-Host @"
================================================================================
  MySQL Rebuild & Verification Test
================================================================================
  Host:         $MysqlHost
  Port:         $MysqlPort
  User:         $MysqlUser
  Database:     $MysqlDatabase
  MySQL Package: $mysqlPackageDir
  Verify Script: $verifyScriptPath
  Report Dir:    $reportDir
================================================================================
"@

# Set environment variables for Node scripts
$env:MYSQL_HOST = $MysqlHost
$env:MYSQL_PORT = $MysqlPort
$env:MYSQL_USER = $MysqlUser
$env:MYSQL_DATABASE = $MysqlDatabase
if ($MysqlPassword) {
    $env:MYSQL_PASSWORD = $MysqlPassword
} elseif (-not $env:MYSQL_PASSWORD) {
    Write-Error "MYSQL_PASSWORD not provided and not in environment"
    exit 1
}

# Test 1: Rebuild
Write-Host "`n[1/2] Rebuilding database from normalized CSV extracts..."
try {
    Push-Location $mysqlPackageDir
    & node run_mysql_build.js
    if ($LASTEXITCODE -ne 0) {
        throw "Build script failed with exit code $LASTEXITCODE"
    }
    Pop-Location
    Write-Host "[1/2] Build completed successfully." -ForegroundColor Green
} catch {
    Write-Host "[1/2] Build FAILED: $_" -ForegroundColor Red
    exit 1
}

# Test 2: Verify row counts
Write-Host "`n[2/2] Verifying CSV vs MySQL row counts..."
try {
    & node $verifyScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Verify script failed with exit code $LASTEXITCODE"
    }
    Write-Host "[2/2] Verification completed successfully." -ForegroundColor Green
} catch {
    Write-Host "[2/2] Verification FAILED: $_" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host @"

================================================================================
  Test Summary
================================================================================
  Build Status:      PASS
  Verify Status:     PASS
  Overall Status:    PASS
  
  Report Location:   $reportDir\mysql-rowcount-report.txt
================================================================================
"@ -ForegroundColor Green

exit 0
