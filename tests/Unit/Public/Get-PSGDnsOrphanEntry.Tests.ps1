BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDnsOrphanEntry' {
    BeforeAll {
        $script:mockAllZones = @(
            [PSCustomObject]@{ ZoneName = 'contoso.com';              IsAutoCreated = $false; ZoneType = 'Primary' },
            [PSCustomObject]@{ ZoneName = '1.168.192.in-addr.arpa';   IsAutoCreated = $false; ZoneType = 'Primary' }
        )

        $script:mockCredential = [PSCredential]::new(
            'contoso\admin',
            (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force)
        )
    }

    Context 'When called without ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once to discover all zones' {
            Get-PSGDnsOrphanEntry
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should return PSGDnsOrphanEntry objects' {
            Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                @([PSCustomObject]@{
                    HostName   = 'server02'
                    RecordType = 'A'
                    RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.20') }
                })
            } -ParameterFilter { $RRType -eq 'A' -and [string]::IsNullOrEmpty($Name) } -ModuleName $script:moduleName

            $result = Get-PSGDnsOrphanEntry -OrphanType MissingPTR
            $result | ForEach-Object { $_ | Should -BeOfType 'PSGDnsOrphanEntry' }
        }
    }

    Context 'When called with ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should restrict forward zone inspection to the specified zone' {
            Get-PSGDnsOrphanEntry -ZoneName 'contoso.com' -OrphanType MissingPTR
            Should -Invoke -CommandName Get-DnsServerResourceRecord `
                -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' } `
                -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When OrphanType is MissingPTR' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should not query PTR records in bulk from reverse zones' {
            Get-PSGDnsOrphanEntry -OrphanType MissingPTR
            Should -Invoke -CommandName Get-DnsServerResourceRecord `
                -ParameterFilter { $RRType -eq 'PTR' -and [string]::IsNullOrEmpty($Name) } `
                -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When OrphanType is MissingA' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should not query A records in bulk from forward zones' {
            Get-PSGDnsOrphanEntry -OrphanType MissingA
            Should -Invoke -CommandName Get-DnsServerResourceRecord `
                -ParameterFilter { $RRType -eq 'A' -and [string]::IsNullOrEmpty($Name) } `
                -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should pass ComputerName to Get-DnsServerZone' {
            Get-PSGDnsOrphanEntry -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone `
                -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } `
                -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDnsOrphanEntry -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName New-CimSession -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with Credential' {
        BeforeAll {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Mock -CommandName Remove-CimSession -MockWith {} -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should create a CimSession' {
            Get-PSGDnsOrphanEntry -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDnsOrphanEntry -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once per server' {
            'dc01', 'dc02' | Get-PSGDnsOrphanEntry
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }
}
