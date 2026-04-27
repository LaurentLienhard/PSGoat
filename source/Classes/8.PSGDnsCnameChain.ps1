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
