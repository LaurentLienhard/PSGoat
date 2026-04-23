function Get-PSGDnsDuplicateEntry
{
    <#
      .SYNOPSIS
        Returns all duplicate DNS entries from one or more DNS zones.

      .DESCRIPTION
        Queries a DNS server for resource records and identifies entries where the same
        hostname has more than one record of the same type. Supports local execution or
        remote execution via the ComputerName parameter, making it usable directly on
        the target DNS server or from an admin workstation.

      .PARAMETER ComputerName
        The DNS server to query. Defaults to the local machine. Accepts pipeline input
        to query multiple servers sequentially.

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

        Returns all duplicate A and AAAA records from the contoso.com zone on dc01.

      .EXAMPLE
        'dc01', 'dc02' | Get-PSGDnsDuplicateEntry -ZoneName 'contoso.com'

        Queries two DNS servers in sequence for duplicate entries in the contoso.com zone.

      .EXAMPLE
        Get-PSGDnsDuplicateEntry -ZoneName 'contoso.com' -RecordType A, CNAME

        Returns duplicate A and CNAME records from the contoso.com zone on the local server.
    #>
    [CmdletBinding()]
    [OutputType([PSGDnsDuplicateEntry[]])]
    param
    (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $ComputerName = $env:COMPUTERNAME,

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
        if ($PSBoundParameters.ContainsKey('ZoneName'))
        {
            $zones = $ZoneName
        }
        else
        {
            Write-Verbose -Message ('Retrieving DNS zones from {0}' -f $ComputerName)
            $zones = [PSGDnsDuplicateEntry]::GetZones($ComputerName)
        }

        foreach ($zone in $zones)
        {
            Write-Verbose -Message ('Processing zone: {0}' -f $zone)

            [PSGDnsDuplicateEntry]::FindInZone($ComputerName, $zone, $RecordType)
        }
    }
}
