
#Requires -Version 5.1
using namespace System.Management.Automation

# Module initialization
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

function ConvertFrom-JsonContentAction {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlElement])]
    param(
        [Parameter(Mandatory)]
        [object]$Action,

        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]$XmlDocument
    )

    switch ($Action.type) {
        'message' {
            $element = $XmlDocument.CreateElement('message', $TargetNamespace)
            $element.InnerText = $Action.text

            if ($Action.noNewline) {
                $element.SetAttribute('nonewline', 'true')
            }
        }
        'file' {
            $element = $XmlDocument.CreateElement('file', $TargetNamespace)
            $element.SetAttribute('source', $Action.source)
            $element.SetAttribute('destination', $Action.destination)

            if ($Action.encoding) {
                $element.SetAttribute('encoding', $Action.encoding)
            }

            if ($Action.openInEditor) {
                $element.SetAttribute('openInEditor', 'true')
            }
        }
        'templateFile' {
            $element = $XmlDocument.CreateElement('templateFile', $TargetNamespace)
            $element.SetAttribute('source', $Action.source)
            $element.SetAttribute('destination', $Action.destination)

            if ($Action.encoding) {
                $element.SetAttribute('encoding', $Action.encoding)
            }

            if ($Action.openInEditor) {
                $element.SetAttribute('openInEditor', 'true')
            }
        }
        'directory' {
            $element = $XmlDocument.CreateElement('file', $TargetNamespace)
            $element.SetAttribute('source', '')
            $element.SetAttribute('destination', $Action.destination)
        }
        'newModuleManifest' {
            $element = $XmlDocument.CreateElement('newModuleManifest', $TargetNamespace)
            $element.SetAttribute('destination', $Action.destination)

            $manifestProperties = @('moduleVersion', 'rootModule', 'author', 'companyName', 'description', 'powerShellVersion', 'copyright', 'encoding')
            foreach ($property in $manifestProperties) {
                if ($Action.PSObject.Properties[$property]) {
                    $element.SetAttribute($property, $Action.$property)
                }
            }

            if ($Action.openInEditor) {
                $element.SetAttribute('openInEditor', 'true')
            }
        }
        'modify' {
            $element = $XmlDocument.CreateElement('modify', $TargetNamespace)
            $element.SetAttribute('path', $Action.path)

            if ($Action.encoding) {
                $element.SetAttribute('encoding', $Action.encoding)
            }

            # Add modifications
            foreach ($modification in $Action.modifications) {
                if ($modification.type -eq 'replace') {
                    $replaceElement = $XmlDocument.CreateElement('replace', $TargetNamespace)

                    $originalElement = $XmlDocument.CreateElement('original', $TargetNamespace)
                    $originalElement.InnerText = $modification.search
                    if ($modification.isRegex) {
                        $originalElement.SetAttribute('expand', 'true')
                    }
                    [void]$replaceElement.AppendChild($originalElement)

                    $substituteElement = $XmlDocument.CreateElement('substitute', $TargetNamespace)
                    $substituteElement.InnerText = $modification.replace
                    $substituteElement.SetAttribute('expand', 'true')
                    [void]$replaceElement.AppendChild($substituteElement)

                    if ($modification.condition) {
                        $replaceElement.SetAttribute('condition', $modification.condition)
                    }

                    [void]$element.AppendChild($replaceElement)
                }
            }
        }
        'requireModule' {
            $element = $XmlDocument.CreateElement('requireModule', $TargetNamespace)
            $element.SetAttribute('name', $Action.name)

            $moduleProperties = @('minimumVersion', 'maximumVersion', 'requiredVersion', 'message')
            foreach ($property in $moduleProperties) {
                if ($Action.PSObject.Properties[$property]) {
                    $element.SetAttribute($property, $Action.$property)
                }
            }
        }
        'execute' {
            # Execute action doesn't have direct XML equivalent, convert to message with warning
            $element = $XmlDocument.CreateElement('message', $TargetNamespace)
            $element.InnerText = "Warning: Execute action not supported in XML format. Script: $($Action.script)"
            Write-PlasterLog -Level Warning -Message "Execute action converted to message - not supported in XML format"
        }
        default {
            throw "Unknown action type: $($Action.type)"
        }
    }

    # Add condition if present
    if ($Action.condition) {
        $element.SetAttribute('condition', $Action.condition)
    }

    return $element
}
function ConvertFrom-JsonManifest {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$JsonContent,

        [Parameter()]
        [switch]$Validate = $true
    )

    begin {
        Write-PlasterLog -Level Debug -Message "Converting JSON manifest to internal format"
    }

    process {
        try {
            # Validate JSON if requested
            if ($Validate) {
                $isValid = Test-JsonManifest -JsonContent $JsonContent -Detailed
                if (-not $isValid) {
                    throw "JSON manifest validation failed"
                }
            }

            # Parse JSON
            $jsonObject = $JsonContent | ConvertFrom-Json

            # Create XML document
            $xmlDoc = New-Object System.Xml.XmlDocument
            $xmlDoc.LoadXml('<?xml version="1.0" encoding="utf-8"?><plasterManifest xmlns="http://www.microsoft.com/schemas/PowerShell/Plaster/v1"></plasterManifest>')

            $manifest = $xmlDoc.DocumentElement
            $manifest.SetAttribute('schemaVersion', '1.2')  # Use XML schema version for compatibility

            if ($jsonObject.metadata.templateType) {
                $manifest.SetAttribute('templateType', $jsonObject.metadata.templateType)
            }

            # Add metadata
            $metadataElement = $xmlDoc.CreateElement('metadata', $TargetNamespace)
            [void]$manifest.AppendChild($metadataElement)

            # Add metadata properties
            $metadataProperties = @('name', 'id', 'version', 'title', 'description', 'author', 'tags')
            foreach ($property in $metadataProperties) {
                if ($jsonObject.metadata.PSObject.Properties[$property]) {
                    $element = $xmlDoc.CreateElement($property, $TargetNamespace)
                    $value = $jsonObject.metadata.$property

                    if ($property -eq 'tags' -and $value -is [array]) {
                        $element.InnerText = $value -join ', '
                    } else {
                        $element.InnerText = $value
                    }
                    [void]$metadataElement.AppendChild($element)
                }
            }

            # Add parameters
            $parametersElement = $xmlDoc.CreateElement('parameters', $TargetNamespace)
            [void]$manifest.AppendChild($parametersElement)

            if ($jsonObject.parameters) {
                foreach ($param in $jsonObject.parameters) {
                    $paramElement = $xmlDoc.CreateElement('parameter', $TargetNamespace)
                    $paramElement.SetAttribute('name', $param.name)
                    $paramElement.SetAttribute('type', $param.type)

                    if ($param.prompt) {
                        $paramElement.SetAttribute('prompt', $param.prompt)
                    }

                    if ($param.default) {
                        if ($param.default -is [array]) {
                            $paramElement.SetAttribute('default', ($param.default -join ','))
                        } else {
                            $paramElement.SetAttribute('default', $param.default)
                        }
                    }

                    if ($param.condition) {
                        $paramElement.SetAttribute('condition', $param.condition)
                    }

                    if ($param.store) {
                        $paramElement.SetAttribute('store', $param.store)
                    }

                    # Add choices for choice/multichoice parameters
                    if ($param.choices) {
                        foreach ($choice in $param.choices) {
                            $choiceElement = $xmlDoc.CreateElement('choice', $TargetNamespace)
                            $choiceElement.SetAttribute('label', $choice.label)
                            $choiceElement.SetAttribute('value', $choice.value)

                            if ($choice.help) {
                                $choiceElement.SetAttribute('help', $choice.help)
                            }

                            [void]$paramElement.AppendChild($choiceElement)
                        }
                    }

                    [void]$parametersElement.AppendChild($paramElement)
                }
            }

            # Add content
            $contentElement = $xmlDoc.CreateElement('content', $TargetNamespace)
            [void]$manifest.AppendChild($contentElement)

            foreach ($action in $jsonObject.content) {
                $actionElement = ConvertFrom-JsonContentAction -Action $action -XmlDocument $xmlDoc
                [void]$contentElement.AppendChild($actionElement)
            }

            Write-PlasterLog -Level Debug -Message "JSON to XML conversion completed successfully"
            return $xmlDoc
        } catch {
            $errorMessage = "Failed to convert JSON manifest: $($_.Exception.Message)"
            Write-PlasterLog -Level Error -Message $errorMessage
            throw $_
        }
    }
}
function ConvertTo-DestinationRelativePath {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    $fullDestPath = $DestinationPath
    if (![System.IO.Path]::IsPathRooted($fullDestPath)) {
        $fullDestPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DestinationPath)
    }

    $fullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    if (!$fullPath.StartsWith($fullDestPath, 'OrdinalIgnoreCase')) {
        throw ($LocalizedData.ErrorPathMustBeUnderDestPath_F2 -f $fullPath, $fullDestPath)
    }

    $fullPath.Substring($fullDestPath.Length).TrimStart('\', '/')
}
function ConvertTo-JsonContentAction {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$ActionNode
    )

    $action = [ordered]@{
        'type' = $ActionNode.LocalName
    }

    switch ($ActionNode.LocalName) {
        'message' {
            $action['text'] = $ActionNode.InnerText
            if ($ActionNode.nonewline -eq 'true') {
                $action['noNewline'] = $true
            }
        }
        'file' {
            $action['source'] = $ActionNode.source
            $action['destination'] = $ActionNode.destination

            if ($ActionNode.encoding) {
                $action['encoding'] = $ActionNode.encoding
            }

            if ($ActionNode.openInEditor -eq 'true') {
                $action['openInEditor'] = $true
            }

            # Handle directory creation (empty source)
            if ([string]::IsNullOrEmpty($ActionNode.source)) {
                $action['type'] = 'directory'
                $action.Remove('source')
            }
        }
        'templateFile' {
            $action['source'] = $ActionNode.source
            $action['destination'] = $ActionNode.destination

            if ($ActionNode.encoding) {
                $action['encoding'] = $ActionNode.encoding
            }

            if ($ActionNode.openInEditor -eq 'true') {
                $action['openInEditor'] = $true
            }
        }
        'newModuleManifest' {
            $action['destination'] = $ActionNode.destination

            $manifestProperties = @('moduleVersion', 'rootModule', 'author', 'companyName', 'description', 'powerShellVersion', 'copyright', 'encoding')
            foreach ($property in $manifestProperties) {
                if ($ActionNode.$property) {
                    $action[$property] = $ActionNode.$property
                }
            }

            if ($ActionNode.openInEditor -eq 'true') {
                $action['openInEditor'] = $true
            }
        }
        'modify' {
            $action['path'] = $ActionNode.path

            if ($ActionNode.encoding) {
                $action['encoding'] = $ActionNode.encoding
            }

            # Extract modifications
            $modifications = @()
            foreach ($child in $ActionNode.ChildNodes) {
                if ($child.NodeType -eq 'Element' -and $child.LocalName -eq 'replace') {
                    $modification = [ordered]@{
                        'type' = 'replace'
                    }

                    $originalNode = $child.SelectSingleNode('*[local-name()="original"]')
                    $substituteNode = $child.SelectSingleNode('*[local-name()="substitute"]')

                    if ($originalNode) {
                        $modification['search'] = $originalNode.InnerText
                        if ($originalNode.expand -eq 'true') {
                            $modification['isRegex'] = $true
                        }
                    }

                    if ($substituteNode) {
                        $modification['replace'] = $substituteNode.InnerText
                    }

                    if ($child.condition) {
                        $modification['condition'] = $child.condition
                    }

                    $modifications += $modification
                }
            }

            $action['modifications'] = $modifications
        }
        'requireModule' {
            $action['name'] = $ActionNode.name

            $moduleProperties = @('minimumVersion', 'maximumVersion', 'requiredVersion', 'message')
            foreach ($property in $moduleProperties) {
                if ($ActionNode.$property) {
                    $action[$property] = $ActionNode.$property
                }
            }
        }
        default {
            Write-PlasterLog -Level Warning -Message "Unknown XML action type: $($ActionNode.LocalName)"
            return $null
        }
    }

    # Add condition if present
    if ($ActionNode.condition) {
        $action['condition'] = $ActionNode.condition
    }

    return $action
}
function ConvertTo-JsonManifest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Xml.XmlDocument]$XmlManifest,

        [Parameter()]
        [switch]$Compress
    )

    begin {
        Write-PlasterLog -Level Debug -Message "Converting XML manifest to JSON format"
    }

    process {
        try {
            $jsonObject = [ordered]@{
                '$schema' = 'https://raw.githubusercontent.com/PowerShellOrg/Plaster/v2/schema/plaster-manifest-v2.json'
                'schemaVersion' = '2.0'
            }

            # Extract metadata
            $metadata = [ordered]@{}
            $metadataNode = $XmlManifest.plasterManifest.metadata

            if ($metadataNode) {
                foreach ($child in $metadataNode.ChildNodes) {
                    if ($child.NodeType -eq 'Element') {
                        $value = $child.InnerText
                        if ($child.LocalName -eq 'tags' -and $value) {
                            $metadata[$child.LocalName] = $value -split ',' | ForEach-Object { $_.Trim() }
                        } else {
                            $metadata[$child.LocalName] = $value
                        }
                    }
                }
            }

            # Add template type if present
            if ($XmlManifest.plasterManifest.templateType) {
                $metadata['templateType'] = $XmlManifest.plasterManifest.templateType
            } else {
                $metadata['templateType'] = 'Project'
            }

            $jsonObject['metadata'] = $metadata

            # Extract parameters
            $parameters = @()
            $parametersNode = $XmlManifest.plasterManifest.parameters

            if ($parametersNode) {
                foreach ($paramNode in $parametersNode.ChildNodes) {
                    if ($paramNode.NodeType -eq 'Element' -and $paramNode.LocalName -eq 'parameter') {
                        $param = [ordered]@{
                            'name' = $paramNode.name
                            'type' = $paramNode.type
                        }

                        if ($paramNode.prompt) {
                            $param['prompt'] = $paramNode.prompt
                        }

                        if ($paramNode.default) {
                            if ($paramNode.type -eq 'multichoice') {
                                $param['default'] = $paramNode.default -split ','
                            } else {
                                $param['default'] = $paramNode.default
                            }
                        }

                        if ($paramNode.condition) {
                            $param['condition'] = $paramNode.condition
                        }

                        if ($paramNode.store) {
                            $param['store'] = $paramNode.store
                        }

                        # Extract choices
                        $choices = @()
                        foreach ($choiceNode in $paramNode.ChildNodes) {
                            if ($choiceNode.NodeType -eq 'Element' -and $choiceNode.LocalName -eq 'choice') {
                                $choice = [ordered]@{
                                    'label' = $choiceNode.label
                                    'value' = $choiceNode.value
                                }

                                if ($choiceNode.help) {
                                    $choice['help'] = $choiceNode.help
                                }

                                $choices += $choice
                            }
                        }

                        if ($choices.Count -gt 0) {
                            $param['choices'] = $choices
                        }

                        $parameters += $param
                    }
                }
            }

            if ($parameters.Count -gt 0) {
                $jsonObject['parameters'] = $parameters
            }

            # Extract content
            $content = @()
            $contentNode = $XmlManifest.plasterManifest.content

            if ($contentNode) {
                foreach ($actionNode in $contentNode.ChildNodes) {
                    if ($actionNode.NodeType -eq 'Element') {
                        $action = ConvertTo-JsonContentAction -ActionNode $actionNode
                        if ($action) {
                            $content += $action
                        }
                    }
                }
            }

            $jsonObject['content'] = $content

            # Convert to JSON
            $jsonParams = @{
                InputObject = $jsonObject
                Depth = 10
            }

            if (-not $Compress) {
                $jsonParams['Compress'] = $false
            }

            $jsonResult = $jsonObject | ConvertTo-Json @jsonParams

            Write-PlasterLog -Level Debug -Message "XML to JSON conversion completed successfully"
            return $jsonResult
        } catch {
            $errorMessage = "Failed to convert XML manifest to JSON: $($_.Exception.Message)"
            Write-PlasterLog -Level Error -Message $errorMessage
            throw $_
        }
    }
}
<#
Plaster zen for file handling. All file related operations should use this
method to actually write/overwrite/modify files in the DestinationPath. This
method handles detecting conflicts, gives the user a chance to determine how to
handle conflicts. The user can choose to use the Force parameter to force the
overwriting of existing files at the destination path. File processing
(expanding substitution variable, modifying file contents) should always be done
to a temp file (be sure to always remove temp file when done). That temp file is
what gets passed to this function as the $SrcPath. This allows Plaster to alert
the user when the repeated application of a template will modify any existing
file.

