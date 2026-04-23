# PROXY HELPER
# used to determine if we have a semantic version
$semVerRegex = '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'

# try to convert the string into a version (semantic or system)
function Get-VersionType
{
    param ( $versionString )

    # if this can be converted into a version, simple return it
    $version = $versionString -as [version]
    if ( $version ) {
        return $version
    }

    # if the string matches a semantic version, return it, but also return a lossy conversion to system.version
    if ( $versionString -match $semVerRegex ) {
        return [pscustomobject]@{
            Major = [int]$Matches['major']
            Minor = [int]$Matches['Minor']
            Patch = [int]$Matches['patch']
            PreReleaseLabel = [string]$matches['prerelease']
            BuildLabel = [string]$matches['buildmetadata']
            originalString = $versionString
            Version = [version]("{0}.{1}.{2}" -f $Matches['major'],$Matches['minor'],$Matches['patch'])
            }
    }
    return $null
}

# this handles comparison of version with semantic versions
# this is all needed as semantic version exists only in core
function Compare-Version
{
    param ([string]$minimum, [string]$maximum)

    # this is done so we can use version to do our comparison
    $reference = Get-VersionType $minimum
    if ( ! $reference ) {
        throw "Cannot convert '$minimum' to version type"
    }
    $difference= Get-VersionType $maximum
    if ( ! $difference ) {
        throw "Cannot convert '$maximum' to version type"
    }

    if ( $reference -is [version] -and $difference -is [version] ) {
        if ( $reference -gt $difference ) {
            return 1
        }
        elseif ( $reference -lt $difference ) {
            return -1
        }
    }
    elseif ( $reference.version -is [version] -and $difference.version -is [version] ) {
        # two semantic versions
        if ( $reference.version -gt $difference.version ) {
            return 1
        }
        elseif ( $reference.version -lt $difference.version ) {
            return -1
        }
    }
    elseif ( $reference -is [version] -and $difference.version -is [version] ) {
        # one semantic version
        if ( $reference -gt $difference.version ) {
            return 1
        }
        elseif ( $reference -lt $difference.version ) {
            return -1
        }
        elseif ( $reference -eq $difference.version ) {
            # 1.0.0 is greater than 1.0.0-preview
            return 1
        }
    }
    elseif ( $reference.version -is [version] -and $difference -is [version] ) {
        # one semantic version
        if ( $reference.version -gt $difference ) {
            return 1
        }
        elseif ( $reference.version -lt $difference ) {
            return -1
        }
        elseif ( $reference.version -eq $difference ) {
            # 1.0.0 is greater than 1.0.0-preview
            return -1
        }
    }
    # Fall through

    if ( $reference.PreReleaseLabel -gt $difference.PreReleaseLabel ) {
        return 1
    }
    if ( $reference.PreReleaseLabel -lt $difference.PreReleaseLabel ) {
        return -1
    }
    # Fall through

    if ( $reference.BuildLabel -gt $difference.BuildLabel ) {
        return 1
    }
    if ( $reference.BuildLabel -lt $difference.BuildLabel ) {
        return -1
    }

    # Fall through, they are equivalent
    return 0
}

# Convert-VersionParamaters -RequiredVersion $RequiredVersion  -MinimumVersion $MinimumVersion -MaximumVersion $MaximumVersion
# this tries to figure out whether we have an improper use of version parameters
# such as RequiredVersion with MinimumVersion or MaximumVersion
function Convert-VersionParamaters
{
    param ( $RequiredVersion, $MinimumVersion, $MaximumVersion )

    # validate that required is not used with minimum or maximum version
    if ( $RequiredVersion -and ($MinimumVersion -or $MaximumVersion) ) {
        throw "RequiredVersion may not be used with MinimumVersion or MaximumVersion"
    }
    elseif ( ! $RequiredVersion -and ! $MinimumVersion -and ! $MaximumVersion ) {
        return $null
    }
    elseif ( $RequiredVersion -and ! $MinimumVersion -and ! $MaximumVersion ) {
        return "$RequiredVersion" }

    # now return the appropriate string
    if ( $MinimumVersion -and ! $MaximumVersion ) {
        return "[$MinimumVersion,)"
    }
    elseif ( ! $MinimumVersion -and $MaximumVersion ) {
        # no minimum version
        return "(,${MaximumVersion}]"
    }
    else {
        $result = Compare-Version $MinimumVersion $MaximumVersion
        if ( $result -ge 0 ) {
            throw "'$MaximumVersion' must be greater than '$MinimumVersion'"
        }

        return "[${MinimumVersion},${MaximumVersion}]"
    }
}

