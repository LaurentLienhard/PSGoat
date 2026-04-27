BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDnsDuplicateIp' {
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
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once to discover all zones' {
            Get-PSGDnsDuplicateIp
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should not call Get-DnsServerZone' {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Get-PSGDnsDuplicateIp -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }

        It 'Should return PSGDnsDuplicateIp objects for shared IPs' {
            Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                @(
                    [PSCustomObject]@{ HostName = 'server01'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } },
                    [PSCustomObject]@{ HostName = 'server02'; RecordType = 'A'; RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') } }
                )
            } -ModuleName $script:moduleName

            $result = Get-PSGDnsDuplicateIp -ZoneName 'contoso.com'
            $result | Should -HaveCount 1
            $result[0] | Should -BeOfType 'PSGDnsDuplicateIp'
            $result[0].IPAddress | Should -Be '192.168.1.10'
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should pass ComputerName to Get-DnsServerZone' {
            Get-PSGDnsDuplicateIp -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone `
                -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } `
                -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDnsDuplicateIp -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName New-CimSession -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with Credential' {
        BeforeAll {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Mock -CommandName Remove-CimSession -MockWith {} -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should create a CimSession' {
            Get-PSGDnsDuplicateIp -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDnsDuplicateIp -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once per server' {
            'dc01', 'dc02' | Get-PSGDnsDuplicateIp
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }
}
