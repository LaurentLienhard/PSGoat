#Region '.\Classes\1.PSGDnsDuplicateEntry.ps1' -1

class PSGDnsDuplicateEntry
{
    [string]$HostName
    [string]$ZoneName
    [string]$RecordType
    [string[]]$RecordData
    [int]$DuplicateCount

    PSGDnsDuplicateEntry()
    {
    }

    PSGDnsDuplicateEntry([string]$HostName, [string]$ZoneName, [string]$RecordType, [string[]]$RecordData)
    {
        $this.HostName       = $HostName
        $this.ZoneName       = $ZoneName
        $this.RecordType     = $RecordType
        $this.RecordData     = $RecordData
        $this.DuplicateCount = $RecordData.Count
    }

    # Creates a CimSession for remote execution with credentials. Returns $null for local execution.
    static [object] NewSession([string]$ComputerName, [PSCredential]$Credential)
    {
        if ($null -eq $Credential)
        {
            return $null
        }

        return New-CimSession -ComputerName $ComputerName -Credential $Credential
    }

    # Removes a CimSession created by NewSession. Safe to call with $null.
    static [void] RemoveSession([object]$CimSession)
    {
        if ($null -ne $CimSession)
        {
            Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
        }
    }

    # Returns all primary non-auto-created zone names from the target DNS server.
    # Pass $null for CimSession when no credentials are required.
    static [string[]] GetZones([string]$ComputerName, [object]$CimSession)
    {
        if ($null -ne $CimSession)
        {
            return (
                Get-DnsServerZone -CimSession $CimSession |
                    Where-Object -FilterScript { -not $_.IsAutoCreated -and $_.ZoneType -eq 'Primary' } |
                    Select-Object -ExpandProperty ZoneName
            )
        }

        return (
            Get-DnsServerZone -ComputerName $ComputerName |
                Where-Object -FilterScript { -not $_.IsAutoCreated -and $_.ZoneType -eq 'Primary' } |
                Select-Object -ExpandProperty ZoneName
        )
    }

    # Extracts the data string from a DNS resource record based on its type.
    static [string] ExtractRecordData([object]$Record)
    {
        switch ($Record.RecordType)
        {
            'A'     { return $Record.RecordData.IPv4Address.IPAddressToString }
            'AAAA'  { return $Record.RecordData.IPv6Address.IPAddressToString }
            'CNAME' { return $Record.RecordData.HostNameAlias }
            'MX'    { return $Record.RecordData.MailExchange }
            'PTR'   { return $Record.RecordData.PtrDomainName }
            'TXT'   { return $Record.RecordData.DescriptiveText }
            #default { return $Record.RecordData.ToString() }
        }
        return $Record.RecordData.ToString()
    }

    # Queries a DNS zone and returns PSGDnsDuplicateEntry objects for every duplicated hostname.
    # Pass $null for CimSession when no credentials are required.
    static [PSGDnsDuplicateEntry[]] FindInZone([string]$ComputerName, [string]$ZoneName, [string[]]$RecordType, [object]$CimSession)
    {
        $allRecords = [System.Collections.Generic.List[object]]::new()

        foreach ($type in $RecordType)
        {
            if ($null -ne $CimSession)
            {
                $records = Get-DnsServerResourceRecord -CimSession $CimSession -ZoneName $ZoneName -RRType $type -ErrorAction SilentlyContinue
            }
            else
            {
                $records = Get-DnsServerResourceRecord -ComputerName $ComputerName -ZoneName $ZoneName -RRType $type -ErrorAction SilentlyContinue
            }

            if ($records)
            {
                $allRecords.AddRange([object[]]@($records))
            }
        }

        $results = [System.Collections.Generic.List[PSGDnsDuplicateEntry]]::new()

        $allRecords |
            Group-Object -Property HostName |
            Where-Object -FilterScript { $_.Count -gt 1 } |
            ForEach-Object -Process {
                $group = $_

                $recordData = $group.Group | ForEach-Object -Process {
                    [PSGDnsDuplicateEntry]::ExtractRecordData($_)
                }

                $results.Add(
                    [PSGDnsDuplicateEntry]::new(
                        $group.Name,
                        $ZoneName,
                        ($group.Group.RecordType | Select-Object -Unique) -join '/',
                        $recordData
                    )
                )
            }

        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[{0}] {1}.{2} - {3} duplicate {4}' -f
            $this.RecordType,
            $this.HostName,
            $this.ZoneName,
            $this.DuplicateCount,
            $(if ($this.DuplicateCount -gt 1) { 'entries' } else { 'entry' })
    }
}
#EndRegion '.\Classes\1.PSGDnsDuplicateEntry.ps1' 136
#Region '.\Classes\2.PSGLogger.ps1' -1

