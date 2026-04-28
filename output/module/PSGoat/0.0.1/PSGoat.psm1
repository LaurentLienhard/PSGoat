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

    # Returns the full PTR name for an IPv4 address.
    # e.g. '192.168.1.10' -> '10.1.168.192.in-addr.arpa'
    static [string] ComputePtrName([string]$IPv4Address)
    {
        $octets = $IPv4Address.Split('.')
        [Array]::Reverse($octets)
        return '{0}.in-addr.arpa' -f ($octets -join '.')
    }

    # Reconstructs the IPv4 address from a PTR record name and its reverse zone.
    # e.g. PtrHostName='10', Zone='1.168.192.in-addr.arpa' -> '192.168.1.10'
    static [string] ComputeIpFromPtr([string]$PtrHostName, [string]$Zone)
    {
        $full           = if ($PtrHostName -eq '@') { $Zone } else { '{0}.{1}' -f $PtrHostName, $Zone }
        $withoutSuffix  = $full -replace '\.in-addr\.arpa$', ''
        $octets         = $withoutSuffix.Split('.')
        [Array]::Reverse($octets)
        return $octets -join '.'
    }

    # Returns the most specific zone from Zones that covers Name, or empty string if none match.
    static [string] FindMatchingZone([string]$Name, [string[]]$Zones)
    {
        if (-not $Zones) { return [string]::Empty }

        foreach ($zone in ($Zones | Sort-Object -Property Length -Descending))
        {
            if ($Name -eq $zone -or $Name -like "*.$zone")
            {
                return $zone
            }
        }

        return [string]::Empty
    }
}
#EndRegion './Classes/0.PSGDnsBase.ps1' 94
#Region './Classes/10.PSGDnsForwardReverseMismatch.ps1' -1

class PSGDnsForwardReverseMismatch : PSGDnsBase
{
    [string]$ForwardFQDN
    [string]$IPAddress
    [string]$ReverseFQDN

    PSGDnsForwardReverseMismatch()
    {
    }

    PSGDnsForwardReverseMismatch([string]$ForwardFQDN, [string]$IPAddress, [string]$ReverseFQDN)
    {
        $this.ForwardFQDN = $ForwardFQDN
        $this.IPAddress   = $IPAddress
        $this.ReverseFQDN = $ReverseFQDN
    }

    # Finds A records whose PTR record exists but points to a different FQDN.
    # Records with no PTR at all are intentionally ignored (use Get-PSGDnsOrphanEntry for that).
    static [PSGDnsForwardReverseMismatch[]] FindMismatches(
        [string]$ComputerName,
        [string[]]$ForwardZones,
        [string[]]$ReverseZones,
        [object]$CimSession
    )
    {
        $params  = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results = [System.Collections.Generic.List[PSGDnsForwardReverseMismatch]]::new()

        $forwardByIp = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new()

        foreach ($zone in $ForwardZones)
        {
            $aRecords = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType A -ErrorAction SilentlyContinue
            Write-Verbose ('[ForwardReverse] [{0}] {1} A record(s) collected' -f $zone, @($aRecords).Count)

            foreach ($record in $aRecords)
            {
                $fqdn = ($record.HostName -eq '@') ? $zone : ('{0}.{1}' -f $record.HostName, $zone)
                $ip   = $record.RecordData.IPv4Address.IPAddressToString

                if (-not $forwardByIp.ContainsKey($ip))
                {
                    $forwardByIp[$ip] = [System.Collections.Generic.List[string]]::new()
                }
                $forwardByIp[$ip].Add($fqdn)
            }
        }

        Write-Verbose ('[ForwardReverse] {0} unique IP(s) from {1} forward zone(s)' -f $forwardByIp.Count, $ForwardZones.Count)

        $reverseMap = [System.Collections.Generic.Dictionary[string, string]]::new()

        foreach ($zone in $ReverseZones)
        {
            $ptrRecords = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType PTR -ErrorAction SilentlyContinue
            Write-Verbose ('[ForwardReverse] [{0}] {1} PTR record(s) collected' -f $zone, @($ptrRecords).Count)

            foreach ($record in $ptrRecords)
            {
                $ip     = [PSGDnsBase]::ComputeIpFromPtr($record.HostName, $zone)
                $target = $record.RecordData.PtrDomainName.TrimEnd('.')
                $reverseMap[$ip] = $target
            }
        }

        Write-Verbose ('[ForwardReverse] {0} PTR record(s) from {1} reverse zone(s)' -f $reverseMap.Count, $ReverseZones.Count)

        foreach ($entry in $forwardByIp.GetEnumerator())
        {
            $ip = $entry.Key

            if (-not $reverseMap.ContainsKey($ip)) { continue }

            $ptrTarget = $reverseMap[$ip]

            foreach ($fqdn in $entry.Value)
            {
                if ($fqdn -ne $ptrTarget)
                {
                    Write-Verbose ('[ForwardReverse] Mismatch -- A:{0}->{1} but PTR:{1}->{2}' -f $fqdn, $ip, $ptrTarget)
                    $results.Add([PSGDnsForwardReverseMismatch]::new($fqdn, $ip, $ptrTarget))
                }
            }
        }

        Write-Verbose ('Scan complete -- {0} mismatch(es) found' -f $results.Count)
        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[ForwardReverse] A:{0}->{1} -- PTR:{1}->{2}' -f $this.ForwardFQDN, $this.IPAddress, $this.ReverseFQDN
    }
}
#EndRegion './Classes/10.PSGDnsForwardReverseMismatch.ps1' 96
#Region './Classes/11.PSGDhcpBase.ps1' -1

class PSGDhcpBase
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

    # Returns all DHCPv4 scopes from the target server.
    static [object[]] GetScopes([string]$ComputerName, [object]$CimSession)
    {
        $params = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        return @(Get-DhcpServerv4Scope @params -ErrorAction Stop)
    }
}
#EndRegion './Classes/11.PSGDhcpBase.ps1' 30
#Region './Classes/12.PSGDhcpScopeUtilization.ps1' -1

class PSGDhcpScopeUtilization : PSGDhcpBase
{
    [string]$ScopeId
    [string]$Name
    [string]$State
    [uint32]$TotalAddresses
    [uint32]$InUse
    [uint32]$Reserved
    [uint32]$Free
    [double]$UtilizationPercent

    PSGDhcpScopeUtilization()
    {
    }

