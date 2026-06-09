BeforeAll {
    $script:functionPath = "$PSScriptRoot/../../../source/Private/Remove-GPOComputerAce.ps1"
    . $script:functionPath
}

Describe "Remove-GPOComputerAce" {
    BeforeAll {
        $script:applyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $script:readGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"
        $script:sid1      = "S-1-5-21-1234567890-987654321-111111111-1001"
        $script:sid2      = "S-1-5-21-1234567890-987654321-111111111-1002"
        $script:sddlBase  = "O:DAG:DAD:P"
    }

    Context "Quand le SDDL ne contient aucune ACE ordinateur" {
        It "Retourne le SDDL inchangé" {
            $sddl = "$script:sddlBase(A;;LCRPLORC;;;AU)"
            $result = Remove-GPOComputerAce -Sddl $sddl
            $result | Should -Be $sddl
        }
    }

    Context "Quand le SDDL contient un ordinateur avec les 3 ACE" {
        BeforeAll {
            $aceGX = "(A;;GX;;;$script:sid1)"
            $aceCR = "(OA;;CR;;$script:applyGuid;$script:sid1)"
            $aceRP = "(OA;;RP;;$script:readGuid;$script:sid1)"
            $script:sddlAvecOrdinateur = "$script:sddlBase(A;;LCRPLORC;;;AU)$aceGX$aceCR$aceRP"
        }

        It "Supprime les 3 ACE liées au SID de l'ordinateur" {
            $result = Remove-GPOComputerAce -Sddl $script:sddlAvecOrdinateur
            $result | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
        }

        It "Préserve les ACE non liées aux ordinateurs" {
            $result = Remove-GPOComputerAce -Sddl $script:sddlAvecOrdinateur
            $result | Should -Match "\(A;;LCRPLORC;;;AU\)"
        }
    }

    Context "Quand le SDDL contient plusieurs ordinateurs" {
        BeforeAll {
            $aceGX1 = "(A;;GX;;;$script:sid1)"
            $aceCR1 = "(OA;;CR;;$script:applyGuid;$script:sid1)"
            $aceRP1 = "(OA;;RP;;$script:readGuid;$script:sid1)"
            $aceGX2 = "(A;;GX;;;$script:sid2)"
            $aceCR2 = "(OA;;CR;;$script:applyGuid;$script:sid2)"
            $aceRP2 = "(OA;;RP;;$script:readGuid;$script:sid2)"
            $script:sddlDeuxOrdinateurs = "$script:sddlBase$aceGX1$aceCR1$aceRP1$aceGX2$aceCR2$aceRP2"
        }

        It "Supprime les ACE des deux ordinateurs" {
            $result = Remove-GPOComputerAce -Sddl $script:sddlDeuxOrdinateurs
            $result | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid1)
            $result | Should -Not -Match [System.Text.RegularExpressions.Regex]::Escape($script:sid2)
        }

        It "Retourne une chaîne contenant uniquement le préfixe SDDL" {
            $result = Remove-GPOComputerAce -Sddl $script:sddlDeuxOrdinateurs
            $result | Should -Be $script:sddlBase
        }
    }

    Context "Quand le SDDL contient un SID bien connu (non-domaine)" {
        It "Ne supprime pas les ACE des SIDs intégrés (ex: S-1-5-11 = Authenticated Users)" {
            $sddl = "$script:sddlBase(A;;LCRPLORC;;;S-1-5-11)"
            $result = Remove-GPOComputerAce -Sddl $sddl
            $result | Should -Be $sddl
        }
    }
}
