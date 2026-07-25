$files = @(
    'C:\WinVPS\src\core\service-manager.ps1',
    'C:\WinVPS\src\core\supervisor.ps1',
    'C:\WinVPS\src\cli\winvps.ps1',
    'C:\WinVPS\src\tunnels\tunnel-manager.ps1',
    'C:\WinVPS\src\core\security.ps1'
)
$passed = 0; $failed = 0
foreach ($f in $files) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errors)
    $name = Split-Path $f -Leaf
    if ($errors.Count -gt 0) {
        Write-Host "FAIL: $name - $($errors.Count) errors"
        $errors | Select-Object -First 3 | ForEach-Object {
            Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)"
        }
        $failed++
    } else {
        Write-Host "PASS: $name"
        $passed++
    }
}
Write-Host "`nResults: $passed passed, $failed failed"