    PSGDhcpScopeUtilization(
        [string]$ScopeId,
        [string]$Name,
        [string]$State,
        [uint32]$TotalAddresses,
        [uint32]$InUse,
        [uint32]$Reserved,
        [uint32]$Free,
        [double]$UtilizationPercent
    )
    {
        $this.ScopeId            = $ScopeId
        $this.Name               = $Name
        $this.State              = $State
        $this.TotalAddresses     = $TotalAddresses
        $this.InUse              = $InUse
        $this.Reserved           = $Reserved
        $this.Free               = $Free
        $this.UtilizationPercent = $UtilizationPercent
    }

    # Returns utilization statistics for DHCPv4 scopes, optionally filtered by ScopeId and minimum
    # utilization threshold. InUse counts active leases; Reserved counts reserved addresses.
    # Both are treated as consumed capacity for the UtilizationPercent calculation.
    static [PSGDhcpScopeUtilization[]] GetUtilization(
        [string]$ComputerName,
        [string[]]$ScopeId,
        [double]$Threshold,
        [object]$CimSession
    )
    {
        $params  = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results = [System.Collections.Generic.List[PSGDhcpScopeUtilization]]::new()

        $allScopes = @(Get-DhcpServerv4Scope @params -ErrorAction SilentlyContinue)
        $scopeMap  = @{}
        foreach ($scope in $allScopes)
        {
            $scopeMap[$scope.ScopeId.ToString()] = $scope
        }

        Write-Verbose ('[ScopeUtilization] {0} scope(s) found on {1}' -f $allScopes.Count, $ComputerName)

        $allStats = @(Get-DhcpServerv4ScopeStatistics @params -ErrorAction SilentlyContinue)

        if ($ScopeId.Count -gt 0)
        {
            $allStats = @($allStats | Where-Object -FilterScript { $ScopeId -contains $_.ScopeId.ToString() })
        }

        Write-Verbose ('[ScopeUtilization] {0} scope(s) to evaluate' -f $allStats.Count)

        foreach ($stat in $allStats)
        {
            $id    = $stat.ScopeId.ToString()
            $scope = $scopeMap[$id]

            if ($null -eq $scope) { continue }

            $total = [uint32]($stat.Free + $stat.InUse + $stat.Reserved)
            $used  = [uint32]($stat.InUse + $stat.Reserved)
            $pct   = if ($total -gt 0) { [Math]::Round($used / $total * 100, 2) } else { [double]0 }

            Write-Verbose ('[ScopeUtilization] [{0}] {1}% used ({2}/{3} addresses)' -f $id, $pct, $used, $total)

            if ($pct -ge $Threshold)
            {
                $results.Add([PSGDhcpScopeUtilization]::new(
                    $id,
                    $scope.Name,
                    $scope.State.ToString(),
                    $total,
                    $stat.InUse,
                    $stat.Reserved,
                    $stat.Free,
                    $pct
                ))
            }
        }

        Write-Verbose ('Scan complete -- {0} scope(s) returned' -f $results.Count)
        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[ScopeUtilization] {0} ({1}) -- {2}% used ({3}/{4} addresses)' -f `
            $this.ScopeId, $this.Name, $this.UtilizationPercent, ($this.InUse + $this.Reserved), $this.TotalAddresses
    }
}
#EndRegion './Classes/12.PSGDhcpScopeUtilization.ps1' 106
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
#Region './Classes/4.PSGDnsOrphanEntry.ps1' -1

class PSGDnsOrphanEntry : PSGDnsBase
{
    [string]$HostName
    [string]$ZoneName
    [string]$IPAddress
    [string]$OrphanType

    PSGDnsOrphanEntry()
    {
    }

    PSGDnsOrphanEntry([string]$HostName, [string]$ZoneName, [string]$IPAddress, [string]$OrphanType)
    {
        $this.HostName   = $HostName
        $this.ZoneName   = $ZoneName
        $this.IPAddress  = $IPAddress
        $this.OrphanType = $OrphanType
    }

    # Cross-references forward and reverse zones to detect orphaned DNS records.
    # ForwardZones: primary forward zones to inspect.
    # ReverseZones: primary reverse zones (*.in-addr.arpa) to inspect.
    # OrphanType: MissingPTR, MissingA, or All.
    static [PSGDnsOrphanEntry[]] FindOrphans([string]$ComputerName, [string[]]$ForwardZones, [string[]]$ReverseZones, [string]$OrphanType, [object]$CimSession)
    {
        $params  = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results = [System.Collections.Generic.List[PSGDnsOrphanEntry]]::new()

        if ($OrphanType -eq 'All' -or $OrphanType -eq 'MissingPTR')
        {
            Write-Verbose ('[MissingPTR] Starting scan — {0} forward zone(s)' -f $ForwardZones.Count)

            foreach ($zone in $ForwardZones)
            {
                $aRecords = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType A -ErrorAction SilentlyContinue
                Write-Verbose ('[MissingPTR] [{0}] {1} A record(s) to check' -f $zone, @($aRecords).Count)

                foreach ($record in $aRecords)
                {
                    $ip          = $record.RecordData.IPv4Address.IPAddressToString
                    $ptrFullName = [PSGDnsBase]::ComputePtrName($ip)
                    $reverseZone = [PSGDnsBase]::FindMatchingZone($ptrFullName, $ReverseZones)

                    if ([string]::IsNullOrEmpty($reverseZone))
                    {
                        Write-Verbose ('[MissingPTR] [{0}] {1} ({2}) — no reverse zone, skipped' -f $zone, $record.HostName, $ip)
                        continue
                    }

                    $ptrHostPart = $ptrFullName -replace ('\.' + [regex]::Escape($reverseZone) + '$'), ''
                    $existingPtr = Get-DnsServerResourceRecord @params -ZoneName $reverseZone -Name $ptrHostPart -RRType PTR -ErrorAction SilentlyContinue

                    if (-not $existingPtr)
                    {
                        Write-Verbose ('[MissingPTR] [{0}] {1} ({2}) — no PTR in {3} [ORPHAN]' -f $zone, $record.HostName, $ip, $reverseZone)
                        $results.Add([PSGDnsOrphanEntry]::new($record.HostName, $zone, $ip, 'MissingPTR'))
                    }
                    else
                    {
                        Write-Verbose ('[MissingPTR] [{0}] {1} ({2}) — PTR found in {3}, ok' -f $zone, $record.HostName, $ip, $reverseZone)
                    }
                }
            }
        }

        if ($OrphanType -eq 'All' -or $OrphanType -eq 'MissingA')
        {
            Write-Verbose ('[MissingA] Starting scan — {0} reverse zone(s)' -f $ReverseZones.Count)

            foreach ($zone in $ReverseZones)
            {
                $ptrRecords = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType PTR -ErrorAction SilentlyContinue
                Write-Verbose ('[MissingA] [{0}] {1} PTR record(s) to check' -f $zone, @($ptrRecords).Count)

                foreach ($record in $ptrRecords)
                {
                    $ptrTarget     = $record.RecordData.PtrDomainName.TrimEnd('.')
                    $ptrTargetZone = [PSGDnsBase]::FindMatchingZone($ptrTarget, $ForwardZones)

                    if ([string]::IsNullOrEmpty($ptrTargetZone))
                    {
                        Write-Verbose ('[MissingA] [{0}] {1} — external target, skipped' -f $zone, $ptrTarget)
                        continue
                    }

                    $hostPart  = $ptrTarget -replace ('\.' + [regex]::Escape($ptrTargetZone) + '$'), ''
                    $existingA = Get-DnsServerResourceRecord @params -ZoneName $ptrTargetZone -Name $hostPart -RRType A -ErrorAction SilentlyContinue

                    if (-not $existingA)
                    {
                        $ip = [PSGDnsBase]::ComputeIpFromPtr($record.HostName, $zone)
                        Write-Verbose ('[MissingA] [{0}] {1} ({2}) — no A in {3} [ORPHAN]' -f $zone, $ptrTarget, $ip, $ptrTargetZone)
                        $results.Add([PSGDnsOrphanEntry]::new($ptrTarget, $zone, $ip, 'MissingA'))
                    }
                    else
                    {
                        Write-Verbose ('[MissingA] [{0}] {1} — A found in {2}, ok' -f $zone, $ptrTarget, $ptrTargetZone)
                    }
                }
            }
        }

        Write-Verbose ('Scan complete — {0} orphaned record(s) found' -f $results.Count)
        return $results.ToArray()
    }

