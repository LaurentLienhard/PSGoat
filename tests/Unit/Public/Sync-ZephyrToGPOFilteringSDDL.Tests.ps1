BeforeAll {
    . "$PSScriptRoot/../../../source/Private/Remove-GPOComputerAce.ps1"
    . "$PSScriptRoot/../../../source/Public/Sync-ZephyrToGPOFilteringSDDL.ps1"
}

Describe "Sync-ZephyrToGPOFilteringSDDL" {
    Context "Paramètre MaxComputers" {
        It "Est obligatoire" {
            { Sync-ZephyrToGPOFilteringSDDL } | Should -Throw
        }

        It "Rejette la valeur 0" {
            { Sync-ZephyrToGPOFilteringSDDL -MaxComputers 0 } | Should -Throw
        }

        It "Accepte les valeurs positives" {
            { Sync-ZephyrToGPOFilteringSDDL -MaxComputers 50 -WhatIf } | Should -Not -Throw
        }
    }

    Context "Quand la GPO est introuvable dans Active Directory" {
        BeforeAll {
            Mock -CommandName Invoke-RestMethod
            Mock -CommandName Write-Error

            $script:gpoSearcherMock = [PSCustomObject]@{}
            Add-Member -InputObject $script:gpoSearcherMock -MemberType ScriptMethod -Name FindOne -Value { return $null }

            Mock -CommandName ADSISearcher -MockWith { return $script:gpoSearcherMock }
        }

        It "Appelle Write-Error" {
            InModuleScope -ScriptBlock {
                Sync-ZephyrToGPOFilteringSDDL -MaxComputers 10
            }
            Should -Invoke -CommandName Write-Error -Times 1
        }
    }

    Context "Quand l'API Zephyr ne retourne aucun ordinateur" {
        BeforeAll {
            $script:applyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
            $script:readGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"

            Mock -CommandName Invoke-RestMethod -MockWith { return $null }
            Mock -CommandName Write-Warning

            $script:sddlObj = [PSCustomObject]@{ Sddl = "O:DAG:DAD:P" }
            Add-Member -InputObject $script:sddlObj -MemberType ScriptMethod -Name GetSecurityDescriptorSddlForm -Value {
                return $script:sddlObj.Sddl
            }

            $script:gpoEntryMock = [PSCustomObject]@{ distinguishedName = "CN=TestGPO,CN=Policies,CN=System,DC=test,DC=local"; ObjectSecurity = $script:sddlObj }

            $script:gpoSearchResultMock = [PSCustomObject]@{}
            Add-Member -InputObject $script:gpoSearchResultMock -MemberType ScriptMethod -Name GetDirectoryEntry -Value {
                return $script:gpoEntryMock
            }

            $script:gpoSearcherMock = [PSCustomObject]@{}
            Add-Member -InputObject $script:gpoSearcherMock -MemberType ScriptMethod -Name FindOne -Value {
                return $script:gpoSearchResultMock
            }
        }

        It "Émet un avertissement et s'arrête sans modifier l'AD" {
            Should -Invoke -CommandName Write-Warning -Times 1 -ParameterFilter {
                $Message -match "Aucun ordinateur"
            }
        }
    }

    Context "Limite MaxComputers respectée" {
        It "N'ajoute pas plus d'ordinateurs que la limite" {
            $applyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
            $readGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"

            $injectedSids = [System.Collections.Generic.List[String]]::new()

            $sddlState = [PSCustomObject]@{ Value = "O:DAG:DAD:P" }

            $sdDescriptor = [PSCustomObject]@{}
            Add-Member -InputObject $sdDescriptor -MemberType ScriptMethod -Name GetSecurityDescriptorSddlForm -Value {
                return $sddlState.Value
            }
            Add-Member -InputObject $sdDescriptor -MemberType ScriptMethod -Name SetSecurityDescriptorSddlForm -Value {
                param([String]$newSddl)
                $sddlState.Value = $newSddl
            }

            $gpoEntry = [PSCustomObject]@{
                distinguishedName = "CN=GPO,DC=test,DC=local"
                ObjectSecurity    = $sdDescriptor
            }
            Add-Member -InputObject $gpoEntry -MemberType ScriptMethod -Name CommitChanges -Value {}

            $gpoResult = [PSCustomObject]@{}
            Add-Member -InputObject $gpoResult -MemberType ScriptMethod -Name GetDirectoryEntry -Value { return $gpoEntry }

            $gpoSearcher = [PSCustomObject]@{}
            Add-Member -InputObject $gpoSearcher -MemberType ScriptMethod -Name FindOne -Value { return $gpoResult }

            Mock -CommandName ADSISearcher -MockWith { return $gpoSearcher }

            Mock -CommandName Invoke-RestMethod -ParameterFilter { $Uri -match "/list/" } -MockWith {
                return @("PC01", "PC02", "PC03", "PC04", "PC05")
            }

            $sidCounter = 0
            Mock -CommandName Invoke-RestMethod -ParameterFilter { $Uri -notmatch "/list/" } -MockWith {
                return [PSCustomObject]@{ step_2_status = 1 }
            }

            $fakeSid = [PSCustomObject]@{ Value = "" }
            Mock -CommandName New-Object -MockWith {
                $script:sidCounter++
                $fakeSid.Value = "S-1-5-21-111-222-333-100$script:sidCounter"
                return $fakeSid
            } -ParameterFilter { $TypeName -eq "System.Security.Principal.SecurityIdentifier" }

            $fakeComputerEntry = [PSCustomObject]@{
                Properties = @{ objectSid = @([byte[]]@(1, 5, 0, 0, 0, 0, 0, 5, 21, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0)) }
            }
            $fakeComputerResult = [PSCustomObject]@{}
            Add-Member -InputObject $fakeComputerResult -MemberType ScriptMethod -Name GetDirectoryEntry -Value {
                return $fakeComputerEntry
            }

            $computerSearcher = [PSCustomObject]@{}
            Add-Member -InputObject $computerSearcher -MemberType ScriptMethod -Name FindOne -Value {
                return $fakeComputerResult
            }

            Mock -CommandName ADSISearcher -MockWith { return $computerSearcher } -ParameterFilter {
                $args[0] -match "objectClass=computer"
            }

            Sync-ZephyrToGPOFilteringSDDL -MaxComputers 3 -WhatIf

            $applyAceCount = ([System.Text.RegularExpressions.Regex]::Matches(
                $sddlState.Value,
                "\(OA;;CR;;$applyGuid;"
            )).Count

            $applyAceCount | Should -BeLessOrEqual 3
        }
    }
}
