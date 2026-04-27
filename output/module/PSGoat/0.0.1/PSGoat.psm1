#Region './Classes/0.PSGDnsBase.ps1' -1

class PSGDnsBase
{
    # Creates a CimSession for remote execution with credentials. Returns $null for local execution.
    static [object] NewSession([string]$ComputerName, [PSCredential]$Credential)
    {
        if ($null -eq $Credential)
        {
            return $null
        }

        return New-CimSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
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
    static [string[]] GetZones([string]$ComputerName, [object]$CimSession)
    {
        $params = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }

        return (
            Get-DnsServerZone @params |
                Where-Object -FilterScript { -not $_.IsAutoCreated -and $_.ZoneType -eq 'Primary' } |
                Select-Object -ExpandProperty ZoneName
        )
    }

    # Returns $true when the record has no DDNS timestamp (i.e. manually created).
    static [bool] IsStaticRecord([object]$Record)
    {
        return ($null -eq $Record.TimeStamp) -or ($Record.TimeStamp -eq [datetime]::MinValue)
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
            'SRV'   { return '{0} {1} {2} {3}' -f $Record.RecordData.Priority, $Record.RecordData.Weight, $Record.RecordData.Port, $Record.RecordData.DomainName }
            'TXT'   { return $Record.RecordData.DescriptiveText }
        }

        return $Record.RecordData.ToString()
    }
}
#EndRegion './Classes/0.PSGDnsBase.ps1' 58
#Region './Classes/2.PSGLogger.ps1' -1

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
#EndRegion './Classes/2.PSGLogger.ps1' 130
#Region './Classes/3.PSGDnsEntry.ps1' -1

class PSGDnsEntry : PSGDnsBase
{
    [string]$HostName
    [string]$ZoneName
    [string]$RecordType
    [string[]]$RecordData
    [int]$Count
    [bool]$IsStatic
    [Nullable[datetime]]$TimeStamp

    PSGDnsEntry()
    {
    }

    PSGDnsEntry([string]$HostName, [string]$ZoneName, [string]$RecordType, [string[]]$RecordData, [bool]$IsStatic, [Nullable[datetime]]$TimeStamp)
    {
        $this.HostName   = $HostName
        $this.ZoneName   = $ZoneName
        $this.RecordType = $RecordType
        $this.RecordData = $RecordData
        $this.Count      = $RecordData.Count
        $this.IsStatic   = $IsStatic
        $this.TimeStamp  = $TimeStamp
    }

    # Queries a DNS zone and returns PSGDnsEntry objects.
    # Filter restricts to Static or Dynamic records. DuplicatesOnly collapses groups with more than one record.
    static [PSGDnsEntry[]] GetEntries([string]$ComputerName, [string]$ZoneName, [string[]]$RecordType, [string]$Filter, [bool]$DuplicatesOnly, [object]$CimSession)
    {
        $params     = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $allRecords = [System.Collections.Generic.List[object]]::new()

        foreach ($type in $RecordType)
        {
            $records = Get-DnsServerResourceRecord @params -ZoneName $ZoneName -RRType $type -ErrorAction SilentlyContinue
            if ($records)
            {
                $allRecords.AddRange([object[]]@($records))
            }
        }

        $filteredRecords = [System.Collections.Generic.List[object]]::new()

        foreach ($record in $allRecords)
        {
            $recordIsStatic = [PSGDnsBase]::IsStaticRecord($record)
            if ($Filter -eq 'Static'  -and -not $recordIsStatic) { continue }
            if ($Filter -eq 'Dynamic' -and $recordIsStatic)      { continue }
            $filteredRecords.Add($record)
        }

        $results = [System.Collections.Generic.List[PSGDnsEntry]]::new()

        if ($DuplicatesOnly)
        {
            $filteredRecords |
                Group-Object -Property HostName, RecordType |
                Where-Object -FilterScript { $_.Count -gt 1 } |
                ForEach-Object -Process {
                    $group     = $_
                    $allStatic = -not ($group.Group | Where-Object -FilterScript { -not [PSGDnsBase]::IsStaticRecord($_) })

                    $ts = if ($allStatic)
                    {
                        $null
                    }
                    else
                    {
                        ($group.Group |
                            Where-Object -FilterScript { -not [PSGDnsBase]::IsStaticRecord($_) } |
                            Sort-Object -Property TimeStamp -Descending |
                            Select-Object -First 1).TimeStamp
                    }

                    $data = $group.Group | ForEach-Object -Process { [PSGDnsBase]::ExtractRecordData($_) }

                    $results.Add([PSGDnsEntry]::new(
                        $group.Group[0].HostName,
                        $ZoneName,
                        $group.Group[0].RecordType,
                        $data,
                        $allStatic,
                        $ts
                    ))
                }
        }
        else
        {
            foreach ($record in $filteredRecords)
            {
                $recordIsStatic = [PSGDnsBase]::IsStaticRecord($record)
                $ts             = if ($recordIsStatic) { $null } else { $record.TimeStamp }

                $results.Add([PSGDnsEntry]::new(
                    $record.HostName,
                    $ZoneName,
                    $record.RecordType,
                    @([PSGDnsBase]::ExtractRecordData($record)),
                    $recordIsStatic,
                    $ts
                ))
            }
        }

        return $results.ToArray()
    }