    [string] ToString()
    {
        switch ($this.OrphanType)
        {
            'MissingPTR' { return '[MissingPTR] {0}.{1} ({2}) - no PTR record' -f $this.HostName, $this.ZoneName, $this.IPAddress }
            'MissingA'   { return '[MissingA] {0} ({1}) - no A record' -f $this.HostName, $this.IPAddress }
        }

        return '[{0}] {1} ({2})' -f $this.OrphanType, $this.HostName, $this.IPAddress
    }
}
#EndRegion './Classes/4.PSGDnsOrphanEntry.ps1' 118
#Region './Classes/5.PSGDnsBrokenCname.ps1' -1

class PSGDnsBrokenCname : PSGDnsBase
{
    [string]$HostName
    [string]$ZoneName
    [string]$Target

    PSGDnsBrokenCname()
    {
    }

    PSGDnsBrokenCname([string]$HostName, [string]$ZoneName, [string]$Target)
    {
        $this.HostName = $HostName
        $this.ZoneName = $ZoneName
        $this.Target   = $Target
    }

    # Returns CNAME records whose target has no A, AAAA or CNAME record in the managed zones.
    # CNAME records pointing to hostnames outside the managed zones are skipped.
    static [PSGDnsBrokenCname[]] FindBrokenCnames([string]$ComputerName, [string[]]$Zones, [object]$CimSession)
    {
        $params  = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results = [System.Collections.Generic.List[PSGDnsBrokenCname]]::new()

        foreach ($zone in $Zones)
        {
            $cnameRecords = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType CNAME -ErrorAction SilentlyContinue

            foreach ($record in $cnameRecords)
            {
                $cnameTarget     = $record.RecordData.HostNameAlias.TrimEnd('.')
                $cnameTargetZone = [PSGDnsBase]::FindMatchingZone($cnameTarget, $Zones)

                if ([string]::IsNullOrEmpty($cnameTargetZone)) { continue }

                $hostPart = if ($cnameTarget -eq $cnameTargetZone)
                {
                    '@'
                }
                else
                {
                    $cnameTarget -replace ('\.' + [regex]::Escape($cnameTargetZone) + '$'), ''
                }

                $targetRecords = Get-DnsServerResourceRecord @params -ZoneName $cnameTargetZone -Name $hostPart -ErrorAction SilentlyContinue |
                    Where-Object -FilterScript { $_.RecordType -in @('A', 'AAAA', 'CNAME') }

                if (-not $targetRecords)
                {
                    $results.Add([PSGDnsBrokenCname]::new($record.HostName, $zone, $cnameTarget))
                }
            }
        }

        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[BrokenCNAME] {0}.{1} -> {2} (target not found)' -f $this.HostName, $this.ZoneName, $this.Target
    }
}
#EndRegion './Classes/5.PSGDnsBrokenCname.ps1' 63
#Region './Classes/6.PSGDnsStaleEntry.ps1' -1

class PSGDnsStaleEntry : PSGDnsBase
{
    [string]$HostName
    [string]$ZoneName
    [string]$RecordType
    [string]$IPAddress
    [datetime]$TimeStamp
    [int]$AgeDays

    PSGDnsStaleEntry()
    {
    }

    PSGDnsStaleEntry([string]$HostName, [string]$ZoneName, [string]$RecordType, [string]$IPAddress, [datetime]$TimeStamp, [int]$AgeDays)
    {
        $this.HostName   = $HostName
        $this.ZoneName   = $ZoneName
        $this.RecordType = $RecordType
        $this.IPAddress  = $IPAddress
        $this.TimeStamp  = $TimeStamp
        $this.AgeDays    = $AgeDays
    }

