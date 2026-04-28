function Get-PSGDhcpScopeUtilization
{
    <#
      .SYNOPSIS
        Returns utilization statistics for DHCPv4 scopes on a Windows DHCP server.

      .DESCRIPTION
        Queries a DHCP server and returns per-scope utilization data: total addresses,
        addresses in use (active leases), reserved addresses, free addresses, and the
        overall utilization percentage. Both active leases and reservations are counted
        as consumed capacity.

        The -Threshold parameter restricts output to scopes whose utilization is at or
        above the specified percentage, making it easy to identify scopes at risk of
        exhaustion.

        Supports local execution or remote execution via ComputerName and Credential.
        When Credential is provided, a CimSession is created automatically and cleaned
        up after execution. Structured logging can be enabled via LogFilePath, producing
        OTel-compatible JSON Lines output.

      .PARAMETER ComputerName
        The DHCP server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

      .PARAMETER Credential
        Credentials to use when connecting to a remote DHCP server. When provided, a
        CimSession is created automatically.

      .PARAMETER ScopeId
        One or more scope IDs (e.g. '192.168.1.0') to inspect. If omitted, all scopes
        on the target server are returned.

      .PARAMETER Threshold
        Minimum utilization percentage to include in results. Scopes below this value
        are silently skipped. Defaults to 0 (all scopes returned).

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format. The file is rotated automatically when it
        exceeds 10 MB.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization

        Returns utilization for all scopes on the local DHCP server.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization -Threshold 80

        Returns only scopes where 80% or more of the address space is consumed.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization -ScopeId '192.168.1.0', '10.0.0.0'

        Returns utilization for two specific scopes.

      .EXAMPLE
        Get-PSGDhcpScopeUtilization -ComputerName 'dhcp01.contoso.com' -Credential (Get-Credential) -Threshold 80

        Returns critical scopes from a remote DHCP server using explicit credentials.

      .EXAMPLE
        'dhcp01.contoso.com', 'dhcp02.contoso.com' | Get-PSGDhcpScopeUtilization -Threshold 80 |
            Format-Table ScopeId, Name, TotalAddresses, InUse, Free, UtilizationPercent

        Returns critical scopes from two DHCP servers formatted as a table.
    #>
    [CmdletBinding()]
    [OutputType([PSGDhcpScopeUtilization[]])]
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
        $ScopeId = @(),

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]
        $Threshold = 0,

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
                $cimSession = [PSGDhcpScopeUtilization]::NewSession($ComputerName, $Credential)
            }

            $logger.Info(
                ('Retrieving DHCP scope utilization from {0} (threshold: {1}%)' -f $ComputerName, $Threshold),
                @{ 'computer.name' = $ComputerName; 'dhcp.threshold' = $Threshold }
            )

            $results = [PSGDhcpScopeUtilization]::GetUtilization($ComputerName, $ScopeId, $Threshold, $cimSession)

            $logger.Info(
                ('{0} scope(s) returned from {1}' -f @($results).Count, $ComputerName),
                @{ 'computer.name' = $ComputerName; 'dhcp.scope.count' = @($results).Count }
            )

            $results
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDhcpScopeUtilization]::RemoveSession($cimSession)
        }
    }
}
