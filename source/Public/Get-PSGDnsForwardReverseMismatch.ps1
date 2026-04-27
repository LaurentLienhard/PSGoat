function Get-PSGDnsForwardReverseMismatch
{
    <#
      .SYNOPSIS
        Returns A records whose corresponding PTR record exists but points to a different FQDN.

      .DESCRIPTION
        Queries a DNS server and cross-references forward zones (A records) with reverse zones
        (PTR records). For each A record where a PTR exists for the same IP, this function checks
        whether the PTR target matches the A record hostname. Records where no PTR exists at all
        are intentionally skipped -- use Get-PSGDnsOrphanEntry to detect those.

        This is useful for detecting stale or inconsistent reverse DNS entries left behind after
        server renames, IP reassignments, or incomplete migrations.

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

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsForwardReverseMismatch

        Returns all forward/reverse mismatches across every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsForwardReverseMismatch -ZoneName 'contoso.com'

        Returns mismatches restricted to the contoso.com forward zone.

      .EXAMPLE
        Get-PSGDnsForwardReverseMismatch -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns mismatches from dc01 using explicit credentials.

      .EXAMPLE
        'dc01.contoso.com', 'dc02.contoso.com' | Get-PSGDnsForwardReverseMismatch

        Returns mismatches from two DNS servers sequentially.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsForwardReverseMismatch[]])]
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
                $cimSession = [PSGDnsForwardReverseMismatch]::NewSession($ComputerName, $Credential)
            }

            $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
            $allZones = [PSGDnsForwardReverseMismatch]::GetZones($ComputerName, $cimSession)

            $reverseZones = @($allZones | Where-Object -FilterScript { $_ -match '\.in-addr\.arpa$|\.ip6\.arpa$' })
            $forwardZones = @($allZones | Where-Object -FilterScript { $_ -notmatch '\.in-addr\.arpa$|\.ip6\.arpa$' })

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $forwardZones = $ZoneName
            }

            $logger.Info(
                ('Scanning {0} forward zone(s) and {1} reverse zone(s) on {2}' -f $forwardZones.Count, $reverseZones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.forward.zone.count' = $forwardZones.Count; 'dns.reverse.zone.count' = $reverseZones.Count }
            )

            Write-Verbose ('Forward zones: {0}' -f ($forwardZones -join ', '))
            Write-Verbose ('Reverse zones: {0}' -f ($reverseZones -join ', '))

            $mismatches = [PSGDnsForwardReverseMismatch]::FindMismatches($ComputerName, $forwardZones, $reverseZones, $cimSession)

            $logger.Info(
                ('{0} forward/reverse mismatch(es) found on {1}' -f @($mismatches).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.mismatch.count' = @($mismatches).Count }
            )

            $mismatches
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsForwardReverseMismatch]::RemoveSession($cimSession)
        }
    }
}
