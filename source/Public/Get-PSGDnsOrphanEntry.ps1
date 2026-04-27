function Get-PSGDnsOrphanEntry
{
    <#
      .SYNOPSIS
        Returns orphaned DNS records: A records without a matching PTR, or PTR records without a matching A.

      .DESCRIPTION
        Queries a DNS server and cross-references forward and reverse zones to detect two categories
        of orphaned records:
        - MissingPTR: an A record exists in a forward zone but no corresponding PTR record exists
          in the appropriate reverse zone (*.in-addr.arpa).
        - MissingA: a PTR record exists in a reverse zone but no corresponding A record exists
          in the target forward zone.
        Reverse zones are always discovered automatically. The -ZoneName parameter restricts which
        forward zones are inspected; if omitted, all primary non-auto-created forward zones are used.
        Supports local execution or remote execution via ComputerName and Credential. When Credential
        is provided, a CimSession is created automatically and cleaned up after execution. Structured
        logging can be enabled via LogFilePath, producing OTel-compatible JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically.

      .PARAMETER ZoneName
        One or more forward DNS zone names to inspect. If omitted, all primary
        non-auto-created forward zones are used. Reverse zones are always discovered
        automatically regardless of this parameter.

      .PARAMETER OrphanType
        Restricts results to a specific orphan category or returns both (default: All).
        - MissingPTR: A records without a corresponding PTR record.
        - MissingA:   PTR records without a corresponding A record.
        - All:        both categories.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsOrphanEntry

        Returns all orphaned records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsOrphanEntry -OrphanType MissingPTR

        Returns only A records that have no corresponding PTR.

      .EXAMPLE
        Get-PSGDnsOrphanEntry -OrphanType MissingA -ZoneName 'contoso.com'

        Returns PTR records whose target hostname has no A record in contoso.com.

      .EXAMPLE
        Get-PSGDnsOrphanEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns all orphaned records from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsOrphanEntry[]])]
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
        [ValidateSet('All', 'MissingPTR', 'MissingA')]
        [string]
        $OrphanType = 'All',

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
                $cimSession = [PSGDnsOrphanEntry]::NewSession($ComputerName, $Credential)
            }

            $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
            $allZones = [PSGDnsOrphanEntry]::GetZones($ComputerName, $cimSession)

            $reverseZones = @($allZones | Where-Object -FilterScript { $_ -match '\.in-addr\.arpa$|\.ip6\.arpa$' })
            $forwardZones = @($allZones | Where-Object -FilterScript { $_ -notmatch '\.in-addr\.arpa$|\.ip6\.arpa$' })

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $forwardZones = @($forwardZones | Where-Object -FilterScript { $_ -in $ZoneName })
            }

            $logger.Info(
                ('Scanning {0} forward zone(s) and {1} reverse zone(s) on {2}' -f $forwardZones.Count, $reverseZones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.forward.count' = $forwardZones.Count; 'dns.reverse.count' = $reverseZones.Count; 'dns.orphan.type' = $OrphanType }
            )

            Write-Verbose ('Forward zones: {0}' -f ($forwardZones -join ', '))
            Write-Verbose ('Reverse zones: {0}' -f ($reverseZones -join ', '))

            $orphans = [PSGDnsOrphanEntry]::FindOrphans($ComputerName, $forwardZones, $reverseZones, $OrphanType, $cimSession)

            $logger.Info(
                ('{0} orphaned record(s) found on {1}' -f @($orphans).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.orphan.count' = @($orphans).Count; 'dns.orphan.type' = $OrphanType }
            )

            $orphans
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsOrphanEntry]::RemoveSession($cimSession)
        }
    }
}
