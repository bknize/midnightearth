# Writes a new 32-byte random token (base64, one line) to the trainer's token file and
# restricts it to trainer. Prints nothing secret.
$b = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$f = 'C:\Users\trainer\.trainer\token'
[System.IO.File]::WriteAllText($f, [Convert]::ToBase64String($b))
icacls $f /inheritance:r /grant:r "trainer:F"
