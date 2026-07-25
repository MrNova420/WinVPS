$coreFiles = Get-ChildItem 'C:\WinVPS\src\core\*.ps1'
$passed = 0
$failed = 0
foreach ($f in $coreFiles) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Host "FAIL: $($f.Name) - $($errors.Count) errors"
        $errors | ForEach-Object { Write-Host "  $_" }
        $failed++
    } else {
        Write-Host "PASS: $($f.Name)"
        $passed++
    }
}
Write-Host ""
Write-Host "Core modules: $passed passed, $failed failed"
