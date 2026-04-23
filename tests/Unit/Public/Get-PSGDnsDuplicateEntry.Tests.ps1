BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDnsDuplicateEntry' {
    BeforeAll {
        $script:mockZones = @(
            [PSCustomObject]@{ ZoneName = 'contoso.com';  IsAutoCreated = $false; ZoneType = 'Primary' },
            [PSCustomObject]@{ ZoneName = 'fabrikam.com'; IsAutoCreated = $false; ZoneType = 'Primary' }
        )

        $script:mockRecordsWithDuplicates = @(
            [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
            [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.11') } },
            [PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.20') } }
        )

        $script:mockRecordsNoDuplicates = @(
            [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
            [PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.20') } }
        )

        $script:mockCredential = [PSCredential]::new('contoso\admin', (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force))
    }

    Context 'When called without ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecordsWithDuplicates } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once' {
            Get-PSGDnsDuplicateEntry
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should return PSGDnsDuplicateEntry objects' {
            $result = Get-PSGDnsDuplicateEntry
            $result | ForEach-Object { $_ | Should -BeOfType 'PSGDnsDuplicateEntry' }
        }

        It 'Should return only duplicate entries' {
            $result = Get-PSGDnsDuplicateEntry
            $result | ForEach-Object { $_.DuplicateCount | Should -BeGreaterThan 1 }
        }
    }

    Context 'When called with ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecordsWithDuplicates } -ModuleName $script:moduleName
        }

        It 'Should not call Get-DnsServerZone' {
            Get-PSGDnsDuplicateEntry -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }

        It 'Should query only the specified zone' {
            Get-PSGDnsDuplicateEntry -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $ZoneName -eq 'contoso.com' } -ModuleName $script:moduleName
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecordsWithDuplicates } -ModuleName $script:moduleName
        }

        It 'Should pass ComputerName to Get-DnsServerZone' {
            Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName New-CimSession -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with Credential' {
        BeforeAll {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Mock -CommandName Remove-CimSession -MockWith {} -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecordsWithDuplicates } -ModuleName $script:moduleName
        }

        It 'Should create a CimSession' {
            Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDnsDuplicateEntry -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When there are no duplicates' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecordsNoDuplicates } -ModuleName $script:moduleName
        }

        It 'Should return nothing' {
            $result = Get-PSGDnsDuplicateEntry
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecordsWithDuplicates } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once per server' {
            'dc01', 'dc02' | Get-PSGDnsDuplicateEntry
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }
}
