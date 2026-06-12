class PSGGpo
{
    [string]$Name
    [string]$Id
    [string]$DistinguishedName
    [string]$SysvolPath
    [PSGGpoStatus]$Status
    [string]$Sddl

    hidden [object]$_entry
    hidden [object]$_securityDescriptor

    PSGGpo() {}

    PSGGpo([string]$Name, [string]$Id, [string]$DistinguishedName, [string]$SysvolPath, [PSGGpoStatus]$Status, [object]$Entry)
    {
        $this.Name                 = $Name
        $this.Id                   = $Id
        $this.DistinguishedName    = $DistinguishedName
        $this.SysvolPath           = $SysvolPath
        $this.Status               = $Status
        $this._entry               = $Entry
        $this._securityDescriptor  = $Entry.ObjectSecurity
        $this.Sddl = $this._securityDescriptor.GetSecurityDescriptorSddlForm(
            [System.Security.AccessControl.AccessControlSections]::Access
        )
    }

    # Finds and returns a PSGGpo from Active Directory by display name. Returns $null if not found.
    static [PSGGpo] Get([string]$DisplayName)
    {
        $searcher = [ADSISearcher]"(&(objectClass=groupPolicyContainer)(displayName=$DisplayName))"
        $result   = $searcher.FindOne()

        if (-not $result)
        {
            return $null
        }

        $entry      = $result.GetDirectoryEntry()
        $dn         = [string]$entry.distinguishedName
        $gpoId      = ($dn -split ',')[0] -replace '^CN=', ''
        $gpoSysvolPath = [string]$entry.Properties['gPCFileSysPath'].Value
        $gpoStatus = [PSGGpoStatus][int]$entry.Properties['flags'].Value

        return [PSGGpo]::new($DisplayName, $gpoId, $dn, $gpoSysvolPath, $gpoStatus, $entry)
    }

    # Returns the distinguished names of all OUs and containers where this GPO is linked.
    [string[]] GetLinks()
    {
        $searcher             = [ADSISearcher]"(gPLink=*$($this.Id)*)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $results              = $searcher.FindAll()

        return @(
            $results |
                ForEach-Object -Process { [string]$_.Properties['distinguishedName'][0] }
        )
    }

    # Links this GPO to the specified OU or container. No-op if already linked.
    [void] AddLink([string]$OuDistinguishedName)
    {
        $ouEntry      = [ADSI]"LDAP://$OuDistinguishedName"
        $currentLinks = [string]$ouEntry.Properties['gPLink'].Value

        if ($currentLinks -match [System.Text.RegularExpressions.Regex]::Escape($this.Id))
        {
            return
        }

        $ouEntry.Properties['gPLink'].Value = $currentLinks + "[LDAP://$($this.DistinguishedName);0]"
        $ouEntry.CommitChanges()
    }

    # Removes the link of this GPO from the specified OU or container.
    [void] RemoveLink([string]$OuDistinguishedName)
    {
        $ouEntry      = [ADSI]"LDAP://$OuDistinguishedName"
        $currentLinks = [string]$ouEntry.Properties['gPLink'].Value
        $escaped      = [System.Text.RegularExpressions.Regex]::Escape($this.Id)
        $newLinks     = $currentLinks -replace "\[LDAP://[^\]]*$escaped[^\]]*;\d\]", ""

        $ouEntry.Properties['gPLink'].Value = $newLinks
        $ouEntry.CommitChanges()
    }

    # Enables all settings of this GPO.
    [void] Enable()
    {
        $this._entry.Properties['flags'].Value = [int][PSGGpoStatus]::AllEnabled
        $this._entry.CommitChanges()
        $this.Status = [PSGGpoStatus]::AllEnabled
    }

    # Disables all settings of this GPO.
    [void] Disable()
    {
        $this._entry.Properties['flags'].Value = [int][PSGGpoStatus]::AllDisabled
        $this._entry.CommitChanges()
        $this.Status = [PSGGpoStatus]::AllDisabled
    }

    # Disables only the User Configuration part of this GPO.
    [void] DisableUserSettings()
    {
        $newValue    = [int]$this.Status -bor 1
        $this._entry.Properties['flags'].Value = $newValue
        $this._entry.CommitChanges()
        $this.Status = [PSGGpoStatus]$newValue
    }

    # Re-enables the User Configuration part of this GPO.
    [void] EnableUserSettings()
    {
        $newValue    = [int]$this.Status -band (-bnot 1)
        $this._entry.Properties['flags'].Value = $newValue
        $this._entry.CommitChanges()
        $this.Status = [PSGGpoStatus]$newValue
    }

    # Disables only the Computer Configuration part of this GPO.
    [void] DisableComputerSettings()
    {
        $newValue    = [int]$this.Status -bor 2
        $this._entry.Properties['flags'].Value = $newValue
        $this._entry.CommitChanges()
        $this.Status = [PSGGpoStatus]$newValue
    }

    # Re-enables the Computer Configuration part of this GPO.
    [void] EnableComputerSettings()
    {
        $newValue    = [int]$this.Status -band (-bnot 2)
        $this._entry.Properties['flags'].Value = $newValue
        $this._entry.CommitChanges()
        $this.Status = [PSGGpoStatus]$newValue
    }

    # Removes all domain computer ACEs from the security filtering SDDL (in memory, call Save() to persist).
    [void] ClearComputerAces()
    {
        $applyGuid        = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $domainSidSegment = "S-1-5-21-\d+-\d+-\d+-\d+"
        $applyAcePattern  = "\(OA;;CR;;$applyGuid;($domainSidSegment)\)"

        $aceMatches   = [System.Text.RegularExpressions.Regex]::Matches($this.Sddl, $applyAcePattern)
        $sidsToRemove = $aceMatches |
            ForEach-Object -Process { $_.Groups[1].Value } |
            Select-Object -Unique

        foreach ($sid in $sidsToRemove)
        {
            $escaped   = [System.Text.RegularExpressions.Regex]::Escape($sid)
            $this.Sddl = $this.Sddl -replace "\([^)]+$escaped\)", ""
        }
    }

    # Grants a computer SID the right to apply this GPO by injecting three ACEs (GX + Apply GUID + Read GUID).
    # Any existing ACEs for that SID are replaced to avoid duplicates.
    [void] GrantComputerApplyRight([string]$SidString)
    {
        $applyGuid = "edacfd8f-ffb3-11d1-b41d-00a4ec21a286"
        $readGuid  = "e47a4747-e549-11d1-bc91-00a4ec21a286"

        $escaped   = [System.Text.RegularExpressions.Regex]::Escape($SidString)
        $this.Sddl = $this.Sddl -replace "\([^)]+$escaped\)", ""

        $this.Sddl += "(A;;GX;;;$SidString)"
        $this.Sddl += "(OA;;CR;;$applyGuid;$SidString)"
        $this.Sddl += "(OA;;RP;;$readGuid;$SidString)"
    }

    # Commits the current SDDL to Active Directory in a single transaction.
    [void] Save()
    {
        $this._securityDescriptor.SetSecurityDescriptorSddlForm($this.Sddl)
        $this._entry.ObjectSecurity = $this._securityDescriptor
        $this._entry.CommitChanges()
    }

    [string] ToString()
    {
        return '[PSGGpo] {0} ({1}) -- Status: {2} -- DN: {3}' -f $this.Name, $this.Id, $this.Status, $this.DistinguishedName
    }
}
