BeforeAll {
    . "$PSScriptRoot/../../../source/Classes/0.PSGGpoStatus.ps1"
    . "$PSScriptRoot/../../../source/Classes/1.PSGGpo.ps1"

    function New-MockEntry
    {
        param([int]$Flags = 0)

        $props = @{
            flags           = [PSCustomObject]@{ Value = $Flags }
            gPCFileSysPath  = [PSCustomObject]@{ Value = "\\domain\sysvol\Policies\{TEST-GUID}" }
        }

        $secDescriptor = [PSCustomObject]@{}
        Add-Member -InputObject $secDescriptor -MemberType ScriptMethod -Name GetSecurityDescriptorSddlForm -Value {
            return "O:DAG:DAD:P"
        }
        Add-Member -InputObject $secDescriptor -MemberType ScriptMethod -Name SetSecurityDescriptorSddlForm -Value {
            param([string]$s)
        }

        $entry = [PSCustomObject]@{
            distinguishedName = "CN={TEST-GUID},CN=Policies,CN=System,DC=test,DC=local"
            ObjectSecurity    = $secDescriptor
            Properties        = $props
        }
        Add-Member -InputObject $entry -MemberType ScriptMethod -Name CommitChanges -Value {}

        return $entry
    }

    function New-MockGpo
    {
        param([PSGGpoStatus]$Status = [PSGGpoStatus]::AllEnabled)

        $entry = New-MockEntry -Flags ([int]$Status)
        $gpo   = [PSGGpo]::new(
            "TestGPO",
            "{TEST-GUID}",
            "CN={TEST-GUID},CN=Policies,CN=System,DC=test,DC=local",
            "\\domain\sysvol\Policies\{TEST-GUID}",
            $Status,
            $entry
        )
        return $gpo
    }
}

