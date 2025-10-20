function Install-WebConfig {
    param(
        [string]$FrontendHost,
        [string]$TargetFolder,
        [string]$TargetFile
    )

    # Build paths
    $TargetPath = Join-Path -Path $TargetFolder -ChildPath $TargetFile
    $ForbiddenTargetFolder = Join-Path -Path $TargetFolder -ChildPath "CustomErrors"
    $ForbiddenTarget = Join-Path -Path $ForbiddenTargetFolder -ChildPath "forbidden.html"

    # Construct the Frontend URL
    $FrontendUrl = "https://$FrontendHost/"

    # Full XML web.config with variable substitution
    $WebConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <!-- 403 Error Handling -->
    <httpErrors errorMode="Custom" existingResponse="Replace">
      <remove statusCode="403" />
      <error statusCode="403"
             path="CustomErrors\forbidden.html"
             responseMode="File" />
    </httpErrors>
    <staticContent>
      <mimeMap fileExtension="." mimeType="text/plain" />
    </staticContent>
    <handlers>
      <add name="ACMEStaticFile" path="*" verb="GET" modules="StaticFileModule" resourceType="File" requireAccess="Read" />
    </handlers>
    <proxy enabled="true" />
    <security>
      <ipSecurity allowUnlisted="false">
        <add ipAddress="127.0.0.1" subnetMask="255.255.255.255" allowed="true" />
      </ipSecurity>
    </security>
    <rewrite>
      <rules>
        <rule name="RedirectToHTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="^OFF$" />
            <add input="{REQUEST_URI}" pattern="^/.well-known/" negate="true" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
        <rule name="PowerSyncProReverseProxyInboundRule" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{REQUEST_URI}" pattern="^/.well-known/" negate="true" />
          </conditions>
          <action type="Rewrite" url="http://localhost:5000/{R:1}" />
        </rule>
      </rules>
      <outboundRules>
        <rule name="PowerSyncProReverseProxyOutboundRule1" preCondition="PowerSyncProResponseIsHtml">
          <match filterByTags="A, Form, Img" pattern="^http(s)?://localhost:5000/(.*)" />
          <action type="Rewrite" value="$FrontendUrl{R:2}" />
        </rule>
        <preConditions>
          <preCondition name="PowerSyncProResponseIsHtml">
            <add input="{RESPONSE_CONTENT_TYPE}" pattern="^text/html" />
          </preCondition>
        </preConditions>
      </outboundRules>
    </rewrite>
  </system.webServer>
  <location path="Agent">
    <system.webServer>
      <security>
        <ipSecurity allowUnlisted="true" />
      </security>
    </system.webServer>
  </location>
  <location path=".well-known">
    <system.webServer>
      <security>
        <ipSecurity allowUnlisted="true" />
      </security>
    </system.webServer>
  </location>
</configuration>
"@

    $ForbiddenPage = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>403 Forbidden</title>
  <link href="https://fonts.googleapis.com/css2?family=Source+Sans+Pro:wght@400;700&display=swap" rel="stylesheet">
  <style>
    body {
      margin: 0;
      height: 100vh;
      font-family: 'Source Sans Pro', Arial, sans-serif;
      background-color: #00a8ff;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .error-box {
      background: #ffffff;
      padding: 40px;
      border-radius: 6px;
      width: 360px;
      box-shadow: 0 2px 6px rgba(0,0,0,0.15);
      text-align: center;
    }
    h1 {
      margin: 0 0 15px;
      font-size: 2.5em;
      font-weight: 700;
      color: #e84118;
    }
    h2 {
      margin: 0 0 15px;
      font-size: 1.3em;
      font-weight: 400;
      color: #2f3640;
    }
    p {
      margin: 0;
      font-size: 0.95em;
      line-height: 1.4;
      color: #636e72;
    }
  </style>
</head>
<body>
  <div class="error-box">
    <h1>403</h1>
    <h2>Access Forbidden</h2>
    <p>
      You don't have permission to access this resource.<br>
      This may be expected behavior or an error.<br><br>
      Please review the documentation or contact your support staff for assistance.
    </p>
  </div>
</body>
</html>
"@

    # Ensure target folder exists
    if (-not (Test-Path $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
        Write-Host "Created folder $TargetFolder"
    }

    # Ensure CustomErrors folder exists
    if (-not (Test-Path $ForbiddenTargetFolder)) {
        New-Item -Path $ForbiddenTargetFolder -ItemType Directory -Force | Out-Null
        Write-Host "Created folder $ForbiddenTargetFolder"
    }

    # Write web.config
    $WebConfig | Out-File -FilePath $TargetPath -Encoding UTF8 -Force
    Write-Host "Full web.config written to $TargetPath with backend $FrontendUrl" -ForegroundColor Green

    # Write forbidden.html
    $ForbiddenPage | Out-File -FilePath $ForbiddenTarget -Encoding UTF8 -Force
    Write-Host "Forbidden page template written to $ForbiddenTarget..." -ForegroundColor Green
}

Install-WebConfig -FrontendHost "psp.aboutsib.com" -TargetFolder "C:\inetpub\wwwroot" -TargetFile "web.config"
