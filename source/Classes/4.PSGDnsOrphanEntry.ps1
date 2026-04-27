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
                    $target     = $record.RecordData.PtrDomainName.TrimEnd('.')
                    $targetZone = [PSGDnsBase]::FindMatchingZone($target, $ForwardZones)

                    if ([string]::IsNullOrEmpty($targetZone))
                    {
                        Write-Verbose ('[MissingA] [{0}] {1} — external target, skipped' -f $zone, $target)
                        continue
                    }

                    $hostPart  = $target -replace ('\.' + [regex]::Escape($targetZone) + '$'), ''
                    $existingA = Get-DnsServerResourceRecord @params -ZoneName $targetZone -Name $hostPart -RRType A -ErrorAction SilentlyContinue

                    if (-not $existingA)
                    {
                        $ip = [PSGDnsBase]::ComputeIpFromPtr($record.HostName, $zone)
                        Write-Verbose ('[MissingA] [{0}] {1} ({2}) — no A in {3} [ORPHAN]' -f $zone, $target, $ip, $targetZone)
                        $results.Add([PSGDnsOrphanEntry]::new($target, $zone, $ip, 'MissingA'))
                    }
                    else
                    {
                        Write-Verbose ('[MissingA] [{0}] {1} — A found in {2}, ok' -f $zone, $target, $targetZone)
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
