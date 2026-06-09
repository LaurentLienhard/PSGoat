
function Sync-ZephyrToGPOFilteringSDDL {
    [CmdletBinding()]
    param (
        [String]$BaseApiUrl   = "http://caw1tzephyr01.fmlogistic.fr:8000/computers",
        [String]$TargetGPOName = "ALL - WKS - CatoClient-Install",
        [Int]$TargetStatus     = 1 # Filtrage ciblé sur le statut 1 (Planed / Init)
    )

    try {
        # 1. Récupération de la liste des machines à l'étape 2
        $listUrl = "$BaseApiUrl/list/2"
        Write-Host "Appel de l'API Zephyr (Liste globale)..." -ForegroundColor Cyan
        $computersList = Invoke-RestMethod -Uri $listUrl -Method Get -TimeoutSec 10 -ErrorAction Stop

        if (-not $computersList) {
            Write-Warning "Aucun ordinateur trouvé dans l'API globale."
            return
        }

        # 2. Récupération de la GPO via ADSI
        $gpoSearcher = [ADSISearcher]"(&(objectClass=groupPolicyContainer)(displayName=$TargetGPOName))"
        $gpoSearchResult = $gpoSearcher.FindOne()

        if (-not $gpoSearchResult) {
            Write-Error "Impossible de trouver la GPO nommée '$TargetGPOName' dans Active Directory."
            return
        }

        $gpoEntry = $gpoSearchResult.GetDirectoryEntry()
        Write-Host "GPO trouvée : $($gpoEntry.distinguishedName)" -ForegroundColor Green

        # Récupération du descripteur de sécurité de la GPO UNE SEULE FOIS au début
        $gpoSecurityDescriptor = $gpoEntry.ObjectSecurity
        $sddlEnCours = $gpoSecurityDescriptor.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)

        # Constantes des GUIDs GPO requis pour l'affichage graphique GPMC
        $gpoApplyGuidString = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $gpoReadGuidString  = "e47a4747-e549-11d1-bc91-00a4ec21a286"

        $matchCount = 0
        Write-Host "Analyse séquentielle des $($computersList.Count) postes pour le statut $TargetStatus..." -ForegroundColor Cyan

        foreach ($pcName in $computersList) {
            try {
                # 3. Interrogation fine de l'API pour valider le statut du PC
                $details = Invoke-RestMethod -Uri "$BaseApiUrl/$pcName" -Method Get -TimeoutSec 3 -ErrorAction Stop

                # Vérification stricte du step_2_status
                if ($details.step_2_status -ne $TargetStatus) {
                    continue # Ignore le PC s'il n'est pas au statut 1
                }

                # 4. Recherche de l'ordinateur dans l'AD
                $computerSearcher = [ADSISearcher]"(&(objectClass=computer)(sAMAccountName=$pcName$))"
                $computerResult = $computerSearcher.FindOne()

                if (-not $computerResult) {
                    Write-Warning "Ordinateur en statut $TargetStatus mais introuvable dans l'AD : $pcName"
                    continue
                }

                $computerEntry = $computerResult.GetDirectoryEntry()
                $computerSid = New-Object System.Security.Principal.SecurityIdentifier($computerEntry.Properties.objectSid[0], 0)
                $sidString = $computerSid.Value

                Write-Host "-> Préparation de $pcName ($sidString) [Statut $TargetStatus]" -ForegroundColor Yellow

                # Purge de toute ancienne règle SDDL liée à ce SID pour éviter les doublons
                if ($sddlEnCours -match "\([^)]+$sidString\)") {
                    $sddlEnCours = $sddlEnCours -replace "\([^)]+$sidString\)", ""
                }

                # Construction des 3 chaînes ACE SDDL
                $aceGenericExecuteSddl = "(A;;GX;;;$sidString)"
                $aceApplySddl          = "(OA;;CR;;$gpoApplyGuidString;$sidString)"
                $aceReadSddl           = "(OA;;RP;;$gpoReadGuidString;$sidString)"

                # Injection des droits dans la chaîne SDDL en mémoire
                if ($sddlEnCours -match "D:") {
                    $sddlEnCours = $sddlEnCours + $aceGenericExecuteSddl + $aceApplySddl + $aceReadSddl
                    $matchCount++
                }
            }
            catch {
                Write-Warning "Erreur lors du traitement réseau de l'ordinateur '$pcName' : $($_.Exception.Message)"
                continue
            }
        }

        # 5. Application finale des changements (Une seule transaction AD)
        if ($matchCount -gt 0) {
            Write-Host "`nÉcriture finale du descripteur de sécurité dans l'AD ($matchCount postes injectés)..." -ForegroundColor Cyan
            $gpoSecurityDescriptor.SetSecurityDescriptorSddlForm($sddlEnCours)
            $gpoEntry.ObjectSecurity = $gpoSecurityDescriptor
            $gpoEntry.CommitChanges()
            Write-Host "[SUCCÈS] Synchronisation SDDL réussie. Les postes sont visibles dans le filtrage de sécurité." -ForegroundColor Green
        } else {
            Write-Host "`nAucun ordinateur trouvé avec le statut $TargetStatus. Aucune modification AD requise." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Erreur critique globale : $($_.Exception.Message)"
    }
}

# Exécution
Sync-ZephyrToGPOFilteringSDDL -Verbose
