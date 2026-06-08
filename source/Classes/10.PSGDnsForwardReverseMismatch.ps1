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