    # Returns dynamic DNS records whose TimeStamp is older than ThresholdDays days.
    static [PSGDnsStaleEntry[]] FindStaleRecords([string]$ComputerName, [string[]]$Zones, [string[]]$RecordTypes, [int]$ThresholdDays, [object]$CimSession)
    {
        $params  = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results = [System.Collections.Generic.List[PSGDnsStaleEntry]]::new()
        $cutoff  = [datetime]::Now.AddDays(-$ThresholdDays)

        foreach ($zone in $Zones)
        {
            Write-Verbose ('[StaleEntry] [{0}] Scanning zone' -f $zone)

            foreach ($rrType in $RecordTypes)
            {
                $records        = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType $rrType -ErrorAction SilentlyContinue
                $dynamicRecords = @($records | Where-Object -FilterScript { -not [PSGDnsBase]::IsStaticRecord($_) })

                Write-Verbose ('[StaleEntry] [{0}] {1} dynamic {2} record(s) to evaluate' -f $zone, $dynamicRecords.Count, $rrType)

                foreach ($record in $dynamicRecords)
                {
                    if ($record.TimeStamp -lt $cutoff)
                    {
                        $staleDays = [int]([datetime]::Now - $record.TimeStamp).TotalDays
                        $recordIp  = [PSGDnsBase]::ExtractRecordData($record)
                        Write-Verbose ('[StaleEntry] [{0}] {1} ({2}) — {3} day(s) old [STALE]' -f $zone, $record.HostName, $recordIp, $staleDays)
                        $results.Add([PSGDnsStaleEntry]::new($record.HostName, $zone, $rrType, $recordIp, $record.TimeStamp, $staleDays))
                    }
                    else
                    {
                        Write-Verbose ('[StaleEntry] [{0}] {1} — fresh, ok' -f $zone, $record.HostName)
                    }
                }
            }
        }

        Write-Verbose ('Scan complete — {0} stale record(s) found' -f $results.Count)
        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[Stale] {0}.{1} ({2}) — last seen {3:yyyy-MM-dd} ({4} day(s))' -f $this.HostName, $this.ZoneName, $this.IPAddress, $this.TimeStamp, $this.AgeDays
    }
}
#EndRegion './Classes/6.PSGDnsStaleEntry.ps1' 68
#Region './Classes/7.PSGDnsDuplicateIp.ps1' -1

class PSGDnsDuplicateIp : PSGDnsBase
{
    [string]$IPAddress
    [string[]]$HostNames
    [int]$Count

    PSGDnsDuplicateIp()
    {
    }

    PSGDnsDuplicateIp([string]$IPAddress, [string[]]$HostNames)
    {
        $this.IPAddress  = $IPAddress
        $this.HostNames  = $HostNames
        $this.Count      = $HostNames.Count
    }

    # Returns A records where the same IP address is shared by more than one hostname across the given zones.
    static [PSGDnsDuplicateIp[]] FindDuplicateIps([string]$ComputerName, [string[]]$Zones, [object]$CimSession)
    {
        $params     = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results    = [System.Collections.Generic.List[PSGDnsDuplicateIp]]::new()
        $allEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($zone in $Zones)
        {
            $aRecords = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType A -ErrorAction SilentlyContinue
            Write-Verbose ('[DuplicateIp] [{0}] {1} A record(s) collected' -f $zone, @($aRecords).Count)

            foreach ($record in $aRecords)
            {
                $fqdn = ($record.HostName -eq '@') ? $zone : ('{0}.{1}' -f $record.HostName, $zone)
                $allEntries.Add([PSCustomObject]@{
                    FQDN     = $fqdn
                    RecordIp = $record.RecordData.IPv4Address.IPAddressToString
                })
            }
        }

        Write-Verbose ('[DuplicateIp] {0} A record(s) total — grouping by IP' -f $allEntries.Count)

        $allEntries |
            Group-Object -Property RecordIp |
            Where-Object -FilterScript { $_.Count -gt 1 } |
            ForEach-Object -Process {
                $sharedFqdns = @($_.Group | Select-Object -ExpandProperty FQDN)
                Write-Verbose ('[DuplicateIp] {0} — shared by {1} host(s): {2}' -f $_.Name, $sharedFqdns.Count, ($sharedFqdns -join ', '))
                $results.Add([PSGDnsDuplicateIp]::new($_.Name, $sharedFqdns))
            }

        Write-Verbose ('Scan complete — {0} duplicate IP(s) found' -f $results.Count)
        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[DuplicateIp] {0} — {1} host(s): {2}' -f $this.IPAddress, $this.Count, ($this.HostNames -join ', ')
    }
}
#EndRegion './Classes/7.PSGDnsDuplicateIp.ps1' 60
#Region './Classes/8.PSGDnsCnameChain.ps1' -1

class PSGDnsCnameChain : PSGDnsBase
{
    [string]$HostName
    [string]$ZoneName
    [string[]]$Chain
    [int]$Depth
    [bool]$IsCircular

    PSGDnsCnameChain()
    {
    }

    PSGDnsCnameChain([string]$HostName, [string]$ZoneName, [string[]]$Chain, [int]$Depth, [bool]$IsCircular)
    {
        $this.HostName   = $HostName
        $this.ZoneName   = $ZoneName
        $this.Chain      = $Chain
        $this.Depth      = $Depth
        $this.IsCircular = $IsCircular
    }

    # Returns CNAME chains with a depth >= MinDepth hops, and all circular chains regardless of depth.
    # A depth of 2 means: alias -> intermediate (CNAME) -> final target.
    static [PSGDnsCnameChain[]] FindCnameChains([string]$ComputerName, [string[]]$Zones, [int]$MinDepth, [object]$CimSession)
    {
        $params  = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results = [System.Collections.Generic.List[PSGDnsCnameChain]]::new()

        # Build a FQDN -> { Target, HostName, ZoneName } lookup for all CNAME records in managed zones.
        $cnameMap = @{}

        foreach ($zone in $Zones)
        {
            $cnameRecords = Get-DnsServerResourceRecord @params -ZoneName $zone -RRType CNAME -ErrorAction SilentlyContinue

            foreach ($record in $cnameRecords)
            {
                $entryFqdn   = if ($record.HostName -eq '@') { $zone } else { '{0}.{1}' -f $record.HostName, $zone }
                $entryTarget = $record.RecordData.HostNameAlias.TrimEnd('.')
                $cnameMap[$entryFqdn] = @{ Target = $entryTarget; HostName = $record.HostName; ZoneName = $zone }
            }
        }

        Write-Verbose ('[CnameChain] {0} CNAME record(s) mapped across all zones' -f $cnameMap.Count)

        foreach ($startFqdn in $cnameMap.Keys)
        {
            $chainPath   = [System.Collections.Generic.List[string]]::new()
            $chainPath.Add($startFqdn)
            $isLoop      = $false
            $currentFqdn = $cnameMap[$startFqdn].Target

            while ($cnameMap.ContainsKey($currentFqdn))
            {
                if ($chainPath.Contains($currentFqdn))
                {
                    $isLoop = $true
                    $chainPath.Add($currentFqdn)
                    break
                }

                $chainPath.Add($currentFqdn)
                $currentFqdn = $cnameMap[$currentFqdn].Target
            }

            if (-not $isLoop)
            {
                $chainPath.Add($currentFqdn)
            }

            $chainDepth = $chainPath.Count - 1

            if ($isLoop -or $chainDepth -ge $MinDepth)
            {
                $entry = $cnameMap[$startFqdn]
                Write-Verbose ('[CnameChain] {0} — depth {1}{2}' -f $startFqdn, $chainDepth, $(if ($isLoop) { ' [CIRCULAR]' } else { '' }))
                $results.Add([PSGDnsCnameChain]::new($entry.HostName, $entry.ZoneName, $chainPath.ToArray(), $chainDepth, $isLoop))
            }
        }

        Write-Verbose ('Scan complete — {0} chain(s) found' -f $results.Count)
        return $results.ToArray()
    }

