# 1. Récupération des entrées DNS dynamiques via ta fonction
$dynamicDnsEntries = Get-PSGDnsEntry -Filter Dynamic -ComputerName caw1pdc03 -Credential (Get-Secret AdmAccount) -Verbose -ZoneName fmlogistic.fr

# 2. Récupération de la liste des serveurs Windows dans l'AD
# On filtre sur 'OperatingSystem' pour cibler "Windows Server"
$adServers = Get-ADComputer -Filter "OperatingSystem -like '*Windows Server*'" -Properties OperatingSystem |
             Select-Object -ExpandProperty Name

# 3. Corrélation et filtrage
$results = foreach ($entry in $dynamicDnsEntries) {
    # On vérifie si le nom de l'entrée DNS (HostName) existe dans notre liste AD
    if ($adServers -contains $entry.HostName) {
        $entry | Select-Object *, @{Name="AD_Status"; Expression={"Found in AD"}},
                                  @{Name="CheckDate"; Expression={Get-Date}}
    }
}

# Affichage des résultats
$results | Out-GridView -Title "Serveurs Windows avec IP Dynamique"
