function Get-PSGDnsBrokenCname
{
    <#
      .SYNOPSIS
        Returns CNAME records whose target has no A, AAAA, or CNAME record in the managed zones.

      .DESCRIPTION
        Queries a DNS server and detects broken CNAME records: entries whose alias target cannot
        be resolved within the set of managed zones. Only CNAMEs pointing to a hostname inside a
        managed zone are checked — CNAMEs pointing to external hostnames are silently skipped.
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
        Get-PSGDnsBrokenCname

        Returns all broken CNAME records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsBrokenCname -ZoneName 'contoso.com'

        Returns broken CNAME records from the contoso.com zone only.

      .EXAMPLE
        Get-PSGDnsBrokenCname -ComputerName 'dc01.contoso.com' -Credential (Get-Credential)

        Returns all broken CNAME records from dc01 using explicit credentials.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsBrokenCname[]])]
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
                $cimSession = [PSGDnsBrokenCname]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsBrokenCname]::GetZones($ComputerName, $cimSession)
            }

            $logger.Info(
                ('Scanning {0} zone(s) for broken CNAME records on {1}' -f $zones.Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dns.zone.count' = $zones.Count }
            )

            [PSGDnsBrokenCname]::FindBrokenCnames($ComputerName, $zones, $cimSession)
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsBrokenCname]::RemoveSession($cimSession)
        }
    }
}
