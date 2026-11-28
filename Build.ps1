$ErrorActionPreference = 'Stop'
$asusCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $asusCompiler)) { throw 'The Windows .NET Framework compiler is unavailable.' }
$asusIcon = Join-Path $PSScriptRoot 'icons\App.ico'
& $asusCompiler /nologo /target:winexe /platform:anycpu /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll /reference:System.ServiceProcess.dll /reference:Microsoft.CSharp.dll ('/win32icon:' + $asusIcon) ('/win32manifest:' + (Join-Path $PSScriptRoot 'app.manifest')) ('/out:' + (Join-Path $PSScriptRoot 'AsusMode.exe')) (Join-Path $PSScriptRoot 'AsusMode.cs')
if ($LASTEXITCODE -ne 0) { throw 'Could not build the windowless mode helper.' }
