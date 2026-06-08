BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDnsForwardReverseMismatch' {
    BeforeAll {
        $script:mockAllZones = @(
            [PSCustomObject]@{ ZoneName = 'contoso.com';             IsAutoCreated = $false; ZoneType = 'Primary' },
            [PSCustomObject]@{ ZoneName = '1.168.192.in-addr.arpa';  IsAutoCreated = $false; ZoneType = 'Primary' }
        )

        $script:mockCredential = [PSCredential]::new(
            'contoso\admin',
            (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force)
        )

        $script:mockARecordMismatch = [PSCustomObject]@{
            HostName   = 'server01'
            RecordType = 'A'
            RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
        }

        $script:mockPtrRecordMismatch = [PSCustomObject]@{
            HostName   = '10'
            RecordType = 'PTR'
            RecordData = [PSCustomObject]@{ PtrDomainName = 'server02.contoso.com.' }
        }

        $script:mockARecordConsistent = [PSCustomObject]@{
            HostName   = 'server01'
            RecordType = 'A'
            RecordData = [PSCustomObject]@{ IPv4Address = [System.Net.IPAddress]::Parse('192.168.1.10') }
        }

        $script:mockPtrRecordConsistent = [PSCustomObject]@{
            HostName   = '10'
            RecordType = 'PTR'
            RecordData = [PSCustomObject]@{ PtrDomainName = 'server01.contoso.com.' }
        }
    }

    Context 'When called without ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once to discover all zones' {
            Get-PSGDnsForwardReverseMismatch
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with ZoneName' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should still call Get-DnsServerZone to discover reverse zones' {
            Get-PSGDnsForwardReverseMismatch -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should restrict A record queries to the specified forward zone' {
            Get-PSGDnsForwardReverseMismatch -ZoneName 'contoso.com'
            Should -Invoke -CommandName Get-DnsServerResourceRecord `
                -ParameterFilter { $ZoneName -eq 'contoso.com' -and $RRType -eq 'A' } `
                -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When A and PTR point to different FQDNs' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord `
                -MockWith { @($script:mockARecordMismatch) } `
                -ParameterFilter { $RRType -eq 'A' } `
                -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord `
                -MockWith { @($script:mockPtrRecordMismatch) } `
                -ParameterFilter { $RRType -eq 'PTR' } `
                -ModuleName $script:moduleName
        }

        It 'Should return one PSGDnsForwardReverseMismatch object' {
            $result = Get-PSGDnsForwardReverseMismatch
            $result | Should -HaveCount 1
            $result[0] | Should -BeOfType 'PSGDnsForwardReverseMismatch'
        }

        It 'Should expose the correct ForwardFQDN' {
            $result = Get-PSGDnsForwardReverseMismatch
            $result[0].ForwardFQDN | Should -Be 'server01.contoso.com'
        }

        It 'Should expose the correct IPAddress' {
            $result = Get-PSGDnsForwardReverseMismatch
            $result[0].IPAddress | Should -Be '192.168.1.10'
        }

        It 'Should expose the correct ReverseFQDN' {
            $result = Get-PSGDnsForwardReverseMismatch
            $result[0].ReverseFQDN | Should -Be 'server02.contoso.com'
        }
    }

    Context 'When A and PTR agree' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord `
                -MockWith { @($script:mockARecordConsistent) } `
                -ParameterFilter { $RRType -eq 'A' } `
                -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord `
                -MockWith { @($script:mockPtrRecordConsistent) } `
                -ParameterFilter { $RRType -eq 'PTR' } `
                -ModuleName $script:moduleName
        }

        It 'Should return no results' {
            $result = Get-PSGDnsForwardReverseMismatch
            $result | Should -HaveCount 0
        }
    }

    Context 'When A record has no PTR' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord `
                -MockWith { @($script:mockARecordMismatch) } `
                -ParameterFilter { $RRType -eq 'A' } `
                -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord `
                -MockWith { @() } `
                -ParameterFilter { $RRType -eq 'PTR' } `
                -ModuleName $script:moduleName
        }

        It 'Should return no results' {
            $result = Get-PSGDnsForwardReverseMismatch
            $result | Should -HaveCount 0
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should pass ComputerName to Get-DnsServerZone' {
            Get-PSGDnsForwardReverseMismatch -ComputerName 'dc01.contoso.com'
            Should -Invoke -CommandName Get-DnsServerZone `
                -ParameterFilter { $ComputerName -eq 'dc01.contoso.com' } `
                -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDnsForwardReverseMismatch -ComputerName 'dc01.contoso.com'
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
            Get-PSGDnsForwardReverseMismatch -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDnsForwardReverseMismatch -ComputerName 'dc01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DnsServerZone -MockWith { $script:mockAllZones } -ModuleName $script:moduleName
            Mock -CommandName Get-DnsServerResourceRecord -MockWith { @() } -ModuleName $script:moduleName
        }

        It 'Should call Get-DnsServerZone once per server' {
            'dc01', 'dc02' | Get-PSGDnsForwardReverseMismatch
            Should -Invoke -CommandName Get-DnsServerZone -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }
}
