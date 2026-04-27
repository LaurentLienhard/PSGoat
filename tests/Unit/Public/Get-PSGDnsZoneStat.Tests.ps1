BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDnsZoneStat' {
    BeforeAll {
        $script:mockZones = @(
            [PSCustomObject]@{ ZoneName = 'contoso.com'; IsAutoCreated = $false; ZoneType = 'Primary' }
        )

        $script:mockCredential = [PSCredential]::new(
            'contoso\admin',
            (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force)
        )
    }

    Context 'When called without ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone              -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord    -MockWith { @() }               -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone to discover zones' {
            Get-PSGDnsZoneStat
            Should -Invoke -CommandName Get-DnsServerZone -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone              -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord    -MockWith { @() }               -ModuleName $script:moduleName
        }

        It 'Should not call Get-DnsServerZone for zone discovery' {
            Get-PSGDnsZoneStat -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should return a PSGDnsZoneStat object' {
            $result = Get-PSGDnsZoneStat -ZoneName 'contoso.com'
            $result | Should -HaveCount 1
            $result[0] | Should -BeOfType 'PSGDnsZoneStat'
            $result[0].ZoneName | Should -Be 'contoso.com'
        }

        It 'Should return correct record counts' {
            Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                param ($RRType)
                if ($RRType -eq 'A')
                {
                    @(
                        [PSCustomObject]@{ RecordType = 'A'; TimeStamp = $null;                        RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                        [PSCustomObject]@{ RecordType = 'A'; TimeStamp = [datetime]::Now.AddDays(-60); RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.11') } }
                    )
                }
                else { @() }
            } -ModuleName $script:moduleName

            $result = Get-PSGDnsZoneStat -ZoneName 'contoso.com' -ThresholdDays 30
            $result[0].TotalRecords | Should -Be 2
            $result[0].StaticCount  | Should -Be 1
            $result[0].DynamicCount | Should -Be 1
            $result[0].StaleCount   | Should -Be 1
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone              -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord    -MockWith { @() }               -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDnsZoneStat -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName New-CimSession -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with Credential' {
        BeforeAll {
            Mock -CommandName New-CimSession              -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Mock -CommandName Remove-CimSession           -MockWith {}                              -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerZone           -MockWith { $script:mockZones }           -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() }                         -ModuleName $script:moduleName
        }

        It 'Should create a CimSession' {
            Get-PSGDnsZoneStat -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDnsZoneStat -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone              -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord    -MockWith { @() }               -ModuleName $script:moduleName
        }

        It 'Should process each server independently' {
            $results = 'dc01', 'dc02' | Get-PSGDnsZoneStat
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'ThresholdDays parameter validation' {
        It 'Should reject a value of 0' {
            { Get-PSGDnsZoneStat -ThresholdDays 0 } | Should -Throw
        }

        It 'Should reject a negative value' {
            { Get-PSGDnsZoneStat -ThresholdDays -1 } | Should -Throw
        }
    }
}
