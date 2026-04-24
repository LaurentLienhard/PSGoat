function Get-PSGDnsEntry
{
    <#
      .SYNOPSIS
        Returns DNS resource records from one or more zones, with optional static/dynamic and duplicate filtering.

      .DESCRIPTION
        Queries a DNS server and returns resource records as PSGDnsEntry objects. Each record
        includes the hostname, zone, record type, data values, whether it is static or dynamic
        (DDNS), its refresh timestamp, and the number of data values. Supports local execution
        or remote execution from an admin workstation via ComputerName and Credential. When
        Credential is provided, a CimSession is created automatically and cleaned up after
        execution. Structured logging to a file can be enabled via LogFilePath, producing
        OTel-compatible JSON Lines output.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DNS server. When provided, a
        CimSession is created automatically. Not required for local execution or when
        the current account already has access to the remote server.

      .PARAMETER ZoneName
        One or more DNS zone names to query. If omitted, all primary non-auto-created
        zones on the target server are queried automatically.

      .PARAMETER RecordType
        The DNS record types to retrieve. Defaults to A and AAAA.
        Accepted values: A, AAAA, CNAME, MX, PTR, SRV, TXT.

      .PARAMETER Filter
        Restricts results to Static records only, Dynamic records only, or All (default).
        Static records are manually created entries with no DDNS timestamp.
        Dynamic records are registered automatically by DHCP clients via DDNS.
        When combined with -Duplicate, the filter is applied before duplicate detection.

      .PARAMETER Duplicate
        When specified, returns only entries where the same hostname has more than one
        record of the same type. Can be combined with -Filter to restrict the source
        records before duplicate detection.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format (one JSON object per line). The file is
        rotated automatically when it exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsEntry

        Returns all A and AAAA records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsEntry -Filter Static

        Returns only manually created A and AAAA records from every primary zone.

      .EXAMPLE
        Get-PSGDnsEntry -Filter Dynamic -ZoneName 'contoso.com'

        Returns only DDNS-registered records from the contoso.com zone.

      .EXAMPLE
        Get-PSGDnsEntry -Duplicate

        Returns only entries where the same hostname appears more than once with the same record type.

      .EXAMPLE
        Get-PSGDnsEntry -Duplicate -Filter Static

        Returns only duplicate entries among statically created records.

      .EXAMPLE
        Get-PSGDnsEntry -ComputerName 'dc01.contoso.com' -Credential (Get-Credential) -Duplicate

        Returns all duplicate entries from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsEntry[]])]
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
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'PTR', 'SRV', 'TXT')]
        [string[]]
        $RecordType = @('A', 'AAAA'),

        [Parameter()]
        [ValidateSet('All', 'Static', 'Dynamic')]
        [string]
        $Filter = 'All',

        [Parameter()]
        [switch]
        $Duplicate,

        [Parameter()]
        [string]
        $LogFilePath
    )

    process
    {
        $moduleVersion = $MyInvocation.MyCommand.Module.Version.ToString()

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
                $cimSession = [PSGDnsEntry]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsEntry]::GetZones($ComputerName, $cimSession)
            }

            foreach ($zone in $zones)
            {
                $logger.Info(
                    ('Processing zone: {0} (filter: {1}, duplicates: {2})' -f $zone, $Filter, $Duplicate.IsPresent),
                    @{ 'dns.zone' = $zone; 'computer.name' = $ComputerName; 'dns.filter' = $Filter; 'dns.duplicate' = $Duplicate.IsPresent }
                )
                [PSGDnsEntry]::GetEntries($ComputerName, $zone, $RecordType, $Filter, $Duplicate.IsPresent, $cimSession)
            }
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsEntry]::RemoveSession($cimSession)
        }
    }
}
