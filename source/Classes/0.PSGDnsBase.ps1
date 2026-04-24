class PSGDnsBase
{
    # Creates a CimSession for remote execution with credentials. Returns $null for local execution.
    static [object] NewSession([string]$ComputerName, [PSCredential]$Credential)
    {
        if ($null -eq $Credential)
        {
            return $null
        }

        return New-CimSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
    }

    # Removes a CimSession created by NewSession. Safe to call with $null.
    static [void] RemoveSession([object]$CimSession)
    {
        if ($null -ne $CimSession)
        {
            Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
        }
    }

    # Returns all primary non-auto-created zone names from the target DNS server.
    static [string[]] GetZones([string]$ComputerName, [object]$CimSession)
    {
        $params = if ($null -ne $CimSession) { @{ CimSession = $CimSession } } else { @{ ComputerName = $ComputerName } }

        return (
            Get-DnsServerZone @params |
                Where-Object -FilterScript { -not $_.IsAutoCreated -and $_.ZoneType -eq 'Primary' } |
                Select-Object -ExpandProperty ZoneName
        )
    }

    # Returns $true when the record has no DDNS timestamp (i.e. manually created).
    static [bool] IsStaticRecord([object]$Record)
    {
        return ($null -eq $Record.TimeStamp) -or ($Record.TimeStamp -eq [datetime]::MinValue)
    }

    # Extracts the data string from a DNS resource record based on its type.
    static [string] ExtractRecordData([object]$Record)
    {
        switch ($Record.RecordType)
        {
            'A'     { return $Record.RecordData.IPv4Address.IPAddressToString }
            'AAAA'  { return $Record.RecordData.IPv6Address.IPAddressToString }
            'CNAME' { return $Record.RecordData.HostNameAlias }
            'MX'    { return $Record.RecordData.MailExchange }
            'PTR'   { return $Record.RecordData.PtrDomainName }
            'SRV'   { return '{0} {1} {2} {3}' -f $Record.RecordData.Priority, $Record.RecordData.Weight, $Record.RecordData.Port, $Record.RecordData.DomainName }
            'TXT'   { return $Record.RecordData.DescriptiveText }
        }

        return $Record.RecordData.ToString()
    }
}