class PSGLogger
{
    [string]$ServiceName
    [string]$ServiceVersion
    [string]$LogFilePath
    [bool]$FileLoggingEnabled
    [string]$TraceId
    [string]$SpanId
    [long]$MaxFileSizeBytes

    # Console-only logger.
    PSGLogger([string]$ServiceName, [string]$ServiceVersion)
    {
        $this.ServiceName        = $ServiceName
        $this.ServiceVersion     = $ServiceVersion
        $this.FileLoggingEnabled = $false
        $this.MaxFileSizeBytes   = 10MB
        $this.TraceId            = [System.Guid]::NewGuid().ToString('N')
        $this.SpanId             = [System.Guid]::NewGuid().ToString('N').Substring(0, 16)
    }

    # Console + file logger.
    PSGLogger([string]$ServiceName, [string]$ServiceVersion, [string]$LogFilePath)
    {
        $this.ServiceName        = $ServiceName
        $this.ServiceVersion     = $ServiceVersion
        $this.LogFilePath        = $LogFilePath
        $this.FileLoggingEnabled = $true
        $this.MaxFileSizeBytes   = 10MB
        $this.TraceId            = [System.Guid]::NewGuid().ToString('N')
        $this.SpanId             = [System.Guid]::NewGuid().ToString('N').Substring(0, 16)
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
    hidden [void] RotateIfNeeded()
    {
        if (-not $this.FileLoggingEnabled) { return }
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
#EndRegion '.\Classes\2.PSGLogger.ps1' 121
#Region '.\Public\Get-PSGDnsDuplicateEntry.ps1' -1

function Get-PSGDnsDuplicateEntry
{
    <#
      .SYNOPSIS
        Returns all duplicate DNS entries from one or more DNS zones.

      .DESCRIPTION
        Queries a DNS server for resource records and identifies entries where the same
        hostname has more than one record of the same type. Supports local execution or
        remote execution from an admin workstation via the ComputerName and Credential
        parameters. When Credential is provided, a CimSession is established automatically
        and cleaned up after execution. Structured logging to a file can be enabled via
        LogFilePath, producing OTel-compatible JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically. Not required for local execution or when
        the current account already has access to the remote server.

      .PARAMETER ZoneName
        One or more DNS zone names to query. If omitted, all primary non-auto-created
        zones on the target server are queried automatically.

      .PARAMETER RecordType
        The DNS record types to check for duplicates. Defaults to A and AAAA.
        Accepted values: A, AAAA, CNAME, MX, PTR, SRV, TXT.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format (one JSON object per line). The file is
        rotated automatically when it exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsDuplicateEntry

        Returns all duplicate A and AAAA records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com' -ZoneName 'contoso.com'

        Returns all duplicate A and AAAA records from the contoso.com zone on dc01 using the current account.

      .EXAMPLE
        $cred = Get-Credential
        Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com' -Credential $cred

        Returns all duplicate entries from dc01 using explicit credentials.

      .EXAMPLE
        Get-PSGDnsDuplicateEntry -ZoneName 'contoso.com' -LogFilePath 'C:\Logs\PSGoat.log'

        Returns duplicate entries and writes structured OTel logs to the specified file.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsDuplicateEntry[]])]
    param
    (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [PSCredential]
        $Credential,

        [Parameter()]
        [string[]]
        $ZoneName,

        [Parameter()]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'PTR', 'SRV', 'TXT')]
        [string[]]
        $RecordType = @('A', 'AAAA'),

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('LogFilePath'))
        {
            $logger = [PSGLogger]::new('PSGoat', '0.1.0', $LogFilePath)
        }
        else
        {
            $logger = [PSGLogger]::new('PSGoat', '0.1.0')
        }

        $cimSession = $null

        try
        {
            if ($PSBoundParameters.ContainsKey('Credential'))
            {
                $logger.Info(('Creating CimSession on {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $cimSession = [PSGDnsDuplicateEntry]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsDuplicateEntry]::GetZones($ComputerName, $cimSession)
            }

            foreach ($zone in $zones)
            {
                $logger.Info(('Processing zone: {0}' -f $zone), @{ 'dns.zone' = $zone; 'computer.name' = $ComputerName })
                [PSGDnsDuplicateEntry]::FindInZone($ComputerName, $zone, $RecordType, $cimSession)
            }
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsDuplicateEntry]::RemoveSession($cimSession)
        }
    }
}
#EndRegion '.\Public\Get-PSGDnsDuplicateEntry.ps1' 132