    [string] ToString()
    {
        $suffix = if ($this.IsCircular) { ' [CIRCULAR]' } else { '' }
        return '[CnameChain] {0}.{1} — depth {2}{3}: {4}' -f $this.HostName, $this.ZoneName, $this.Depth, $suffix, ($this.Chain -join ' -> ')
    }
}
#EndRegion './Classes/8.PSGDnsCnameChain.ps1' 91
#Region './Classes/9.PSGDnsZoneStat.ps1' -1

class PSGDnsZoneStat : PSGDnsBase
{
    [string]$ZoneName
    [string]$ZoneType
    [int]$TotalRecords
    [int]$StaticCount
    [int]$DynamicCount
    [int]$StaleCount
    [hashtable]$ByType

    PSGDnsZoneStat()
    {
    }

    PSGDnsZoneStat([string]$ZoneName, [string]$ZoneType, [int]$TotalRecords, [int]$StaticCount, [int]$DynamicCount, [int]$StaleCount, [hashtable]$ByType)
    {
        $this.ZoneName     = $ZoneName
        $this.ZoneType     = $ZoneType
        $this.TotalRecords = $TotalRecords
        $this.StaticCount  = $StaticCount
        $this.DynamicCount = $DynamicCount
        $this.StaleCount   = $StaleCount
        $this.ByType       = $ByType
    }

    # Returns statistics for each zone: record counts by type, static/dynamic split, and stale count.
    static [PSGDnsZoneStat[]] GetZoneStats([string]$ComputerName, [string[]]$Zones, [int]$ThresholdDays, [object]$CimSession)
    {
        $params  = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }
        $results = [System.Collections.Generic.List[PSGDnsZoneStat]]::new()
        $cutoff  = [datetime]::Now.AddDays(-$ThresholdDays)
        $rrTypes = @('A', 'AAAA', 'CNAME', 'MX', 'PTR', 'SRV', 'TXT')

        $zoneTypeMap = @{}
        foreach ($zi in (Get-DnsServerZone @params -ErrorAction SilentlyContinue))
        {
            $zoneTypeMap[$zi.ZoneName] = $zi.ZoneType.ToString()
        }

        foreach ($zone in $Zones)
        {
            Write-Verbose ('[ZoneStat] [{0}] Collecting statistics' -f $zone)

            $statTotal   = 0
            $statStatic  = 0
            $statDynamic = 0
            $statStale   = 0
            $statByType  = @{}

            foreach ($rrType in $rrTypes)
            {
                $records            = @(Get-DnsServerResourceRecord @params -ZoneName $zone -RRType $rrType -ErrorAction SilentlyContinue)
                $statByType[$rrType] = $records.Count
                $statTotal          += $records.Count

                foreach ($record in $records)
                {
                    if ([PSGDnsBase]::IsStaticRecord($record))
                    {
                        $statStatic++
                    }
                    else
                    {
                        $statDynamic++
                        if ($record.TimeStamp -lt $cutoff)
                        {
                            $statStale++
                        }
                    }
                }
            }

            $zoneTypeName = if ($zoneTypeMap.ContainsKey($zone)) { $zoneTypeMap[$zone] } else { 'Unknown' }

            Write-Verbose ('[ZoneStat] [{0}] Total={1} Static={2} Dynamic={3} Stale={4}' -f $zone, $statTotal, $statStatic, $statDynamic, $statStale)

            $results.Add([PSGDnsZoneStat]::new($zone, $zoneTypeName, $statTotal, $statStatic, $statDynamic, $statStale, $statByType))
        }

        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[ZoneStat] {0} ({1}) — Total: {2} | Static: {3} | Dynamic: {4} | Stale: {5}' -f $this.ZoneName, $this.ZoneType, $this.TotalRecords, $this.StaticCount, $this.DynamicCount, $this.StaleCount
    }
}
#EndRegion './Classes/9.PSGDnsZoneStat.ps1' 88
#Region './Public/Get-PSGDhcpScopeUtilization.ps1' -1

