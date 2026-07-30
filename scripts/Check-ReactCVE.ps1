<#
.SYNOPSIS
    Checks a URL for indicators of CVE-2025-55182/CVE-2025-66478 "React2Shell" vulnerability
.DESCRIPTION
    Checks based on the SearchLight Cyber post: https://slcyber.io/research-center/high-fidelity-detection-mechanism-for-rsc-next-js-rce-cve-2025-55182-cve-2025-66478/
	I assume no responsibility for any loss, damage, downtime etc. due to running this script.
.PARAMETER Url
    Mandatory. 
	Specify the url to check.
.EXAMPLE
	Check-ReactCVE -Url https://contoso.com
.VERSION
	1.0
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$Url
)

# Ignore Invalid cert warnings, saved to variables to restore settings after command runs
$OriginalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
$OriginalProtocol = [System.Net.ServicePointManager]::SecurityProtocol
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

$Target = $Url.TrimEnd('/')
$Boundary = "----WebKitFormBoundaryx8jO2oVc6SWP3Sad"
$CRLF = "`r`n"

try {
	$Headers = @{
		"User-Agent"                = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.113 Safari/537.36 Assetnote/1.0.0"
		"Next-Action"               = "x"
		"X-Nextjs-Request-Id"       = "b5dce965"
		"Next-Router-State-Tree"    = "%5B%22%22%2C%7B%22children%22%3A%5B%22__PAGE__%22%2C%7B%7D%2Cnull%2Cnull%5D%7D%2Cnull%2Cnull%2Ctrue%5D"
		"X-Nextjs-Html-Request-Id"  = "SSTMXm7OJ_g0Ncx6jpQt9"
	}

	# Multipart Body (Strict formatting)
	$BodyLines = @(
		"--$Boundary",
		'Content-Disposition: form-data; name="1"',
		'',
		'{}',
		"--$Boundary",
		'Content-Disposition: form-data; name="0"',
		'',
		'["$1:a:a"]',
		"--$Boundary--"
	)
	$BodyPayload = $BodyLines -join $CRLF
	Write-Host "Disabling strict TLS checking...`n" -ForegroundColor DarkGray
	Start-Sleep -seconds 1
	Write-Host "Sending Payload to: $Target`n" -ForegroundColor Cyan

	try {
		$response = Invoke-WebRequest -Uri $Target `
			-Method Post `
			-Headers $Headers `
			-ContentType "multipart/form-data; boundary=$Boundary" `
			-Body $BodyPayload `
			-UseBasicParsing
		
		# Display this if server doesn't return HTTP 500 or any other errors
		Write-Host "[-] Server returned code $($response.StatusCode). Vulnerability likely NOT triggered." -ForegroundColor Green

	} catch {
		# Error handling
		$errResp = $_.Exception.Response

		if ($null -ne $errResp) {
			$statusCode = [int]$errResp.StatusCode
			$cType = $errResp.Headers["Content-Type"]
			
			# Read the error stream
			$stream = $errResp.GetResponseStream()
			$reader = New-Object System.IO.StreamReader($stream)
			$content = $reader.ReadToEnd()
			
			# Confirm error code
			if ($statusCode -eq 500) {
				Write-Host "[!] 500 Internal Server Error detected." -ForegroundColor Yellow
				
				if ($cType -match "text/x-component") {
					Write-Host "[!] Content-Type 'text/x-component' confirmed." -ForegroundColor Yellow
					
					# Check for the specific RSC error structure: 1:E{"digest":"..."}
					if ($content -match '1:E\{"digest":') {
						Write-Host "`n[VULNERABLE] Target confirmed vulnerable to CVE-2025-55182" -ForegroundColor Red
						Write-Host "Match Found: $($Matches[0])" -ForegroundColor Red
						return
					}
				}
			}
			
			Write-Host "[-] Response did not match vulnerability signature." -ForegroundColor Gray
			Write-Host "    Status: $statusCode | Type: $cType" -ForegroundColor Gray
		} else {
			Write-Host "Error sending request: $($_.Exception.Message)" -ForegroundColor Red
		}
	}
} finally {
	# Re-enable default TLS settings
	[System.Net.ServicePointManager]::ServerCertificateValidationCallback = $OriginalCallback
	[System.Net.ServicePointManager]::SecurityProtocol = $OriginalProtocol
	Write-Host "`nSSL/TLS security settings restored to defaults." -ForegroundColor DarkGray
}