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
