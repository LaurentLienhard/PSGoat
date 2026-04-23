class PSGDnsDuplicateEntry
{
    [string]$HostName
    [string]$ZoneName
    [string]$RecordType
    [string[]]$RecordData
    [int]$DuplicateCount

    PSGDnsDuplicateEntry()
    {
    }

    PSGDnsDuplicateEntry([string]$HostName, [string]$ZoneName, [string]$RecordType, [string[]]$RecordData)
    {
        $this.HostName       = $HostName
        $this.ZoneName       = $ZoneName
        $this.RecordType     = $RecordType
        $this.RecordData     = $RecordData
        $this.DuplicateCount = $RecordData.Count
    }

    # Creates a CimSession for remote execution with credentials. Returns $null for local execution.
    static [object] NewSession([string]$ComputerName, [PSCredential]$Credential)
    {
        if ($null -eq $Credential)
        {
            return $null
        }

        return New-CimSession -ComputerName $ComputerName -Credential $Credential
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
    # Pass $null for CimSession when no credentials are required.
    static [string[]] GetZones([string]$ComputerName, [object]$CimSession)
    {
        if ($null -ne $CimSession)
        {
            return (
                Get-DnsServerZone -CimSession $CimSession |
                    Where-Object -FilterScript { -not $_.IsAutoCreated -and $_.ZoneType -eq 'Primary' } |
                    Select-Object -ExpandProperty ZoneName
            )
        }

        return (
            Get-DnsServerZone -ComputerName $ComputerName |
                Where-Object -FilterScript { -not $_.IsAutoCreated -and $_.ZoneType -eq 'Primary' } |
                Select-Object -ExpandProperty ZoneName
        )
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
            'TXT'   { return $Record.RecordData.DescriptiveText }
        }

        return $Record.RecordData.ToString()
    }

    # Queries a DNS zone and returns PSGDnsDuplicateEntry objects for every duplicated hostname.
    # Pass $null for CimSession when no credentials are required.
    static [PSGDnsDuplicateEntry[]] FindInZone([string]$ComputerName, [string]$ZoneName, [string[]]$RecordType, [object]$CimSession)
    {
        $allRecords = [System.Collections.Generic.List[object]]::new()

        foreach ($type in $RecordType)
        {
            if ($null -ne $CimSession)
            {
                $records = Get-DnsServerResourceRecord -CimSession $CimSession -ZoneName $ZoneName -RRType $type -ErrorAction SilentlyContinue
            }
            else
            {
                $records = Get-DnsServerResourceRecord -ComputerName $ComputerName -ZoneName $ZoneName -RRType $type -ErrorAction SilentlyContinue
            }

            if ($records)
            {
                $allRecords.AddRange([object[]]@($records))
            }
        }

        $results = [System.Collections.Generic.List[PSGDnsDuplicateEntry]]::new()

        $allRecords |
            Group-Object -Property HostName |
            Where-Object -FilterScript { $_.Count -gt 1 } |
            ForEach-Object -Process {
                $group = $_

                $recordData = $group.Group | ForEach-Object -Process {
                    [PSGDnsDuplicateEntry]::ExtractRecordData($_)
                }

                $results.Add(
                    [PSGDnsDuplicateEntry]::new(
                        $group.Name,
                        $ZoneName,
                        ($group.Group.RecordType | Select-Object -Unique) -join '/',
                        $recordData
                    )
                )
            }

        return $results.ToArray()
    }

    [string] ToString()
    {
        return '[{0}] {1}.{2} - {3} duplicate {4}' -f
            $this.RecordType,
            $this.HostName,
            $this.ZoneName,
            $this.DuplicateCount,
            $(if ($this.DuplicateCount -gt 1) { 'entries' } else { 'entry' })
    }
}
