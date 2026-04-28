BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSGDhcpScopeUtilization' {
    BeforeAll {
        $script:mockCredential = [PSCredential]::new(
            'contoso\admin',
            (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force)
        )

        $script:mockScopes = @(
            [PSCustomObject]@{ ScopeId = [System.Net.IPAddress]::Parse('192.168.1.0'); Name = 'LAN-Floor1'; State = 'Active' },
            [PSCustomObject]@{ ScopeId = [System.Net.IPAddress]::Parse('192.168.2.0'); Name = 'LAN-Floor2'; State = 'Active' }
        )

        $script:mockStats = @(
            [PSCustomObject]@{
                ScopeId  = [System.Net.IPAddress]::Parse('192.168.1.0')
                Free     = [uint32]20
                InUse    = [uint32]70
                Reserved = [uint32]10
            },
            [PSCustomObject]@{
                ScopeId  = [System.Net.IPAddress]::Parse('192.168.2.0')
                Free     = [uint32]200
                InUse    = [uint32]30
                Reserved = [uint32]5
            }
        )
    }

    Context 'When called without ScopeId filter' {
        BeforeAll {
            Mock -CommandName Get-DhcpServerv4Scope -MockWith { $script:mockScopes } -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4ScopeStatistics -MockWith { $script:mockStats } -ModuleName $script:moduleName
        }

        It 'Should return PSGDhcpScopeUtilization objects' {
            $result = Get-PSGDhcpScopeUtilization
            $result | ForEach-Object { $_ | Should -BeOfType 'PSGDhcpScopeUtilization' }
        }

        It 'Should return all scopes when no Threshold is set' {
            $result = Get-PSGDhcpScopeUtilization
            $result | Should -HaveCount 2
        }
    }

    Context 'When Threshold filters scopes' {
        BeforeAll {
            Mock -CommandName Get-DhcpServerv4Scope -MockWith { $script:mockScopes } -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4ScopeStatistics -MockWith { $script:mockStats } -ModuleName $script:moduleName
        }

        It 'Should return only scopes at or above the Threshold' {
            # LAN-Floor1: (70+10)/(70+10+20) = 80%, LAN-Floor2: (30+5)/(30+5+200) = ~14.8%
            $result = Get-PSGDhcpScopeUtilization -Threshold 80
            $result | Should -HaveCount 1
            $result[0].ScopeId | Should -Be '192.168.1.0'
        }

        It 'Should return no scopes when Threshold is above all scopes' {
            $result = Get-PSGDhcpScopeUtilization -Threshold 100
            $result | Should -HaveCount 0
        }
    }

    Context 'When ScopeId restricts results' {
        BeforeAll {
            Mock -CommandName Get-DhcpServerv4Scope -MockWith { $script:mockScopes } -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4ScopeStatistics -MockWith { $script:mockStats } -ModuleName $script:moduleName
        }

        It 'Should return only the requested scope' {
            $result = Get-PSGDhcpScopeUtilization -ScopeId '192.168.2.0'
            $result | Should -HaveCount 1
            $result[0].ScopeId | Should -Be '192.168.2.0'
        }
    }

    Context 'When computing utilization values' {
        BeforeAll {
            Mock -CommandName Get-DhcpServerv4Scope -MockWith { $script:mockScopes } -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4ScopeStatistics -MockWith { $script:mockStats } -ModuleName $script:moduleName
        }

        It 'Should compute TotalAddresses as InUse + Reserved + Free' {
            $result = Get-PSGDhcpScopeUtilization -ScopeId '192.168.1.0'
            $result[0].TotalAddresses | Should -Be 100
        }

        It 'Should set InUse from active leases' {
            $result = Get-PSGDhcpScopeUtilization -ScopeId '192.168.1.0'
            $result[0].InUse | Should -Be 70
        }

        It 'Should set Reserved from reserved addresses' {
            $result = Get-PSGDhcpScopeUtilization -ScopeId '192.168.1.0'
            $result[0].Reserved | Should -Be 10
        }

        It 'Should set Free from available addresses' {
            $result = Get-PSGDhcpScopeUtilization -ScopeId '192.168.1.0'
            $result[0].Free | Should -Be 20
        }

        It 'Should compute UtilizationPercent as (InUse + Reserved) / Total * 100' {
            $result = Get-PSGDhcpScopeUtilization -ScopeId '192.168.1.0'
            $result[0].UtilizationPercent | Should -Be 80.0
        }
    }

    Context 'When called with ComputerName only' {
        BeforeAll {
            Mock -CommandName Get-DhcpServerv4Scope -MockWith { $script:mockScopes } -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4ScopeStatistics -MockWith { $script:mockStats } -ModuleName $script:moduleName
        }

        It 'Should pass ComputerName to Get-DhcpServerv4Scope' {
            Get-PSGDhcpScopeUtilization -ComputerName 'dhcp01.contoso.com'
            Should -Invoke -CommandName Get-DhcpServerv4Scope `
                -ParameterFilter { $ComputerName -eq 'dhcp01.contoso.com' } `
                -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should not create a CimSession' {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Get-PSGDhcpScopeUtilization -ComputerName 'dhcp01.contoso.com'
            Should -Invoke -CommandName New-CimSession -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When called with Credential' {
        BeforeAll {
            Mock -CommandName New-CimSession -MockWith { [PSCustomObject]@{ Id = 1 } } -ModuleName $script:moduleName
            Mock -CommandName Remove-CimSession -MockWith {} -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4Scope -MockWith { $script:mockScopes } -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4ScopeStatistics -MockWith { $script:mockStats } -ModuleName $script:moduleName
        }

        It 'Should create a CimSession' {
            Get-PSGDhcpScopeUtilization -ComputerName 'dhcp01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName New-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }

        It 'Should remove the CimSession after execution' {
            Get-PSGDhcpScopeUtilization -ComputerName 'dhcp01.contoso.com' -Credential $script:mockCredential
            Should -Invoke -CommandName Remove-CimSession -Exactly -Times 1 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When piping ComputerName values' {
        BeforeAll {
            Mock -CommandName Get-DhcpServerv4Scope -MockWith { $script:mockScopes } -ModuleName $script:moduleName
            Mock -CommandName Get-DhcpServerv4ScopeStatistics -MockWith { $script:mockStats } -ModuleName $script:moduleName
        }

        It 'Should query each server independently' {
            'dhcp01', 'dhcp02' | Get-PSGDhcpScopeUtilization
            Should -Invoke -CommandName Get-DhcpServerv4Scope -Exactly -Times 2 -Scope It -ModuleName $script:moduleName
        }
    }
}