function Get-PSGDhcpScopeUtilization
{
    <#
      .SYNOPSIS
        Returns utilization statistics for DHCPv4 scopes on a Windows DHCP server.

      .DESCRIPTION
        Queries a DHCP server and returns per-scope utilization data: total addresses,
        addresses in use (active leases), reserved addresses, free addresses, and the
        overall utilization percentage. Both active leases and reservations are counted
        as consumed capacity.

        The -Threshold parameter restricts output to scopes whose utilization is at or
        above the specified percentage, making it easy to identify scopes at risk of
        exhaustion.

        Supports local execution or remote execution via ComputerName and Credential.
        When Credential is provided, a CimSession is created automatically and cleaned
        up after execution. Structured logging can be enabled via LogFilePath, producing
        OTel-compatible JSON Lines output.

      .PARAMETER ComputerName
        The DHCP server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DHCP server. When provided, a
        CimSession is created automatically.

      .PARAMETER ScopeId
        One or more scope IDs (e.g. '192.168.1.0') to inspect. If omitted, all scopes
        on the target server are returned.

      .PARAMETER Threshold
        Minimum utilization percentage to include in results. Scopes below this value
        are silently skipped. Defaults to 0 (all scopes returned).

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization

        Returns utilization for all scopes on the local DHCP server.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization -Threshold 80

        Returns only scopes where 80% or more of the address space is consumed.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization -ScopeId '192.168.1.0', '10.0.0.0'

        Returns utilization for two specific scopes.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization -ComputerName 'dhcp01.contoso.com' -Credential (Get-Credential) -Threshold 80

        Returns critical scopes from a remote DHCP server using explicit credentials.

      .EXAMPLE
        'dhcp01.contoso.com', 'dhcp02.contoso.com' | Get-PSGDhcpScopeUtilization -Threshold 80 |
            Format-Table ScopeId, Name, TotalAddresses, InUse, Free, UtilizationPercent

        Returns critical scopes from two DHCP servers formatted as a table.
    #>
    [CmdletBinding()]
    [OutputType([PSGDhcpScopeUtilization[]])]
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
        $ScopeId = @(),

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]
        $Threshold = 0,

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDhcpScopeUtilization]::NewSession($ComputerName, $Credential)
            }

            $logger.Info(
                ('Retrieving DHCP scope utilization from {0} (threshold: {1}%)' -f $ComputerName, $Threshold),
                @{ 'computer.name' = $ComputerName; 'dhcp.threshold' = $Threshold }
            )

            $results = [PSGDhcpScopeUtilization]::GetUtilization($ComputerName, $ScopeId, $Threshold, $cimSession)

            $logger.Info(
                ('{0} scope(s) returned from {1}' -f @($results).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dhcp.scope.count' = @($results).Count }
            )

            $results
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDhcpScopeUtilization]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDhcpScopeUtilization.ps1' 143
#Region './Public/Get-PSGDnsBrokenCname.ps1' -1

function Get-PSGDnsBrokenCname
{
    <#
      .SYNOPSIS
        Returns CNAME records whose target has no A, AAAA, or CNAME record in the managed zones.

      .DESCRIPTION
        Queries a DNS server and detects broken CNAME records: entries whose alias target cannot
        be resolved within the set of managed zones. Only CNAMEs pointing to a hostname inside a
        managed zone are checked — CNAMEs pointing to external hostnames are silently skipped.
        Supports local execution or remote execution via ComputerName and Credential. When
        Credential is provided, a CimSession is created automatically and cleaned up after
        execution. Structured logging can be enabled via LogFilePath, producing OTel-compatible
        JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more DNS zone names to inspect. If omitted, all primary non-auto-created
        zones on the target server are used.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsBrokenCname

        Returns all broken CNAME records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsBrokenCname -ZoneName 'contoso.com'

        Returns broken CNAME records from the contoso.com zone only.

      .EXAMPLE
        Get-PSGDnsBrokenCname -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns all broken CNAME records from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsBrokenCname[]])]
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
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDnsBrokenCname]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsBrokenCname]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Scanning {0} zone(s) for broken CNAME records on {1}' -f $zones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count }
            )

            [PSGDnsBrokenCname]::FindBrokenCnames($ComputerName, $zones, $cimSession)
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsBrokenCname]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsBrokenCname.ps1' 120
#Region './Public/Get-PSGDnsCnameChain.ps1' -1

function Get-PSGDnsCnameChain
{
    <#
      .SYNOPSIS
        Returns CNAME chains longer than a given depth, and all circular CNAME references.

      .DESCRIPTION
        Queries a DNS server and maps all CNAME records within the managed zones. For each
        CNAME it follows the chain of aliases until a non-CNAME target is reached, an external
        target is encountered, or a loop is detected. Reports chains whose depth is equal to
        or greater than MinDepth, and all circular chains regardless of depth. Depth is the
        number of CNAME hops: a single CNAME pointing directly to an A record has a depth
        of 1 (normal); a CNAME pointing to another CNAME before reaching a final record has
        a depth of 2 or more (potentially problematic).
        Supports local execution or remote execution via ComputerName and Credential. When
        Credential is provided, a CimSession is created automatically and cleaned up after
        execution. Structured logging can be enabled via LogFilePath, producing OTel-compatible
        JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more DNS zone names to inspect. If omitted, all primary non-auto-created
        zones on the target server are used.

      .PARAMETER MinDepth
        Minimum number of CNAME hops to report. Defaults to 2. A value of 1 would return
        all CNAME records. Circular chains are always returned regardless of this value.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsCnameChain

        Returns all CNAME chains with 2 or more hops, and all circular references.

      .EXAMPLE
        Get-PSGDnsCnameChain -MinDepth 3

        Returns only chains with 3 or more hops, and all circular references.

      .EXAMPLE
        Get-PSGDnsCnameChain -ZoneName 'contoso.com'

        Returns CNAME chains from contoso.com only.

      .EXAMPLE
        Get-PSGDnsCnameChain -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns CNAME chains from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsCnameChain[]])]
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
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $MinDepth = 2,

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDnsCnameChain]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsCnameChain]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Scanning {0} zone(s) for CNAME chains on {1} (min depth: {2})' -f $zones.Count, $ComputerName, $MinDepth),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count; 'dns.cname.mindepth' = $MinDepth }
            )

            Write-Verbose ('Zones: {0}' -f ($zones -join ', '))

            $chains = [PSGDnsCnameChain]::FindCnameChains($ComputerName, $zones, $MinDepth, $cimSession)

            $logger.Info(
                ('{0} CNAME chain(s) found on {1}' -f @($chains).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.cname.chain.count' = @($chains).Count }
            )

            $chains
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsCnameChain]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsCnameChain.ps1' 147
#Region './Public/Get-PSGDnsDuplicateIp.ps1' -1

function Get-PSGDnsDuplicateIp
{
    <#
      .SYNOPSIS
        Returns IP addresses shared by more than one hostname across the managed DNS zones.

      .DESCRIPTION
        Queries a DNS server and collects all A records across the specified zones. Groups
        records by IP address and returns only those where the same address is assigned to
        more than one distinct hostname. This is useful for detecting incomplete migrations,
        forgotten aliases, or IP address conflicts.
        Supports local execution or remote execution via ComputerName and Credential. When
        Credential is provided, a CimSession is created automatically and cleaned up after
        execution. Structured logging can be enabled via LogFilePath, producing OTel-compatible
        JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more DNS zone names to inspect. If omitted, all primary non-auto-created
        zones on the target server are used.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsDuplicateIp

        Returns all IP addresses shared by more than one hostname across every primary zone.

      .EXAMPLE
        Get-PSGDnsDuplicateIp -ZoneName 'contoso.com', 'fabrikam.com'

        Returns duplicate IPs across two specific zones.

      .EXAMPLE
        Get-PSGDnsDuplicateIp -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns duplicate IPs from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsDuplicateIp[]])]
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
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDnsDuplicateIp]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsDuplicateIp]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Scanning {0} zone(s) for duplicate IPs on {1}' -f $zones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count }
            )

            Write-Verbose ('Zones: {0}' -f ($zones -join ', '))

            $duplicates = [PSGDnsDuplicateIp]::FindDuplicateIps($ComputerName, $zones, $cimSession)

            $logger.Info(
                ('{0} duplicate IP(s) found on {1}' -f @($duplicates).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.duplicate.count' = @($duplicates).Count }
            )

            $duplicates
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsDuplicateIp]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsDuplicateIp.ps1' 130
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
        $RecordType = @('A', 'AAAA', 'CNAME', 'MX', 'PTR', 'SRV', 'TXT'),

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
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
#Region './Public/Get-PSGDnsForwardReverseMismatch.ps1' -1

