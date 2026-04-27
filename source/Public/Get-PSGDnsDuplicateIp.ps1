function Get-PSGDnsDuplicateIp
{
    <#
      .SYNOPSIS
        Returns IP addresses shared by more than one hostname across the managed DNS zones.

      .DESCRIPTION
        Queries a DNS server and collects all A records across the specified zones. Groups
        records by IP address and returns only those where the same address is assigned to
        more than one distinct hostname. This is useful for detecting incomplete migrations,
        forgotten aliases, or IP address conflicts.
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

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsDuplicateIp

        Returns all IP addresses shared by more than one hostname across every primary zone.

      .EXAMPLE
        Get-PSGDnsDuplicateIp -ZoneName 'contoso.com', 'fabrikam.com'

        Returns duplicate IPs across two specific zones.

      .EXAMPLE
        Get-PSGDnsDuplicateIp -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns duplicate IPs from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsDuplicateIp[]])]
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
                $cimSession = [PSGDnsDuplicateIp]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsDuplicateIp]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Scanning {0} zone(s) for duplicate IPs on {1}' -f $zones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count }
            )

            Write-Verbose ('Zones: {0}' -f ($zones -join ', '))

            $duplicates = [PSGDnsDuplicateIp]::FindDuplicateIps($ComputerName, $zones, $cimSession)

            $logger.Info(
                ('{0} duplicate IP(s) found on {1}' -f @($duplicates).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.duplicate.count' = @($duplicates).Count }
            )

            $duplicates
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsDuplicateIp]::RemoveSession($cimSession)
        }
    }
}
