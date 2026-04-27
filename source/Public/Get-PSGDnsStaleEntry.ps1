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
