[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SignToolPath,

    [Parameter(Mandatory)]
    [string]$SigningDlibPath,

    [Parameter(Mandatory)]
    [string]$MetadataPath,

    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0',

    [string]$InnoCompilerPath = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
)

$ErrorActionPreference = 'Stop'
$signTool = (Resolve-Path -LiteralPath $SignToolPath).Path
$dlib = (Resolve-Path -LiteralPath $SigningDlibPath).Path
$metadata = (Resolve-Path -LiteralPath $MetadataPath).Path
$compiler = (Resolve-Path -LiteralPath $InnoCompilerPath).Path
$timestampUrl = 'http://timestamp.acs.microsoft.com'

function Assert-TimestampedSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or !$signature.TimeStamperCertificate) {
        throw "Missing a valid timestamped signature: $Path"
    }
}

Push-Location $PSScriptRoot
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows release build failed.' }

    $release = '.\build\windows\x64\runner\Release'
    $app = (Get-Item -LiteralPath (Join-Path $release 'RealFaceAI.exe')).FullName
    $binaries = Get-ChildItem -LiteralPath $release -Recurse -File |
        Where-Object { $_.Extension -in '.exe', '.dll' }

    foreach ($binary in $binaries) {
        $path = $binary.FullName
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($path -ne $app -and $signature.Status -eq 'Valid') { continue }
        if ($signature.Status -notin 'NotSigned', 'Valid') {
            throw "Existing signature on $path has status $($signature.Status). Check the source binary."
        }

        & $signTool sign /fd SHA256 /tr $timestampUrl /td SHA256 /dlib $dlib /dmdf $metadata $path
        if ($LASTEXITCODE -ne 0) { throw "SignTool failed for $path." }
        Assert-TimestampedSignature $path
    }

    # Inno expands $q to a quote and $f to the quoted file it is signing.
    $signCommand = '/SAzureArtifactSigning=$q{0}$q sign /fd SHA256 /tr {1} /td SHA256 /dlib $q{2}$q /dmdf $q{3}$q $f' -f $signTool, $timestampUrl, $dlib, $metadata
    & $compiler "/DAppVer=$Version" '/DUseAzureArtifactSigning=1' $signCommand '.\installer.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup signing or compilation failed.' }

    $setup = (Get-Item -LiteralPath ".\installer_output\RealFaceAI-Setup-$Version.exe").FullName
    Assert-TimestampedSignature $setup
    Write-Output "Signed installer: $setup"
} finally {
    Pop-Location
}