function Get-PSGDnsForwardReverseMismatch
{
    <#
      .SYNOPSIS
        Returns A records whose corresponding PTR record exists but points to a different FQDN.

      .DESCRIPTION
        Queries a DNS server and cross-references forward zones (A records) with reverse zones
        (PTR records). For each A record where a PTR exists for the same IP, this function checks
        whether the PTR target matches the A record hostname. Records where no PTR exists at all
        are intentionally skipped -- use Get-PSGDnsOrphanEntry to detect those.

        This is useful for detecting stale or inconsistent reverse DNS entries left behind after
        server renames, IP reassignments, or incomplete migrations.

        Reverse zones are always discovered automatically. The -ZoneName parameter restricts which
        forward zones are inspected; if omitted, all primary non-auto-created forward zones are used.
        Supports local execution or remote execution via ComputerName and Credential. When Credential
        is provided, a CimSession is created automatically and cleaned up after execution. Structured
        logging can be enabled via LogFilePath, producing OTel-compatible JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more forward DNS zone names to inspect. If omitted, all primary
        non-auto-created forward zones are used. Reverse zones are always discovered
        automatically regardless of this parameter.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsForwardReverseMismatch

        Returns all forward/reverse mismatches across every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsForwardReverseMismatch -ZoneName 'contoso.com'

        Returns mismatches restricted to the contoso.com forward zone.

      .EXAMPLE
        Get-PSGDnsForwardReverseMismatch -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns mismatches from dc01 using explicit credentials.

      .EXAMPLE
        'dc01.contoso.com', 'dc02.contoso.com' | Get-PSGDnsForwardReverseMismatch

        Returns mismatches from two DNS servers sequentially.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsForwardReverseMismatch[]])]
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
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDnsForwardReverseMismatch]::NewSession($ComputerName, $Credential)
            }

            $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
            $allZones = [PSGDnsForwardReverseMismatch]::GetZones($ComputerName, $cimSession)

            $reverseZones = @($allZones | Where-Object -FilterScript { $_ -match '\.in-addr\.arpa$|\.ip6\.arpa$' })
            $forwardZones = @($allZones | Where-Object -FilterScript { $_ -notmatch '\.in-addr\.arpa$|\.ip6\.arpa$' })

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $forwardZones = $ZoneName
            }

            $logger.Info(
                ('Scanning {0} forward zone(s) and {1} reverse zone(s) on {2}' -f $forwardZones.Count, $reverseZones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.forward.zone.count' = $forwardZones.Count; 'dns.reverse.zone.count' = $reverseZones.Count }
            )

            Write-Verbose ('Forward zones: {0}' -f ($forwardZones -join ', '))
            Write-Verbose ('Reverse zones: {0}' -f ($reverseZones -join ', '))

            $mismatches = [PSGDnsForwardReverseMismatch]::FindMismatches($ComputerName, $forwardZones, $reverseZones, $cimSession)

            $logger.Info(
                ('{0} forward/reverse mismatch(es) found on {1}' -f @($mismatches).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.mismatch.count' = @($mismatches).Count }
            )

            $mismatches
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsForwardReverseMismatch]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsForwardReverseMismatch.ps1' 143
#Region './Public/Get-PSGDnsOrphanEntry.ps1' -1

function Get-PSGDnsOrphanEntry
{
    <#
      .SYNOPSIS
        Returns orphaned DNS records: A records without a matching PTR, or PTR records without a matching A.

      .DESCRIPTION
        Queries a DNS server and cross-references forward and reverse zones to detect two categories
        of orphaned records:
        - MissingPTR: an A record exists in a forward zone but no corresponding PTR record exists
          in the appropriate reverse zone (*.in-addr.arpa).
        - MissingA: a PTR record exists in a reverse zone but no corresponding A record exists
          in the target forward zone.
        Reverse zones are always discovered automatically. The -ZoneName parameter restricts which
        forward zones are inspected; if omitted, all primary non-auto-created forward zones are used.
        Supports local execution or remote execution via ComputerName and Credential. When Credential
        is provided, a CimSession is created automatically and cleaned up after execution. Structured
        logging can be enabled via LogFilePath, producing OTel-compatible JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more forward DNS zone names to inspect. If omitted, all primary
        non-auto-created forward zones are used. Reverse zones are always discovered
        automatically regardless of this parameter.

      .PARAMETER OrphanType
        Restricts results to a specific orphan category or returns both (default: All).
        - MissingPTR: A records without a corresponding PTR record.
        - MissingA:   PTR records without a corresponding A record.
        - All:        both categories.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsOrphanEntry

        Returns all orphaned records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsOrphanEntry -OrphanType MissingPTR

        Returns only A records that have no corresponding PTR.

      .EXAMPLE
        Get-PSGDnsOrphanEntry -OrphanType MissingA -ZoneName 'contoso.com'

        Returns PTR records whose target hostname has no A record in contoso.com.

      .EXAMPLE
        Get-PSGDnsOrphanEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns all orphaned records from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsOrphanEntry[]])]
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
        [ValidateSet('All', 'MissingPTR', 'MissingA')]
        [string]
        $OrphanType = 'All',

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDnsOrphanEntry]::NewSession($ComputerName, $Credential)
            }

            $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
            $allZones = [PSGDnsOrphanEntry]::GetZones($ComputerName, $cimSession)

            $reverseZones = @($allZones | Where-Object -FilterScript { $_ -match '\.in-addr\.arpa$|\.ip6\.arpa$' })
            $forwardZones = @($allZones | Where-Object -FilterScript { $_ -notmatch '\.in-addr\.arpa$|\.ip6\.arpa$' })

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $forwardZones = @($forwardZones | Where-Object -FilterScript { $_ -in $ZoneName })
            }

            $logger.Info(
                ('Scanning {0} forward zone(s) and {1} reverse zone(s) on {2}' -f $forwardZones.Count, $reverseZones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.forward.count' = $forwardZones.Count; 'dns.reverse.count' = $reverseZones.Count; 'dns.orphan.type' = $OrphanType }
            )

            Write-Verbose ('Forward zones: {0}' -f ($forwardZones -join ', '))
            Write-Verbose ('Reverse zones: {0}' -f ($reverseZones -join ', '))

            $orphans = [PSGDnsOrphanEntry]::FindOrphans($ComputerName, $forwardZones, $reverseZones, $OrphanType, $cimSession)

            $logger.Info(
                ('{0} orphaned record(s) found on {1}' -f @($orphans).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.orphan.count' = @($orphans).Count; 'dns.orphan.type' = $OrphanType }
            )

            $orphans
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsOrphanEntry]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsOrphanEntry.ps1' 152
#Region './Public/Get-PSGDnsStaleEntry.ps1' -1

function Get-PSGDnsStaleEntry
{
    <#
      .SYNOPSIS
        Returns dynamic DNS records that have not been refreshed within a given number of days.

      .DESCRIPTION
        Queries a DNS server and identifies stale dynamic (DDNS) records: entries registered
        automatically by DHCP clients whose TimeStamp has not been updated within the specified
        threshold. Static records (no TimeStamp) are always ignored.
        Supports local execution or remote execution via ComputerName and Credential. When
        Credential is provided, a CimSession is created automatically and cleaned up after
        execution. Structured logging can be enabled via LogFilePath, producing OTel-compatible
        JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more DNS zone names to inspect. If omitted, all primary non-auto-created
        zones on the target server are used.

      .PARAMETER RecordType
        The DNS record types to evaluate. Defaults to A and AAAA, which are the most
        common dynamic record types. Accepted values: A, AAAA.

      .PARAMETER ThresholdDays
        Number of days without a refresh after which a dynamic record is considered stale.
        Must be a positive integer. Defaults to 30.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsStaleEntry

        Returns all dynamic records not refreshed in the last 30 days, from every primary zone.

      .EXAMPLE
        Get-PSGDnsStaleEntry -ThresholdDays 60

        Returns dynamic records not refreshed in the last 60 days.

      .EXAMPLE
        Get-PSGDnsStaleEntry -ZoneName 'contoso.com' -ThresholdDays 14

        Returns stale records from contoso.com only, with a 14-day threshold.

      .EXAMPLE
        Get-PSGDnsStaleEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns stale records from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsStaleEntry[]])]
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
        [ValidateSet('A', 'AAAA')]
        [string[]]
        $RecordType = @('A', 'AAAA'),

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $ThresholdDays = 30,

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDnsStaleEntry]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsStaleEntry]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Scanning {0} zone(s) for stale records on {1} (threshold: {2} day(s))' -f $zones.Count, $ComputerName, $ThresholdDays),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count; 'dns.stale.threshold' = $ThresholdDays }
            )

            Write-Verbose ('Zones: {0}' -f ($zones -join ', '))

            $staleRecords = [PSGDnsStaleEntry]::FindStaleRecords($ComputerName, $zones, $RecordType, $ThresholdDays, $cimSession)

            $logger.Info(
                ('{0} stale record(s) found on {1}' -f @($staleRecords).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.stale.count' = @($staleRecords).Count; 'dns.stale.threshold' = $ThresholdDays }
            )

            $staleRecords
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsStaleEntry]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsStaleEntry.ps1' 152
#Region './Public/Get-PSGDnsZoneStat.ps1' -1

