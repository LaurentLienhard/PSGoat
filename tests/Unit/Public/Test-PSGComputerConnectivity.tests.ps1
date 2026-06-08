BeforeAll {
    $script:moduleName = 'PSGoat'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Test-PSGComputerConnectivity' {

    Context 'When ping succeeds' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { $true } -ModuleName $script:moduleName
        }

        It 'Should return an object with the correct type name' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.GetType().Name | Should -Be 'PSGComputer'
        }

        It 'Should set IsUp to true' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.IsUp | Should -BeTrue
        }

        It 'Should set DetectionMethod to Ping' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.DetectionMethod | Should -Be 'Ping'
        }

        It 'Should set PingSuccess to true' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.PingSuccess | Should -BeTrue
        }

        It 'Should not probe any port' {
            Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            Should -Invoke -CommandName Test-Connection -ParameterFilter { $null -ne $TcpPort } `
                -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }

        It 'Should set all port flags to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.Port445Open  | Should -BeFalse
            $result.Port3389Open | Should -BeFalse
            $result.Port5985Open | Should -BeFalse
        }
    }

    Context 'When ping fails and all ports respond' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { $false } -ModuleName $script:moduleName
            Mock -CommandName Test-Connection -ParameterFilter { $null -ne $TcpPort } `
                -MockWith { $true } -ModuleName $script:moduleName
        }

        It 'Should set IsUp to true' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.IsUp | Should -BeTrue
        }

        It 'Should set DetectionMethod to Port' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.DetectionMethod | Should -Be 'Port'
        }

        It 'Should set PingSuccess to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.PingSuccess | Should -BeFalse
        }

        It 'Should probe exactly three ports' {
            Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            Should -Invoke -CommandName Test-Connection -ParameterFilter { $null -ne $TcpPort } `
                -Exactly -Times 3 -Scope It -ModuleName $script:moduleName
        }

        It 'Should set all port flags to true' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.Port445Open  | Should -BeTrue
            $result.Port3389Open | Should -BeTrue
            $result.Port5985Open | Should -BeTrue
        }
    }

    Context 'When ping fails and only port 3389 responds' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { $false } -ModuleName $script:moduleName
            Mock -CommandName Test-Connection -ParameterFilter { $TcpPort -eq 3389 } `
                -MockWith { $true } -ModuleName $script:moduleName
        }

        It 'Should set IsUp to true' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.IsUp | Should -BeTrue
        }

        It 'Should set DetectionMethod to Port' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.DetectionMethod | Should -Be 'Port'
        }

        It 'Should set Port445Open to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.Port445Open | Should -BeFalse
        }

        It 'Should set Port3389Open to true' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.Port3389Open | Should -BeTrue
        }

        It 'Should set Port5985Open to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.Port5985Open | Should -BeFalse
        }
    }

    Context 'When ping and all ports fail' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { $false } -ModuleName $script:moduleName
        }

        It 'Should set IsUp to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.IsUp | Should -BeFalse
        }

        It 'Should set DetectionMethod to Unreachable' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.DetectionMethod | Should -Be 'Unreachable'
        }

        It 'Should set PingSuccess to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.PingSuccess | Should -BeFalse
        }

        It 'Should set all port flags to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.Port445Open  | Should -BeFalse
            $result.Port3389Open | Should -BeFalse
            $result.Port5985Open | Should -BeFalse
        }
    }

    Context 'When Test-Connection throws an exception on ping' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { throw 'Host not found' } -ModuleName $script:moduleName
        }

        It 'Should fall through to port probing' {
            # Exception in ping is swallowed; port probes also throw, so machine is Unreachable.
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.PingSuccess | Should -BeFalse
        }

        It 'Should set DetectionMethod to Unreachable' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.DetectionMethod | Should -Be 'Unreachable'
        }
    }

    Context 'When piping multiple computer names' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { $true } -ModuleName $script:moduleName
        }

        It 'Should return one result per computer' {
            $results = 'server01.contoso.com', 'server02.contoso.com' | Test-PSGComputerConnectivity
            $results | Should -HaveCount 2
        }

        It 'Should populate ComputerName on each result' {
            $results = 'server01.contoso.com', 'server02.contoso.com' | Test-PSGComputerConnectivity
            $results[0].ComputerName | Should -Be 'server01.contoso.com'
            $results[1].ComputerName | Should -Be 'server02.contoso.com'
        }
    }
}
