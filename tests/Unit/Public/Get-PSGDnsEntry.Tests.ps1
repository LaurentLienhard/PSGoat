BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDnsEntry' {
    BeforeAll {
        $script:mockZones = @(
            [PSCustomObject]@{ ZoneName = 'contoso.com';  IsAutoCreated = $false; ZoneType = 'Primary' },
            [PSCustomObject]@{ ZoneName = 'fabrikam.com'; IsAutoCreated = $false; ZoneType = 'Primary' }
        )

        $script:mockRecords = @(
            [PSCustomObject]@{
                HostName   = 'server01'
                RecordType = 'A'
                TimeStamp  = [datetime]::MinValue
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
            },
            [PSCustomObject]@{
                HostName   = 'workstation01'
                RecordType = 'A'
                TimeStamp  = [datetime]'2025-01-15 10:00:00'
                RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.50') }
            }
        )

        $script:mockCredential = [PSCredential]::new('contoso\admin', (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force))
    }

    Context 'When called without ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecords } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once' {
            Get-PSGDnsEntry
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should return PSGDnsEntry objects' {
            $result = Get-PSGDnsEntry
            $result | ForEach-Object { $_ | Should -BeOfType 'PSGDnsEntry' }
        }
    }

    Context 'When called with ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecords } -ModuleName $script:moduleName
        }

        It 'Should not call Get-DnsServerZone' {
            Get-PSGDnsEntry -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }

        It 'Should query only the specified zone' {
            Get-PSGDnsEntry -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerResourceRecord -ParameterFilter { $ZoneName -eq 'contoso.com' } -ModuleName $script:moduleName
        }
    }

    Context 'When Filter is Static' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecords } -ModuleName $script:moduleName
        }

        It 'Should return only static entries' {
            $result = Get-PSGDnsEntry -ZoneName 'contoso.com' -Filter Static
            $result | ForEach-Object { $_.IsStatic | Should -BeTrue }
        }
    }

    Context 'When Filter is Dynamic' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecords } -ModuleName $script:moduleName
        }

        It 'Should return only dynamic entries' {
            $result = Get-PSGDnsEntry -ZoneName 'contoso.com' -Filter Dynamic
            $result | ForEach-Object { $_.IsStatic | Should -BeFalse }
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecords } -ModuleName $script:moduleName
        }

        It 'Should pass ComputerName to Get-DnsServerZone' {
            Get-PSGDnsEntry -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDnsEntry -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName New-CimSession -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with Credential' {
        BeforeAll {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Mock -CommandName Remove-CimSession -MockWith {} -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecords } -ModuleName $script:moduleName
        }

        It 'Should create a CimSession' {
            Get-PSGDnsEntry -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDnsEntry -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { $script:mockRecords } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once per server' {
            'dc01', 'dc02' | Get-PSGDnsEntry
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }
}
