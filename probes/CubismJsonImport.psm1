Set-StrictMode -Version Latest
function ConvertTo-CubismJsonText([string]$Text) {
    # Tokenize strings first; preserve IDs and numerical values.
    # Pinned SDK ParseNumeric requires newline/comma, not brackets or spaces,
    # and does not support exponent notation.
    $null=ConvertFrom-Json -InputObject $Text -ErrorAction Stop
    $pattern='"(?:\\.|[^"\\])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
    $result=[regex]::Replace($Text,$pattern,[Text.RegularExpressions.MatchEvaluator]{
        param($token)
        $value=$token.Value
        if($value.StartsWith('"')){return $value}
        if($value -match '[eE]'){
            $pieces=$value -split '[eE]'
            $exponent=[int]$pieces[1]
            if([Math]::Abs($exponent) -gt 1000){throw 'Numeric exponent exceeds model import bound.'}
            $sign=''
            $mantissa=$pieces[0]
            if($mantissa.StartsWith('-')){$sign='-';$mantissa=$mantissa.Substring(1)}
            $dot=$mantissa.IndexOf('.')
            if($dot -lt 0){$dot=$mantissa.Length}
            $digits=$mantissa.Replace('.','')
            $position=$dot+$exponent
            if($position -le 0){$value=$sign+'0.'+('0'*(-$position))+$digits}
            elseif($position -ge $digits.Length){$value=$sign+$digits+('0'*($position-$digits.Length))}
            else{$value=$sign+$digits.Substring(0,$position)+'.'+$digits.Substring($position)}
        }
        return $value+[Environment]::NewLine
    })
    $null=ConvertFrom-Json -InputObject $result -ErrorAction Stop
    return $result
}
function Convert-PrivateModelJson([string]$ModelDirectory) {
    foreach($file in @(Get-ChildItem -LiteralPath $ModelDirectory -Recurse -File -Filter '*.json')){
        $text=[IO.File]::ReadAllText($file.FullName)
        $converted=ConvertTo-CubismJsonText $text
        [IO.File]::WriteAllText($file.FullName,$converted,(New-Object Text.UTF8Encoding($false)))
    }
}
Export-ModuleMember -Function ConvertTo-CubismJsonText,Convert-PrivateModelJson