function Get-PSGDnsZoneStat
{
    <#
      .SYNOPSIS
        Returns statistics per DNS zone: record counts by type, static/dynamic split, and stale record count.

      .DESCRIPTION
        Queries a DNS server and produces a summary for each zone: total number of resource
        records, breakdown by record type (A, AAAA, CNAME, MX, PTR, SRV, TXT), number of
        static vs dynamic (DDNS) records, and number of dynamic records whose TimeStamp has
        not been refreshed within ThresholdDays. This provides a quick health overview of
        the DNS infrastructure without querying individual records.
        Supports local execution or remote execution via ComputerName and Credential. When
        Credential is provided, a CimSession is created automatically and cleaned up after
        execution. Structured logging can be enabled via LogFilePath, producing OTel-compatible
        JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more DNS zone names to inspect. If omitted, all primary non-auto-created
        zones on the target server are used.

      .PARAMETER ThresholdDays
        Number of days without a refresh after which a dynamic record is counted as stale.
        Must be a positive integer. Defaults to 30.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsZoneStat

        Returns statistics for every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsZoneStat | Format-Table ZoneName, TotalRecords, StaticCount, DynamicCount, StaleCount

        Displays a summary table for all zones.

      .EXAMPLE
        Get-PSGDnsZoneStat -ZoneName 'contoso.com' -ThresholdDays 60

        Returns statistics for contoso.com, counting stale records older than 60 days.

      .EXAMPLE
        Get-PSGDnsZoneStat -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns zone statistics from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsZoneStat[]])]
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
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $ThresholdDays = 30,

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = if ($MyInvocation.MyCommand.Module) { $MyInvocation.MyCommand.Module.Version.ToString() } else { '0.0.0' }

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
                $cimSession = [PSGDnsZoneStat]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsZoneStat]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Computing statistics for {0} zone(s) on {1} (stale threshold: {2} day(s))' -f $zones.Count, $ComputerName, $ThresholdDays),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count; 'dns.stale.threshold' = $ThresholdDays }
            )

            Write-Verbose ('Zones: {0}' -f ($zones -join ', '))

            $stats = [PSGDnsZoneStat]::GetZoneStats($ComputerName, $zones, $ThresholdDays, $cimSession)

            $logger.Info(
                ('Statistics computed for {0} zone(s) on {1}' -f @($stats).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = @($stats).Count }
            )

            $stats
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsZoneStat]::RemoveSession($cimSession)
        }
    }
}
#EndRegion './Public/Get-PSGDnsZoneStat.ps1' 145