####
####
# Proxy functions
# This is where we map the parameters from v2 to v3
# In some cases we have the same parameters
# In some cases we have parameters which are not used in v3 - these we will silently ignore
#  the goal in ignoring them is to provide ways for automation to succeed without error rather than provide exact
#  semantic behavior between v2 and v3
# In some cases we have a way to map a v2 parameter into a v3 parameter
#  In those cases, we need to remove the parameter from the bound parameters and apply the value to the newly mapped parameter
# In some cases we have a completely new parameter which we need to set.
####
####
function Find-Command {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkId=733636')]
param(
    [Parameter(Position=0)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [ValidateNotNullOrEmpty()]
    [string]
    ${ModuleName},

    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [switch]
    ${AllVersions},

    [switch]
    ${AllowPrerelease},

    [ValidateNotNull()]
    [string[]]
    ${Tag},

    [ValidateNotNull()]
    [string]
    ${Filter},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( $PSBoundParameters['Name'] )               { $null = $PSBoundParameters.Remove('Name'); $PSBoundParameters['CommandName'] = $Name }
            if ( $PSBoundParameters['AllowPrerelease'] )     { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['ModuleName'] )          { $null = $PSBoundParameters.Remove('ModuleName') }
            if ( $PSBoundParameters['MinimumVersion'] )      { $null = $PSBoundParameters.Remove('MinimumVersion') }
            if ( $PSBoundParameters['MaximumVersion'] )      { $null = $PSBoundParameters.Remove('MaximumVersion') }
            if ( $PSBoundParameters['RequiredVersion'] )     { $null = $PSBoundParameters.Remove('RequiredVersion') }
            if ( $PSBoundParameters['AllVersions'] )         { $null = $PSBoundParameters.Remove('AllVersions') }
            if ( $PSBoundParameters['Tag'] )                 { $null = $PSBoundParameters.Remove('Tag') }
            if ( $PSBoundParameters['Filter'] )              { $null = $PSBoundParameters.Remove('Filter') }
            if ( $PSBoundParameters['Proxy'] )               { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )     { $null = $PSBoundParameters.Remove('ProxyCredential') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Find-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {

            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Find-Command
    .ForwardHelpCategory Function
    #>
}

function Find-DscResource {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkId=517196')]
param(
    [Parameter(Position=0)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [ValidateNotNullOrEmpty()]
    [string]
    ${ModuleName},

    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [switch]
    ${AllVersions},

    [switch]
    ${AllowPrerelease},

    [ValidateNotNull()]
    [string[]]
    ${Tag},

    [ValidateNotNull()]
    [string]
    ${Filter},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( $PSBoundParameters['Name'] )                { $null = $PSBoundParameters.Remove('Name'); $PSBoundParameters['DscResourceName'] = $Name }
            if ( $PSBoundParameters['AllowPrerelease'] )     { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['ModuleName'] )          { $null = $PSBoundParameters.Remove('ModuleName') }
            if ( $PSBoundParameters['MinimumVersion'] )      { $null = $PSBoundParameters.Remove('MinimumVersion') }
            if ( $PSBoundParameters['MaximumVersion'] )      { $null = $PSBoundParameters.Remove('MaximumVersion') }
            if ( $PSBoundParameters['RequiredVersion'] )     { $null = $PSBoundParameters.Remove('RequiredVersion') }
            if ( $PSBoundParameters['AllVersions'] )         { $null = $PSBoundParameters.Remove('AllVersions') }
            if ( $PSBoundParameters['Tag'] )                 { $null = $PSBoundParameters.Remove('Tag') }
            if ( $PSBoundParameters['Filter'] )              { $null = $PSBoundParameters.Remove('Filter') }
            if ( $PSBoundParameters['Proxy'] )               { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )     { $null = $PSBoundParameters.Remove('ProxyCredential') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Find-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }
            $steppablePipeline.End()
        }
        catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Find-DscResource
    .ForwardHelpCategory Function
    #>
}

function Find-Module {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkID=398574')]
param(
    [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [switch]
    ${AllVersions},

    [switch]
    ${IncludeDependencies},

    [ValidateNotNull()]
    [string]
    ${Filter},

    [ValidateNotNull()]
    [string[]]
    ${Tag},

    [ValidateSet('DscResource','Cmdlet','Function','RoleCapability')]
    [ValidateNotNull()]
    [string[]]
    ${Includes},

    [ValidateNotNull()]
    [string[]]
    ${DscResource},

    [ValidateNotNull()]
    [string[]]
    ${RoleCapability},

    [ValidateNotNull()]
    [string[]]
    ${Command},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [switch]
    ${AllowPrerelease})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # add new specifier
            $PSBoundParameters['Type'] = 'module'
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )      { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )      { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )     { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllVersions'] )         { $null = $PSBoundParameters.Remove('AllVersions'); $PSBoundParameters['Version'] = '*' }
            if ( $PSBoundParameters['AllowPrerelease'] )     { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Filter'] )              { $null = $PSBoundParameters.Remove('Filter') }
            if ( $PSBoundParameters['Includes'] )            { $null = $PSBoundParameters.Remove('Includes') }
            if ( $PSBoundParameters['DscResource'] )         { $null = $PSBoundParameters.Remove('DscResource'); }
            if ( $PSBoundParameters['RoleCapability'] )      { $null = $PSBoundParameters.Remove('RoleCapability'); }
            if ( $PSBoundParameters['Command'] )             { $null = $PSBoundParameters.Remove('Command'); }
            if ( $PSBoundParameters['Proxy'] )               { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )     { $null = $PSBoundParameters.Remove('ProxyCredential') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Find-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }
            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Find-Module
    .ForwardHelpCategory Function
    #>
}

function Find-RoleCapability {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkId=718029')]
param(
    [Parameter(Position=0)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [ValidateNotNullOrEmpty()]
    [string]
    ${ModuleName},

    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [switch]
    ${AllVersions},

    [switch]
    ${AllowPrerelease},

    [ValidateNotNull()]
    [string[]]
    ${Tag},

    [ValidateNotNull()]
    [string]
    ${Filter},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository})

    begin
    {
        # Find-RoleCability is no longer supported
        Write-Warning -Message "The cmdlet 'Find-RoleCapability' is deprecated."
    }
    <#
    .ForwardHelpTargetName Find-RoleCapability
    .ForwardHelpCategory Function
    #>
}

function Find-Script {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkId=619785')]
param(
    [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [switch]
    ${AllVersions},

    [switch]
    ${IncludeDependencies},

    [ValidateNotNull()]
    [string]
    ${Filter},

    [ValidateNotNull()]
    [string[]]
    ${Tag},

    [ValidateSet('Function','Workflow')]
    [ValidateNotNull()]
    [string[]]
    ${Includes},

    [ValidateNotNull()]
    [string[]]
    ${Command},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [switch]
    ${AllowPrerelease})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # add new specifier
            $PSBoundParameters['Type'] = 'script'
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )      { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )      { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )     { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllVersions'] )         { $null = $PSBoundParameters.Remove('AllVersions'); $PSBoundParameters['Version'] = '*' }
            if ( $PSBoundParameters['AllowPrerelease'] )     { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }

            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Filter'] )              { $null = $PSBoundParameters.Remove('Filter') }
            if ( $PSBoundParameters['Includes'] )            { $null = $PSBoundParameters.Remove('Includes') }
            if ( $PSBoundParameters['Command'] )             { $null = $PSBoundParameters.Remove('Command') }
            if ( $PSBoundParameters['Proxy'] )               { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )     { $null = $PSBoundParameters.Remove('ProxyCredential') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Find-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }
            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Find-Script
    .ForwardHelpCategory Function
    #>
}

function Get-InstalledModule {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkId=526863')]
param(
    [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [switch]
    ${AllVersions},

    [switch]
    ${AllowPrerelease})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )     { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )     { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )    { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllVersions'] )        { $null = $PSBoundParameters.Remove('AllVersions'); $PSBoundParameters['Version'] = '*' }
            if ( $PSBoundParameters['AllowPrerelease'] )    { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Get-InstalledPSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Get-InstalledModule
    .ForwardHelpCategory Function
    #>
}

function Get-InstalledScript {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkId=619790')]
param(
    [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [switch]
    ${AllowPrerelease})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )     { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )     { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )    { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllowPrerelease'] )    { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Get-InstalledPSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Get-InstalledScript
    .ForwardHelpCategory Function
    #>
}

function Get-PSRepository {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkID=517127')]
param(
    [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Get-PSResourceRepository', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Get-PSRepository
    .ForwardHelpCategory Function
    #>
}

function Install-Module {
[CmdletBinding(DefaultParameterSetName='NameParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkID=398573')]
param(
    [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ParameterSetName='InputObject', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [psobject[]]
    ${InputObject},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ParameterSetName='NameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [ValidateSet('CurrentUser','AllUsers')]
    [string]
    ${Scope},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [switch]
    ${AllowClobber},

    [switch]
    ${SkipPublisherCheck},

    [switch]
    ${Force},

    [Parameter(ParameterSetName='NameParameterSet')]
    [switch]
    ${AllowPrerelease},

    [switch]
    ${AcceptLicense},

    [switch]
    ${PassThru})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )     { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )     { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )    { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllowPrerelease'] )    { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            $PSBoundParameters['NoClobber'] = $true
            if ( $PSBoundParameters['AllowClobber'] )    { $null = $PSBoundParameters.Remove('AllowClobber'); $PSBoundParameters['NoClobber'] = (-not $AllowClobber) }
            $PSBoundParameters['AuthenticodeCheck'] = $true
            if ( $PSBoundParameters['SkipPublisherCheck'] ) { $null = $PSBoundParameters.Remove('SkipPublisherCheck'); $PSBoundParameters['AuthenticodeCheck'] = (-not $SkipPublisherCheck) }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Proxy'] )              { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )    { $null = $PSBoundParameters.Remove('ProxyCredential') }
            if ( $PSBoundParameters['Force'] )              { $null = $PSBoundParameters.Remove('Force') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Install-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Install-Module
    .ForwardHelpCategory Function
    #>
}

function Install-Script {
[CmdletBinding(DefaultParameterSetName='NameParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkId=619784')]
param(
    [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ParameterSetName='InputObject', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [psobject[]]
    ${InputObject},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ParameterSetName='NameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository},

    [ValidateSet('CurrentUser','AllUsers')]
    [string]
    ${Scope},

    [switch]
    ${NoPathUpdate},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [switch]
    ${Force},

    [Parameter(ParameterSetName='NameParameterSet')]
    [switch]
    ${AllowPrerelease},

    [switch]
    ${AcceptLicense},

    [switch]
    ${PassThru})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )   { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )   { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )  { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllowPrerelease'] )  { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['NoPathUpdate'] )     { $null = $PSBoundParameters.Remove('NoPathUpdate') }
            if ( $PSBoundParameters['Proxy'] )            { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )  { $null = $PSBoundParameters.Remove('ProxyCredential') }
            if ( $PSBoundParameters['Force'] )            { $null = $PSBoundParameters.Remove('Force') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Install-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Install-Script
    .ForwardHelpCategory Function
    #>
}

function New-ScriptFileInfo {
[CmdletBinding(PositionalBinding=$false, SupportsShouldProcess=$true, HelpUri='https://go.microsoft.com/fwlink/?LinkId=619792')]
param(
    [Parameter(Position=0, Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Path},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Version},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Author},

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Description},

    [ValidateNotNullOrEmpty()]
    [Guid]
    ${Guid},

    [ValidateNotNullOrEmpty()]
    [string]
    ${CompanyName},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Copyright},

    [ValidateNotNullOrEmpty()]
    [Object[]]
    ${RequiredModules},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${ExternalModuleDependencies},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${RequiredScripts},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${ExternalScriptDependencies},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Tags},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${ProjectUri},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${LicenseUri},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${IconUri},

    [string[]]
    ${ReleaseNotes},

    [ValidateNotNullOrEmpty()]
    [string]
    ${PrivateData},

    [switch]
    ${PassThru},

    [switch]
    ${Force})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( !$PSBoundParameters['Path'] ) {
                $RandomScriptPath = Join-Path -Path . -ChildPath "$(Get-Random).ps1";
                $PSBoundParameters['Path'] = $RandomScriptPath
            }
            # Translate from string[] to string
            if ( $PSBoundParameters['ReleaseNotes'] ) {
                $PSBoundParameters['ReleaseNotes'] = $PSBoundParameters['ReleaseNotes'] -join "; "
            }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['PassThru'] )      { $null = $PSBoundParameters.Remove('PassThru') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('New-PSScriptFileInfo', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Test-ScriptFileInfo
    .ForwardHelpCategory Function
    #>
}

function Publish-Module {
[CmdletBinding(DefaultParameterSetName='ModuleNameParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', PositionalBinding=$false, HelpUri='https://go.microsoft.com/fwlink/?LinkID=398575')]
param(
    [Parameter(ParameterSetName='ModuleNameParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Name},

    [Parameter(ParameterSetName='ModulePathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Path},

    [Parameter(ParameterSetName='ModuleNameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${RequiredVersion},

    [ValidateNotNullOrEmpty()]
    [string]
    ${NuGetApiKey},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Repository},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [version]
    ${FormatVersion},

    [string[]]
    ${ReleaseNotes},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Tags},

    [ValidateNotNullOrEmpty()]
    [uri]
    ${LicenseUri},

    [ValidateNotNullOrEmpty()]
    [uri]
    ${IconUri},

    [ValidateNotNullOrEmpty()]
    [uri]
    ${ProjectUri},

    [Parameter(ParameterSetName='ModuleNameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Exclude},

    [switch]
    ${Force},

    [Parameter(ParameterSetName='ModuleNameParameterSet')]
    [switch]
    ${AllowPrerelease},

    [switch]
    ${SkipAutomaticTags})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( $PSBoundParameters['NuGetApiKey'] )       { $null = $PSBoundParameters.Remove('NuGetApiKey'); $PSBoundParameters['APIKey'] = $NuGetApiKey }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Name'] )              { $null = $PSBoundParameters.Remove('Name') }
            if ( $PSBoundParameters['RequiredVersion'] )   { $null = $PSBoundParameters.Remove('RequiredVersion') }
            if ( $PSBoundParameters['FormatVersion'] )     { $null = $PSBoundParameters.Remove('FormatVersion') }
            if ( $PSBoundParameters['ReleaseNotes'] )      { $null = $PSBoundParameters.Remove('ReleaseNotes') }
            if ( $PSBoundParameters['Tags'] )              { $null = $PSBoundParameters.Remove('Tags') }
            if ( $PSBoundParameters['LicenseUri'] )        { $null = $PSBoundParameters.Remove('LicenseUri') }
            if ( $PSBoundParameters['IconUri'] )           { $null = $PSBoundParameters.Remove('IconUri') }
            if ( $PSBoundParameters['ProjectUri'] )        { $null = $PSBoundParameters.Remove('ProjectUri') }
            if ( $PSBoundParameters['Exclude'] )           { $null = $PSBoundParameters.Remove('Exclude') }
            if ( $PSBoundParameters['Force'] )             { $null = $PSBoundParameters.Remove('Force') }
            if ( $PSBoundParameters['AllowPrerelease'] )   { $null = $PSBoundParameters.Remove('AllowPrerelease') }
            if ( $PSBoundParameters['SkipAutomaticTags'] ) { $null = $PSBoundParameters.Remove('SkipAutomaticTags') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Publish-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Publish-Module
    .ForwardHelpCategory Function
    #>
}

function Publish-Script {
[CmdletBinding(DefaultParameterSetName='PathParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', PositionalBinding=$false, HelpUri='https://go.microsoft.com/fwlink/?LinkId=619788')]
param(
    [Parameter(ParameterSetName='PathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Path},

    [Parameter(ParameterSetName='LiteralPathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('PSPath')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${LiteralPath},

    [ValidateNotNullOrEmpty()]
    [string]
    ${NuGetApiKey},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Repository},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [switch]
    ${Force})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( $PSBoundParameters['LiteralPath'] )  { $null = $PSBoundParameters.Remove('LiteralPath'); $PSBoundParameters['Path'] = $LiteralPath }
            if ( $PSBoundParameters['NuGetApiKey'] )  { $null = $PSBoundParameters.Remove('NuGetApiKey'); $PSBoundParameters['APIKey'] = $NuGetApiKey }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Force'] )        { $null = $PSBoundParameters.Remove('Force') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Publish-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Publish-Script
    .ForwardHelpCategory Function
    #>
}

function Register-PSRepository {
[CmdletBinding(DefaultParameterSetName='NameParameterSet', HelpUri='https://go.microsoft.com/fwlink/?LinkID=517129')]
param(
    [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Name},

    [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${SourceLocation},

    [Parameter(ParameterSetName='NameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${PublishLocation},

    [Parameter(ParameterSetName='NameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${ScriptSourceLocation},

    [Parameter(ParameterSetName='NameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${ScriptPublishLocation},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [Parameter(ParameterSetName='PSGalleryParameterSet', Mandatory=$true)]
    [switch]
    ${Default},

    [ValidateSet('Trusted','Untrusted')]
    [string]
    ${InstallationPolicy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [Parameter(ParameterSetName='NameParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${PackageManagementProvider})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( $PSBoundParameters['InstallationPolicy'] ) {
                $null = $PSBoundParameters.Remove('InstallationPolicy')
                if  ( $InstallationPolicy -eq "Trusted" ) {
                    $PSBoundParameters['Trusted'] = $true
                }
            }
            if ( $PSBoundParameters['SourceLocation'] )            { $null = $PSBoundParameters.Remove('SourceLocation'); $PSBoundParameters['Uri'] = $SourceLocation }
            if ( $PSBoundParameters['Default'] )                   { $null = $PSBoundParameters.Remove('Default'); $PSBoundParameters['PSGallery'] = $Default }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['PublishLocation'] )           { $null = $PSBoundParameters.Remove('PublishLocation') }
            if ( $PSBoundParameters['ScriptSourceLocation'] )      { $null = $PSBoundParameters.Remove('ScriptSourceLocation') }
            if ( $PSBoundParameters['ScriptPublishLocation'] )     { $null = $PSBoundParameters.Remove('ScriptPublishLocation') }
            if ( $PSBoundParameters['Credential'] )                { $null = $PSBoundParameters.Remove('Credential') }
            if ( $PSBoundParameters['Proxy'] )                     { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )           { $null = $PSBoundParameters.Remove('ProxyCredential') }
            if ( $PSBoundParameters['PackageManagementProvider'] ) { $null = $PSBoundParameters.Remove('PackageManagementProvider') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Register-PSResourceRepository', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Register-PSRepository
    .ForwardHelpCategory Function
    #>
}

function Save-Module {
[CmdletBinding(DefaultParameterSetName='NameAndPathParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkId=531351')]
param(
    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ParameterSetName='InputObjectAndLiteralPathParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='InputObjectAndPathParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [psobject[]]
    ${InputObject},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository},

    [Parameter(ParameterSetName='InputObjectAndPathParameterSet', Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
    [string]
    ${Path},

    [Parameter(ParameterSetName='InputObjectAndLiteralPathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('PSPath')]
    [string]
    ${LiteralPath},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [switch]
    ${Force},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet')]
    [Parameter(ParameterSetName='NameAndPathParameterSet')]
    [switch]
    ${AllowPrerelease},

    [switch]
    ${AcceptLicense})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )   { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )   { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )  { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllowPrerelease'] )  { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            if ( $PSBoundParameters['LiteralPath'] )      { $null = $PSBoundParameters.Remove('LiteralPath'); $PSBoundParameters['Path'] = $LiteralPath }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Proxy'] )            { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )  { $null = $PSBoundParameters.Remove('ProxyCredential') }
            if ( $PSBoundParameters['Force'] )            { $null = $PSBoundParameters.Remove('Force') }
            if ( $PSBoundParameters['AcceptLicense'] )    { $null = $PSBoundParameters.Remove('AcceptLicense') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Save-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Save-Module
    .ForwardHelpCategory Function
    #>
}

function Save-Script {
[CmdletBinding(DefaultParameterSetName='NameAndPathParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkId=619786')]
param(
    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ParameterSetName='InputObjectAndLiteralPathParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='InputObjectAndPathParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [psobject[]]
    ${InputObject},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Repository},

    [Parameter(ParameterSetName='InputObjectAndPathParameterSet', Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndPathParameterSet', Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
    [string]
    ${Path},

    [Parameter(ParameterSetName='InputObjectAndLiteralPathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('PSPath')]
    [string]
    ${LiteralPath},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [switch]
    ${Force},

    [Parameter(ParameterSetName='NameAndLiteralPathParameterSet')]
    [Parameter(ParameterSetName='NameAndPathParameterSet')]
    [switch]
    ${AllowPrerelease},

    [switch]
    ${AcceptLicense})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )   { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )   { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )  { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllowPrerelease'] )  { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            if ( $PSBoundParameters['LiteralPath'] )      { $null = $PSBoundParameters.Remove('LiteralPath'); $PSBoundParameters['Path'] = $LiteralPath }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Proxy'] )            { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )  { $null = $PSBoundParameters.Remove('ProxyCredential') }
            if ( $PSBoundParameters['Force'] )            { $null = $PSBoundParameters.Remove('Force') }
            if ( $PSBoundParameters['AcceptLicense'] )    { $null = $PSBoundParameters.Remove('AcceptLicense') }

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Save-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Save-Script
    .ForwardHelpCategory Function
    #>
}

function Set-PSRepository {
[CmdletBinding(PositionalBinding=$false, HelpUri='https://go.microsoft.com/fwlink/?LinkID=517128')]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Name},

    [Parameter(Position=1)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${SourceLocation},

    [ValidateNotNullOrEmpty()]
    [uri]
    ${PublishLocation},

    [ValidateNotNullOrEmpty()]
    [uri]
    ${ScriptSourceLocation},

    [ValidateNotNullOrEmpty()]
    [uri]
    ${ScriptPublishLocation},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [ValidateSet('Trusted','Untrusted')]
    [string]
    ${InstallationPolicy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [ValidateNotNullOrEmpty()]
    [string]
    ${PackageManagementProvider})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( $PSBoundParameters['InstallationPolicy'] ) {
                $null = $PSBoundParameters.Remove('InstallationPolicy')
                if  ( $InstallationPolicy -eq "Trusted" ) {
                    $PSBoundParameters['Trusted'] = $true
                }
                else {
                    $PSBoundParameters['Trusted'] = $false
                }
            }
            if ( $PSBoundParameters['SourceLocation'] )            { $null = $PSBoundParameters.Remove('SourceLocation'); $PSBoundParameters['Uri'] = $SourceLocation }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['PublishLocation'] )           { $null = $PSBoundParameters.Remove('PublishLocation') }
            if ( $PSBoundParameters['ScriptSourceLocation'] )      { $null = $PSBoundParameters.Remove('ScriptSourceLocation') }
            if ( $PSBoundParameters['ScriptPublishLocation'] )     { $null = $PSBoundParameters.Remove('ScriptPublishLocation') }
            if ( $PSBoundParameters['Credential'] )                { $null = $PSBoundParameters.Remove('Credential') }
            if ( $PSBoundParameters['Proxy'] )                     { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )           { $null = $PSBoundParameters.Remove('ProxyCredential') }
            if ( $PSBoundParameters['PackageManagementProvider'] ) { $null = $PSBoundParameters.Remove('PackageManagementProvider') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Set-PSResourceRepository', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Set-PSRepository
    .ForwardHelpCategory Function
    #>
}

function Test-ScriptFileInfo {
[CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'PathParameterSet', HelpUri = 'https://go.microsoft.com/fwlink/?LinkId=619791')]
param(
    [Parameter(ParameterSetName='PathParameterSet', Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Path},

    [Parameter(ParameterSetName='LiteralPathParameterSet', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [Alias('PSPath')]
    [string]
    ${LiteralPath})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['LiteralPath'] )      { $null = $PSBoundParameters.Remove('LiteralPath'); $PSBoundParameters['Path'] = $LiteralPath }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Test-PSScriptFileInfo', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Test-ScriptFileInfo
    .ForwardHelpCategory Function
    #>
}

function Uninstall-Module {
[CmdletBinding(DefaultParameterSetName='NameParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkId=526864')]
param(
    [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ParameterSetName='InputObject', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [psobject[]]
    ${InputObject},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ParameterSetName='NameParameterSet')]
    [switch]
    ${AllVersions},

    [switch]
    ${Force},

    [Parameter(ParameterSetName='NameParameterSet')]
    [switch]
    ${AllowPrerelease})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )      { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )      { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )     { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllVersions'] )         { $null = $PSBoundParameters.Remove('AllVersions'); $PSBoundParameters['Version'] = '*' }
            if ( $PSBoundParameters['AllowPrerelease'] )     { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Force'] )               { $null = $PSBoundParameters.Remove('Force') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Uninstall-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Uninstall-Module
    .ForwardHelpCategory Function
    #>
}

function Uninstall-Script {
[CmdletBinding(DefaultParameterSetName='NameParameterSet', SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkId=619789')]
param(
    [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ParameterSetName='InputObject', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [psobject[]]
    ${InputObject},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MinimumVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ParameterSetName='NameParameterSet', ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [switch]
    ${Force},

    [Parameter(ParameterSetName='NameParameterSet')]
    [switch]
    ${AllowPrerelease})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MinimumVersion'] )      { $null = $PSBoundParameters.Remove('MinimumVersion'); $verArgs['MinimumVersion'] = $MinimumVersion }
            if ( $PSBoundParameters['MaximumVersion'] )      { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )     { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllowPrerelease'] )     { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Force'] )               { $null = $PSBoundParameters.Remove('Force') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Uninstall-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Uninstall-Script
    .ForwardHelpCategory Function
    #>
}

function Unregister-PSRepository {
[CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkID=517130')]
param(
    [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # No changes between Unregister-PSRepository and Unregister-PSResourceRepository
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Unregister-PSResourceRepository', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Unregister-PSRepository
    .ForwardHelpCategory Function
    #>
}

function Update-Module {
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkID=398576')]
param(
    [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [ValidateSet('CurrentUser','AllUsers')]
    [string]
    ${Scope},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [switch]
    ${Force},

    [switch]
    ${AllowPrerelease},

    [switch]
    ${AcceptLicense},

    [switch]
    ${PassThru})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MaximumVersion'] )     { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )    { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            if ( $PSBoundParameters['AllowPrerelease'] )    { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Proxy'] )              { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )    { $null = $PSBoundParameters.Remove('ProxyCredential') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Update-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Update-Module
    .ForwardHelpCategory Function
    #>
}

function Update-Script {
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkId=619787')]
param(
    [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${RequiredVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [string]
    ${MaximumVersion},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [uri]
    ${Proxy},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${ProxyCredential},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [switch]
    ${Force},

    [switch]
    ${AllowPrerelease},

    [switch]
    ${AcceptLicense},

    [switch]
    ${PassThru})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            $verArgs = @{}
            if ( $PSBoundParameters['MaximumVersion'] )     { $null = $PSBoundParameters.Remove('MaximumVersion'); $verArgs['MaximumVersion'] = $MaximumVersion }
            if ( $PSBoundParameters['RequiredVersion'] )    { $null = $PSBoundParameters.Remove('RequiredVersion'); $verArgs['RequiredVersion'] = $RequiredVersion }
            $ver = Convert-VersionParamaters @verArgs
            if ( $ver ) {
                $PSBoundParameters['Version'] = $ver
            }
            # Parameter translations
            if ( $PSBoundParameters['AllowPrerelease'] )    { $null = $PSBoundParameters.Remove('AllowPrerelease'); $PSBoundParameters['Prerelease'] = $AllowPrerelease }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['Proxy'] )              { $null = $PSBoundParameters.Remove('Proxy') }
            if ( $PSBoundParameters['ProxyCredential'] )    { $null = $PSBoundParameters.Remove('ProxyCredential') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Update-PSResource', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Update-Script
    .ForwardHelpCategory Function
    #>
}

function Update-ModuleManifest {
[CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'PathParameterSet', SupportsShouldProcess = $true, HelpUri = 'https://go.microsoft.com/fwlink/?LinkId=619793')]
param(
    [Parameter(ParameterSetName = 'PathParameterSet', Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Path},

    [Parameter(ParameterSetName = 'LiteralPathParameterSet', Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('PSPath')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${LiteralPath},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Version},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Author},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Description},

    [ValidateNotNullOrEmpty()]
    [Guid]
    ${Guid},

    [ValidateNotNullOrEmpty()]
    [string]
    ${CompanyName},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Copyright},

    [ValidateNotNullOrEmpty()]
    [Object[]]
    ${RequiredModules},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${ExternalModuleDependencies},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${RequiredScripts},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${ExternalScriptDependencies},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Tags},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${ProjectUri},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${LicenseUri},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${IconUri},

    [string[]]
    ${ReleaseNotes},

    [ValidateNotNullOrEmpty()]
    [string]
    ${PrivateData},

    [switch]
    ${PassThru},

    [switch]
    ${Force})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # No parameter translations
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Update-PSModuleManifest', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Update-ModuleManifest
    .ForwardHelpCategory Function
    #>
}

function Update-ScriptFileInfo {
[CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'PathParameterSet', SupportsShouldProcess = $true, HelpUri = 'https://go.microsoft.com/fwlink/?LinkId=619793')]
param(
    [Parameter(ParameterSetName = 'PathParameterSet', Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Path},

    [Parameter(ParameterSetName = 'LiteralPathParameterSet', Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('PSPath')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${LiteralPath},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Version},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Author},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Description},

    [ValidateNotNullOrEmpty()]
    [Guid]
    ${Guid},

    [ValidateNotNullOrEmpty()]
    [string]
    ${CompanyName},

    [ValidateNotNullOrEmpty()]
    [string]
    ${Copyright},

    [ValidateNotNullOrEmpty()]
    [Object[]]
    ${RequiredModules},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${ExternalModuleDependencies},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${RequiredScripts},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${ExternalScriptDependencies},

    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Tags},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${ProjectUri},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${LicenseUri},

    [ValidateNotNullOrEmpty()]
    [Uri]
    ${IconUri},

    [string[]]
    ${ReleaseNotes},

    [ValidateNotNullOrEmpty()]
    [string]
    ${PrivateData},

    [switch]
    ${PassThru},

    [switch]
    ${Force})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            # PARAMETER MAP
            # Parameter translations
            if ( $PSBoundParameters['LiteralPath'] )      { $null = $PSBoundParameters.Remove('LiteralPath'); $PSBoundParameters['Path'] = $LiteralPath }
            # Translate from string[] to string
            if ( $PSBoundParameters['ReleaseNotes'] ) {
                $PSBoundParameters['ReleaseNotes'] = $PSBoundParameters['ReleaseNotes'] -join "; "
            }
            # Parameter Deletions (unsupported in v3)
            if ( $PSBoundParameters['PassThru'] )      { $null = $PSBoundParameters.Remove('PassThru') }
            if ( $PSBoundParameters['Force'] )         { $null = $PSBoundParameters.Remove('Force') }
            if ( $PSBoundParameters['WhatIf'] )        { $null = $PSBoundParameters.Remove('WhatIf') }
            if ( $PSBoundParameters['Confirm'] )       { $null = $PSBoundParameters.Remove('Confirm') }
            # END PARAMETER MAP

            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Update-PSScriptFileInfo', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            # Set internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $true)
            } catch {
                # Ignore if not available
            }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } catch {
            throw
        }
    }

    process
    {
        try {
            $steppablePipeline.Process($_)
        } catch {
            throw
        }
    }

    end
    {
        try {
            # Reset internal hook for being invoked from Compat module
            try {
                [Microsoft.PowerShell.PSResourceGet.UtilClasses.InternalHooks]::SetTestHook("InvokedFromCompat", $false)
            }
            catch {
                # Ignore if not available
            }

            $steppablePipeline.End()
        } catch {
            throw
        }
    }
    <#
    .ForwardHelpTargetName Update-ScriptFileInfo
    .ForwardHelpCategory Function
    #>
}

New-Alias -Name fimo -Value Find-Module
New-Alias -Name inmo -Value Install-Module
New-Alias -Name pumo -Value Publish-Module
New-Alias -Name upmo -Value Update-Module

$functionsToExport = @(
    "Find-Command",
    "Find-DscResource",
    "Find-Module",
    "Find-RoleCapability",
    "Find-Script",
    "Get-InstalledModule",
    "Get-InstalledScript",
    "Get-PSRepository",
    "Install-Module",
    "Install-Script",
    "New-ScriptFileInfo",
    "Publish-Module",
    "Publish-Script",
    "Register-PSRepository",
    "Save-Module",
    "Save-Script",
    "Set-PSRepository",
    "Test-ScriptFileInfo",
    "Uninstall-Module",
    "Uninstall-Script",
    "Unregister-PSRepository",
    "Update-Module",
    "Update-Script",
    "Update-ScriptFileInfo"
)

$aliasesToExport = @('
    fimo',
    'inmo',
    'pumo',
    'upmo'
)

export-ModuleMember -Function $functionsToExport -Alias $aliasesToExport

# SIG # Begin signature block
# MIIoLQYJKoZIhvcNAQcCoIIoHjCCKBoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCGl7kgNs3R0DmL
# CJE0Wn02xUZLKvSzCHSwVR96fCuihqCCDXYwggX0MIID3KADAgECAhMzAAADTrU8
# esGEb+srAAAAAANOMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjMwMzE2MTg0MzI5WhcNMjQwMzE0MTg0MzI5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDdCKiNI6IBFWuvJUmf6WdOJqZmIwYs5G7AJD5UbcL6tsC+EBPDbr36pFGo1bsU
# p53nRyFYnncoMg8FK0d8jLlw0lgexDDr7gicf2zOBFWqfv/nSLwzJFNP5W03DF/1
# 1oZ12rSFqGlm+O46cRjTDFBpMRCZZGddZlRBjivby0eI1VgTD1TvAdfBYQe82fhm
# WQkYR/lWmAK+vW/1+bO7jHaxXTNCxLIBW07F8PBjUcwFxxyfbe2mHB4h1L4U0Ofa
# +HX/aREQ7SqYZz59sXM2ySOfvYyIjnqSO80NGBaz5DvzIG88J0+BNhOu2jl6Dfcq
# jYQs1H/PMSQIK6E7lXDXSpXzAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUnMc7Zn/ukKBsBiWkwdNfsN5pdwAw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMDUxNjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAD21v9pHoLdBSNlFAjmk
# mx4XxOZAPsVxxXbDyQv1+kGDe9XpgBnT1lXnx7JDpFMKBwAyIwdInmvhK9pGBa31
# TyeL3p7R2s0L8SABPPRJHAEk4NHpBXxHjm4TKjezAbSqqbgsy10Y7KApy+9UrKa2
# kGmsuASsk95PVm5vem7OmTs42vm0BJUU+JPQLg8Y/sdj3TtSfLYYZAaJwTAIgi7d
# hzn5hatLo7Dhz+4T+MrFd+6LUa2U3zr97QwzDthx+RP9/RZnur4inzSQsG5DCVIM
# pA1l2NWEA3KAca0tI2l6hQNYsaKL1kefdfHCrPxEry8onJjyGGv9YKoLv6AOO7Oh
# JEmbQlz/xksYG2N/JSOJ+QqYpGTEuYFYVWain7He6jgb41JbpOGKDdE/b+V2q/gX
# UgFe2gdwTpCDsvh8SMRoq1/BNXcr7iTAU38Vgr83iVtPYmFhZOVM0ULp/kKTVoir
# IpP2KCxT4OekOctt8grYnhJ16QMjmMv5o53hjNFXOxigkQWYzUO+6w50g0FAeFa8
# 5ugCCB6lXEk21FFB1FdIHpjSQf+LP/W2OV/HfhC3uTPgKbRtXo83TZYEudooyZ/A
# Vu08sibZ3MkGOJORLERNwKm2G7oqdOv4Qj8Z0JrGgMzj46NFKAxkLSpE5oHQYP1H
# tPx1lPfD7iNSbJsP6LiUHXH1MIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGg0wghoJAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAANOtTx6wYRv6ysAAAAAA04wDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGPTcAfvBcjXuyZHQ479ZtiW
# HFTMeGMdybLcbFtJixciMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAbcDGOVKMEb8M49ojEmLFVgtKMhHI54QmR75IDgQBXhe8bX6+AG6utMjA
# hPg4GdmazIO8y7gLWJk55plu5bEqcRg7rI1NyDLGgiaeIDmG6nvdyCfurW4h7H/x
# 0EVi2ufhx31TwZz1p+HngLrx0wdVvXDTMjoZbXQtCf2ez2XPk3rvIBlSjZs5sD/2
# zlYe5Ish9Tnf7aVCY29VtxXZUuWZEREt4F07hvEePj1OjJzaR62RBjrPGWUKY30P
# 3LjYcf56dmWx5EZwPSX1SDzkvYaDSn8XEF5VHvE7xoTHqO/h57NauQXqFPZbe5Ut
# yTwYkE+F6JthaZI9fBAFMm8SbYayFaGCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCC
# F38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsq
# hkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCCQMCjX9GY/J0gJ1tkxsRefIPiHoslKLPEdzioiNsKnGgIGZSitfiui
# GBMyMDIzMTAyNjIzNDM1NS4zOTdaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RTAwMi0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# ghHtMIIHIDCCBQigAwIBAgITMwAAAdmcXAWSsINrPgABAAAB2TANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMzA2MDExODMy
# NThaFw0yNDAyMDExODMyNThaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RTAwMi0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDV6SDN1rgY2305yLdCdUNvHCEE4Z0ucD6CKvL5lA7H
# M81SMkW36RU77UaBL9PScviqfVzE2r2pRbRMtDBMwEx1iaizV2EZsNGGuzeR3XNY
# ObQvJVLaCiBktAZdq75BNFIil+SfdpXgKzVQZiDBJDN50WCADNrrb48Z4Z7/Kvyz
# aD4Gb+aZeCioB2Gg1m53d+6pUTBc3WO5xHZi/rrI/XdnhiE6/bspjpU5aufClIDx
# 0QDq1QRw04adrKhcDWyGL3SaBp/hjN+4JJU7KzvsKWZVdTuXPojnaTwWcHdEGfzx
# iaF30zd8SY4YRUcMGPOQORH1IPwkwwlqQkc0HBkJCQziaXY/IpgMRw/XP4Uv+JBJ
# 8RZGKZN1zRPWT9d5vHGUSmX3m77RKoCfkgSJifIiQi6Fc0OYKS6gZOA7nd4t+liA
# rr9niqeC/UcNOuVrcVC4CbkwfJ2eHkaWh18sUt3UD8QHYLQwn95P+Hm8PZJigr1S
# RLcsm8pOPee7PBbndI/VeKJsmQdjek2aFO9VGnUtzDDBowlhXshswZMMkLJ/4jUz
# QmUBfm+JAH1516E+G02wS7NgzMwmpHWCmAaFdd7DyJIqGa6bcZrR7QALdkwIhVQD
# gzZAuNxqwvh4Ia4ZI5Voyj4b7zWAhmurpwpMpijz+ieeWwf6ZdmysRjR/yZ6UXmG
# awIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFBw6wSlTZ6gFXl05w/s3Ga1f51wnMB8G
# A1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCG
# Tmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4w
# XAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2Vy
# dHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwG
# A1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQD
# AgeAMA0GCSqGSIb3DQEBCwUAA4ICAQAqNtVYLO61TMuIanC7clt0i+XRRbHwnwNo
# 05Q3s4ppFtd4nCmB/TJPDJ6uvEryxs0vw5Y+jQwUiKnhl2VGGwIq0pWDIuaW4ppM
# V1pYQfJ6dtBGkRiTP1eKVvARYZMRaITe9ZhwJJnYP83pMxHCxaEsZC4ilY3/55dq
# d4ZXTCz/cpG5anmDartnWmgysygNstTwbWJJRj85gYRkjxi/nxKAiEFxl6GfkcnX
# Vy8DRFQj1d3AiqsePoeIzxu1iuAJRwDrfe4NnKHqoTgWsv7eCWJnWjWWRt7RRGrp
# vzLQo/BxUb8i49UwRg9G5bxpd5Su1b224Gv6G1HRU+qJHB1zoe41D2r/ic2BPous
# V9neYK5qI5PHLshAn6YTQllbV9pCbOUvZO0dtdwp5HH2fw6ofJNwKcPElaqkEcxv
# rhhRWqwNgaEVTyIV4jMc8jPbx2Nh9zAztnb9NfnDFOE+/gF8cZqTa/T65TGNP3uM
# iP3gr8nIXQ2IRwMVUoLmGu2qfmhDoews3dcvk6s1aA6mXHw+MANEIDKKjw3i2G6J
# tZkEemu1OXtskg/tGnfywaMgq5CauU9b6enTtA+UE+GKnmiQW6YUHPhBI0L2QG76
# TRBre5PpNVHiyc/01bjUEMpeaB+InAH4nDxYXx18wbJE+e/IbMv0147EFL792dEL
# F0XwqqcU0TCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZI
# hvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# MjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAy
# MDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25Phdg
# M/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPF
# dvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6
# GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBp
# Dco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50Zu
# yjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3E
# XzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0
# lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1q
# GFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ
# +QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PA
# PBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkw
# EgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxG
# NSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARV
# MFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAK
# BggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMC
# AYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvX
# zpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20v
# cGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYI
# KwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG
# 9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0x
# M7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmC
# VgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449
# xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wM
# nosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDS
# PeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2d
# Y3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxn
# GSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+Crvs
# QWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokL
# jzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL
# 6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQ
# MIICOAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEn
# MCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkUwMDItMDVFMC1EOTQ3MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDi
# HEW6Ca3n5BgZV/tQ/fCR09Tf96CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA6OT3RzAiGA8yMDIzMTAyNjE0MzM0
# M1oYDzIwMjMxMDI3MTQzMzQzWjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDo5PdH
# AgEAMAoCAQACAhsNAgH/MAcCAQACAhLCMAoCBQDo5kjHAgEAMDYGCisGAQQBhFkK
# BAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJ
# KoZIhvcNAQELBQADggEBAHmraFAp0rZotlvhnbdcyl1kK7+lfiXWFsWYE04a8Gvb
# kinCVLTbNmC77/k2iyLs7jvRr2QtKb6oRetFzn0AuQbBO790Hmwon3/C2C/ksfcO
# RoNjwIzL+TZHG+AwsupkJs/e4tFUiOS1j6o+dY6ep4ALVFyn5ZNHX4SMpqV/abh1
# QYkt8D88HiNvzhJqF524A0FaOGEOTloowDUJcXyxabhld1Qmiq1CQgZ80tYwuiwg
# 5zlctLzR8Y1KPNZzV8cLcwheY93gxsvR5dF1zRsSTw+SL53ReW5ms+Jw41g/FRku
# ym/ZFV4IBU6XyciRy9RSg0/6mLYYBk6+gVHOLx6Y2roxggQNMIIECQIBATCBkzB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAdmcXAWSsINrPgABAAAB
# 2TANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEE
# MC8GCSqGSIb3DQEJBDEiBCCueXPsHXYULYbLmyc2rSZBO6aX5uR+2VRf9Z6KvfY0
# FTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIJ+gFbItOm/UMDAnETzbJe0u
# 0DWd2Mgpgb0ScbQgB3nzMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAHZnFwFkrCDaz4AAQAAAdkwIgQgRtyznrfDYIRC0buJeqG3HFJN
# fBgqeIeZGhHSedsGlk8wDQYJKoZIhvcNAQELBQAEggIAGjtGfd3igwVIZ/RlbT/y
# qxh2wLkPG93I0yJp+GMxpMDUnauLXSDci8kGEh0KZgwOEj/JxxNtTtjpbmTpVu2p
# d+X33tNwKxnH3iOnq+hWqZvBo017+IudpAq+EwSA0QhYvv+IGAzzKBdXDbocYrKy
# Fz308zPRPWBnVWkO/2sewMCl/kVwmddr0sy0luQF6do/oyw7cN4wK2iHoTqZfppj
# zqFP83WZl8VE5hqnpNrqIZYHG7ilVMQz50diai4xWVgEC0osxqEkodCA4ZQlwOBD
# bBdEIbXnqHAloUJhSLRPA9C9n2jXBl7JWBnQa3UmhWR0Oz5NzYUEwHEHI1lEFiRh
# mFuG79MeXKXsyx+SBO0GKVkk8l7ZGUwjgzhipdoEn0Dp8GTx4mIhJ5WKUAPEzeDG
# JN4fqLISOGOAI/KKB6oh35NIj4BoYS4+EBNmJt4PCNIRbK2wDjSFmLEVfPPmuWfN
# Fd9eSCGzropMzHkQotMUxLJnBr9feTmvsQ1GsTU+6JqWx660ezcVLiw640NE/3ZV
# pOe/NrULTxPEGEWXNZB0vBs46FE/rIMD7TttM7j6c0Jk8ZD2SLZ/k5vihSJaDT5b
# ewmH56FwGydTnsCm9yI1miZOjWgyLng8oz/j82Oz5ik9Cxtw1/eiAVvTOkEzjusA
# a5qBzcmDocI+WmvqUHs4980=
# SIG # End signature block
