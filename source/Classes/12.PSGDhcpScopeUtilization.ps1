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
