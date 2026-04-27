BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDnsCnameChain' {
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
            Get-PSGDnsCnameChain
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should not call Get-DnsServerZone' {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Get-PSGDnsCnameChain -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }

        It 'Should return PSGDnsCnameChain objects for deep chains' {
            Mock -CommandName Get-DnsServerResourceRecord -MockWith {
                @(
                    [PSCustomObject]@{ HostName = 'alias';        RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'intermediate.contoso.com.' } },
                    [PSCustomObject]@{ HostName = 'intermediate'; RecordType = 'CNAME'; RecordData = [PSCustomObject]@{ HostNameAlias = 'server01.contoso.com.' } }
                )
            } -ModuleName $script:moduleName

            $result = Get-PSGDnsCnameChain -ZoneName 'contoso.com' -MinDepth 2
            $chainResult = @($result | Where-Object -FilterScript { $_.HostName -eq 'alias' })
            $chainResult | Should -HaveCount 1
            $chainResult[0] | Should -BeOfType 'PSGDnsCnameChain'
            $chainResult[0].Depth | Should -Be 2
        }
    }

    Context 'MinDepth parameter validation' {
        It 'Should reject a value of 0' {
            { Get-PSGDnsCnameChain -MinDepth 0 } | Should -Throw
        }

        It 'Should reject a negative value' {
            { Get-PSGDnsCnameChain -MinDepth -1 } | Should -Throw
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should pass ComputerName to Get-DnsServerZone' {
            Get-PSGDnsCnameChain -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone `
                -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } `
                -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDnsCnameChain -ComputerName 'dc01.contoso.com'
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
            Get-PSGDnsCnameChain -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDnsCnameChain -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once per server' {
            'dc01', 'dc02' | Get-PSGDnsCnameChain
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }
}
