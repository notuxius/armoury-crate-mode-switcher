$ErrorActionPreference = 'Stop'
$asusCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $asusCompiler)) { throw 'The Windows .NET Framework compiler is unavailable.' }
& $asusCompiler /nologo /target:winexe /platform:anycpu /optimize+ /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll /reference:System.ServiceProcess.dll /reference:Microsoft.CSharp.dll ('/win32manifest:' + (Join-Path $PSScriptRoot 'app.manifest')) ('/out:' + (Join-Path $PSScriptRoot 'AsusMode.exe')) (Join-Path $PSScriptRoot 'AsusMode.cs')
if ($LASTEXITCODE -ne 0) { throw 'Could not build the windowless mode helper.' }
# The source PNGs are unmodified ASUS THROTTLEGEAR_*6 resources.
# Convert them to a neutral menu color, preserving the original alpha/outline.
Add-Type -AssemblyName System.Drawing
foreach ($asusMode in @('Silent','Performance','Turbo')) {
    $asusIconsPath = Join-Path $PSScriptRoot 'icons'
    $asusSource = [Drawing.Bitmap]::new((Join-Path $asusIconsPath ($asusMode + '.png')))
    $asusImages = [Collections.Generic.List[byte[]]]::new()
    $asusSizes = @(16,20,24,32,40,48,64,256)
    try {
        foreach ($asusSize in $asusSizes) {
            $asusBitmap = [Drawing.Bitmap]::new($asusSize,$asusSize,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $asusGraphics = [Drawing.Graphics]::FromImage($asusBitmap)
            $asusAttributes = [Drawing.Imaging.ImageAttributes]::new()
            $asusStream = [IO.MemoryStream]::new()
            try {
                $asusGraphics.Clear([Drawing.Color]::Transparent)
                $asusGraphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                $asusGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $asusGraphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $asusMatrix = [Drawing.Imaging.ColorMatrix]::new()
                $asusMatrix.Matrix00 = 176.0 / 255.0
                $asusMatrix.Matrix11 = 186.0 / 255.0
                $asusMatrix.Matrix22 = 195.0 / 255.0
                $asusAttributes.SetColorMatrix($asusMatrix)
                $asusRect = [Drawing.Rectangle]::new(0,0,$asusSize,$asusSize)
                $asusGraphics.DrawImage($asusSource,$asusRect,0,0,$asusSource.Width,$asusSource.Height,[Drawing.GraphicsUnit]::Pixel,$asusAttributes)
                $asusBitmap.Save($asusStream,[Drawing.Imaging.ImageFormat]::Png)
                $asusImages.Add($asusStream.ToArray())
            } finally {
                $asusStream.Dispose(); $asusAttributes.Dispose(); $asusGraphics.Dispose(); $asusBitmap.Dispose()
            }
        }
        # Windows supports PNG-backed ICO frames, retaining partial alpha at every size.
        $asusFile = [IO.File]::Create((Join-Path $asusIconsPath ($asusMode + '.ico')))
        $asusWriter = [IO.BinaryWriter]::new($asusFile)
        try {
            $asusWriter.Write([UInt16]0); $asusWriter.Write([UInt16]1); $asusWriter.Write([UInt16]$asusSizes.Count)
            $asusOffset = 6 + 16 * $asusSizes.Count
            for ($asusIndex = 0; $asusIndex -lt $asusSizes.Count; $asusIndex++) {
                $asusDimension = if ($asusSizes[$asusIndex] -eq 256) { 0 } else { $asusSizes[$asusIndex] }
                $asusWriter.Write([byte]$asusDimension); $asusWriter.Write([byte]$asusDimension)
                $asusWriter.Write([byte]0); $asusWriter.Write([byte]0)
                $asusWriter.Write([UInt16]1); $asusWriter.Write([UInt16]32)
                $asusWriter.Write([UInt32]$asusImages[$asusIndex].Length); $asusWriter.Write([UInt32]$asusOffset)
                $asusOffset += $asusImages[$asusIndex].Length
            }
            foreach ($asusImage in $asusImages) { $asusWriter.Write([byte[]]$asusImage) }
        } finally { $asusWriter.Dispose() }
    } finally { $asusSource.Dispose() }
}
