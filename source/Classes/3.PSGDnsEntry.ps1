class PSGDnsEntry : PSGDnsBase
{
    [string]$HostName
    [string]$ZoneName
    [string]$RecordType
    [string[]]$RecordData
    [int]$Count
    [bool]$IsStatic
    [datetime]$TimeStamp

    PSGDnsEntry()
    {
    }

    PSGDnsEntry([string]$HostName, [string]$ZoneName, [string]$RecordType, [string[]]$RecordData, [bool]$IsStatic, [datetime]$TimeStamp)
    {
        $this.HostName   = $HostName
        $this.ZoneName   = $ZoneName
        $this.RecordType = $RecordType
        $this.RecordData = $RecordData
        $this.Count      = $RecordData.Count
        $this.IsStatic   = $IsStatic
        $this.TimeStamp  = $TimeStamp
    }

    # Queries a DNS zone and returns PSGDnsEntry objects.
    # Filter restricts to Static or Dynamic records. DuplicatesOnly collapses groups with more than one record.
    static [PSGDnsEntry[]] GetEntries([string]$ComputerName, [string]$ZoneName, [string[]]$RecordType, [string]$Filter, [bool]$DuplicatesOnly, [object]$CimSession)
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

        $filteredRecords = [System.Collections.Generic.List[object]]::new()

        foreach ($record in $allRecords)
        {
            $isStatic = [PSGDnsBase]::IsStaticRecord($record)
            if ($Filter -eq 'Static'  -and -not $isStatic) { continue }
            if ($Filter -eq 'Dynamic' -and $isStatic)      { continue }
            $filteredRecords.Add($record)
        }

        $results = [System.Collections.Generic.List[PSGDnsEntry]]::new()

        if ($DuplicatesOnly)
        {
            $filteredRecords |
                Group-Object -Property HostName, RecordType |
                Where-Object -FilterScript { $_.Count -gt 1 } |
                ForEach-Object -Process {
                    $group    = $_
                    $allStatic = -not ($group.Group | Where-Object -FilterScript { -not [PSGDnsBase]::IsStaticRecord($_) })

                    $ts = if ($allStatic)
                    {
                        [datetime]::MinValue
                    }
                    else
                    {
                        ($group.Group |
                            Where-Object -FilterScript { -not [PSGDnsBase]::IsStaticRecord($_) } |
                            Sort-Object -Property TimeStamp -Descending |
                            Select-Object -First 1).TimeStamp
                    }

                    $data = $group.Group | ForEach-Object -Process { [PSGDnsBase]::ExtractRecordData($_) }

                    $results.Add([PSGDnsEntry]::new(
                        $group.Group[0].HostName,
                        $ZoneName,
                        $group.Group[0].RecordType,
                        $data,
                        $allStatic,
                        $ts
                    ))
                }
        }
        else
        {
            foreach ($record in $filteredRecords)
            {
                $isStatic = [PSGDnsBase]::IsStaticRecord($record)
                $ts       = if ($null -eq $record.TimeStamp) { [datetime]::MinValue } else { $record.TimeStamp }

                $results.Add([PSGDnsEntry]::new(
                    $record.HostName,
                    $ZoneName,
                    $record.RecordType,
                    @([PSGDnsBase]::ExtractRecordData($record)),
                    $isStatic,
                    $ts
                ))
            }
        }

        return $results.ToArray()
    }

    [string] ToString()
    {
        $entryType = if ($this.IsStatic) { 'Static' } else { 'Dynamic' }

        if ($this.Count -gt 1)
        {
            return '[{0}] [{1}] {2}.{3} - {4} records: {5}' -f
                $this.RecordType, $entryType, $this.HostName, $this.ZoneName,
                $this.Count, ($this.RecordData -join ', ')
        }

        return '[{0}] [{1}] {2}.{3} = {4}' -f
            $this.RecordType, $entryType, $this.HostName, $this.ZoneName, $this.RecordData[0]
    }
}
