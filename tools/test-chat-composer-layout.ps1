$ErrorActionPreference = "Stop"

$composerPath = Join-Path $PSScriptRoot "../App/Views/Chat/ChatComposerView.swift"
$source = Get-Content -Raw -LiteralPath $composerPath

if ($source -notmatch [regex]::Escape('.fixedSize(horizontal: false, vertical: true)')) {
    throw "ChatComposerView must use its intrinsic vertical size; otherwise Shape backgrounds expand inside safeAreaInset."
}

Write-Output "ChatComposerView intrinsic-height guard passed."
