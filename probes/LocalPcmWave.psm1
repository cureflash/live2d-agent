Set-StrictMode -Version Latest
function Get-LocalPcmWaveInfo([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    $reader=New-Object IO.BinaryReader($stream)
    try {
        if($stream.Length -lt 44 -or $stream.Length -gt 32MB){throw 'WAV size unsupported.'}
        if([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -cne 'RIFF'){throw 'RIFF missing.'}
        if(([long]$reader.ReadUInt32()+8) -ne $stream.Length){throw 'RIFF size mismatch.'}
        if([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -cne 'WAVE'){throw 'WAVE missing.'}
        $format=$null; $dataLength=$null
        while($stream.Position+8 -le $stream.Length) {
            $tag=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            $size=[long]$reader.ReadUInt32()
            $next=$stream.Position+$size+($size % 2)
            if($next -gt $stream.Length){throw 'WAV chunk exceeds file.'}
            if($tag -ceq 'fmt ') {
                if($null -ne $format -or $size -lt 16){throw 'Invalid format chunk.'}
                $format=[ordered]@{Tag=$reader.ReadUInt16();Channels=$reader.ReadUInt16();Rate=$reader.ReadUInt32();ByteRate=$reader.ReadUInt32();Align=$reader.ReadUInt16();Bits=$reader.ReadUInt16()}
            } elseif($tag -ceq 'data') {
                if($null -ne $dataLength){throw 'Duplicate data chunk.'}
                $dataLength=$size
            }
            $stream.Position=$next
        }
        if($null -eq $format -or $null -eq $dataLength -or $dataLength -eq 0){throw 'WAV format/data missing.'}
        if($format.Tag -ne 1 -or $format.Bits -ne 16 -or $format.Channels -notin @(1,2) -or
           $format.Rate -lt 8000 -or $format.Rate -gt 192000 -or
           $format.Align -ne ($format.Channels*2) -or $format.ByteRate -ne ($format.Rate*$format.Align) -or
           $dataLength % $format.Align -ne 0){throw 'Native player requires PCM16 mono/stereo.'}
        [pscustomobject]@{Seconds=[double]$dataLength/$format.ByteRate;Channels=$format.Channels;SampleRate=$format.Rate;Bits=$format.Bits}
    } finally { $reader.Dispose(); $stream.Dispose() }
}
Export-ModuleMember -Function Get-LocalPcmWaveInfo
