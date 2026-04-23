function Get-PSGDnsDuplicateEntry
{
    <#
      .SYNOPSIS
        Returns all duplicate DNS entries from one or more DNS zones.

      .DESCRIPTION
        Queries a DNS server for resource records and identifies entries where the same
        hostname has more than one record of the same type. Supports local execution or
        remote execution from an admin workstation via the ComputerName and Credential
        parameters. When Credential is provided, a CimSession is established automatically
        and cleaned up after execution. Structured logging to a file can be enabled via
        LogFilePath, producing OTel-compatible JSON Lines output.

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
        The DNS record types to check for duplicates. Defaults to A and AAAA.
        Accepted values: A, AAAA, CNAME, MX, PTR, SRV, TXT.

      .PARAMETER LogFilePath
        Optional path to a log file. When provided, all log entries are written in
        OTel-compatible JSON Lines format (one JSON object per line). The file is
        rotated automatically when it exceeds 10 MB.

      .EXAMPLE
        Get-PSGDnsDuplicateEntry

        Returns all duplicate A and AAAA records from every primary zone on the local DNS server.

      .EXAMPLE
        Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com' -ZoneName 'contoso.com'

        Returns all duplicate A and AAAA records from the contoso.com zone on dc01 using the current account.

      .EXAMPLE
        $cred = Get-Credential
        Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com' -Credential $cred

        Returns all duplicate entries from dc01 using explicit credentials.

      .EXAMPLE
        Get-PSGDnsDuplicateEntry -ZoneName 'contoso.com' -LogFilePath 'C:\Logs\PSGoat.log'

        Returns duplicate entries and writes structured OTel logs to the specified file.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsDuplicateEntry[]])]
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
        [string]
        $LogFilePath
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('LogFilePath'))
        {
            $logger = [PSGLogger]::new('PSGoat', '0.1.0', $LogFilePath)
        }
        else
        {
            $logger = [PSGLogger]::new('PSGoat', '0.1.0')
        }

        $cimSession = $null

        try
        {
            if ($PSBoundParameters.ContainsKey('Credential'))
            {
                $logger.Info(('Creating CimSession on {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $cimSession = [PSGDnsDuplicateEntry]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                $logger.Info(('Retrieving DNS zones from {0}' -f $ComputerName), @{ 'computer.name' = $ComputerName })
                $zones = [PSGDnsDuplicateEntry]::GetZones($ComputerName, $cimSession)
            }

            foreach ($zone in $zones)
            {
                $logger.Info(('Processing zone: {0}' -f $zone), @{ 'dns.zone' = $zone; 'computer.name' = $ComputerName })
                [PSGDnsDuplicateEntry]::FindInZone($ComputerName, $zone, $RecordType, $cimSession)
            }
        }
        catch
        {
            $logger.Error($_.Exception.Message, @{ 'computer.name' = $ComputerName; 'error.type' = $_.Exception.GetType().Name })
            throw
        }
        finally
        {
            [PSGDnsDuplicateEntry]::RemoveSession($cimSession)
        }
    }
}
