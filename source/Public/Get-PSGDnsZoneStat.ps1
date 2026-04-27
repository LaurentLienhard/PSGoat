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
