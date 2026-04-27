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
