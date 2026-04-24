class PSGDnsDuplicateEntry : PSGDnsBase
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
            Group-Object -Property HostName, RecordType |
            Where-Object -FilterScript { $_.Count -gt 1 } |
            ForEach-Object -Process {
                $group = $_

                $recordData = $group.Group | ForEach-Object -Process {
                    [PSGDnsBase]::ExtractRecordData($_)
                }

                $results.Add(
                    [PSGDnsDuplicateEntry]::new(
                        $group.Group[0].HostName,
                        $ZoneName,
                        $group.Group[0].RecordType,
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
