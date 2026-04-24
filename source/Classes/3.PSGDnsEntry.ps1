class PSGDnsEntry : PSGDnsBase
{
    [string]$HostName
    [string]$ZoneName
    [string]$RecordType
    [string]$RecordData
    [bool]$IsStatic
    [datetime]$TimeStamp

    PSGDnsEntry()
    {
    }

    PSGDnsEntry([string]$HostName, [string]$ZoneName, [string]$RecordType, [string]$RecordData, [bool]$IsStatic, [datetime]$TimeStamp)
    {
        $this.HostName   = $HostName
        $this.ZoneName   = $ZoneName
        $this.RecordType = $RecordType
        $this.RecordData = $RecordData
        $this.IsStatic   = $IsStatic
        $this.TimeStamp  = $TimeStamp
    }

    # Returns $true when the record has no DDNS timestamp (i.e. manually created).
    static [bool] IsStaticRecord([object]$Record)
    {
        return ($null -eq $Record.TimeStamp) -or ($Record.TimeStamp -eq [datetime]::MinValue)
    }

    # Queries a DNS zone and returns PSGDnsEntry objects, optionally filtered by Static or Dynamic.
    # Pass $null for CimSession when no credentials are required.
    static [PSGDnsEntry[]] GetEntries([string]$ComputerName, [string]$ZoneName, [string[]]$RecordType, [string]$Filter, [object]$CimSession)
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

        $results = [System.Collections.Generic.List[PSGDnsEntry]]::new()

        foreach ($record in $allRecords)
        {
            $isStatic = [PSGDnsEntry]::IsStaticRecord($record)

            if ($Filter -eq 'Static' -and -not $isStatic) { continue }
            if ($Filter -eq 'Dynamic' -and $isStatic) { continue }

            $ts = if ($null -eq $record.TimeStamp) { [datetime]::MinValue } else { $record.TimeStamp }

            $results.Add(
                [PSGDnsEntry]::new(
                    $record.HostName,
                    $ZoneName,
                    $record.RecordType,
                    [PSGDnsBase]::ExtractRecordData($record),
                    $isStatic,
                    $ts
                )
            )
        }

        return $results.ToArray()
    }

    [string] ToString()
    {
        $entryType = if ($this.IsStatic) { 'Static' } else { 'Dynamic' }
        return '[{0}] [{1}] {2}.{3} = {4}' -f $this.RecordType, $entryType, $this.HostName, $this.ZoneName, $this.RecordData
    }
}