NOTE: Plaster keeps track of which files it has "created" (as opposed to
overwritten) so that any later change to that file doesn't trigger conflict
handling.
#>
function Copy-FileWithConflictDetection {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$SrcPath,
        [string]$DstPath
    )
    # Just double-checking that DstPath parameter is an absolute path otherwise
    # it could fail the check that the DstPath is under the overall DestinationPath.
    if (![System.IO.Path]::IsPathRooted($DstPath)) {
        $DstPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DstPath)
    }

    # Check if DstPath file conflicts with an existing SrcPath file.
    $operation = $LocalizedData.OpCreate
    $opMessage = ConvertTo-DestinationRelativePath $DstPath
    if (Test-Path -LiteralPath $DstPath) {
        if (Test-FilesIdentical $SrcPath $DstPath) {
            $operation = $LocalizedData.OpIdentical
        } elseif ($script:templateCreatedFiles.ContainsKey($DstPath)) {
            # Plaster created this file previously during template invocation
            # therefore, there is no conflict.  We're simply updating the file.
            $operation = $LocalizedData.OpUpdate
        } elseif ($Force) {
            $operation = $LocalizedData.OpForce
        } else {
            $operation = $LocalizedData.OpConflict
        }
    }

    # Copy the file to the destination
    if ($PSCmdlet.ShouldProcess($DstPath, $operation)) {
        Write-OperationStatus -Operation $operation -Message $opMessage

        if ($operation -eq $LocalizedData.OpIdentical) {
            # If the files are identical, no need to do anything
            return
        }

        if (
            ($operation -eq $LocalizedData.OpCreate) -or
            ($operation -eq $LocalizedData.OpUpdate)
        ) {
            Copy-Item -LiteralPath $SrcPath -Destination $DstPath
            if ($PassThru) {
                $InvokePlasterInfo.CreatedFiles += $DstPath
            }
            $script:templateCreatedFiles[$DstPath] = $null
        } elseif (
            $Force -or
            $PSCmdlet.ShouldContinue(
                ($LocalizedData.OverwriteFile_F1 -f $DstPath),
                $LocalizedData.FileConflict,
                [ref]$script:fileConflictConfirmYesToAll,
                [ref]$script:fileConflictConfirmNoToAll
            )
        ) {
            $backupFilename = New-BackupFilename $DstPath
            Copy-Item -LiteralPath $DstPath -Destination $backupFilename
            Copy-Item -LiteralPath $SrcPath -Destination $DstPath
            if ($PassThru) {
                $InvokePlasterInfo.UpdatedFiles += $DstPath
            }
            $script:templateCreatedFiles[$DstPath] = $null
        }
    }
}
function Expand-FileSourceSpec {
    [CmdletBinding()]
    param(
        [string]$SourceRelativePath,
        [string]$DestinationRelativePath
    )
    $srcPath = Join-Path $templateAbsolutePath $SourceRelativePath
    $dstPath = Join-Path $destinationAbsolutePath $DestinationRelativePath

    if ($SourceRelativePath.IndexOfAny([char[]]('*', '?')) -lt 0) {
        # No wildcard spec in srcRelPath so return info on single file.
        # Also, if dstRelPath is empty, then use source rel path.
        if (!$DestinationRelativePath) {
            $dstPath = Join-Path $destinationAbsolutePath $SourceRelativePath
        }

        return (New-FileSystemCopyInfo $srcPath $dstPath)
    }

    # Prepare parameter values for call to Get-ChildItem to get list of files
    # based on wildcard spec.
    $gciParams = @{}
    $parent = Split-Path $srcPath -Parent
    $leaf = Split-Path $srcPath -Leaf
    $gciParams['LiteralPath'] = $parent
    $gciParams['File'] = $true

    if ($leaf -eq '**') {
        $gciParams['Recurse'] = $true
    } else {
        if ($leaf.IndexOfAny([char[]]('*', '?')) -ge 0) {
            $gciParams['Filter'] = $leaf
        }

        $leaf = Split-Path $parent -Leaf
        if ($leaf -eq '**') {
            $parent = Split-Path $parent -Parent
            $gciParams['LiteralPath'] = $parent
            $gciParams['Recurse'] = $true
        }
    }

    $srcRelRootPathLength = $gciParams['LiteralPath'].Length

    # Generate a FileCopyInfo object for every file expanded by the wildcard spec.
    $files = @(Microsoft.PowerShell.Management\Get-ChildItem @gciParams)
    foreach ($file in $files) {
        $fileSrcPath = $file.FullName
        $relPath = $fileSrcPath.Substring($srcRelRootPathLength)
        $fileDstPath = Join-Path $dstPath $relPath
        New-FileSystemCopyInfo $fileSrcPath $fileDstPath
    }

    # Copy over empty directories - if any.
    $gciParams.Remove('File')
    $gciParams['Directory'] = $true
    $dirs = @(Microsoft.PowerShell.Management\Get-ChildItem @gciParams |
            Where-Object { $_.GetFileSystemInfos().Length -eq 0 })
    foreach ($dir in $dirs) {
        $dirSrcPath = $dir.FullName
        $relPath = $dirSrcPath.Substring($srcRelRootPathLength)
        $dirDstPath = Join-Path $dstPath $relPath
        New-FileSystemCopyInfo $dirSrcPath $dirDstPath
    }
}
function Get-ColorForOperation {
    param(
        $operation
    )
    switch ($operation) {
        $LocalizedData.OpConflict      { 'Red' }
        $LocalizedData.OpCreate        { 'Green' }
        $LocalizedData.OpForce         { 'Yellow' }
        $LocalizedData.OpIdentical     { 'Cyan' }
        $LocalizedData.OpModify        { 'Magenta' }
        $LocalizedData.OpUpdate        { 'Green' }
        $LocalizedData.OpMissing       { 'Red' }
        $LocalizedData.OpVerify        { 'Green' }
        default { $Host.UI.RawUI.ForegroundColor }
    }
}
function Get-ErrorLocationFileAttrVal {
    param(
        [string]$ElementName,
        [string]$AttributeName
    )
    $LocalizedData.ExpressionErrorLocationFile_F2 -f $ElementName, $AttributeName
}
function Get-ErrorLocationModifyAttrVal {
    param(
        [string]$AttributeName
    )
    $LocalizedData.ExpressionErrorLocationModify_F1 -f $AttributeName
}
function Get-ErrorLocationNewModManifestAttrVal {
    param(
        [string]$AttributeName
    )
    $LocalizedData.ExpressionErrorLocationNewModManifest_F1 -f $AttributeName
}
function Get-ErrorLocationParameterAttrVal {
    param(
        [string]$ParameterName,
        [string]$AttributeName
    )
    $LocalizedData.ExpressionErrorLocationParameter_F2 -f $ParameterName, $AttributeName
}
function Get-ErrorLocationRequireModuleAttrVal {
    param(
        [string]$ModuleName,
        [string]$AttributeName
    )
    $LocalizedData.ExpressionErrorLocationRequireModule_F2 -f $ModuleName, $AttributeName
}
function Get-GitConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$name
    )
    # Very simplistic git config lookup
    # Won't work with namespace, just use final element, e.g. 'name' instead of 'user.name'

    # The $Home dir may not be reachable e.g. if on network share and/or script not running as admin.
    # See issue https://github.com/PowerShell/Plaster/issues/92
    if (!(Test-Path -LiteralPath $Home)) {
        return
    }

    $gitConfigPath = Join-Path $Home '.gitconfig'
    $PSCmdlet.WriteDebug("Looking for '$name' value in Git config: $gitConfigPath")

    if (Test-Path -LiteralPath $gitConfigPath) {
        $matches = Select-String -LiteralPath $gitConfigPath -Pattern "\s+$name\s+=\s+(.+)$"
        if (@($matches).Count -gt 0) {
            $matches.Matches.Groups[1].Value
        }
    }
}
function Get-ManifestsUnderPath {
    <#
    .SYNOPSIS
    Retrieves Plaster manifest files under a specified path.

    .DESCRIPTION
    This function searches for Plaster manifest files (`plasterManifest.xml`)
    under a specified root path and returns template objects created from those
    manifests.

    .PARAMETER RootPath
    The root path to search for Plaster manifest files.

    .PARAMETER Recurse
    Whether to search subdirectories for manifest files.

    .PARAMETER Name
    The name of the template to retrieve.
    If not specified, all templates will be returned.

    .PARAMETER Tag
    The tag of the template to retrieve.
    If not specified, templates with any tag will be returned.

    .EXAMPLE
    Get-ManifestsUnderPath -RootPath "C:\Templates" -Recurse -Name "MyTemplate" -Tag "Tag1"

    Retrieves all Plaster templates named "MyTemplate" with the tag "Tag1"
    under the "C:\Templates" directory and its subdirectories.

    .NOTES
    This is a private function used internally by Plaster to manage templates.
    It is not intended for direct use by end users.
    #>
    [CmdletBinding()]
    param(
        [string]
        $RootPath,
        [bool]
        $Recurse,
        [string]
        $Name,
        [string]
        $Tag
    )
    $getChildItemSplat = @{
        Path = $RootPath
        Include = "plasterManifest.xml", "plasterManifest.json"
        Recurse = $Recurse
    }
    $manifestPaths = Get-ChildItem @getChildItemSplat
    foreach ($manifestPath in $manifestPaths) {
        $newTemplateObjectFromManifestSplat = @{
            ManifestPath = $manifestPath
            Name = $Name
            Tag = $Tag
            ErrorAction = 'SilentlyContinue'
        }
        New-TemplateObjectFromManifest @newTemplateObjectFromManifestSplat
    }
}
function Get-MaxOperationLabelLength {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    (
        $LocalizedData.OpCreate,
        $LocalizedData.OpIdentical,
        $LocalizedData.OpConflict,
        $LocalizedData.OpForce,
        $LocalizedData.OpMissing,
        $LocalizedData.OpModify,
        $LocalizedData.OpUpdate,
        $LocalizedData.OpVerify |
            Measure-Object -Property Length -Maximum).Maximum
}
function Get-ModuleExtension {
    <#
    .SYNOPSIS
    Retrieves module extensions based on specified criteria.

    .DESCRIPTION
    This function retrieves module extensions that match the specified module
    name and version criteria.

    .PARAMETER ModuleName
    The name of the module to retrieve extensions for.

    .PARAMETER ModuleVersion
    The version of the module to retrieve extensions for.

    .PARAMETER ListAvailable
    Indicates whether to list all available modules or only the the latest
    version of each module.

    .EXAMPLE
    Get-ModuleExtension -ModuleName "MyModule" -ModuleVersion "1.0.0"

    Retrieves extensions for the module "MyModule" with version "1.0.0".
    .NOTES

    #>
    [CmdletBinding()]
    param(
        [string]
        $ModuleName,

        [Version]
        $ModuleVersion,

        [Switch]
        $ListAvailable
    )

    # Only get the latest version of each module
    $modules = Get-Module -ListAvailable
    if (!$ListAvailable.IsPresent) {
        $modules = $modules |
            Group-Object Name |
            ForEach-Object {
                $_.group |
                    Sort-Object Version |
                    Select-Object -Last 1
                }
    }

    Write-Verbose "Found $($modules.Length) installed modules to scan for extensions."

    foreach ($module in $modules) {
        if ($module.PrivateData -and
            $module.PrivateData.PSData -and
            $module.PrivateData.PSData.Extensions) {

            Write-Verbose "Found module with extensions: $($module.Name)"

            foreach ($extension in $module.PrivateData.PSData.Extensions) {

                Write-Verbose "Comparing against module extension: $($extension.Module)"

                if ([String]::IsNullOrEmpty($extension.MinimumVersion)) {
                    # Fill with a default value if not specified
                    $minimumVersion = $null
                } else {
                    $minimumVersion = Resolve-ModuleVersionString $extension.MinimumVersion
                }
                if ([String]::IsNullOrEmpty($extension.MaximumVersion)) {
                    # Fill with a default value if not specified
                    $maximumVersion = $null
                } else {
                    $maximumVersion = Resolve-ModuleVersionString $extension.MaximumVersion
                }

                if (($extension.Module -eq $ModuleName) -and
                    (!$minimumVersion -or $ModuleVersion -ge $minimumVersion) -and
                    (!$maximumVersion -or $ModuleVersion -le $maximumVersion)) {
                    # Return a new object with the extension information
                    [PSCustomObject]@{
                        Module = $module
                        MinimumVersion = $minimumVersion
                        MaximumVersion = $maximumVersion
                        Details = $extension.Details
                    }
                }
            }
        }
    }
}
function Get-PlasterManifestPathForCulture {
    <#
    .SYNOPSIS
    Returns the path to the Plaster manifest file for a specific culture.

    .DESCRIPTION
    This function checks for the existence of a Plaster manifest file that
    matches the specified culture. It first looks for a culture-specific
    manifest, then checks for a parent culture manifest, and finally falls back
    to an invariant culture manifest if no specific match is found. The function
    returns the path to the manifest file if found, or $null if no matching
    manifest is found.

    .PARAMETER TemplatePath
    The path to the template directory.
    This should be a fully qualified path to the directory containing the
    Plaster manifest files.

    .PARAMETER Culture
    The culture information for which to retrieve the Plaster manifest file.

    .EXAMPLE
    Get-PlasterManifestPathForCulture -TemplatePath "C:\Templates" -Culture (Get-Culture)

    This example retrieves the path to the Plaster manifest file for the current culture.
    .NOTES
    This is a private function used by Plaster to locate the appropriate
    manifest file based on the specified culture.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param (
        [string]
        $TemplatePath,
        [ValidateNotNull()]
        [CultureInfo]
        $Culture
    )
    if (![System.IO.Path]::IsPathRooted($TemplatePath)) {
        $TemplatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TemplatePath)
    }

    # Check for culture-locale first.
    $plasterManifestBasename = "plasterManifest"
    $plasterManifestFilename = "${plasterManifestBasename}_$($culture.Name).xml"
    $plasterManifestPath = Join-Path $TemplatePath $plasterManifestFilename
    if (Test-Path $plasterManifestPath) {
        return $plasterManifestPath
    }

    # Check for culture next.
    if ($culture.Parent.Name) {
        $plasterManifestFilename = "${plasterManifestBasename}_$($culture.Parent.Name).xml"
        $plasterManifestPath = Join-Path $TemplatePath $plasterManifestFilename
        if (Test-Path $plasterManifestPath) {
            return $plasterManifestPath
        }
    }

    # Fallback to invariant culture manifest.
    $plasterManifestPath = Join-Path $TemplatePath "${plasterManifestBasename}.xml"
    if (Test-Path $plasterManifestPath) {
        return $plasterManifestPath
    }

    # If no manifest is found, return $null.
    # TODO: Should we throw an error instead?
    return $null
}
function Get-PlasterManifestType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest file not found: $ManifestPath"
    }

    try {
        $content = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop

        # Check file extension first
        $extension = [System.IO.Path]::GetExtension($ManifestPath).ToLower()
        if ($extension -eq '.json') {
            # Validate it's actually JSON
            try {
                $jsonObject = $content | ConvertFrom-Json -ErrorAction Stop
                # Check for Plaster 2.0 JSON schema
                if ($jsonObject.schemaVersion -eq '2.0') {
                    return 'JSON'
                }
                # Also accept older JSON formats without strict version check
                if ($jsonObject.PSObject.Properties['metadata'] -and $jsonObject.PSObject.Properties['content']) {
                    return 'JSON'
                }
            } catch {
                throw "File has .json extension but contains invalid JSON: $($_.Exception.Message)"
            }
        } elseif ($extension -eq '.xml') {
            # Validate it's actually XML
            try {
                $xmlDoc = New-Object System.Xml.XmlDocument
                $xmlDoc.LoadXml($content)
                if ($xmlDoc.DocumentElement.LocalName -eq 'plasterManifest') {
                    return 'XML'
                }
            } catch {
                throw "File has .xml extension but contains invalid XML: $($_.Exception.Message)"
            }
        }

        # If no extension or ambiguous, try to detect by content
        $trimmedContent = $content.TrimStart()

        # Check for JSON format (starts with { or [)
        if ($trimmedContent -match '^[\s]*[\{\[]') {
            try {
                $jsonObject = $content | ConvertFrom-Json -ErrorAction Stop
                # Validate it's a Plaster JSON manifest
                if ($jsonObject.PSObject.Properties['metadata'] -and $jsonObject.PSObject.Properties['content']) {
                    return 'JSON'
                }
            } catch {
                # Not valid JSON, continue to XML check
            }
        }

        # Check for XML format
        if ($trimmedContent -match '^[\s]*<\?xml' -or $trimmedContent -match '<plasterManifest') {
            try {
                $xmlDoc = New-Object System.Xml.XmlDocument
                $xmlDoc.LoadXml($content)
                if ($xmlDoc.DocumentElement.LocalName -eq 'plasterManifest') {
                    return 'XML'
                }
            } catch {
                # Not valid XML
            }
        }

        throw "Unable to determine manifest format. File must be valid XML or JSON."
    } catch {
        throw "Error determining manifest type for '$ManifestPath': $($_.Exception.Message)"
    }
}
function Get-PSSnippetFunction {
    param(
        [String]$FilePath
    )

    # Test if Path Exists
    if (!(Test-Path $substitute -PathType Leaf)) {
        throw ($LocalizedData.ErrorPathDoesNotExist_F1 -f $FilePath)
    }
    # Load File
    return Get-Content -LiteralPath $substitute -Raw
}
function Initialize-PredefinedVariables {
    <#
    .SYNOPSIS
    Initializes predefined variables used by Plaster.

    .DESCRIPTION
    This function sets up several predefined variables that are used throughout
    the Plaster template processing. It includes variables for the template
    path, destination path, and other relevant information.

    .PARAMETER TemplatePath
    The file system path to the Plaster template directory.

    .PARAMETER DestPath
    The file system path to the destination directory.

    .EXAMPLE
    Initialize-PredefinedVariables -TemplatePath "C:\Templates\MyTemplate" -DestPath "C:\Projects\MyProject"

    This example initializes the predefined variables with the specified
    template and destination paths.
    .NOTES
    This function is typically called at the beginning of the Plaster template
    processing to ensure that all necessary variables are set up before any
    template processing occurs.
    #>
    [CmdletBinding()]
    param(
        [string]
        $TemplatePath,
        [string]
        $DestPath
    )

    # Always set these variables, even if the command has been run with -WhatIf
    $WhatIfPreference = $false

    Set-Variable -Name PLASTER_TemplatePath -Value $TemplatePath.TrimEnd('\', '/') -Scope Script

    $destName = Split-Path -Path $DestPath -Leaf
    Set-Variable -Name PLASTER_DestinationPath -Value $DestPath.TrimEnd('\', '/') -Scope Script
    Set-Variable -Name PLASTER_DestinationName -Value $destName -Scope Script
    Set-Variable -Name PLASTER_DirSepChar      -Value ([System.IO.Path]::DirectorySeparatorChar) -Scope Script
    Set-Variable -Name PLASTER_HostName        -Value $Host.Name -Scope Script
    Set-Variable -Name PLASTER_Version         -Value $MyInvocation.MyCommand.Module.Version -Scope Script

    Set-Variable -Name PLASTER_Guid1 -Value ([Guid]::NewGuid()) -Scope Script
    Set-Variable -Name PLASTER_Guid2 -Value ([Guid]::NewGuid()) -Scope Script
    Set-Variable -Name PLASTER_Guid3 -Value ([Guid]::NewGuid()) -Scope Script
    Set-Variable -Name PLASTER_Guid4 -Value ([Guid]::NewGuid()) -Scope Script
    Set-Variable -Name PLASTER_Guid5 -Value ([Guid]::NewGuid()) -Scope Script

    $now = [DateTime]::Now
    Set-Variable -Name PLASTER_Date -Value ($now.ToShortDateString()) -Scope Script
    Set-Variable -Name PLASTER_Time -Value ($now.ToShortTimeString()) -Scope Script
    Set-Variable -Name PLASTER_Year -Value ($now.Year) -Scope Script
}
function Invoke-ExpressionImpl {
    [CmdletBinding()]
    param (
        [string]$Expression
    )
    try {
        $powershell = [PowerShell]::Create()

        if ($null -eq $constrainedRunspace) {
            $constrainedRunspace = New-ConstrainedRunspace
        }
        $powershell.Runspace = $constrainedRunspace

        try {
            $powershell.AddScript($Expression) > $null
            $res = $powershell.Invoke()

            # Enhanced logging for JSON expressions
            if ($Expression -match '\$\{.*\}' -and $manifestType -eq 'JSON') {
                Write-PlasterLog -Level Debug -Message "JSON expression evaluated: $Expression -> $res"
            }

            return $res
        } catch {
            throw ($LocalizedData.ExpressionInvalid_F2 -f $Expression, $_)
        }

        if ($powershell.Streams.Error.Count -gt 0) {
            $err = $powershell.Streams.Error[0]
            throw ($LocalizedData.ExpressionNonTermErrors_F2 -f $Expression, $err)
        }
    } finally {
        if ($powershell) {
            $powershell.Dispose()
        }
    }
}
# Enhanced error handling wrapper
function Invoke-PlasterOperation {
    <#
    .SYNOPSIS
    Wraps the execution of a script block with enhanced error handling and
    logging capabilities.

    .DESCRIPTION
    This function wraps the execution of a script block with enhanced error
    handling and logging capabilities.

    .PARAMETER ScriptBlock
    The script block to execute.

    .PARAMETER OperationName
    The name of the operation being performed.

    .PARAMETER PassThru
    If specified, the output of the script block output will be returned.

    .EXAMPLE
    Invoke-PlasterOperation -ScriptBlock { Get-Process } -OperationName 'GetProcesses' -PassThru

    This example executes the `Get-Process` cmdlet within the context of the
    `Invoke-PlasterOperation` function, logging the operation and returning the
    output.

    .NOTES
    This function is designed to be used within the Plaster module to ensure
    consistent logging and error handling across various operations.
    It is not intended for direct use outside of the Plaster context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]
        $ScriptBlock,

        [string]
        $OperationName = 'PlasterOperation',

        [switch]
        $PassThru
    )
    try {
        Write-PlasterLog -Level Debug -Message "Starting operation: $OperationName"
        $result = & $ScriptBlock
        Write-PlasterLog -Level Debug -Message "Completed operation: $OperationName"

        if ($PassThru) {
            return $result
        }
    } catch {
        $errorMessage = "Operation '$OperationName' failed: $($_.Exception.Message)"
        Write-PlasterLog -Level Error -Message $errorMessage
        throw $_
    }
}
function New-BackupFilename {
    [CmdletBinding()]
    param(
        [string]$Path
    )
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    $filename = [System.IO.Path]::GetFileName($Path)
    $backupPath = Join-Path -Path $dir -ChildPath "${filename}.bak"
    $i = 1
    while (Test-Path -LiteralPath $backupPath) {
        $backupPath = Join-Path -Path $dir -ChildPath "${filename}.bak$i"
        $i++
    }

    $backupPath
}
function New-ConstrainedRunspace {
    [CmdletBinding()]
    param ()
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
    if (!$IsCoreCLR) {
        $iss.ApartmentState = [System.Threading.ApartmentState]::STA
    }
    $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage
    $iss.DisableFormatUpdates = $true

    # Add providers
    $sspe = New-Object System.Management.Automation.Runspaces.SessionStateProviderEntry 'Environment', ([Microsoft.PowerShell.Commands.EnvironmentProvider]), $null
    $iss.Providers.Add($sspe)

    $sspe = New-Object System.Management.Automation.Runspaces.SessionStateProviderEntry 'FileSystem', ([Microsoft.PowerShell.Commands.FileSystemProvider]), $null
    $iss.Providers.Add($sspe)

    # Add cmdlets with enhanced set for JSON processing
    $cmdlets = @(
        'Get-Content', 'Get-Date', 'Get-ChildItem', 'Get-Item', 'Get-ItemProperty',
        'Get-Module', 'Get-Variable', 'Test-Path', 'Out-String', 'Compare-Object',
        'ConvertFrom-Json', 'ConvertTo-Json'  # JSON support
    )

    foreach ($cmdletName in $cmdlets) {
        #$cmdletType = [Microsoft.PowerShell.Commands.GetContentCommand].Assembly.GetType("Microsoft.PowerShell.Commands.$($cmdletName -replace '-')Command")
        $cmdletType = "Microsoft.PowerShell.Commands.$($cmdletName -replace '-')Command" -as [Type]
        if ($cmdletType) {
            $ssce = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry $cmdletName, $cmdletType, $null
            $iss.Commands.Add($ssce)
        }
    }

    # Add enhanced variable set including JSON manifest type
    $scopedItemOptions = [System.Management.Automation.ScopedItemOptions]::AllScope
    $plasterVars = Get-Variable -Name PLASTER_*, PSVersionTable

    # Add platform detection variables
    if (Test-Path Variable:\IsLinux) { $plasterVars += Get-Variable -Name IsLinux }
    if (Test-Path Variable:\IsOSX) { $plasterVars += Get-Variable -Name IsOSX }
    if (Test-Path Variable:\IsMacOS) { $plasterVars += Get-Variable -Name IsMacOS }
    if (Test-Path Variable:\IsWindows) { $plasterVars += Get-Variable -Name IsWindows }

    # Add manifest type variable (new for 2.0)
    $manifestTypeVar = New-Object System.Management.Automation.PSVariable 'PLASTER_ManifestType', $manifestType, 'None'
    $plasterVars += $manifestTypeVar

    foreach ($var in $plasterVars) {
        $ssve = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry `
            $var.Name, $var.Value, $var.Description, $scopedItemOptions
        $iss.Variables.Add($ssve)
    }

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $runspace.Open()
    if ($destinationAbsolutePath) {
        $runspace.SessionStateProxy.Path.SetLocation($destinationAbsolutePath) > $null
    }

    Write-PlasterLog -Level Debug -Message "Created enhanced constrained runspace with $manifestType support"
    return $runspace
}
function New-FileSystemCopyInfo {
    [CmdletBinding()]
    param(
        [string]$srcPath,
        [string]$dstPath
    )
    [PSCustomObject]@{
        SrcFileName = $srcPath
        DstFileName = $dstPath
    }
}
function New-JsonManifestStructure {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,

        [Parameter(Mandatory)]
        [string]$TemplateType,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$TemplateVersion = "1.0.0",

        [Parameter()]
        [string]$Title = $TemplateName,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [string]$Author = "",

        [Parameter()]
        [string[]]$Tags = @()
    )

    $manifest = [ordered]@{
        '$schema' = 'https://raw.githubusercontent.com/PowerShellOrg/Plaster/v2/schema/plaster-manifest-v2.json'
        'schemaVersion' = '2.0'
        'metadata' = [ordered]@{
            'name' = $TemplateName
            'id' = $Id
            'version' = $TemplateVersion
            'title' = $Title
            'description' = $Description
            'author' = $Author
            'templateType' = $TemplateType
        }
        'parameters' = @()
        'content' = @()
    }

    if ($Tags.Count -gt 0) {
        $manifest.metadata['tags'] = $Tags
    }

    return $manifest
}
function New-TemplateObjectFromManifest {
    <#
    .SYNOPSIS
    Creates a Plaster template object from a manifest file.

    .DESCRIPTION
    This function takes a path to a Plaster manifest file and creates a
    template object from its contents.

    .PARAMETER ManifestPath
    The path to the Plaster manifest file.

    .PARAMETER Name
    The name of the template.
    If not specified, all templates will be returned.

    .PARAMETER Tag
    The tag of the template.
    If not specified, templates with any tag will be returned.

    .EXAMPLE
    Get-TemplateObjectFromManifest -ManifestPath "C:\Templates\MyTemplate\plasterManifest.xml" -Name "MyTemplate" -Tag "Tag1"

    Retrieves a template object for the specified manifest file with the given name and tag.
    .NOTES
    This function is used internally by Plaster to manage templates.
    It is not intended for direct use by end users.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [System.IO.FileInfo]$ManifestPath,
        [string]$Name,
        [string]$Tag
    )

    try{
        $manifestXml = Test-PlasterManifest -Path $ManifestPath
        $metadata = $manifestXml["plasterManifest"]["metadata"]

        $manifestObj = [PSCustomObject]@{
            Name = [string]$metadata.name
            Title = [string]$metadata.title
            Author = [string]$metadata.author
            Version = [System.Version]::Parse([string]$metadata.version)
            Description  = if ($metadata.description) { [string]$metadata.description } else { "" }
                        Tags         = if ($metadata.tags) { ([string]$metadata.tags).split(",") | ForEach-Object { $_.Trim() } } else { @() }
                        TemplatePath = $manifestPath.Directory.FullName
                        Format       = if ($manifestPath.Extension -eq '.json') { 'JSON' } else { 'XML' }
        }

        $manifestObj.PSTypeNames.Insert(0, "Microsoft.PowerShell.Plaster.PlasterTemplate")
        $addMemberSplat = @{
            MemberType = 'ScriptMethod'
            InputObject = $manifestObj
            Name = "InvokePlaster"
            Value = { Invoke-Plaster -TemplatePath $this.TemplatePath }
        }
        Add-Member @addMemberSplat

        # Fix the filtering logic
        $result = $manifestObj
        if ($name -and $name -ne "*") {
            $result = $result | Where-Object Name -like $name
        }
        if ($tag -and $tag -ne "*") {
            # Only filter by tags if the template actually has tags
            if ($result.Tags -and $result.Tags.Count -gt 0) {
                $result = $result | Where-Object { $_.Tags -contains $tag -or ($_.Tags | Where-Object { $_ -like $tag }) }
            } elseif ($tag -ne "*") {
                # If template has no tags but we're filtering for a specific tag, exclude it
                $result = $null
            }
        }
        return $result
    } catch {
        Write-Debug "Failed to process manifest at $($manifestPath.FullName): $($_.Exception.Message)"
        return $null
    }
}
function Read-PromptForChoice {
    [CmdletBinding()]
    param(
        [string]
        $ParameterName,
        [ValidateNotNull()]
        $ChoiceNodes,
        [string]
        $prompt,
        [int[]]
        $defaults,
        [switch]
        $IsMultiChoice
    )
    $choices = New-Object 'System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]'
    $values = New-Object object[] $ChoiceNodes.Count
    $i = 0

    foreach ($choiceNode in $ChoiceNodes) {
        $label = Resolve-AttributeValue $choiceNode.label (Get-ErrorLocationParameterAttrVal $ParameterName label)
        $help = Resolve-AttributeValue $choiceNode.help  (Get-ErrorLocationParameterAttrVal $ParameterName help)
        $value = Resolve-AttributeValue $choiceNode.value (Get-ErrorLocationParameterAttrVal $ParameterName value)

        $choice = New-Object System.Management.Automation.Host.ChoiceDescription -Arg $label, $help
        $choices.Add($choice)
        $values[$i++] = $value
    }

    $returnValue = [PSCustomObject]@{Values = @(); Indices = @() }

    if ($IsMultiChoice) {
        $selections = $Host.UI.PromptForChoice('', $prompt, $choices, $defaults)
        foreach ($selection in $selections) {
            $returnValue.Values += $values[$selection]
            $returnValue.Indices += $selection
        }
    } else {
        if ($defaults.Count -gt 1) {
            throw ($LocalizedData.ParameterTypeChoiceMultipleDefault_F1 -f $ChoiceNodes.ParentNode.name)
        }

        $selection = $Host.UI.PromptForChoice('', $prompt, $choices, $defaults[0])
        $returnValue.Values = $values[$selection]
        $returnValue.Indices = $selection
    }

    $returnValue
}
function Read-PromptForInput {
    [CmdletBinding()]
    param(
        $prompt,
        $default,
        $pattern
    )
    if (!$pattern) {
        $patternMatch = $true
    }

    do {
        $value = Read-Host -Prompt $prompt
        if (!$value -and $default) {
            $value = $default
            $patternMatch = $true
        } elseif ($value -and $pattern) {
            if ($value -match $pattern) {
                $patternMatch = $true
            } else {
                $PSCmdlet.WriteDebug("Value '$value' did not match the pattern '$pattern'")
            }
        }
    } while (!$value -or !$patternMatch)

    $value
}
function Resolve-AttributeValue {
    [CmdletBinding()]
    param(
        [string]$Value,
        [string]$Location
    )

    if ($null -eq $Value) {
        return [string]::Empty
    } elseif ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    try {
        # Handle both XML-style ${PLASTER_PARAM_Name} and JSON-style ${Name} variables
        if ($manifestType -eq 'JSON') {
            # Convert JSON-style variables to XML-style for processing
            $Value = $Value -replace '\$\{(?!PLASTER_)([A-Za-z][A-Za-z0-9_]*)\}', '${PLASTER_PARAM_$1}'
        }

        $res = @(Invoke-ExpressionImpl "`"$Value`"")
        [string]$res[0]
    } catch {
        throw ($LocalizedData.InterpolationError_F3 -f $Value.Trim(), $Location, $_)
    }
}
function Resolve-ModuleVersionString {
    <#
    .SYNOPSIS
    Resolve a module version string to a System.Version or
    System.Management.Automation.SemanticVersion object.

    .DESCRIPTION
    This function takes a version string and returns a parsed version object.
    It ensures that the version string is in a valid format, particularly for
    Semantic Versioning 2.0, which requires at least three components
    (major.minor.patch). If the patch component is missing, the function will
    append ".0" to the version string.

    .PARAMETER versionString
    The version string to resolve.

    .EXAMPLE
    Resolve-ModuleVersionString -versionString "1.2"

    This example resolves the version string "1.2" to a valid version object.
    .NOTES
    This function is designed to be used within the Plaster module to ensure consistent version handling.
    It is not intended for direct use outside of the Plaster context.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        $VersionString
    )

    # We're targeting Semantic Versioning 2.0 so make sure the version has
    # at least 3 components (X.X.X).  This logic ensures that the "patch"
    # (third) component has been specified.
    $versionParts = $VersionString.Split('.')
    if ($versionParts.Length -lt 3) {
        $VersionString = "$VersionString.0"
    }

    if ($PSVersionTable.PSEdition -eq "Core") {
        $newObjectSplat = @{
            TypeName = "System.Management.Automation.SemanticVersion"
            ArgumentList = $VersionString
        }
        return New-Object @newObjectSplat
    } else {
        $newObjectSplat = @{
            TypeName = "System.Version"
            ArgumentList = $VersionString
        }
        return New-Object @newObjectSplat
    }
}
function Resolve-ProcessMessage {
    [CmdletBinding()]
    param(
        [ValidateNotNull()]
        $Node
    )
    $text = Resolve-AttributeValue $Node.InnerText '<message>'
    $noNewLine = $Node.nonewline -eq 'true'

    # Eliminate whitespace before and after the text that just happens to get inserted because you want
    # the text on different lines than the start/end element tags.
    $trimmedText = $text -replace '^[ \t]*\n', '' -replace '\n[ \t]*$', ''

    $condition = $Node.condition
    if ($condition -and !(Test-ConditionAttribute $condition "'<$($Node.LocalName)>'")) {
        $debugText = $trimmedText -replace '\r|\n', ' '
        $maxLength = [Math]::Min(40, $debugText.Length)
        $PSCmdlet.WriteDebug("Skipping message '$($debugText.Substring(0, $maxLength))', condition evaluated to false.")
        return
    }

    Write-Host $trimmedText -NoNewline:($noNewLine -eq 'true')
}
function Resolve-ProcessNewModuleManifest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateNotNull()]$Node
    )
    $moduleVersion = Resolve-AttributeValue $Node.moduleVersion (Get-ErrorLocationNewModManifestAttrVal moduleVersion)
    $rootModule = Resolve-AttributeValue $Node.rootModule (Get-ErrorLocationNewModManifestAttrVal rootModule)
    $author = Resolve-AttributeValue $Node.author (Get-ErrorLocationNewModManifestAttrVal author)
    $companyName = Resolve-AttributeValue $Node.companyName (Get-ErrorLocationNewModManifestAttrVal companyName)
    $description = Resolve-AttributeValue $Node.description (Get-ErrorLocationNewModManifestAttrVal description)
    $dstRelPath = Resolve-AttributeValue $Node.destination (Get-ErrorLocationNewModManifestAttrVal destination)
    $powerShellVersion = Resolve-AttributeValue $Node.powerShellVersion (Get-ErrorLocationNewModManifestAttrVal powerShellVersion)
    $nestedModules = Resolve-AttributeValue $Node.NestedModules (Get-ErrorLocationNewModManifestAttrVal NestedModules)
    $dscResourcesToExport = Resolve-AttributeValue $Node.DscResourcesToExport (Get-ErrorLocationNewModManifestAttrVal DscResourcesToExport)
    $copyright = Resolve-AttributeValue $Node.copyright (Get-ErrorLocationNewModManifestAttrVal copyright)

    # We could choose to not check this if the condition eval'd to false
    # but I think it is better to let the template author know they've broken the
    # rules for any of the file directives (not just the ones they're testing/enabled).
    if ([System.IO.Path]::IsPathRooted($dstRelPath)) {
        throw ($LocalizedData.ErrorPathMustBeRelativePath_F2 -f $dstRelPath, $Node.LocalName)
    }

    $dstPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath((Join-Path $DestinationPath $dstRelPath))

    $condition = $Node.condition
    if ($condition -and !(Test-ConditionAttribute $condition "'<$($Node.LocalName)>'")) {
        $PSCmdlet.WriteDebug("Skipping module manifest generation for '$dstPath', condition evaluated to false.")
        return
    }

    $encoding = $Node.encoding
    if (!$encoding) {
        $encoding = $DefaultEncoding
    }

    if ($PSCmdlet.ShouldProcess($dstPath, $LocalizedData.ShouldProcessNewModuleManifest)) {
        $manifestDir = Split-Path $dstPath -Parent
        if (!(Test-Path $manifestDir)) {
            Test-PathIsUnderDestinationPath $manifestDir
            Write-Verbose ($LocalizedData.NewModManifest_CreatingDir_F1 -f $manifestDir)
            New-Item $manifestDir -ItemType Directory > $null
        }

        $newModuleManifestParams = @{}

        # If there is an existing module manifest, load it so we can reuse old values not specified by
        # template.
        if (Test-Path -LiteralPath $dstPath) {
            $manifestFileName = Split-Path $dstPath -Leaf
            $newModuleManifestParams = Import-LocalizedData -BaseDirectory $manifestDir -FileName $manifestFileName
            if ($newModuleManifestParams.PrivateData) {
                $newModuleManifestParams += $newModuleManifestParams.PrivateData.psdata
                $newModuleManifestParams.Remove('PrivateData')
            }
        }

        if (![string]::IsNullOrWhiteSpace($moduleVersion)) {
            $newModuleManifestParams['ModuleVersion'] = $moduleVersion
        }
        if (![string]::IsNullOrWhiteSpace($rootModule)) {
            $newModuleManifestParams['RootModule'] = $rootModule
        }
        if (![string]::IsNullOrWhiteSpace($author)) {
            $newModuleManifestParams['Author'] = $author
        }
        if (![string]::IsNullOrWhiteSpace($companyName)) {
            $newModuleManifestParams['CompanyName'] = $companyName
        }
        if (![string]::IsNullOrWhiteSpace($copyright)) {
            $newModuleManifestParams['Copyright'] = $copyright
        }
        if (![string]::IsNullOrWhiteSpace($description)) {
            $newModuleManifestParams['Description'] = $description
        }
        if (![string]::IsNullOrWhiteSpace($powerShellVersion)) {
            $newModuleManifestParams['PowerShellVersion'] = $powerShellVersion
        }
        if (![string]::IsNullOrWhiteSpace($nestedModules)) {
            $newModuleManifestParams['NestedModules'] = $nestedModules
        }
        if (![string]::IsNullOrWhiteSpace($dscResourcesToExport)) {
            $newModuleManifestParams['DscResourcesToExport'] = $dscResourcesToExport
        }

        $tempFile = $null

        try {
            $tempFileBaseName = "moduleManifest-" + [Guid]::NewGuid()
            $tempFile = [System.IO.Path]::GetTempPath() + "${tempFileBaseName}.psd1"
            $PSCmdlet.WriteDebug("Created temp file for new module manifest - $tempFile")
            $newModuleManifestParams['Path'] = $tempFile

            # Generate manifest into a temp file.
            New-ModuleManifest @newModuleManifestParams

            # Typically the manifest is re-written with a new encoding (UTF8-NoBOM) because Git hates UTF-16.
            $content = Get-Content -LiteralPath $tempFile -Raw

            # Replace the temp filename in the generated manifest file's comment header with the actual filename.
            $dstBaseName = [System.IO.Path]::GetFileNameWithoutExtension($dstPath)
            $content = $content -replace "(?<=\s*#.*?)$tempFileBaseName", $dstBaseName

            Write-ContentWithEncoding -Path $tempFile -Content $content -Encoding $encoding

            Copy-FileWithConflictDetection $tempFile $dstPath

            if ($PassThru -and ($Node.openInEditor -eq 'true')) {
                $InvokePlasterInfo.OpenFiles += $dstPath
            }
        } finally {
            if ($tempFile -and (Test-Path $tempFile)) {
                Remove-Item -LiteralPath $tempFile
                $PSCmdlet.WriteDebug("Removed temp file for new module manifest - $tempFile")
            }
        }
    }
}
function Resolve-ProcessParameter {
    [CmdletBinding()]
    param(
        [ValidateNotNull()]$Node
    )

    $name = $Node.name
    $type = $Node.type
    $store = $Node.store

    $pattern = $Node.pattern

    $condition = $Node.condition

    $default = Resolve-AttributeValue $Node.default (Get-ErrorLocationParameterAttrVal $name default)

    if ($condition -and !(Test-ConditionAttribute $condition "'<$($Node.LocalName)>'")) {
        if (-not [string]::IsNullOrEmpty($default) -and $type -eq 'text') {
            Set-PlasterVariable -Name $name -Value $default -IsParam $true
            $PSCmdlet.WriteDebug("The condition of the parameter $($name) with the type 'text' evaluated to false. The parameter has a default value which will be used.")
        } else {
            # Define the parameter so later conditions can use it but its value will be $null
            Set-PlasterVariable -Name $name -Value $null -IsParam $true
            $PSCmdlet.WriteDebug("Skipping parameter $($name), condition evaluated to false.")
        }

        return
    }

    $prompt = Resolve-AttributeValue $Node.prompt (Get-ErrorLocationParameterAttrVal $name prompt)

    # Check if parameter was provided via a dynamic parameter.
    if ($script:boundParameters.ContainsKey($name)) {
        $value = $script:boundParameters[$name]
    } else {
        # Not a dynamic parameter so prompt user for the value but first check for a stored default value.
        if ($store -and ($null -ne $script:defaultValueStore[$name])) {
            $default = $script:defaultValueStore[$name]
            $PSCmdlet.WriteDebug("Read default value '$default' for parameter '$name' from default value store.")

            if (($store -eq 'encrypted') -and ($default -is [System.Security.SecureString])) {
                try {
                    $cred = New-Object -TypeName PSCredential -ArgumentList 'jsbplh', $default
                    $default = $cred.GetNetworkCredential().Password
                    $PSCmdlet.WriteDebug("Unencrypted default value for parameter '$name'.")
                } catch [System.Exception] {
                    Write-Warning ($LocalizedData.ErrorUnencryptingSecureString_F1 -f $name)
                }
            }
        }

        # If the prompt message failed to evaluate or was empty, supply a diagnostic prompt message
        if (!$prompt) {
            $prompt = $LocalizedData.MissingParameterPrompt_F1 -f $name
        }

        # Some default values might not come from the template e.g. some are harvested from .gitconfig if it exists.
        $defaultNotFromTemplate = $false

        $splat = @{}

        if ($null -ne $pattern) {
            $splat.Add('pattern', $pattern)
        }

        # Now prompt user for parameter value based on the parameter type.
        switch -regex ($type) {
            'text' {
                # Display an appropriate "default" value in the prompt string.
                if ($default) {
                    if ($store -eq 'encrypted') {
                        $obscuredDefault = $default -replace '(....).*', '$1****'
                        $prompt += " ($obscuredDefault)"
                    } else {
                        $prompt += " ($default)"
                    }
                }
                # Prompt the user for text input.
                $value = Read-PromptForInput $prompt $default @splat
                $valueToStore = $value
            }
            'user-fullname' {
                # If no default, try to get a name from git config.
                if (!$default) {
                    $default = Get-GitConfigValue('name')
                    $defaultNotFromTemplate = $true
                }

                if ($default) {
                    if ($store -eq 'encrypted') {
                        $obscuredDefault = $default -replace '(....).*', '$1****'
                        $prompt += " ($obscuredDefault)"
                    } else {
                        $prompt += " ($default)"
                    }
                }

                # Prompt the user for text input.
                $value = Read-PromptForInput $prompt $default @splat
                $valueToStore = $value
            }
            'user-email' {
                # If no default, try to get an email from git config
                if (-not $default) {
                    $default = Get-GitConfigValue('email')
                    $defaultNotFromTemplate = $true
                }

                if ($default) {
                    if ($store -eq 'encrypted') {
                        $obscuredDefault = $default -replace '(....).*', '$1****'
                        $prompt += " ($obscuredDefault)"
                    } else {
                        $prompt += " ($default)"
                    }
                }

                # Prompt the user for text input.
                $value = Read-PromptForInput $prompt $default @splat
                $valueToStore = $value
            }
            'choice|multichoice' {
                $choices = $Node.ChildNodes
                $defaults = [int[]]($default -split ',')

                # Prompt the user for choice or multichoice selection input.
                $selections = Read-PromptForChoice $name $choices $prompt $defaults -IsMultiChoice:($type -eq 'multichoice')
                $value = $selections.Values
                $OFS = ","
                $valueToStore = "$($selections.Indices)"
            }
            default { throw ($LocalizedData.UnrecognizedParameterType_F2 -f $type, $Node.LocalName) }
        }

        # If parameter specifies that user's input be stored as the default value,
        # store it to file if the value has changed.
        if ($store -and (($default -ne $valueToStore) -or $defaultNotFromTemplate)) {
            if ($store -eq 'encrypted') {
                $PSCmdlet.WriteDebug("Storing new, encrypted default value for parameter '$name' to default value store.")
                $script:defaultValueStore[$name] = ConvertTo-SecureString -String $valueToStore -AsPlainText -Force
            } else {
                $PSCmdlet.WriteDebug("Storing new default value '$valueToStore' for parameter '$name' to default value store.")
                $script:defaultValueStore[$name] = $valueToStore
            }

            $script:flags.DefaultValueStoreDirty = $true
        }
    }

    # Make template defined parameters available as a PowerShell variable PLASTER_PARAM_<parameterName>.
    Set-PlasterVariable -Name $name -Value $value -IsParam $true
    Write-PlasterLog -Level Debug -Message "Set parameter variable: PLASTER_PARAM_$name = $value"
}
function Set-PlasterVariable {
    <#
    .SYNOPSIS
    Sets a Plaster variable in the script scope and updates the
    ConstrainedRunspace if it exists.

    .DESCRIPTION
    This function sets a variable in the script scope and updates the
    ConstrainedRunspace if it exists. It is used to manage Plaster variables,
    which can be parameters or other types of variables.

    .PARAMETER Name
    The name of the variable to set.

    .PARAMETER Value
    The value to assign to the variable.

    .PARAMETER IsParam
    Indicates if the variable is a parameter.
    If true, the variable is treated as a Plaster parameter and prefixed with
    "PLASTER_PARAM_".

    .EXAMPLE
    Set-PlasterVariable -Name "MyVariable" -Value "MyValue" -IsParam $true

    Sets a Plaster parameter variable named "PLASTER_PARAM_MyVariable" with the
    value "MyValue".
    .NOTES
    All Plaster variables should be set via this method so that the
    ConstrainedRunspace can be configured to use the new variable. This method
    will null out the ConstrainedRunspace so that later, when we need to
    evaluate script in that runspace, it will get recreated first with all
    the latest Plaster variables.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter()]
        [bool]
        $IsParam = $true
    )

    # Variables created from a <parameter> in the Plaster manifest are prefixed
    # PLASTER_PARAM all others are just PLASTER_.
    $variableName = if ($IsParam) { "PLASTER_PARAM_$Name" } else { "PLASTER_$Name" }

    Set-Variable -Name $variableName -Value $Value -Scope Script -WhatIf:$false

    # If the constrained runspace has been created, it needs to be disposed so that the next string
    # expansion (or condition eval) gets an updated runspace that contains this variable or its new value.
    if ($null -ne $script:ConstrainedRunspace) {
        $script:ConstrainedRunspace.Dispose()
        $script:ConstrainedRunspace = $null
    }
}
# Processes both the <file> and <templateFile> directives.
function Start-ProcessFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateNotNull()]
        $Node
    )
    $srcRelPath = Resolve-AttributeValue $Node.source (Get-ErrorLocationFileAttrVal $Node.localName source)
    $dstRelPath = Resolve-AttributeValue $Node.destination (Get-ErrorLocationFileAttrVal $Node.localName destination)

    $condition = $Node.condition
    if ($condition -and !(Test-ConditionAttribute $condition "'<$($Node.LocalName)>'")) {
        $PSCmdlet.WriteDebug("Skipping $($Node.localName) '$srcRelPath' -> '$dstRelPath', condition evaluated to false.")
        return
    }

    # Only validate paths for conditions that evaluate to true.
    # The path may not be valid if it evaluates to false depending
    # on whether or not conditional parameters are used in the template.
    if ([System.IO.Path]::IsPathRooted($srcRelPath)) {
        throw ($LocalizedData.ErrorPathMustBeRelativePath_F2 -f $srcRelPath, $Node.LocalName)
    }

    if ([System.IO.Path]::IsPathRooted($dstRelPath)) {
        throw ($LocalizedData.ErrorPathMustBeRelativePath_F2 -f $dstRelPath, $Node.LocalName)
    }

    # Check if node is the specialized, <templateFile> node.
    # Only <templateFile> nodes expand templates and use the encoding attribute.
    $isTemplateFile = $Node.localName -eq 'templateFile'
    if ($isTemplateFile) {
        $encoding = $Node.encoding
        if (!$encoding) {
            $encoding = $DefaultEncoding
        }
    }

    # Check if source specifies a wildcard and if so, expand the wildcard
    # and then process each file system object (file or empty directory).
    $expandFileSourceSpecSplat = @{
        SourceRelativePath = $srcRelPath
        DestinationRelativePath = $dstRelPath
    }
    $fileSystemCopyInfoObjs = Expand-FileSourceSpec @expandFileSourceSpecSplat
    foreach ($fileSystemCopyInfo in $fileSystemCopyInfoObjs) {
        $srcPath = $fileSystemCopyInfo.SrcFileName
        $dstPath = $fileSystemCopyInfo.DstFileName

        # The file's destination path must be under the DestinationPath specified by the user.
        Test-PathIsUnderDestinationPath $dstPath

        # Check to see if we're copying an empty dir
        if (Test-Path -LiteralPath $srcPath -PathType Container) {
            if (!(Test-Path -LiteralPath $dstPath)) {
                if ($PSCmdlet.ShouldProcess($parentDir, $LocalizedData.ShouldProcessCreateDir)) {
                    Write-OperationStatus $LocalizedData.OpCreate `
                    ($dstRelPath.TrimEnd(([char]'\'), ([char]'/')) + [System.IO.Path]::DirectorySeparatorChar)
                    New-Item -Path $dstPath -ItemType Directory > $null
                }
            }

            continue
        }

        # If the file's parent dir doesn't exist, create it.
        $parentDir = Split-Path $dstPath -Parent
        if (!(Test-Path -LiteralPath $parentDir)) {
            if ($PSCmdlet.ShouldProcess($parentDir, $LocalizedData.ShouldProcessCreateDir)) {
                New-Item -Path $parentDir -ItemType Directory > $null
            }
        }

        $tempFile = $null

        try {
            # If processing a <templateFile>, copy to a temp file to expand the template file,
            # then apply the normal file conflict detection/resolution handling.
            $target = $LocalizedData.TempFileTarget_F1 -f (ConvertTo-DestinationRelativePath $dstPath)
            if ($isTemplateFile -and $PSCmdlet.ShouldProcess($target, $LocalizedData.ShouldProcessExpandTemplate)) {
                $content = Get-Content -LiteralPath $srcPath -Raw

                # Eval script expression delimiters
                if ($content -and ($content.Count -gt 0)) {
                    $newContent = [regex]::Replace($content, '(<%=)(.*?)(%>)', {
                            param($match)
                            $expr = $match.groups[2].value
                            $res = Test-Expression $expr "templateFile '$srcRelPath'"
                            $PSCmdlet.WriteDebug("Replacing '$expr' with '$res' in contents of template file '$srcPath'")
                            $res
                        }, @('IgnoreCase'))

                    # Eval script block delimiters
                    $newContent = [regex]::Replace($newContent, '(^<%)(.*?)(^%>)', {
                            param($match)
                            $expr = $match.groups[2].value
                            $res = Test-Script  $expr "templateFile '$srcRelPath'"
                            $res = $res -join [System.Environment]::NewLine
                            $PSCmdlet.WriteDebug("Replacing '$expr' with '$res' in contents of template file '$srcPath'")
                            $res
                        }, @('IgnoreCase', 'SingleLine', 'MultiLine'))

                    $srcPath = $tempFile = [System.IO.Path]::GetTempFileName()
                    $PSCmdlet.WriteDebug("Created temp file for expanded templateFile - $tempFile")

                    Write-ContentWithEncoding -Path $tempFile -Content $newContent -Encoding $encoding
                } else {
                    $PSCmdlet.WriteDebug("Skipping template file expansion for $($Node.localName) '$srcPath', file is empty.")
                }
            }

            Copy-FileWithConflictDetection $srcPath $dstPath

            if ($PassThru -and ($Node.openInEditor -eq 'true')) {
                $InvokePlasterInfo.OpenFiles += $dstPath
            }
        } finally {
            if ($tempFile -and (Test-Path $tempFile)) {
                Remove-Item -LiteralPath $tempFile
                $PSCmdlet.WriteDebug("Removed temp file for expanded templateFile - $tempFile")
            }
        }
    }
}
function Start-ProcessFileProcessRequireModule {
    [CmdletBinding()]
    param(
        [ValidateNotNull()]
        $Node
    )

    $name = $Node.name

    $condition = $Node.condition
    if ($condition -and !(Test-ConditionAttribute $condition "'<$($Node.LocalName)>'")) {
        $PSCmdlet.WriteDebug("Skipping $($Node.localName) for module '$name', condition evaluated to false.")
        return
    }

    $message = Resolve-AttributeValue $Node.message (Get-ErrorLocationRequireModuleAttrVal $name message)
    $minimumVersion = $Node.minimumVersion
    $maximumVersion = $Node.maximumVersion
    $requiredVersion = $Node.requiredVersion

    $getModuleParams = @{
        ListAvailable = $true
        ErrorAction = 'SilentlyContinue'
    }

    # Configure $getModuleParams with correct parameters based on parameterset to be used.
    # Also construct an array of version strings that can be displayed to the user.
    $versionInfo = @()
    if ($requiredVersion) {
        $getModuleParams["FullyQualifiedName"] = @{ModuleName = $name; RequiredVersion = $requiredVersion }
        $versionInfo += $LocalizedData.RequireModuleRequiredVersion_F1 -f $requiredVersion
    } elseif ($minimumVersion -or $maximumVersion) {
        $getModuleParams["FullyQualifiedName"] = @{ModuleName = $name }

        if ($minimumVersion) {
            $getModuleParams.FullyQualifiedName["ModuleVersion"] = $minimumVersion
            $versionInfo += $LocalizedData.RequireModuleMinVersion_F1 -f $minimumVersion
        }
        if ($maximumVersion) {
            $getModuleParams.FullyQualifiedName["MaximumVersion"] = $maximumVersion
            $versionInfo += $LocalizedData.RequireModuleMaxVersion_F1 -f $maximumVersion
        }
    } else {
        $getModuleParams["Name"] = $name
    }

    # Flatten array of version strings into a single string.
    $versionRequirements = ""
    if ($versionInfo.Length -gt 0) {
        $OFS = ", "
        $versionRequirements = " ($versionInfo)"
    }

    # PowerShell v3 Get-Module command does not have the FullyQualifiedName parameter.
    if ($PSVersionTable.PSVersion.Major -lt 4) {
        $getModuleParams.Remove("FullyQualifiedName")
        $getModuleParams["Name"] = $name
    }

    $module = Get-Module @getModuleParams

    $moduleDesc = if ($versionRequirements) { "${name}:$versionRequirements" } else { $name }

    if ($null -eq $module) {
        Write-OperationStatus $LocalizedData.OpMissing ($LocalizedData.RequireModuleMissing_F2 -f $name, $versionRequirements)
        if ($message) {
            Write-OperationAdditionalStatus $message
        }
        if ($PassThru) {
            $InvokePlasterInfo.MissingModules += $moduleDesc
        }
    } else {
        if ($PSVersionTable.PSVersion.Major -gt 3) {
            Write-OperationStatus $LocalizedData.OpVerify ($LocalizedData.RequireModuleVerified_F2 -f $name, $versionRequirements)
        } else {
            # On V3, we have to the version matching with the results that Get-Module return.
            $installedVersion = $module | Sort-Object Version -Descending | Select-Object -First 1 | ForEach-Object Version
            if ($installedVersion.Build -eq -1) {
                $installedVersion = [System.Version]"${installedVersion}.0.0"
            } elseif ($installedVersion.Revision -eq -1) {
                $installedVersion = [System.Version]"${installedVersion}.0"
            }

            if (($requiredVersion -and ($installedVersion -ne $requiredVersion)) -or
                ($minimumVersion -and ($installedVersion -lt $minimumVersion)) -or
                ($maximumVersion -and ($installedVersion -gt $maximumVersion))) {

                Write-OperationStatus $LocalizedData.OpMissing ($LocalizedData.RequireModuleMissing_F2 -f $name, $versionRequirements)
                if ($PassThru) {
                    $InvokePlasterInfo.MissingModules += $moduleDesc
                }
            } else {
                Write-OperationStatus $LocalizedData.OpVerify ($LocalizedData.RequireModuleVerified_F2 -f $name, $versionRequirements)
            }
        }
    }
}
function Start-ProcessModifyFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateNotNull()]
        $Node
    )
    $path = Resolve-AttributeValue $Node.path (Get-ErrorLocationModifyAttrVal path)

    # We could choose to not check this if the condition eval'd to false
    # but I think it is better to let the template author know they've broken the
    # rules for any of the file directives (not just the ones they're testing/enabled).
    if ([System.IO.Path]::IsPathRooted($path)) {
        throw ($LocalizedData.ErrorPathMustBeRelativePath_F2 -f $path, $Node.LocalName)
    }

    $filePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath((Join-Path $DestinationPath $path))

    # The file's path must be under the DestinationPath specified by the user.
    Test-PathIsUnderDestinationPath $filePath

    $condition = $Node.condition
    if ($condition -and !(Test-ConditionAttribute $condition "'<$($Node.LocalName)>'")) {
        $PSCmdlet.WriteDebug("Skipping $($Node.LocalName) of '$filePath', condition evaluated to false.")
        return
    }

    $fileContent = [string]::Empty
    if (Test-Path -LiteralPath $filePath) {
        $fileContent = Get-Content -LiteralPath $filePath -Raw
    }

    # Set a Plaster (non-parameter) variable in this and the constrained runspace.
    Set-PlasterVariable -Name 'FileContent' -Value $fileContent -IsParam $false

    $encoding = $Node.encoding
    if (!$encoding) {
        $encoding = $DefaultEncoding
    }

    # If processing a <modify> directive, write the modified contents to a temp file,
    # then apply the normal file conflict detection/resolution handling.
    $target = $LocalizedData.TempFileTarget_F1 -f $filePath
    if ($PSCmdlet.ShouldProcess($target, $LocalizedData.OpModify)) {
        Write-OperationStatus $LocalizedData.OpModify ($LocalizedData.TempFileOperation_F1 -f (ConvertTo-DestinationRelativePath $filePath))

        $modified = $false

        foreach ($childNode in $Node.ChildNodes) {
            if ($childNode -isnot [System.Xml.XmlElement]) { continue }

            switch ($childNode.LocalName) {
                'replace' {
                    $condition = $childNode.condition
                    if ($condition -and !(Test-ConditionAttribute $condition "'<$($Node.LocalName)><$($childNode.LocalName)>'")) {
                        $PSCmdlet.WriteDebug("Skipping $($Node.LocalName) $($childNode.LocalName) of '$filePath', condition evaluated to false.")
                        continue
                    }

                    if ($childNode.original -is [string]) {
                        $original = $childNode.original
                    } else {
                        $original = $childNode.original.InnerText
                    }

                    if ($childNode.original.expand -eq 'true') {
                        $original = Resolve-AttributeValue $original (Get-ErrorLocationModifyAttrVal original)
                    }

                    if ($childNode.substitute -is [string]) {
                        $substitute = $childNode.substitute
                    } else {
                        $substitute = $childNode.substitute.InnerText
                    }

                    if ($childNode.substitute.isFile -eq 'true') {
                        $substitute = Get-PSSnippetFunction $substitute
                    } elseif ($childNode.substitute.expand -eq 'true') {
                        $substitute = Resolve-AttributeValue $substitute (Get-ErrorLocationModifyAttrVal substitute)
                    }

                    # Perform Literal Replacement on FileContent (since it will have regex characters)
                    if ($childNode.substitute.isFile) {
                        $fileContent = $fileContent.Replace($original, $substitute)
                    } else {
                        $fileContent = $fileContent -replace $original, $substitute
                    }

                    # Update the Plaster (non-parameter) variable's value in this and the constrained runspace.
                    Set-PlasterVariable -Name FileContent -Value $fileContent -IsParam $false

                    $modified = $true
                }
                default { throw ($LocalizedData.UnrecognizedContentElement_F1 -f $childNode.LocalName) }
            }
        }

        $tempFile = $null

        try {
            # We could use Copy-FileWithConflictDetection to handle the "identical" (not modified) case
            # but if nothing was changed, I'd prefer not to generate a temp file, copy the unmodified contents
            # into that temp file with hopefully the right encoding and then potentially overwrite the original file
            # (different encoding will make the files look different) with the same contents but different encoding.
            # If the intent of the <modify> was simply to change an existing file's encoding then the directive will
            # need to make a whitespace change to the file.
            if ($modified) {
                $tempFile = [System.IO.Path]::GetTempFileName()
                $PSCmdlet.WriteDebug("Created temp file for modified file - $tempFile")

                Write-ContentWithEncoding -Path $tempFile -Content $PLASTER_FileContent -Encoding $encoding
                Copy-FileWithConflictDetection $tempFile $filePath

                if ($PassThru -and ($Node.openInEditor -eq 'true')) {
                    $InvokePlasterInfo.OpenFiles += $filePath
                }
            } else {
                Write-OperationStatus $LocalizedData.OpIdentical (ConvertTo-DestinationRelativePath $filePath)
            }
        } finally {
            if ($tempFile -and (Test-Path $tempFile)) {
                Remove-Item -LiteralPath $tempFile
                $PSCmdlet.WriteDebug("Removed temp file for modified file - $tempFile")
            }
        }
    }
}
function Test-ConditionAttribute {
    [CmdletBinding()]
    param(
        [string]$Expression,
        [string]$Location
    )
    if ($null -eq $Expression) {
        return [string]::Empty
    } elseif ([string]::IsNullOrWhiteSpace($Expression)) {
        return $Expression
    }

    try {
        $expressionToEvaluate = $Expression

        if ($manifestType -eq 'JSON') {
            $expressionToEvaluate = $expressionToEvaluate -replace '\$\{(?!PLASTER_)([A-Za-z][A-Za-z0-9_]*)\}', '${PLASTER_PARAM_$1}'
        }

        $res = @(Invoke-ExpressionImpl $expressionToEvaluate)
        [bool]$res[0]
    } catch {
        throw ($LocalizedData.ExpressionInvalidCondition_F3 -f $Expression, $Location, $_)
    }
}
function Test-Expression {
    [CmdletBinding()]
    param(
        [string]$Expression,
        [string]$Location
    )
    if ($null -eq $Expression) {
        return [string]::Empty
    } elseif ([string]::IsNullOrWhiteSpace($Expression)) {
        return $Expression
    }

    try {
        $res = @(Invoke-ExpressionImpl $Expression)
        [string]$res[0]
    } catch {
        throw ($LocalizedData.ExpressionExecError_F2 -f $Location, $_)
    }
}
function Test-FilesIdentical {
    [CmdletBinding()]
    param(
        $Path1,
        $Path2
    )
    $file1 = Get-Item -LiteralPath $Path1 -Force
    $file2 = Get-Item -LiteralPath $Path2 -Force

    if ($file1.Length -ne $file2.Length) {
        return $false
    }

    $hash1 = (Get-FileHash -LiteralPath $path1 -Algorithm SHA1).Hash
    $hash2 = (Get-FileHash -LiteralPath $path2 -Algorithm SHA1).Hash

    $hash1 -eq $hash2
}
function Test-JsonManifest {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$JsonContent,

        [Parameter()]
        [string]$SchemaPath,

        [Parameter()]
        [switch]$Detailed
    )

    begin {
        Write-PlasterLog -Level Debug -Message "Starting JSON manifest validation"

        # Default schema path
        if (-not $SchemaPath) {
            $SchemaPath = Join-Path $PSScriptRoot "..\schema\plaster-manifest-v2.json"
        }
    }

    process {
        try {
            # Parse JSON content
            $jsonObject = $JsonContent | ConvertFrom-Json -ErrorAction Stop

            # Basic structure validation
            $requiredProperties = @('schemaVersion', 'metadata', 'content')
            foreach ($property in $requiredProperties) {
                if (-not $jsonObject.PSObject.Properties[$property]) {
                    throw "Missing required property: $property"
                }
            }

            # Schema version validation
            if ($jsonObject.schemaVersion -ne '2.0') {
                throw "Unsupported schema version: $($jsonObject.schemaVersion). Expected: 2.0"
            }

            # Metadata validation
            $metadata = $jsonObject.metadata
            $requiredMetadata = @('name', 'id', 'version', 'title', 'author')
            foreach ($property in $requiredMetadata) {
                if (-not $metadata.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace($metadata.$property)) {
                    throw "Missing or empty required metadata property: $property"
                }
            }

            # Validate GUID format for ID
            try {
                [Guid]::Parse($metadata.id) | Out-Null
            } catch {
                throw "Invalid GUID format for metadata.id: $($metadata.id)"
            }

            # Validate semantic version format
            if ($metadata.version -notmatch '^\d+\.\d+\.\d+([+-].*)?$') {
                throw "Invalid version format: $($metadata.version). Expected semantic versioning (e.g., 1.0.0)"
            }

            # Validate template name pattern
            if ($metadata.name -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
                throw "Invalid template name: $($metadata.name). Must start with letter and contain only letters, numbers, underscore, or hyphen"
            }

            # Parameters validation
            # Parameters validation
            if ($jsonObject.PSObject.Properties['parameters'] -and $jsonObject.parameters -and $jsonObject.parameters.Count -gt 0) {
                Test-JsonManifestParameters -Parameters $jsonObject.parameters
            }

            # Content validation
            # Content validation
            # Content validation
            if ($jsonObject.content -and $jsonObject.content.Count -gt 0) {
                Test-JsonManifestContent -Content $jsonObject.content
            } else {
                throw "Content section cannot be empty"
            }

            Write-PlasterLog -Level Debug -Message "JSON manifest validation successful"
            return $true
        } catch {
            $errorMessage = "JSON manifest validation failed: $($_.Exception.Message)"
            Write-PlasterLog -Level Error -Message $errorMessage

            if ($Detailed) {
                throw $_
            }

            return $false
        }
    }
}
function Test-JsonManifestContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Content
    )

    if ($Content.Count -eq 0) {
        throw "Content section cannot be empty"
    }

    foreach ($action in $Content) {
        if (-not $action.type) {
            throw "Content action missing required 'type' property"
        }

        # Validate action type and required properties
        switch ($action.type) {
            'message' {
                if (-not $action.text) {
                    throw "Message action missing required 'text' property"
                }
            }
            'file' {
                # Both source and destination cannot be empty/missing
                # Empty destination means copy to root, empty source would be directory (but should use 'directory' type)
                if ((-not $action.source -and -not $action.destination) -or
                    (-not $action.PSObject.Properties['source'] -and -not $action.PSObject.Properties['destination'])) {
                    throw "File action missing required 'source' or 'destination' property"
                }
                # At least one must be non-empty
                if ([string]::IsNullOrWhiteSpace($action.source) -and [string]::IsNullOrWhiteSpace($action.destination)) {
                    throw "File action missing required 'source' or 'destination' property"
                }
            }
            'templateFile' {
                # Both source and destination cannot be empty/missing
                # Empty destination means copy to root
                if ((-not $action.source -and -not $action.destination) -or
                    (-not $action.PSObject.Properties['source'] -and -not $action.PSObject.Properties['destination'])) {
                    throw "TemplateFile action missing required 'source' or 'destination' property"
                }
                # At least one must be non-empty
                if ([string]::IsNullOrWhiteSpace($action.source) -and [string]::IsNullOrWhiteSpace($action.destination)) {
                    throw "TemplateFile action missing required 'source' or 'destination' property"
                }
            }
            'directory' {
                if (-not $action.destination) {
                    throw "Directory action missing required 'destination' property"
                }
            }
            'newModuleManifest' {
                if (-not $action.destination) {
                    throw "NewModuleManifest action missing required 'destination' property"
                }
            }
            'modify' {
                if (-not $action.path -or -not $action.modifications) {
                    throw "Modify action missing required 'path' or 'modifications' property"
                }

                # Validate modifications
                foreach ($modification in $action.modifications) {
                    if (-not $modification.type) {
                        throw "Modification missing required 'type' property"
                    }

                    if ($modification.type -eq 'replace') {
                        if (-not $modification.PSObject.Properties['search'] -or -not $modification.PSObject.Properties['replace']) {
                            throw "Replace modification missing required 'search' or 'replace' property"
                        }
                    }
                }
            }
            'requireModule' {
                if (-not $action.name) {
                    throw "RequireModule action missing required 'name' property"
                }
            }
            'execute' {
                if (-not $action.script) {
                    throw "Execute action missing required 'script' property"
                }
            }
            default {
                throw "Unknown content action type: $($action.type)"
            }
        }

        # Validate condition if present
        if ($action.condition) {
            Test-PlasterCondition -Condition $action.condition -Context "Content action ($($action.type))"
        }
    }
}
function Test-JsonManifestParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Parameters
    )

    $parameterNames = @()

    foreach ($param in $Parameters) {
        # Required properties
        if (-not $param.name -or -not $param.type) {
            throw "Parameter missing required 'name' or 'type' property"
        }

        # Validate parameter name pattern
        if ($param.name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            throw "Invalid parameter name: $($param.name). Must start with letter and contain only letters, numbers, or underscore"
        }

        # Check for duplicate parameter names
        if ($param.name -in $parameterNames) {
            throw "Duplicate parameter name: $($param.name)"
        }
        $parameterNames += $param.name

        # Validate parameter type
        $validTypes = @('text', 'user-fullname', 'user-email', 'choice', 'multichoice', 'switch')
        if ($param.type -notin $validTypes) {
            throw "Invalid parameter type: $($param.type). Valid types: $($validTypes -join ', ')"
        }

        # Choice parameters must have choices
        if ($param.type -in @('choice', 'multichoice') -and -not $param.choices) {
            throw "Parameter '$($param.name)' of type '$($param.type)' must have 'choices' property"
        }

        # Validate choices if present
        if ($param.choices) {
            foreach ($choice in $param.choices) {
                if (-not $choice.label -or -not $choice.value) {
                    throw "Choice in parameter '$($param.name)' missing required 'label' or 'value' property"
                }
            }
        }

        # Validate dependsOn references
        if ($param.dependsOn) {
            foreach ($dependency in $param.dependsOn) {
                if ($dependency -notin $parameterNames -and $dependency -ne $param.name) {
                    # Note: We'll validate this after processing all parameters
                    Write-PlasterLog -Level Debug -Message "Parameter '$($param.name)' depends on '$dependency'"
                }
            }
        }

        # Validate condition syntax if present
        if ($param.condition) {
            Test-PlasterCondition -Condition $param.condition -ParameterName $param.name
        }
    }
}
function Test-PathIsUnderDestinationPath() {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]
        $FullPath
    )
    if (![System.IO.Path]::IsPathRooted($FullPath)) {
        $PSCmdlet.WriteDebug("The FullPath parameter '$FullPath' must be an absolute path.")
    }

    $fullDestPath = $DestinationPath
    if (![System.IO.Path]::IsPathRooted($fullDestPath)) {
        $fullDestPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DestinationPath)
    }

    if (!$FullPath.StartsWith($fullDestPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw ($LocalizedData.ErrorPathMustBeUnderDestPath_F2 -f $FullPath, $fullDestPath)
    }
}
function Test-PlasterCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Condition,

        [Parameter()]
        [string]$ParameterName,

        [Parameter()]
        [string]$Context = 'condition'
    )

    try {
        # Basic syntax validation - ensure it's valid PowerShell
        $tokens = $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($Condition, [ref]$tokens, [ref]$errors)

        if ($errors.Count -gt 0) {
            $errorMsg = if ($ParameterName) {
                "Invalid condition in parameter '$ParameterName': $($errors[0].Message)"
            } else {
                "Invalid condition in ${Context}: $($errors[0].Message)"
            }
            throw $errorMsg
        }

        Write-PlasterLog -Level Debug -Message "Condition validation passed: $Condition"
        return $true
    } catch {
        Write-PlasterLog -Level Error -Message "Condition validation failed: $($_.Exception.Message)"
        throw $_
    }
}
function Test-Script {
    [CmdletBinding()]
    param(
        [string]$Script,
        [string]$Location
    )
    if ($null -eq $Script) {
        return @([string]::Empty)
    } elseif ([string]::IsNullOrWhiteSpace($Script)) {
        return $Script
    }

    try {
        $res = @(Invoke-ExpressionImpl $Script)
        [string[]]$res
    } catch {
        throw ($LocalizedData.ExpressionExecError_F2 -f $Location, $_)
    }
}
function Write-ContentWithEncoding {
    [CmdletBinding()]
    param(
        [string]
        $Path,
        [string[]]
        $Content,
        [string]
        $Encoding
    )

    if ($Encoding -match '-nobom') {
        $Encoding, $dummy = $Encoding -split '-'

        $noBomEncoding = $null
        switch ($Encoding) {
            'utf8' { $noBomEncoding = New-Object System.Text.UTF8Encoding($false) }
        }

        if ($null -eq $Content) {
            $Content = [string]::Empty
        }

        [System.IO.File]::WriteAllLines($Path, $Content, $noBomEncoding)
    } else {
        Set-Content -LiteralPath $Path -Value $Content -Encoding $Encoding
    }
}
function Write-OperationAdditionalStatus {
    [CmdletBinding()]
    param(
        [string[]]$Message
    )
    $maxLen = Get-MaxOperationLabelLength
    foreach ($msg in $Message) {
        $lines = $msg -split "`n"
        foreach ($line in $lines) {
            Write-Host ("{0,$maxLen} {1}" -f "", $line)
        }
    }
}
function Write-OperationStatus {
    [CmdletBinding()]
    param(
        $Operation,
        $Message
    )
    $maxLen = Get-MaxOperationLabelLength
    Write-Host ("{0,$maxLen} " -f $Operation) -ForegroundColor (Get-ColorForOperation $Operation) -NoNewline
    Write-Host $Message
}
function Write-PlasterLog {
    <#
    .SYNOPSIS
    Logs messages with different severity levels for Plaster operations.

    .DESCRIPTION
    This function logs messages with different severity levels for Plaster
    operations.

    .PARAMETER Level
    The severity level of the log message. Possible values are 'Error',
    'Warning', 'Information', 'Verbose', and 'Debug'. The log message will be
    formatted with a timestamp and the source of the log.

    .PARAMETER Message
    The message to log.

    .PARAMETER Source
    The source of the log message.

    .EXAMPLE
    Write-PlasterLog -Level 'Information' -Message 'This is an informational message.'

    This example logs an informational message with the specified level and
    source.
    .NOTES
    This function is designed to be used within the Plaster module to ensure
    consistent logging across various operations.
    It is not intended for direct use outside of the Plaster context.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Source = 'Plaster'
    )

    # Check if we should log at this level
    $logLevels = @{
        'Error'       = 0
        'Warning'     = 1
        'Information' = 2
        'Verbose'     = 3
        'Debug'       = 4
    }

    $currentLogLevel = if ($null -ne $script:LogLevel) { $script:LogLevel } else { 'Information' }
    $currentLevelValue = if ($null -ne $logLevels[$currentLogLevel]) { $logLevels[$currentLogLevel] } else { 2 }
    $messageLevelValue = if ($null -ne $logLevels[$Level]) { $logLevels[$Level] } else { 2 }

    if ($messageLevelValue -gt $currentLevelValue) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [$Source] $Message"

    # Handle different log levels appropriately
    switch ($Level) {
        'Error' {
            Write-Error $logMessage -ErrorAction Continue
        }
        'Warning' {
            Write-Warning $logMessage
        }
        'Information' {
            Write-Information $logMessage -InformationAction Continue
        }
        'Verbose' {
            Write-Verbose $logMessage
        }
        'Debug' {
            Write-Debug $logMessage
        }
    }

    # Also write to host for immediate feedback during interactive sessions
    if ($Level -in @('Error', 'Warning') -and $Host.Name -ne 'ServerRemoteHost') {
        $color = switch ($Level) {
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            default { 'White' }
        }
        Write-Host $logMessage -ForegroundColor $color
    }
}
function Get-PlasterTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0,
            ParameterSetName = "Path",
            HelpMessage = "Specifies a path to a folder containing a Plaster template or multiple template folders.  Can also be a path to plasterManifest.xml.")]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Position = 1,
            ParameterSetName = "Path",
            HelpMessage = "Will return templates that match the name.")]
        [Parameter(Position = 1,
            ParameterSetName = "IncludedTemplates",
            HelpMessage = "Will return templates that match the name.")]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name = "*",

        [Parameter(ParameterSetName = "Path",
            HelpMessage = "Will return templates that match the tag.")]
        [Parameter(ParameterSetName = "IncludedTemplates",
            HelpMessage = "Will return templates that match the tag.")]
        [ValidateNotNullOrEmpty()]
        [string]
        $Tag = "*",

        [Parameter(ParameterSetName = "Path",
            HelpMessage = "Indicates that this cmdlet gets the items in the specified locations and in all child items of the locations.")]
        [switch]
        $Recurse,

        [Parameter(Position = 0,
            Mandatory = $true,
            ParameterSetName = "IncludedTemplates",
            HelpMessage = "Initiates a search for latest version Plaster templates inside of installed modules.")]
        [switch]
        [Alias("IncludeModules")]
        $IncludeInstalledModules,

        [Parameter(ParameterSetName = "IncludedTemplates",
            HelpMessage = "If specified, searches for Plaster templates inside of all installed module versions.")]
        [switch]
        $ListAvailable
    )

    process {
        if ($Path) {
            if (!$Recurse.IsPresent) {
                if (Test-Path $Path -PathType Container) {
                    # Check for JSON first, then XML
                    $jsonPath = Join-Path $Path "plasterManifest.json"
                    $xmlPath = Join-Path $Path "plasterManifest.xml"

                    if (Test-Path $jsonPath) {
                        $Path = $jsonPath
                    } elseif (Test-Path $xmlPath) {
                        $Path = $xmlPath
                    } else {
                        $Path = Resolve-Path "$Path/plasterManifest.*" -ErrorAction SilentlyContinue | Select-Object -First 1
                    }
                }

                Write-Verbose "Attempting to get Plaster template at path: $Path"
                $newTemplateObjectFromManifestSplat = @{
                    ManifestPath = $Path
                    Name = $Name
                    Tag = $Tag
                }
                New-TemplateObjectFromManifest @newTemplateObjectFromManifestSplat
            } else {
                Write-Verbose "Attempting to get Plaster templates recursively under path: $Path"
                $getManifestsUnderPathSplat = @{
                    RootPath = $Path
                    Recurse = $Recurse.IsPresent
                    Name = $Name
                    Tag = $Tag
                }
                Get-ManifestsUnderPath @getManifestsUnderPathSplat
            }
        } else {
            # Return all templates included with Plaster
            $getManifestsUnderPathSplat = @{
                RootPath = "$PSScriptRoot\Templates"
                Recurse = $true
                Name = $Name
                Tag = $Tag
            }
            Get-ManifestsUnderPath @getManifestsUnderPathSplat

            if ($IncludeInstalledModules.IsPresent) {
                # Search for templates in module path
                $GetModuleExtensionParams = @{
                    ModuleName = "Plaster"
                    ModuleVersion = $PlasterVersion
                    ListAvailable = $ListAvailable
                }
                $extensions = Get-ModuleExtension @GetModuleExtensionParams

                foreach ($extension in $extensions) {
                    # Scan all module paths registered in the module
                    foreach ($templatePath in $extension.Details.TemplatePaths) {
                        # Check for both JSON and XML manifests
                        $jsonManifestPath = [System.IO.Path]::Combine(
                            $extension.Module.ModuleBase,
                            $templatePath,
                            "plasterManifest.json")

                        $xmlManifestPath = [System.IO.Path]::Combine(
                            $extension.Module.ModuleBase,
                            $templatePath,
                            "plasterManifest.xml")

                        $newTemplateObjectFromManifestSplat = @{
                            Name = $Name
                            Tag = $Tag
                            ErrorAction = 'SilentlyContinue'
                        }
                        if (Test-Path $jsonManifestPath) {
                            $newTemplateObjectFromManifestSplat.ManifestPath = $jsonManifestPath
                        } elseif (Test-Path $xmlManifestPath) {
                            $newTemplateObjectFromManifestSplat.ManifestPath = $xmlManifestPath
                        }
                        New-TemplateObjectFromManifest @newTemplateObjectFromManifestSplat
                    }
                }
            }
        }
    }
}
## TODO: Create tests to ensure check for these.
## DEVELOPERS NOTES & CONVENTIONS
##
##  1. All text displayed to the user except for Write-Debug (or $PSCmdlet.WriteDebug()) text must be added to the
##     string tables in:
##         en-US\Plaster.psd1
##         Plaster.psm1
##  2. If a new manifest element is added, it must be added to the Schema\PlasterManifest-v1.xsd file and then
##     processed in the appropriate function in this script.  Any changes to <parameter> attributes must be
##     processed not only in the Resolve-ProcessParameter function but also in the dynamicparam function.
##
##  3. Non-exported functions should avoid using the PowerShell standard Verb-Noun naming convention.
##     They should use PascalCase instead.
##
##  4. Please follow the scripting style of this file when adding new script.

