# The downloaded DLL is loaded into the session with Add-Type, so the default
# install is a pinned release whose package hash was verified against nuget.org's
# catalog when it was pinned. Bump both values together; the hash is the SHA-512
# of qrcoder.<version>.nupkg (Get-FileHash -Algorithm SHA512).
$script:QRCoderPinnedVersion = '1.8.1'
$script:QRCoderPinnedSha512 = 'DCC83E692A0234ACFBC37390E8AC6988DC44BBA020384E65AAC39134DBBADE179175ABBDC0CDF82140A6B6F90A0C2082DA8ADAC7194E553297FC7B17600C4753'
