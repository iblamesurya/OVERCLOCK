$root = 'c:\Users\tummala surya\Downloads\roblox'
$mapping = @{
    'ReplicatedStorage' = 'src\shared'
    'ServerScriptService' = 'src\server'
    'StarterPlayerScripts' = 'src\client'
}

$files = Get-ChildItem -Path "$root\src" -Recurse -Filter '*.luau'
$errors = 0
$checked = 0

foreach ($file in $files) {
    $lines = Get-Content -Path $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match 'require\((ReplicatedStorage|ServerScriptService|StarterPlayerScripts)\.([^)]+)\)') {
            $checked++
            $service = $matches[1]
            $relPath = $matches[2] -replace '\.', '\'
            $diskBase = $mapping[$service]
            $targetPath1 = Join-Path $root "$diskBase\$relPath.luau"
            $targetPath2 = Join-Path $root "$diskBase\$relPath\init.luau"
            if ((-not (Test-Path $targetPath1)) -and (-not (Test-Path $targetPath2))) {
                Write-Host "MISSING IMPORT: $($file.FullName):$($i+1): $line -> Target not found: $targetPath1 or $targetPath2"
                $errors++
            }
        }
    }
}
Write-Host "Checked $checked absolute require statements. Errors found: $errors"
