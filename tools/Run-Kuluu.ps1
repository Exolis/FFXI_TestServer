<#
.SYNOPSIS
    Launches the Kuluu FFXI client against a local LandSandBoat server.

.DESCRIPTION
    Sets FFXI_DAT_PATH to the retail install (read-only; nothing is written to it)
    and forwards all arguments to kuluu.exe.

    Kuluu's defaults already match stock LSB, so no protocol flags are needed:
      --server 127.0.0.1  --auth-port 54231  --data-port 54230  --view-port 54001
      --auth-flavor json      ("json" is the LSB flavor; "binary" is HorizonXI)

.PARAMETER KuluuArgs
    Arguments passed straight through to kuluu.exe.

.EXAMPLE
    .\Run-Kuluu.ps1 play
    Native window. Prompts for username / password, then lists characters.

.EXAMPLE
    .\Run-Kuluu.ps1 play MyUser MyPass Mychar
    Skips the prompts and auto-selects the named character.

.EXAMPLE
    .\Run-Kuluu.ps1 model-viewer
    Renders a character model straight from the DATs. Needs no server.

.EXAMPLE
    .\Run-Kuluu.ps1 --server 192.168.1.50 play
    Point at a LAN server instead of localhost.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$KuluuArgs
)

$ErrorActionPreference = 'Stop'

$KuluuRepo = 'G:\FFXI_Kuluu'
$DatRoot   = 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI'
$Exe       = Join-Path $KuluuRepo 'target\debug\kuluu.exe'

if (-not (Test-Path $Exe)) {
    Write-Error @"
kuluu.exe not found at:
  $Exe

Build it first:
  `$env:PATH = "`$env:USERPROFILE\.cargo\bin;`$env:PATH"
  cd $KuluuRepo
  cargo build -p kuluu -p xtask

Note: 'cargo build' (whole workspace) fails on Windows because kuluu-mcp
imports tokio::net::UnixStream. Building -p kuluu -p xtask skips it.
"@
}

if (-not (Test-Path $DatRoot)) {
    Write-Error "FFXI install not found at: $DatRoot"
}

# Read-only: the client only reads VTABLE/FTABLE/ROM* from here.
$env:FFXI_DAT_PATH = $DatRoot

if (-not $KuluuArgs -or $KuluuArgs.Count -eq 0) {
    $KuluuArgs = @('play')
}

# --require-dat turns a missing/unreadable install into an immediate hard error
# instead of silently rendering every static NPC name as '?'.
$final = @('--require-dat') + $KuluuArgs

Write-Host "FFXI_DAT_PATH = $DatRoot" -ForegroundColor DarkGray
Write-Host "kuluu.exe $($final -join ' ')" -ForegroundColor Cyan
Write-Host ''

& $Exe @final
exit $LASTEXITCODE
