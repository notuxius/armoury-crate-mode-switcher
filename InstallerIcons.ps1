function New-AsusModeIcon {
    param([byte[]]$Png)

    $asusSourceStream = [IO.MemoryStream]::new($Png, $false)
    $asusOutput = [IO.MemoryStream]::new()
    $asusWriter = [IO.BinaryWriter]::new($asusOutput)
    try {
        $asusSource = [Drawing.Image]::FromStream($asusSourceStream, $false, $true)
        try {
            if ($asusSource.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid) {
                throw 'The ASUS icon resource is not a PNG.'
            }
            $asusSizes = @(16,20,24,32,40,48,64,256)
            $asusImages = [Collections.Generic.List[byte[]]]::new()
            $asusAttributes = [Drawing.Imaging.ImageAttributes]::new()
            try {
                # Preserve the neutral menu color of the previously installed ASUS artwork.
                $asusMatrix = [Drawing.Imaging.ColorMatrix]::new()
                $asusMatrix.Matrix00 = 176.0 / 255.0
                $asusMatrix.Matrix11 = 186.0 / 255.0
                $asusMatrix.Matrix22 = 195.0 / 255.0
                $asusAttributes.SetColorMatrix($asusMatrix)
                foreach ($asusSize in $asusSizes) {
                    $asusBitmap = [Drawing.Bitmap]::new($asusSize,$asusSize,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
                    $asusGraphics = [Drawing.Graphics]::FromImage($asusBitmap)
                    $asusFrame = [IO.MemoryStream]::new()
                    try {
                        $asusGraphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                        $asusGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $asusGraphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                        $asusRect = [Drawing.Rectangle]::new(0,0,$asusSize,$asusSize)
                        $asusGraphics.DrawImage($asusSource,$asusRect,0,0,$asusSource.Width,$asusSource.Height,[Drawing.GraphicsUnit]::Pixel,$asusAttributes)
                        $asusBitmap.Save($asusFrame,[Drawing.Imaging.ImageFormat]::Png)
                        $asusImages.Add($asusFrame.ToArray())
                    } finally {
                        $asusFrame.Dispose(); $asusGraphics.Dispose(); $asusBitmap.Dispose()
                    }
                }
            } finally { $asusAttributes.Dispose() }
        } finally { $asusSource.Dispose() }

        # PNG-backed ICO frames preserve transparency at all menu and shortcut sizes.
        $asusWriter.Write([UInt16]0); $asusWriter.Write([UInt16]1); $asusWriter.Write([UInt16]$asusSizes.Count)
        $asusOffset = 6 + 16 * $asusSizes.Count
        for ($asusIndex = 0; $asusIndex -lt $asusSizes.Count; $asusIndex++) {
            $asusDimension = $asusSizes[$asusIndex] % 256
            $asusWriter.Write([byte]$asusDimension); $asusWriter.Write([byte]$asusDimension)
            $asusWriter.Write([byte]0); $asusWriter.Write([byte]0)
            $asusWriter.Write([UInt16]1); $asusWriter.Write([UInt16]32)
            $asusWriter.Write([UInt32]$asusImages[$asusIndex].Length); $asusWriter.Write([UInt32]$asusOffset)
            $asusOffset += $asusImages[$asusIndex].Length
        }
        foreach ($asusImage in $asusImages) { $asusWriter.Write([byte[]]$asusImage) }
        return ,($asusOutput.ToArray())
    } finally {
        $asusWriter.Dispose(); $asusSourceStream.Dispose()
    }
}

function Install-AsusModeIcons {
    param([string]$Destination)

    $asusDll = Join-Path $env:ProgramData 'ASUS\ASUS System Control Interface\AsusOptimization\ASUS Keyboard Hotkeys\ATKOSD2Help.dll'
    $asusCanExtract = $false
    try {
        if (Test-Path -LiteralPath $asusDll -PathType Leaf) {
            $asusSignature = Get-AuthenticodeSignature -LiteralPath $asusDll
            if ($asusSignature.Status -eq 'Valid' -and $asusSignature.SignerCertificate.GetNameInfo('SimpleName', $false) -eq 'ASUSTeK COMPUTER INC.') {
                Add-Type -AssemblyName System.Drawing
                if (-not ('AsusModeIconResource' -as [type])) {
                    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AsusModeIconResource {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindResource(IntPtr module, string name, string type);
    [DllImport("kernel32.dll")]
    static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")]
    static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")]
    static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll")]
    static extern bool FreeLibrary(IntPtr module);

    public static byte[] Read(string path, string name) {
        // Map the DLL as data and resources. Never initialize or execute its code.
        IntPtr module = LoadLibraryEx(path, IntPtr.Zero, 0x02 | 0x20);
        if (module == IntPtr.Zero) return null;
        try {
            IntPtr resource = FindResource(module, name, "4K");
            if (resource == IntPtr.Zero) return null;
            uint size = SizeofResource(module, resource);
            if (size < 8 || size > 4 * 1024 * 1024) return null;
            IntPtr loaded = LoadResource(module, resource);
            if (loaded == IntPtr.Zero) return null;
            IntPtr data = LockResource(loaded);
            if (data == IntPtr.Zero) return null;
            byte[] png = new byte[(int)size];
            Marshal.Copy(data, png, 0, png.Length);
            return png;
        } finally {
            FreeLibrary(module);
        }
    }
}
'@
                }
                $asusCanExtract = $true
            }
        }
    } catch {
        Write-Verbose ('ASUS icon source unavailable: ' + $_.Exception.Message)
    }

    $asusResources = [ordered]@{ Silent = 'SILENT'; Performance = 'DEFAULT'; Turbo = 'TURBO' }
    foreach ($asusMode in $asusResources.Keys) {
        [byte[]]$asusIcon = $null
        if ($asusCanExtract) {
            try {
                $asusPng = [AsusModeIconResource]::Read($asusDll, "THROTTLEGEAR_$($asusResources[$asusMode])6")
                if ($asusPng) { $asusIcon = New-AsusModeIcon -Png $asusPng }
            } catch {
                Write-Verbose ('ASUS icon unavailable for ' + $asusMode + ': ' + $_.Exception.Message)
            }
        }
        # Retain the established paths used by already-pinned shortcuts.
        $asusIconPath = Join-Path $Destination ($asusMode + '-menu-asus6.ico')
        if ($null -ne $asusIcon) {
            [IO.File]::WriteAllBytes($asusIconPath, $asusIcon)
        } else {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('icons\Fallback\' + $asusMode + '.ico')) -Destination $asusIconPath -Force
        }
    }
}