    [string] ToString()
    {
        $entryType = if ($this.IsStatic) { 'Static' } else { 'Dynamic' }

        if ($this.Count -gt 1)
        {
            return '[{0}] [{1}] {2}.{3} - {4} records: {5}' -f
                $this.RecordType, $entryType, $this.HostName, $this.ZoneName,
                $this.Count, ($this.RecordData -join ', ')
        }

        return '[{0}] [{1}] {2}.{3} = {4}' -f
            $this.RecordType, $entryType, $this.HostName, $this.ZoneName, $this.RecordData[0]
    }
}
#EndRegion './Classes/3.PSGDnsEntry.ps1' 123
#Region './Public/Get-PSGDnsEntry.ps1' -1

function Get-PSGDnsEntry
{
    <#
      .SYNOPSIS
        Returns DNS resource records from one or more zones, with optional static/dynamic and duplicate filtering.

      .DESCRIPTION
        Queries a DNS server and returns resource records as PSGDnsEntry objects. Each record
        includes the hostname, zone, record type, data values, whether it is static or dynamic
        (DDNS), its refresh timestamp, and the number of data values. Supports local execution
        or remote execution from an admin workstation via ComputerName and Credential. When
        Credential is provided, a CimSession is created automatically and cleaned up after
        execution. Structured logging to a file can be enabled via LogFilePath, producing
        OTel-compatible JSON Lines output.

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
        The DNS record types to retrieve. Defaults to A and AAAA.
        Accepted values: A, AAAA, CNAME, MX, PTR, SRV, TXT.

      .PARAMETER Filter
        Restricts results to Static records only, Dynamic records only, or All (default).
        Static records are manually created entries with no DDNS timestamp.
        Dynamic records are registered automatically by DHCP clients via DDNS.
        When combined with -Duplicate, the filter is applied before duplicate detection.

      .PARAMETER Duplicate
        When specified, returns only entries where the same hostname has more than one
        record of the same type. Can be combined with -Filter to restrict the source
        records before duplicate detection.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format (one JSON object per line). The file is
        rotated automatically when it exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsEntry

        Returns all A and AAAA records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsEntry -Filter Static

        Returns only manually created A and AAAA records from every primary zone.

      .EXAMPLE
        Get-PSGDnsEntry -Filter Dynamic -ZoneName 'contoso.com'

        Returns only DDNS-registered records from the contoso.com zone.

      .EXAMPLE
        Get-PSGDnsEntry -Duplicate

        Returns only entries where the same hostname appears more than once with the same record type.

      .EXAMPLE
        Get-PSGDnsEntry -Duplicate -Filter Static

        Returns only duplicate entries among statically created records.

      .EXAMPLE
        Get-PSGDnsEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential) -Duplicate

        Returns all duplicate entries from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsEntry[]])]
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
        [ValidateSet('All', 'Static', 'Dynamic')]
        [string]
        $Filter = 'All',

        [Parameter()]
        [switch]
        $Duplicate,

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = $MyInvocation.MyCommand.Module.Version.ToString()

        if ($PSBoundParameters.ContainsKey('LogFilePath'))
        {
            $logger = [PSGLogger]::new('PSGoat', $moduleVersion, $LogFilePath)
        }
        else
        {
            $logger = [PSGLogger]::new('PSGoat', $moduleVersion)
        }

        $cimSession = $null

        try
        {
            if ($PSBoundParameters.ContainsKey('Credential'))
            {
                $logger.Info(('Creating CimSession on {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $cimSession = [PSGDnsEntry]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsEntry]::GetZones($ComputerName, $cimSession)
            }

            foreach ($zone in $zones)
            {
                $logger.Info(
                    ('Processing zone: {0} (filter: {1}, duplicates: {2})' -f $zone, $Filter, $Duplicate.IsPresent),
                    @{ 'dns.zone' = $zone; 'computer.name' = $ComputerName; 'dns.filter' = $Filter; 'dns.duplicate' = $Duplicate.IsPresent }
                )
                [PSGDnsEntry]::GetEntries($ComputerName, $zone, $RecordType, $Filter, $Duplicate.IsPresent, $cimSession)
            }
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsEntry]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsEntry.ps1' 167
