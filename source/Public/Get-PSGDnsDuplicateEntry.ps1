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
        and cleaned up after execution.

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
        'dc01', 'dc02' | Get-PSGDnsDuplicateEntry -ZoneName 'contoso.com' -Credential (Get-Credential)

        Queries two remote DNS servers in sequence using the same credentials.
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
        $RecordType = @('A', 'AAAA')
    )

    process
    {
        $cimSession = $null

        try
        {
            if ($PSBoundParameters.ContainsKey('Credential'))
            {
                Write-Verbose -Message ('Creating CimSession on {0}' -f $ComputerName)
                $cimSession = [PSGDnsDuplicateEntry]::NewSession($ComputerName, $Credential)
            }

            if ($PSBoundParameters.ContainsKey('ZoneName'))
            {
                $zones = $ZoneName
            }
            else
            {
                Write-Verbose -Message ('Retrieving DNS zones from {0}' -f $ComputerName)
                $zones = [PSGDnsDuplicateEntry]::GetZones($ComputerName, $cimSession)
            }

            foreach ($zone in $zones)
            {
                Write-Verbose -Message ('Processing zone: {0}' -f $zone)
                [PSGDnsDuplicateEntry]::FindInZone($ComputerName, $zone, $RecordType, $cimSession)
            }
        }
        finally
        {
            [PSGDnsDuplicateEntry]::RemoveSession($cimSession)
        }
    }
}
