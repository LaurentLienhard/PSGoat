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
