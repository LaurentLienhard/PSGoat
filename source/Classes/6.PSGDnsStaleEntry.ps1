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
