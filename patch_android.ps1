# Ajoute la permission internet et le nom "Scan FR" dans le manifeste Android
$p = Join-Path $PSScriptRoot 'android\app\src\main\AndroidManifest.xml'
$c = [IO.File]::ReadAllText($p)
if ($c -notmatch 'android.permission.INTERNET') {
    $c = $c -replace '<application', "<uses-permission android:name=`"android.permission.INTERNET`"/>`r`n    <application"
}
$c = $c -replace 'android:label="scan_fr"', 'android:label="Scan FR"'
[IO.File]::WriteAllText($p, $c)
