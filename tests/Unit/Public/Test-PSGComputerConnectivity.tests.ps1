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

        It 'Should not probe any port' {
            Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            Should -Invoke -CommandName Test-Connection -ParameterFilter { $null -ne $TcpPort } `
                -Exactly -Times 0 -Scope It -ModuleName $script:moduleName
        }
    }

    Context 'When ping fails and a port responds' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { $false } -ModuleName $script:moduleName
            Mock -CommandName Test-Connection -ParameterFilter { $null -ne $TcpPort } `
                -MockWith { $true } -ModuleName $script:moduleName
        }

        It 'Should set IsUp to true' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.IsUp | Should -BeTrue
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
    }

    Context 'When Test-Connection throws an exception on ping' {
        BeforeAll {
            Mock -CommandName Test-Connection -MockWith { throw 'Host not found' } -ModuleName $script:moduleName
        }

        It 'Should set IsUp to false' {
            $result = Test-PSGComputerConnectivity -ComputerName 'server01.contoso.com'
            $result.IsUp | Should -BeFalse
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