function Invoke-Plaster {
    [CmdletBinding(DefaultParameterSetName = 'TemplatePath', SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'TemplatePath')]
        [ValidateNotNullOrEmpty()]
        [string]
        $TemplatePath,

        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'TemplateDefinition')]
        [ValidateNotNullOrEmpty()]
        [string]
        $TemplateDefinition,

        [Parameter(Position = 1, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $DestinationPath,

        [Parameter()]
        [switch]
        $Force,

        [Parameter()]
        [switch]
        $NoLogo,

        # Enhanced dynamic parameter processing for both XML and JSON
        [switch]
        $PassThru
    )

    # Process the template's Plaster manifest file to convert parameters defined there into dynamic parameters.
    dynamicparam {
        $paramDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        $manifest = $null
        $manifestPath = $null
        $templateAbsolutePath = $null

        # Nothing to do until the TemplatePath parameter has been provided.
        if ($null -eq $TemplatePath) {
            return
        }

        try {
            # Let's convert non-terminating errors in this function to terminating so we
            # catch and format the error message as a warning.
            $ErrorActionPreference = 'Stop'

            <# The constrained runspace is not available in the dynamicparam
            block. Shouldn't be needed since we are only evaluating the
            parameters in the manifest - no need for Test-ConditionAttribute as
            we are not building up multiple parametersets. And no need for
            EvaluateAttributeValue since we are only grabbing the parameter's
            value which is static.#>

            $templateAbsolutePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TemplatePath)

            # Load manifest file using culture lookup - try both JSON and XML formats
            $manifestPath = Get-PlasterManifestPathForCulture -TemplatePath $templateAbsolutePath -Culture $PSCulture

            # If XML not found, try JSON
            if (($null -eq $manifestPath) -or (!(Test-Path $manifestPath))) {
                $jsonManifestPath = Join-Path $templateAbsolutePath 'plasterManifest.json'
                if (Test-Path $jsonManifestPath) {
                    $manifestPath = $jsonManifestPath
                }
            }

            # Determine manifest type and process accordingly
            try {
                $manifestType = Get-PlasterManifestType -ManifestPath $manifestPath
                Write-Debug "Detected manifest type: $manifestType for path: $manifestPath"
            } catch {
                Write-Warning "Failed to determine manifest type for '$manifestPath': $($_.Exception.Message)"
                return
            }

            #Process JSON manifests
            if ($manifestType -eq 'JSON') {
                try {
                    $jsonContent = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
                    $manifest = ConvertFrom-JsonManifest -JsonContent $jsonContent -ErrorAction Stop
                    Write-Debug "Successfully converted JSON manifest to XML for processing"
                } catch {
                    Write-Warning "Failed to process JSON manifest '$manifestPath': $($_.Exception.Message)"
                    return
                }
            } else {
                # Process XML manifests (existing logic)
                $manifest = Test-PlasterManifest -Path $manifestPath -ErrorAction Stop 3>$null
            }

            # The user-defined parameters in the Plaster manifest are converted to dynamic parameters
            # which allows the user to provide the parameters via the command line.
            # This enables non-interactive use cases.
            foreach ($node in $manifest.plasterManifest.parameters.ChildNodes) {
                if ($node -isnot [System.Xml.XmlElement]) {
                    continue
                }

                $name = $node.name
                $type = $node.type
                $prompt = if ($node.prompt) { $node.prompt } else { $LocalizedData.MissingParameterPrompt_F1 -f $name }

                if (!$name -or !$type) { continue }

                # Configure ParameterAttribute and add to attr collection
                $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $paramAttribute = New-Object System.Management.Automation.ParameterAttribute
                $paramAttribute.HelpMessage = $prompt
                $attributeCollection.Add($paramAttribute)

                switch -regex ($type) {
                    'text|user-fullname|user-email' {
                        $param = New-Object System.Management.Automation.RuntimeDefinedParameter `
                            -ArgumentList ($name, [string], $attributeCollection)
                        break
                    }

                    'choice|multichoice' {
                        $choiceNodes = $node.ChildNodes
                        $setValues = New-Object string[] $choiceNodes.Count
                        $i = 0

                        foreach ($choiceNode in $choiceNodes) {
                            $setValues[$i++] = $choiceNode.value
                        }

                        $validateSetAttr = New-Object System.Management.Automation.ValidateSetAttribute $setValues
                        $attributeCollection.Add($validateSetAttr)
                        $type = if ($type -eq 'multichoice') { [string[]] } else { [string] }
                        $param = New-Object System.Management.Automation.RuntimeDefinedParameter `
                            -ArgumentList ($name, $type, $attributeCollection)
                        break
                    }

                    default { throw ($LocalizedData.UnrecognizedParameterType_F2 -f $type, $name) }
                }

                $paramDictionary.Add($name, $param)
            }
        } catch {
            Write-Warning ($LocalizedData.ErrorProcessingDynamicParams_F1 -f $_)
        }

        $paramDictionary
    }

    begin {
        # Enhanced logo with JSON support indicator
        $plasterLogo = @'
  ____  _           _                ____     ___
 |  _ \| | __ _ ___| |_ ___ _ __    |___ \   / _ \
 | |_) | |/ _` / __| __/ _ \ '__|     __) | | | | |
 |  __/| | (_| \__ \ ||  __/ |       / __/|_| |_| |
 |_|   |_|\__,_|___/\__\___|_|      |_____|_|\___/
'@

        if (!$NoLogo) {
            $versionString = "v$PlasterVersion (JSON Enhanced)"
            Write-Host $plasterLogo -ForegroundColor Blue
            Write-Host ((" " * (50 - $versionString.Length)) + $versionString) -ForegroundColor Cyan
            Write-Host ("=" * 50) -ForegroundColor Blue
        }

        #region Script Scope Variables
        # These are used across different private functions.
        $script:boundParameters = $PSBoundParameters
        $script:constrainedRunspace = $null
        $script:templateCreatedFiles = @{}
        $script:defaultValueStore = @{}
        $script:fileConflictConfirmNoToAll = $false
        $script:fileConflictConfirmYesToAll = $false
        $script:flags = @{
            DefaultValueStoreDirty = $false
        }
        #endregion Script Scope Variables

        # Determine template source and type
        if ($PSCmdlet.ParameterSetName -eq 'TemplatePath') {
            $templateAbsolutePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($TemplatePath)
            if (!(Test-Path -LiteralPath $templateAbsolutePath -PathType Container)) {
                throw ($LocalizedData.ErrorTemplatePathIsInvalid_F1 -f $templateAbsolutePath)
            }

            # Determine manifest type and path
            $jsonManifestPath = Join-Path $templateAbsolutePath 'plasterManifest.json'
            $xmlManifestPath = Get-PlasterManifestPathForCulture $templateAbsolutePath $PSCulture

            if (Test-Path -LiteralPath $jsonManifestPath) {
                $manifestPath = $jsonManifestPath
                $manifestType = 'JSON'
                Write-PlasterLog -Level Information -Message "Using JSON manifest: $($manifestPath | Split-Path -Leaf)"
            } elseif (($null -ne $xmlManifestPath) -and (Test-Path $xmlManifestPath)) {
                $manifestPath = $xmlManifestPath
                $manifestType = 'XML'
                Write-PlasterLog -Level Information -Message "Using XML manifest: $($manifestPath | Split-Path -Leaf)"
            } else {
                throw ($LocalizedData.ManifestFileMissing_F1 -f "plasterManifest.json or plasterManifest.xml")
            }

        } else {
            # TemplateDefinition parameter set
            $manifestType = if ($TemplateDefinition.TrimStart() -match '^[\s]*[\{\[]') { 'JSON' } else { 'XML' }
            $templateAbsolutePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DestinationPath)
            Write-PlasterLog -Level Information -Message "Using inline $manifestType template definition"
        }

        # Process manifest based on type

        if ($null -eq $manifest) {
            if ($manifestType -eq 'JSON') {
                $manifestContent = if ($manifestPath) {
                    Get-Content -LiteralPath $manifestPath -Raw
                } else {
                    $TemplateDefinition
                }

                # Validate and convert JSON manifest
                $isValid = Test-JsonManifest -JsonContent $manifestContent -Detailed
                if (-not $isValid) {
                    throw "JSON manifest validation failed"
                }

                $manifest = ConvertFrom-JsonManifest -JsonContent $manifestContent
                Write-PlasterLog -Level Debug -Message "JSON manifest converted to internal format"

            } else {
                # Load XML manifest
                if ($manifestPath -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                    $manifest = Test-PlasterManifest -Path $manifestPath -ErrorAction Stop 3>$null
                    $PSCmdlet.WriteDebug("Loading XML manifest file '$manifestPath'")
                } else {
                    throw ($LocalizedData.ManifestFileMissing_F1 -f $manifestPath)
                }
            }
        }

        # Validate destination path
        $destinationAbsolutePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DestinationPath)
        if (!(Test-Path -LiteralPath $destinationAbsolutePath)) {
            New-Item $destinationAbsolutePath -ItemType Directory > $null
            Write-PlasterLog -Level Information -Message "Created destination directory: $destinationAbsolutePath"
        }

        # Prepare output object if user has specified the -PassThru parameter.
        if ($PassThru) {
            $InvokePlasterInfo = [PSCustomObject]@{
                TemplatePath = if ($templateAbsolutePath) { $templateAbsolutePath } else { 'Inline Definition' }
                DestinationPath = $destinationAbsolutePath
                ManifestType = $manifestType
                Success = $false
                TemplateType = if ($manifest.plasterManifest.templateType) { $manifest.plasterManifest.templateType } else { 'Unspecified' }
                CreatedFiles = [string[]]@()
                UpdatedFiles = [string[]]@()
                MissingModules = [string[]]@()
                OpenFiles = [string[]]@()
                ProcessingTime = $null
            }
        }

        # Initialize pre-defined variables
        if ($templateAbsolutePath) {
            Initialize-PredefinedVariables -TemplatePath $templateAbsolutePath -DestPath $destinationAbsolutePath
        } else {
            Initialize-PredefinedVariables -TemplatePath $destinationAbsolutePath -DestPath $destinationAbsolutePath
        }

        # Enhanced default value store handling
        $templateId = $manifest.plasterManifest.metadata.id
        $templateVersion = $manifest.plasterManifest.metadata.version
        $templateName = $manifest.plasterManifest.metadata.name
        $storeFilename = "$templateName-$templateVersion-$templateId.clixml"
        $script:defaultValueStorePath = Join-Path $ParameterDefaultValueStoreRootPath $storeFilename
        if (Test-Path $script:defaultValueStorePath) {
            try {
                $PSCmdlet.WriteDebug("Loading default value store from '$script:defaultValueStorePath'.")
                $script:defaultValueStore = Import-Clixml $script:defaultValueStorePath -ErrorAction Stop
                Write-PlasterLog -Level Debug -Message "Loaded parameter defaults from store"
            } catch {
                Write-Warning ($LocalizedData.ErrorFailedToLoadStoreFile_F1 -f $script:defaultValueStorePath)
            }
        }
    }

    end {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            Write-PlasterLog -Level Information -Message "Starting template processing ($manifestType format)"

            # Process parameters with enhanced JSON support
            foreach ($node in $manifest.plasterManifest.parameters.ChildNodes) {
                if ($node -isnot [System.Xml.XmlElement]) { continue }
                switch ($node.LocalName) {
                    'parameter' { Resolve-ProcessParameter $node }
                    default { throw ($LocalizedData.UnrecognizedParametersElement_F1 -f $node.LocalName) }
                }
            }

            # Output processed parameters for debugging
            $parameters = Get-Variable -Name PLASTER_* | Out-String
            $PSCmdlet.WriteDebug("Parameter values are:`n$($parameters -split "`n")")

            # Stores any updated default values back to the store file.
            if ($script:flags.DefaultValueStoreDirty) {
                $directory = Split-Path $script:defaultValueStorePath -Parent
                if (!(Test-Path $directory)) {
                    $PSCmdlet.WriteDebug("Creating directory for template's DefaultValueStore '$directory'.")
                    New-Item $directory -ItemType Directory > $null
                }

                $PSCmdlet.WriteDebug("DefaultValueStore is dirty, saving updated values to '$script:defaultValueStorePath'.")
                $script:defaultValueStore | Export-Clixml -LiteralPath $script:defaultValueStorePath
            }

            # Output destination path
            Write-Host ($LocalizedData.DestPath_F1 -f $destinationAbsolutePath)

            # Process content with enhanced logging
            foreach ($node in $manifest.plasterManifest.content.ChildNodes) {
                if ($node -isnot [System.Xml.XmlElement]) { continue }

                Write-PlasterLog -Level Debug -Message "Processing content action: $($node.LocalName)"
                switch -Regex ($node.LocalName) {
                    'file|templateFile' { Start-ProcessFile $node; break }
                    'message' { Resolve-ProcessMessage $node; break }
                    'modify' { Start-ProcessModifyFile $node; break }
                    'newModuleManifest' { Resolve-ProcessNewModuleManifest $node; break }
                    'requireModule' { Start-ProcessFileProcessRequireModule $node; break }
                    default { throw ($LocalizedData.UnrecognizedContentElement_F1 -f $node.LocalName) }
                }
            }
            $stopwatch.Stop()

            if ($PassThru) {
                $InvokePlasterInfo.Success = $true
                $InvokePlasterInfo.ProcessingTime = $stopwatch.Elapsed
                Write-PlasterLog -Level Information -Message "Template processing completed successfully in $($stopwatch.Elapsed.TotalSeconds) seconds"
                return $InvokePlasterInfo
            } else {
                Write-PlasterLog -Level Information -Message "Template processing completed successfully in $($stopwatch.Elapsed.TotalSeconds) seconds"
            }
        } catch {
            $stopwatch.Stop()
            $errorMessage = "Template processing failed after $($stopwatch.Elapsed.TotalSeconds) seconds: $($_.Exception.Message)"
            Write-PlasterLog -Level Error -Message $errorMessage

            if ($PassThru) {
                $InvokePlasterInfo.Success = $false
                $InvokePlasterInfo.ProcessingTime = $stopwatch.Elapsed
                return $InvokePlasterInfo
            }

            throw $_
        } finally {
            # Enhanced cleanup
            if ($script:constrainedRunspace) {
                $script:constrainedRunspace.Dispose()
                $script:constrainedRunspace = $null
                Write-PlasterLog -Level Debug -Message "Disposed constrained runspace"
            }
        }
    }
}
function New-PlasterManifest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-zA-Z_-]+$')]
        [string]
        $TemplateName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Item', 'Project')]
        [string]
        $TemplateType,

        [Parameter()]
        [Guid]
        $Id = [guid]::NewGuid(),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^\d+\.\d+(\.\d+((\.\d+|(\+|-).*)?)?)?$')]
        [string]
        $TemplateVersion = "1.0.0",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Title = $TemplateName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Description,

        [Parameter()]
        [string[]]
        $Tags,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Author,

        [Parameter()]
        [switch]
        $AddContent,

        [Parameter()]
        [ValidateSet('XML', 'JSON')]
        [string]
        $Format = 'JSON',

        [Parameter()]
        [switch]
        $ConvertFromXml
    )

    begin {
        # Set default path based on format if not provided
        if (-not $PSBoundParameters.ContainsKey('Path')) {
            $Path = if ($Format -eq 'JSON') { "$pwd\plasterManifest.json" } else { "$pwd\plasterManifest.xml" }
        }

        $resolvedPath = $PSCmdLet.GetUnresolvedProviderPathFromPSPath($Path)

        $caseCorrectedTemplateType = [System.Char]::ToUpper($TemplateType[0]) + $TemplateType.Substring(1).ToLower()

        $manifestStr = @"
<?xml version="1.0" encoding="utf-8"?>
<plasterManifest schemaVersion="$LatestSupportedSchemaVersion"
                 templateType="$caseCorrectedTemplateType"
                 xmlns="http://www.microsoft.com/schemas/PowerShell/Plaster/v1">

    <metadata>
        <name></name>
        <id></id>
        <version></version>
        <title></title>
        <description></description>
        <author></author>
        <tags></tags>
    </metadata>
    <parameters>
    </parameters>
    <content>
    </content>
</plasterManifest>
"@
    }

    end {
        if ($Format -eq 'JSON') {
            # Create JSON manifest
            $jsonManifest = [ordered]@{
                '$schema'       = 'https://raw.githubusercontent.com/PowerShellOrg/Plaster/v2/schema/plaster-manifest-v2.json'
                'schemaVersion' = '2.0'
                'metadata'      = [ordered]@{
                    'name'         = $TemplateName
                    'id'           = $Id.ToString()
                    'version'      = $TemplateVersion
                    'title'        = $Title
                    'description'  = $Description
                    'author'       = $Author
                    'templateType' = $caseCorrectedTemplateType
                }
                'parameters'    = @()
                'content'       = @()
            }

            if ($Tags) {
                $jsonManifest.metadata['tags'] = $Tags
            }

            if ($AddContent) {
                $baseDir = Split-Path $resolvedPath -Parent
                $filenames = Get-ChildItem $baseDir -Recurse -File -Name
                foreach ($filename in $filenames) {
                    if ($filename -match "plasterManifest.*\.(xml|json)") {
                        continue
                    }

                    $fileAction = [ordered]@{
                        'type'        = 'file'
                        'source'      = $filename
                        'destination' = $filename
                    }
                    $jsonManifest.content += $fileAction
                }
            }

            $jsonContent = $jsonManifest | ConvertTo-Json -Depth 10
            if ($PSCmdlet.ShouldProcess($resolvedPath, $LocalizedData.ShouldCreateNewPlasterManifest)) {
                Set-Content -Path $resolvedPath -Value $jsonContent -Encoding UTF8
            }

        } else {
            $manifest = [xml]$manifestStr

            # Set via .innerText to get .NET to encode special XML chars as entity references.
            $manifest.plasterManifest.metadata["name"].innerText = "$TemplateName"
            $manifest.plasterManifest.metadata["id"].innerText = "$Id"
            $manifest.plasterManifest.metadata["version"].innerText = "$TemplateVersion"
            $manifest.plasterManifest.metadata["title"].innerText = "$Title"
            $manifest.plasterManifest.metadata["description"].innerText = "$Description"
            $manifest.plasterManifest.metadata["author"].innerText = "$Author"

            $OFS = ", "
            $manifest.plasterManifest.metadata["tags"].innerText = "$Tags"

            if ($AddContent) {
                $baseDir = Split-Path $Path -Parent
                $filenames = Get-ChildItem $baseDir -Recurse -File -Name
                foreach ($filename in $filenames) {
                    if ($filename -match "plasterManifest.*\.xml") {
                        continue
                    }

                    $fileElem = $manifest.CreateElement('file', $TargetNamespace)

                    $srcAttr = $manifest.CreateAttribute("source")
                    $srcAttr.Value = $filename
                    $fileElem.Attributes.Append($srcAttr) > $null

                    $dstAttr = $manifest.CreateAttribute("destination")
                    $dstAttr.Value = $filename
                    $fileElem.Attributes.Append($dstAttr) > $null

                    $manifest.plasterManifest["content"].AppendChild($fileElem) > $null
                }
            }

            # This configures the XmlWriter to put attributes on a new line
            $xmlWriterSettings = New-Object System.Xml.XmlWriterSettings
            $xmlWriterSettings.Indent = $true
            $xmlWriterSettings.NewLineOnAttributes = $true

            try {
                if ($PSCmdlet.ShouldProcess($resolvedPath, $LocalizedData.ShouldCreateNewPlasterManifest)) {
                    $xmlWriter = [System.Xml.XmlWriter]::Create($resolvedPath, $xmlWriterSettings)
                    $manifest.Save($xmlWriter)
                }
            } finally {
                if ($xmlWriter) {
                    $xmlWriter.Dispose()
                }
            }
        }
    }
}
function Test-PlasterManifest {
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param(
        [Parameter(Position = 0,
            ParameterSetName = "Path",
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Specifies a path to a plasterManifest.xml or plasterManifest.json file.")]
        [Alias("PSPath")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path = @("$pwd\plasterManifest.xml")
    )

    begin {
        $schemaPath = [System.IO.Path]::Combine($PSScriptRoot, "Schema", "PlasterManifest-v1.xsd")

        # Schema validation is not available on .NET Core - at the moment.
        if ('System.Xml.Schema.XmlSchemaSet' -as [type]) {
            $xmlSchemaSet = New-Object System.Xml.Schema.XmlSchemaSet
            $xmlSchemaSet.Add($TargetNamespace, $schemaPath) > $null
        } else {
            $PSCmdLet.WriteWarning($LocalizedData.TestPlasterNoXmlSchemaValidationWarning)
        }
    }

    process {
        foreach ($aPath in $Path) {
            $aPath = $PSCmdLet.GetUnresolvedProviderPathFromPSPath($aPath)

            if (!(Test-Path -LiteralPath $aPath)) {
                $ex = New-Object System.Management.Automation.ItemNotFoundException ($LocalizedData.ErrorPathDoesNotExist_F1 -f $aPath)
                $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
                $errRecord = New-Object System.Management.Automation.ErrorRecord $ex, 'PathNotFound', $category, $aPath
                $PSCmdLet.WriteError($errRecord)
                return
            }

            $filename = Split-Path $aPath -Leaf

            # Verify the manifest has the correct filename. Allow for localized template manifest files as well.
            $isXmlManifest = ($filename -eq 'plasterManifest.xml') -or ($filename -match 'plasterManifest_[a-zA-Z]+(-[a-zA-Z]+){0,2}.xml')
            $isJsonManifest = ($filename -eq 'plasterManifest.json') -or ($filename -match 'plasterManifest_[a-zA-Z]+(-[a-zA-Z]+){0,2}.json')

            if (!$isXmlManifest -and !$isJsonManifest) {
                Write-Error ($LocalizedData.ManifestWrongFilename_F1 -f $filename)
                return
            }

            # Detect manifest format and process accordingly
            try {
                $manifestType = Get-PlasterManifestType -ManifestPath $aPath
                Write-Verbose "Detected manifest format: $manifestType"
            } catch {
                Write-Error "Failed to determine manifest format for '$aPath': $($_.Exception.Message)"
                return
            }

            # Handle JSON manifests
            if ($manifestType -eq 'JSON') {
                Write-Verbose "Processing JSON manifest: $aPath"

                try {
                    $jsonContent = Get-Content -LiteralPath $aPath -Raw -ErrorAction Stop
                    $validationResult = Test-JsonManifest -JsonContent $jsonContent -Detailed

                    if ($validationResult) {
                        Write-Verbose "JSON manifest validation passed"
                        # Convert JSON to XML for consistent return type
                        $xmlManifest = ConvertFrom-JsonManifest -JsonContent $jsonContent
                        return $xmlManifest
                    } else {
                        Write-Error "JSON manifest validation failed for '$aPath'"
                        return $null
                    }
                } catch {
                    $ex = New-Object System.Exception ("JSON manifest validation failed for '$aPath': $($_.Exception.Message)"), $_.Exception
                    $category = [System.Management.Automation.ErrorCategory]::InvalidData
                    $errRecord = New-Object System.Management.Automation.ErrorRecord $ex, 'InvalidJsonManifestFile', $category, $aPath
                    $PSCmdLet.WriteError($errRecord)
                    return $null
                }
            }

            # Handle XML manifests (existing logic)
            # Verify the manifest loads into an XmlDocument i.e. verify it is well-formed.
            $manifest = $null
            try {
                $manifest = [xml](Get-Content $aPath)
            } catch {
                $ex = New-Object System.Exception ($LocalizedData.ManifestNotWellFormedXml_F2 -f $aPath, $_.Exception.Message), $_.Exception
                $category = [System.Management.Automation.ErrorCategory]::InvalidData
                $errRecord = New-Object System.Management.Automation.ErrorRecord $ex, 'InvalidManifestFile', $category, $aPath
                $psCmdlet.WriteError($errRecord)
                return
            }

            # Validate the manifest contains the required root element and target namespace that the following
            # XML schema validation will apply to.
            if (!$manifest.plasterManifest) {
                Write-Error ($LocalizedData.ManifestMissingDocElement_F2 -f $aPath, $TargetNamespace)
                return
            }

            if ($manifest.plasterManifest.NamespaceURI -cne $TargetNamespace) {
                Write-Error ($LocalizedData.ManifestMissingDocTargetNamespace_F2 -f $aPath, $TargetNamespace)
                return
            }

            # Valid flag is stashed in a hashtable so the ValidationEventHandler scriptblock can set the value.
            $manifestIsValid = @{Value = $true }

            # Configure an XmlReader and XmlReaderSettings to perform schema validation on xml file.
            $xmlReaderSettings = New-Object System.Xml.XmlReaderSettings

            # Schema validation is not available on .NET Core - at the moment.
            if ($xmlSchemaSet) {
                $xmlReaderSettings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings
                $xmlReaderSettings.ValidationType = [System.Xml.ValidationType]::Schema
                $xmlReaderSettings.Schemas = $xmlSchemaSet
            }

            # Schema validation is not available on .NET Core - at the moment.
            if ($xmlSchemaSet) {
                # Event handler scriptblock for the ValidationEventHandler event.
                $validationEventHandler = {
                    param($sender, $eventArgs)

                    if ($eventArgs.Severity -eq [System.Xml.Schema.XmlSeverityType]::Error) {
                        Write-Verbose ($LocalizedData.ManifestSchemaValidationError_F2 -f $aPath, $eventArgs.Message)
                        $manifestIsValid.Value = $false
                    }
                }

                $xmlReaderSettings.add_ValidationEventHandler($validationEventHandler)
            }

            [System.Xml.XmlReader]$xmlReader = $null
            try {
                $xmlReader = [System.Xml.XmlReader]::Create($aPath, $xmlReaderSettings)
                while ($xmlReader.Read()) {}
            } catch {
                Write-Error ($LocalizedData.ManifestErrorReading_F1 -f $_)
                $manifestIsValid.Value = $false
            } finally {
                # Schema validation is not available on .NET Core - at the moment.
                if ($xmlSchemaSet) {
                    $xmlReaderSettings.remove_ValidationEventHandler($validationEventHandler)
                }
                if ($xmlReader) { $xmlReader.Dispose() }
            }

            # Validate default values for choice/multichoice parameters containing 1 or more ints
            $xpath = "//tns:parameter[@type='choice'] | //tns:parameter[@type='multichoice']"
            $choiceParameters = Select-Xml -Xml $manifest -XPath $xpath  -Namespace @{tns = $TargetNamespace }
            foreach ($choiceParameterXmlInfo in $choiceParameters) {
                $choiceParameter = $choiceParameterXmlInfo.Node
                if (!$choiceParameter.default) { continue }

                if ($choiceParameter.type -eq 'choice') {
                    if ($null -eq ($choiceParameter.default -as [int])) {
                        $PSCmdLet.WriteVerbose(($LocalizedData.ManifestSchemaInvalidChoiceDefault_F3 -f $choiceParameter.default, $choiceParameter.name, $aPath))
                        $manifestIsValid.Value = $false
                    }
                } else {
                    if ($null -eq (($choiceParameter.default -split ',') -as [int[]])) {
                        $PSCmdLet.WriteVerbose(($LocalizedData.ManifestSchemaInvalidMultichoiceDefault_F3 -f $choiceParameter.default, $choiceParameter.name, $aPath))
                        $manifestIsValid.Value = $false
                    }
                }
            }

            # Validate that the requireModule attribute requiredVersion is mutually exclusive from both
            # the version and maximumVersion attributes.
            $requireModules = Select-Xml -Xml $manifest -XPath '//tns:requireModule' -Namespace @{tns = $TargetNamespace }
            foreach ($requireModuleInfo in $requireModules) {
                $requireModuleNode = $requireModuleInfo.Node
                if ($requireModuleNode.requiredVersion -and ($requireModuleNode.minimumVersion -or $requireModuleNode.maximumVersion)) {
                    $PSCmdLet.WriteVerbose(($LocalizedData.ManifestSchemaInvalidRequireModuleAttrs_F2 -f $requireModuleNode.name, $aPath))
                    $manifestIsValid.Value = $false
                }
            }

            # Validate that all the condition attribute values are valid PowerShell script.
            $conditionAttrs = Select-Xml -Xml $manifest -XPath '//@condition'
            foreach ($conditionAttr in $conditionAttrs) {
                $tokens = $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($conditionAttr.Node.Value, [ref] $tokens, [ref] $errors)
                if ($errors.Count -gt 0) {
                    $msg = $LocalizedData.ManifestSchemaInvalidCondition_F3 -f $conditionAttr.Node.Value, $aPath, $errors[0]
                    $PSCmdLet.WriteVerbose($msg)
                    $manifestIsValid.Value = $false
                }
            }

            # Validate all interpolated attribute values are valid within a PowerShell string interpolation context.
            $interpolatedAttrs = @(Select-Xml -Xml $manifest -XPath '//tns:parameter/@default' -Namespace @{tns = $TargetNamespace })
            $interpolatedAttrs += @(Select-Xml -Xml $manifest -XPath '//tns:parameter/@prompt' -Namespace @{tns = $TargetNamespace })
            $interpolatedAttrs += @(Select-Xml -Xml $manifest -XPath '//tns:content/tns:*/@*' -Namespace @{tns = $TargetNamespace })
            foreach ($interpolatedAttr in $interpolatedAttrs) {
                $name = $interpolatedAttr.Node.LocalName
                if ($name -eq 'condition') { continue }

                $tokens = $errors = $null
                $value = $interpolatedAttr.Node.Value
                $null = [System.Management.Automation.Language.Parser]::ParseInput("`"$value`"", [ref] $tokens, [ref] $errors)
                if ($errors.Count -gt 0) {
                    $ownerName = $interpolatedAttr.Node.OwnerElement.LocalName
                    $msg = $LocalizedData.ManifestSchemaInvalidAttrValue_F5 -f $name, $value, $ownerName, $aPath, $errors[0]
                    $PSCmdLet.WriteVerbose($msg)
                    $manifestIsValid.Value = $false
                }
            }

            if ($manifestIsValid.Value) {
                # Verify manifest schema version is supported.
                $manifestSchemaVersion = [System.Version]$manifest.plasterManifest.schemaVersion

                # Use a simplified form (no patch version) of semver for checking XML schema version compatibility.
                if (($manifestSchemaVersion.Major -gt $LatestSupportedSchemaVersion.Major) -or
                    (($manifestSchemaVersion.Major -eq $LatestSupportedSchemaVersion.Major) -and
                     ($manifestSchemaVersion.Minor -gt $LatestSupportedSchemaVersion.Minor))) {

                    Write-Error ($LocalizedData.ManifestSchemaVersionNotSupported_F2 -f $manifestSchemaVersion, $aPath)
                    return
                }

                # Verify that the plasterVersion is supported.
                if ($manifest.plasterManifest.plasterVersion) {
                    $requiredPlasterVersion = [System.Version]$manifest.plasterManifest.plasterVersion

                    # Is user specifies major.minor, change build to 0 (from default of -1) so compare works correctly.
                    if ($requiredPlasterVersion.Build -eq -1) {
                        $requiredPlasterVersion = [System.Version]"${requiredPlasterVersion}.0"
                    }

                    if ($requiredPlasterVersion -gt $MyInvocation.MyCommand.Module.Version) {
                        $plasterVersion = $manifest.plasterManifest.plasterVersion
                        Write-Error ($LocalizedData.ManifestPlasterVersionNotSupported_F2 -f $aPath, $plasterVersion)
                        return
                    }
                }

                $manifest
            } else {
                if ($PSBoundParameters['Verbose']) {
                    Write-Error ($LocalizedData.ManifestNotValid_F1 -f $aPath)
                } else {
                    Write-Error ($LocalizedData.ManifestNotValidVerbose_F1 -f $aPath)
                }
            }
        }
    }
}
# spell-checker:ignore Multichoice Assigments
# Import localized data
data LocalizedData {
    # culture="en-US"
    ConvertFrom-StringData @'
    DestPath_F1=Destination path: {0}
    ErrorFailedToLoadStoreFile_F1=Failed to load the default value store file: '{0}'.
    ErrorProcessingDynamicParams_F1=Failed to create dynamic parameters from the template's manifest file.  Template-based dynamic parameters will not be available until the error is corrected.  The error was: {0}
    ErrorTemplatePathIsInvalid_F1=The TemplatePath parameter value must refer to an existing directory. The specified path '{0}' does not.
    ErrorUnencryptingSecureString_F1=Failed to unencrypt value for parameter '{0}'.
    ErrorPathDoesNotExist_F1=Cannot find path '{0}' because it does not exist.
    ErrorPathMustBeRelativePath_F2=The path '{0}' specified in the {1} directive in the template manifest cannot be an absolute path.  Change the path to a relative path.
    ErrorPathMustBeUnderDestPath_F2=The path '{0}' must be under the specified DestinationPath '{1}'.
    ExpressionInvalid_F2=The expression '{0}' is invalid or threw an exception. Error: {1}
    ExpressionNonTermErrors_F2=The expression '{0}' generated error output - {1}
    ExpressionExecError_F2=PowerShell expression failed execution. Location: {0}. Error: {1}
    ExpressionErrorLocationFile_F2=<{0}> attribute '{1}'
    ExpressionErrorLocationModify_F1=<modify> attribute '{0}'
    ExpressionErrorLocationNewModManifest_F1=<newModuleManifest> attribute '{0}'
    ExpressionErrorLocationParameter_F2=<parameter> name='{0}', attribute '{1}'
    ExpressionErrorLocationRequireModule_F2=<requireModule> name='{0}', attribute '{1}'
    ExpressionInvalidCondition_F3=The Plaster manifest condition '{0}' failed. Location: {1}. Error: {2}
    InterpolationError_F3=The Plaster manifest attribute value '{0}' failed string interpolation. Location: {1}. Error: {2}
    FileConflict=Plaster file conflict
    ManifestFileMissing_F1=The Plaster manifest file '{0}' was not found.
    ManifestMissingDocElement_F2=The Plaster manifest file '{0}' is missing the document element. It should be specified as <plasterManifest xmlns="{1}"></plasterManifest>.
    ManifestMissingDocTargetNamespace_F2=The Plaster manifest file '{0}' is missing or has an invalid target namespace on the document element. It should be specified as <plasterManifest xmlns="{1}"></plasterManifest>.
    ManifestPlasterVersionNotSupported_F2=The template file '{0}' specifies a plasterVersion of {1} which is greater than the installed version of Plaster. Update the Plaster module and try again.
    ManifestSchemaInvalidAttrValue_F5=Invalid '{0}' attribute value '{1}' on '{2}' element in file '{3}'. Error: {4}
    ManifestSchemaInvalidCondition_F3=Invalid condition '{0}' in file '{1}'. Error: {2}
    ManifestSchemaInvalidChoiceDefault_F3=Invalid default attribute value '{0}' for parameter '{1}' in file '{2}'. The default value must specify a zero-based integer index that corresponds to the default choice.
    ManifestSchemaInvalidMultichoiceDefault_F3=Invalid default attribute value '{0}' for parameter '{1}' in file '{2}'. The default value must specify one or more zero-based integer indexes in a comma separated list that correspond to the default choices.
    ManifestSchemaInvalidRequireModuleAttrs_F2=The requireModule attribute 'requiredVersion' for module '{0}' in file '{1}' cannot be used together with either the 'minimumVersion' or 'maximumVersion' attribute.
    ManifestSchemaValidationError_F2=Plaster manifest schema error in file '{0}'. Error: {1}
    ManifestSchemaVersionNotSupported_F2=The template's manifest schema version ({0}) in file '{1}' requires a newer version of Plaster. Update the Plaster module and try again.
    ManifestErrorReading_F1=Error reading Plaster manifest: {0}
    ManifestNotValid_F1=The Plaster manifest '{0}' is not valid.
    ManifestNotValidVerbose_F1=The Plaster manifest '{0}' is not valid. Specify -Verbose to see the specific schema errors.
    ManifestNotWellFormedXml_F2=The Plaster manifest '{0}' is not a well-formed XML file. {1}
    ManifestWrongFilename_F1=The Plaster manifest filename '{0}' is not valid. The value of the Path argument must refer to a file named 'plasterManifest.xml' or 'plasterManifest_<culture>.xml'. Change the Plaster manifest filename and then try again.
    MissingParameterPrompt_F1=<Missing prompt value for parameter '{0}'>
    NewModManifest_CreatingDir_F1=Creating destination directory for module manifest: {0}
    OpConflict=Conflict
    OpCreate=Create
    OpForce=Force
    OpIdentical=Identical
    OpMissing=Missing
    OpModify=Modify
    OpUpdate=Update
    OpVerify=Verify
    OverwriteFile_F1=Overwrite {0}
    ParameterTypeChoiceMultipleDefault_F1=Parameter name {0} is of type='choice' and can only have one default value.
    RequireModuleVerified_F2=The required module {0}{1} is already installed.
    RequireModuleMissing_F2=The required module {0}{1} was not found.
    RequireModuleMinVersion_F1=minimum version: {0}
    RequireModuleMaxVersion_F1=maximum version: {0}
    RequireModuleRequiredVersion_F1=required version: {0}
    ShouldCreateNewPlasterManifest=Create Plaster manifest
    ShouldProcessCreateDir=Create directory
    ShouldProcessExpandTemplate=Expand template file
    ShouldProcessNewModuleManifest=Create new module manifest
    TempFileOperation_F1={0} into temp file before copying to destination
    TempFileTarget_F1=temp file for '{0}'
    TestPlasterNoXmlSchemaValidationWarning=The version of .NET Core that PowerShell is running on does not support XML schema-based validation. Test-PlasterManifest will operate in "limited validation" mode primarily verifying the specified manifest file is well-formed XML. For full, XML schema-based validation, run this command on Windows PowerShell.
    UnrecognizedParametersElement_F1=Unrecognized manifest parameters child element: {0}.
    UnrecognizedParameterType_F2=Unrecognized parameter type '{0}' on parameter name '{1}'.
    UnrecognizedContentElement_F1=Unrecognized manifest content child element: {0}.
'@
}

# Import localized data with improved error handling
try {
    Microsoft.PowerShell.Utility\Import-LocalizedData LocalizedData -FileName 'Plaster.Resources.psd1' -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Failed to import localized data: $_"
}

# Module variables with proper scoping and type safety
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$PlasterVersion = (Test-ModuleManifest -Path (Join-Path $PSScriptRoot 'Plaster.psd1')).Version

[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$JsonSchemaPath = Join-Path $PSScriptRoot "Schema\plaster-manifest-v2.json"

[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$LatestSupportedSchemaVersion = [System.Version]'1.2'

[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$TargetNamespace = "http://www.microsoft.com/schemas/PowerShell/Plaster/v1"

[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$DefaultEncoding = 'UTF8-NoBOM'

# Cross-platform parameter store path configuration
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$ParameterDefaultValueStoreRootPath = switch ($true) {
    # Windows (both Desktop and Core)
    (($PSVersionTable.PSVersion.Major -le 5) -or ($PSVersionTable.PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)) {
        if ($env:LOCALAPPDATA) {
            "$env:LOCALAPPDATA\Plaster"
        } else {
            "$env:USERPROFILE\AppData\Local\Plaster"
        }
    }
    # Linux - Follow XDG Base Directory Specification
    ($IsLinux -eq $true) {
        if ($env:XDG_DATA_HOME) {
            "$env:XDG_DATA_HOME/plaster"
        } else {
            "$Home/.local/share/plaster"
        }
    }
    # macOS and other Unix-like systems
    default {
        "$Home/.plaster"
    }
}

# Enhanced platform detection with fallback
if (-not (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue)) {
    $script:IsWindows = $PSVersionTable.PSVersion.Major -le 5 -or $PSVersionTable.PSEdition -eq 'Desktop'
}

if (-not (Get-Variable -Name 'IsLinux' -ErrorAction SilentlyContinue)) {
    $script:IsLinux = $false
}

if (-not (Get-Variable -Name 'IsMacOS' -ErrorAction SilentlyContinue)) {
    $script:IsMacOS = $false
}

# .NET Core compatibility check for XML Schema validation
$script:XmlSchemaValidationSupported = $null -ne ('System.Xml.Schema.XmlSchemaSet' -as [type])

if (-not $script:XmlSchemaValidationSupported) {
    Write-Verbose "XML Schema validation is not supported on this platform. Limited validation will be performed."
}

# Module logging configuration
$script:LogLevel = if ($env:PLASTER_LOG_LEVEL) { $env:PLASTER_LOG_LEVEL } else { 'Information' }

# Global variables and constants for Plaster 2.0

# Enhanced $TargetNamespace definition with proper scoping
if (-not (Get-Variable -Name 'TargetNamespace' -Scope Script -ErrorAction SilentlyContinue)) {
    Set-Variable -Name 'TargetNamespace' -Value 'http://www.microsoft.com/schemas/PowerShell/Plaster/v1' -Scope Script -Option ReadOnly
}

# Enhanced $DefaultEncoding definition
if (-not (Get-Variable -Name 'DefaultEncoding' -Scope Script -ErrorAction SilentlyContinue)) {
    Set-Variable -Name 'DefaultEncoding' -Value 'UTF8-NoBOM' -Scope Script -Option ReadOnly
}

# JSON Schema version for new manifests
if (-not (Get-Variable -Name 'JsonSchemaVersion' -Scope Script -ErrorAction SilentlyContinue)) {
    Set-Variable -Name 'JsonSchemaVersion' -Value '2.0' -Scope Script -Option ReadOnly
}

# Export the variables that need to be available globally
Export-ModuleMember -Variable @('TargetNamespace', 'DefaultEncoding', 'JsonSchemaVersion')

# Module cleanup on removal
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Write-PlasterLog -Level Information -Message "Plaster module is being removed"

    # Clean up any module-scoped variables or resources
    Remove-Variable -Name 'PlasterVersion' -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name 'LatestSupportedSchemaVersion' -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name 'TargetNamespace' -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name 'DefaultEncoding' -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name 'ParameterDefaultValueStoreRootPath' -Scope Script -ErrorAction SilentlyContinue
}

# Module initialization complete
Write-PlasterLog -Level Information -Message "Plaster v$PlasterVersion module loaded successfully (PowerShell $($PSVersionTable.PSVersion))"