Describe "PSGGpo" {
    BeforeAll {
        $script:applyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $script:readGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"
        $script:sid1      = "S-1-5-21-1234567890-987654321-111111111-1001"
        $script:sid2      = "S-1-5-21-1234567890-987654321-111111111-1002"
        $script:sddlBase  = "O:DAG:DAD:P"
    }

    Context "Constructeur par défaut" {
        It "Crée une instance avec des propriétés vides" {
            $gpo = [PSGGpo]::new()
            $gpo.Name              | Should -BeNullOrEmpty
            $gpo.Id                | Should -BeNullOrEmpty
            $gpo.DistinguishedName | Should -BeNullOrEmpty
            $gpo.SysvolPath        | Should -BeNullOrEmpty
            $gpo.Status            | Should -Be ([PSGGpoStatus]::AllEnabled)
        }
    }

    Context "ToString()" {
        It "Retourne le nom, l'Id, le statut et le DN" {
            $gpo = New-MockGpo
            $gpo.ToString() | Should -Match "TestGPO"
            $gpo.ToString() | Should -Match "\{TEST-GUID\}"
            $gpo.ToString() | Should -Match "AllEnabled"
            $gpo.ToString() | Should -Match "DN:"
        }
    }

    Context "Enable() / Disable()" {
        It "Enable() positionne Status à AllEnabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllDisabled)
            $gpo.Enable()
            $gpo.Status | Should -Be ([PSGGpoStatus]::AllEnabled)
        }

        It "Disable() positionne Status à AllDisabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllEnabled)
            $gpo.Disable()
            $gpo.Status | Should -Be ([PSGGpoStatus]::AllDisabled)
        }
    }

    Context "DisableUserSettings() / EnableUserSettings()" {
        It "DisableUserSettings() passe de AllEnabled à UserSettingsDisabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllEnabled)
            $gpo.DisableUserSettings()
            $gpo.Status | Should -Be ([PSGGpoStatus]::UserSettingsDisabled)
        }

        It "EnableUserSettings() passe de AllDisabled à ComputerSettingsDisabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllDisabled)
            $gpo.EnableUserSettings()
            $gpo.Status | Should -Be ([PSGGpoStatus]::ComputerSettingsDisabled)
        }

        It "EnableUserSettings() sur GPO déjà active laisse Status à AllEnabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllEnabled)
            $gpo.EnableUserSettings()
            $gpo.Status | Should -Be ([PSGGpoStatus]::AllEnabled)
        }
    }

    Context "DisableComputerSettings() / EnableComputerSettings()" {
        It "DisableComputerSettings() passe de AllEnabled à ComputerSettingsDisabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllEnabled)
            $gpo.DisableComputerSettings()
            $gpo.Status | Should -Be ([PSGGpoStatus]::ComputerSettingsDisabled)
        }

        It "EnableComputerSettings() passe de AllDisabled à UserSettingsDisabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllDisabled)
            $gpo.EnableComputerSettings()
            $gpo.Status | Should -Be ([PSGGpoStatus]::UserSettingsDisabled)
        }

        It "EnableComputerSettings() sur GPO déjà active laisse Status à AllEnabled" {
            $gpo = New-MockGpo -Status ([PSGGpoStatus]::AllEnabled)
            $gpo.EnableComputerSettings()
            $gpo.Status | Should -Be ([PSGGpoStatus]::AllEnabled)
        }
    }

    Context "AddLink() / RemoveLink()" {
        BeforeEach {
            $script:ouProps = @{ gPLink = [PSCustomObject]@{ Value = "" } }
            $script:ouEntry = [PSCustomObject]@{ Properties = $script:ouProps }
            Add-Member -InputObject $script:ouEntry -MemberType ScriptMethod -Name CommitChanges -Value {}
        }

        It "AddLink() ajoute l'entrée dans gPLink si absente" {
            $gpo = New-MockGpo

            Mock -CommandName ADSI -MockWith { return $script:ouEntry }

            $gpo.AddLink("OU=TestOU,DC=test,DC=local")

            $script:ouEntry.Properties['gPLink'].Value | Should -Match [System.Text.RegularExpressions.Regex]::Escape($gpo.DistinguishedName)
        }

        It "AddLink() n'ajoute pas de doublon si déjà lié" {
            $gpo = New-MockGpo
            $script:ouEntry.Properties['gPLink'].Value = "[LDAP://$($gpo.DistinguishedName);0]"

            $gpo.AddLink("OU=TestOU,DC=test,DC=local")

            $count = ([regex]::Matches($script:ouEntry.Properties['gPLink'].Value, [regex]::Escape($gpo.Id))).Count
            $count | Should -Be 1
        }

        It "RemoveLink() retire l'entrée de gPLink" {
            $gpo = New-MockGpo
            $script:ouEntry.Properties['gPLink'].Value = "[LDAP://$($gpo.DistinguishedName);0]"

            $gpo.RemoveLink("OU=TestOU,DC=test,DC=local")

            $script:ouEntry.Properties['gPLink'].Value | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($gpo.Id)
        }

        It "RemoveLink() préserve les autres liens présents" {
            $gpo    = New-MockGpo
            $otherId = "{OTHER-GUID}"
            $script:ouEntry.Properties['gPLink'].Value = "[LDAP://CN=$otherId,CN=Policies,DC=test;0][LDAP://$($gpo.DistinguishedName);0]"

            $gpo.RemoveLink("OU=TestOU,DC=test,DC=local")

            $script:ouEntry.Properties['gPLink'].Value | Should -Match [System.Text.RegularExpressions.Regex]::Escape($otherId)
        }
    }

    Context "ClearComputerAces()" {
        It "Supprime les 3 ACE d'un ordinateur" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
        }

        It "Préserve les ACE non ordinateur" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(A;;LCRPLORC;;;S-1-5-11)" +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Match "\(A;;LCRPLORC;;;S-1-5-11\)"
        }

        It "Supprime plusieurs ordinateurs en une seule passe" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid2)"

            $gpo.ClearComputerAces()

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }
    }

    Context "GrantComputerApplyRight()" {
        It "Ajoute les 3 ACE pour un SID" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase

            $gpo.GrantComputerApplyRight($script:sid1)

            $gpo.Sddl | Should -Match "\(A;;GX;;;$([regex]::Escape($script:sid1))\)"
            $gpo.Sddl | Should -Match "\(OA;;CR;;$script:applyGuid;$([regex]::Escape($script:sid1))\)"
            $gpo.Sddl | Should -Match "\(OA;;RP;;$script:readGuid;$([regex]::Escape($script:sid1))\)"
        }

        It "Remplace les ACE existantes (pas de doublon)" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(A;;GX;;;$script:sid1)" +
                "(OA;;CR;;$script:applyGuid;$script:sid1)" +
                "(OA;;RP;;$script:readGuid;$script:sid1)"

            $gpo.GrantComputerApplyRight($script:sid1)

            $count = ([regex]::Matches($gpo.Sddl, "\(OA;;CR;;$script:applyGuid;$([regex]::Escape($script:sid1))\)")).Count
            $count | Should -Be 1
        }
    }

    Context "ClearComputerAces() puis GrantComputerApplyRight()" {
        It "Repart d'un filtrage propre et injecte uniquement le nouveau SID" {
            $gpo      = New-MockGpo
            $gpo.Sddl = $script:sddlBase +
                "(OA;;CR;;$script:applyGuid;$script:sid1)"

            $gpo.ClearComputerAces()
            $gpo.GrantComputerApplyRight($script:sid2)

            $gpo.Sddl | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
            $gpo.Sddl | Should -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }
    }
}
