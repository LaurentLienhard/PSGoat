function Get-PSGDnsCnameChain
{
    <#
      .SYNOPSIS
        Returns CNAME chains longer than a given depth, and all circular CNAME references.

      .DESCRIPTION
        Queries a DNS server and maps all CNAME records within the managed zones. For each
        CNAME it follows the chain of aliases until a non-CNAME target is reached, an external
        target is encountered, or a loop is detected. Reports chains whose depth is equal to
        or greater than MinDepth, and all circular chains regardless of depth. Depth is the
        number of CNAME hops: a single CNAME pointing directly to an A record has a depth
        of 1 (normal); a CNAME pointing to another CNAME before reaching a final record has
        a depth of 2 or more (potentially problematic).
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

      .PARAMETER MinDepth
        Minimum number of CNAME hops to report. Defaults to 2. A value of 1 would return
        all CNAME records. Circular chains are always returned regardless of this value.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsCnameChain

        Returns all CNAME chains with 2 or more hops, and all circular references.

      .EXAMPLE
        Get-PSGDnsCnameChain -MinDepth 3

        Returns only chains with 3 or more hops, and all circular references.

      .EXAMPLE
        Get-PSGDnsCnameChain -ZoneName 'contoso.com'

        Returns CNAME chains from contoso.com only.

      .EXAMPLE
        Get-PSGDnsCnameChain -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns CNAME chains from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsCnameChain[]])]
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
        $MinDepth = 2,

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
                $cimSession = [PSGDnsCnameChain]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsCnameChain]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Scanning {0} zone(s) for CNAME chains on {1} (min depth: {2})' -f $zones.Count, $ComputerName, $MinDepth),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count; 'dns.cname.mindepth' = $MinDepth }
            )

            Write-Verbose ('Zones: {0}' -f ($zones -join ', '))

            $chains = [PSGDnsCnameChain]::FindCnameChains($ComputerName, $zones, $MinDepth, $cimSession)

            $logger.Info(
                ('{0} CNAME chain(s) found on {1}' -f @($chains).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.cname.chain.count' = @($chains).Count }
            )

            $chains
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsCnameChain]::RemoveSession($cimSession)
        }
    }
}
