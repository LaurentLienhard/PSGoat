class PSGLogger
{
    [string]$ServiceName
    [string]$ServiceVersion
    [string]$LogFilePath
    [bool]$FileLoggingEnabled
    [string]$TraceId
    [string]$SpanId
    [long]$MaxFileSizeBytes
    [int]$RotationCheckInterval
    hidden [int]$WriteCount

    hidden [void] Init([string]$ServiceName, [string]$ServiceVersion)
    {
        $this.ServiceName           = $ServiceName
        $this.ServiceVersion        = $ServiceVersion
        $this.FileLoggingEnabled    = $false
        $this.MaxFileSizeBytes      = 10MB
        $this.RotationCheckInterval = 100
        $this.TraceId               = [System.Guid]::NewGuid().ToString('N')
        $this.SpanId                = [System.Guid]::NewGuid().ToString('N').Substring(0, 16)
    }

    # Console-only logger.
    PSGLogger([string]$ServiceName, [string]$ServiceVersion)
    {
        $this.Init($ServiceName, $ServiceVersion)
    }

    # Console + file logger.
    PSGLogger([string]$ServiceName, [string]$ServiceVersion, [string]$LogFilePath)
    {
        $this.Init($ServiceName, $ServiceVersion)
        $this.LogFilePath        = $LogFilePath
        $this.FileLoggingEnabled = $true
    }

    # Builds an OTel-compatible JSON log record (NDJSON / JSON Lines format).
    hidden [string] BuildRecord([string]$SeverityText, [int]$SeverityNumber, [string]$Message, [hashtable]$Attributes)
    {
        $record = [ordered]@{
            timestamp      = [System.DateTime]::UtcNow.ToString('o')
            severityText   = $SeverityText
            severityNumber = $SeverityNumber
            traceId        = $this.TraceId
            spanId         = $this.SpanId
            body           = $Message
            resource       = [ordered]@{
                'service.name'    = $this.ServiceName
                'service.version' = $this.ServiceVersion
                'host.name'       = $env:COMPUTERNAME
                'os.type'         = [System.Environment]::OSVersion.Platform.ToString()
            }
            attributes     = $Attributes
        }

        return ($record | ConvertTo-Json -Compress -Depth 5)
    }

    # Rotates the log file when it exceeds MaxFileSizeBytes.
    # Checks are throttled to every RotationCheckInterval writes to reduce filesystem overhead.
    hidden [void] RotateIfNeeded()
    {
        if (-not $this.FileLoggingEnabled) { return }

        $this.WriteCount++
        if ($this.WriteCount % $this.RotationCheckInterval -ne 0) { return }

        if (-not (Test-Path -Path $this.LogFilePath)) { return }

        if ((Get-Item -Path $this.LogFilePath).Length -ge $this.MaxFileSizeBytes)
        {
            $archive = $this.LogFilePath -replace '\.log$', ('_{0}.log' -f [System.DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
            Move-Item -Path $this.LogFilePath -Destination $archive -Force
        }
    }

    hidden [void] WriteToFile([string]$JsonLine)
    {
        if (-not $this.FileLoggingEnabled) { return }

        $this.RotateIfNeeded()
        Add-Content -Path $this.LogFilePath -Value $JsonLine -Encoding UTF8
    }

    [void] Debug([string]$Message)
    {
        $this.Debug($Message, @{})
    }

    [void] Debug([string]$Message, [hashtable]$Attributes)
    {
        Write-Debug -Message $Message
        $this.WriteToFile($this.BuildRecord('DEBUG', 5, $Message, $Attributes))
    }

    [void] Info([string]$Message)
    {
        $this.Info($Message, @{})
    }

    [void] Info([string]$Message, [hashtable]$Attributes)
    {
        Write-Verbose -Message $Message
        $this.WriteToFile($this.BuildRecord('INFO', 9, $Message, $Attributes))
    }

    [void] Warn([string]$Message)
    {
        $this.Warn($Message, @{})
    }

    [void] Warn([string]$Message, [hashtable]$Attributes)
    {
        Write-Warning -Message $Message
        $this.WriteToFile($this.BuildRecord('WARN', 13, $Message, $Attributes))
    }

    [void] Error([string]$Message)
    {
        $this.Error($Message, @{})
    }

    [void] Error([string]$Message, [hashtable]$Attributes)
    {
        Write-Error -Message $Message
        $this.WriteToFile($this.BuildRecord('ERROR', 17, $Message, $Attributes))
    }
}
