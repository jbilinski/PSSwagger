﻿Microsoft.PowerShell.Core\Set-StrictMode -Version Latest

# Have to require these for now until we start using NuGet packages for all dependencies (e.g. Microsoft.Rest.ClientRuntime.dll)
if ((Get-Variable -Name PSEdition -ErrorAction Ignore) -and ('Core' -eq $PSEdition)) {
    . (Join-Path -Path "$PSScriptRoot" -ChildPath "Test-CoreRequirements.ps1")
    $moduleName = 'AzureRM.Profile.NetCore.Preview'
} else {
    . (Join-Path -Path "$PSScriptRoot" -ChildPath "Test-FullRequirements.ps1")
    $moduleName = 'AzureRM.Profile'
}

<#
.DESCRIPTION
  Gets the content of a file. Removes the signature block, if it exists.

.PARAMETER
  Path to the file whose contents should be read.
#>
function Get-SignedCodeContent {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $content = Get-Content -Path $Path
    if ($content) {
        $sigStartOneIndexed = $content | Select-String "# SIG # Begin signature block"
        $sigEnd = $content | Select-String "# SIG # End signature block"
        if ($sigEnd -and $sigStartOneIndexed) {
            $content[0..($sigStartOneIndexed.LineNumber-2)]
        } else {
            $content
        }
    }
}

<#
.DESCRIPTION
  Gets the list of required modules to be imported for the scriptblock.

.PARAMETER  ModuleInfo
  PSModuleInfo object of the Swagger command.
#>
function Get-RequiredModulesPath
{
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSModuleInfo]
        $ModuleInfo
    )
    
    $ModulePaths = @()
    $ModulePaths += $ModuleInfo.RequiredModules | ForEach-Object { Get-RequiredModulesPath -ModuleInfo $_}

    $ManifestPath = Join-Path -Path (Split-Path -Path $ModuleInfo.Path -Parent) -ChildPath "$($ModuleInfo.Name).psd1"
    if(Test-Path -Path $ManifestPath)
    {
        $ModulePaths += $ManifestPath
    }
    else
    {
        $ModulePaths += $ModuleInfo.Path
    }

    return $ModulePaths | Select-Object -Unique
}

<#
.DESCRIPTION
  Invokes the specified script block as PSSwaggerJob.

.PARAMETER  ScriptBlock
  ScriptBlock to be executed in the PSSwaggerJob

.PARAMETER  CallerPSCmdlet
  Called $PSCmldet object to set the failure status.

.PARAMETER  CallerPSBoundParameters
  Parameters to be passed into the specified script block.

.PARAMETER  CallerModule
  PSModuleInfo object of the Swagger command.
#>
function Invoke-SwaggerCommandUtility
{
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.ScriptBlock]
        $ScriptBlock,

        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCmdlet]
        $CallerPSCmdlet,

        [Parameter(Mandatory=$true)]
        $CallerPSBoundParameters,

        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSModuleInfo]
        $CallerModule
    )

    $AsJob = $false
    if($CallerPSBoundParameters.ContainsKey('AsJob'))
    {
        $AsJob = $true
    }
    
    $null = $CallerPSBoundParameters.Remove('WarningVariable')
    $null = $CallerPSBoundParameters.Remove('ErrorVariable')
    $null = $CallerPSBoundParameters.Remove('OutVariable')
    $null = $CallerPSBoundParameters.Remove('OutBuffer')
    $null = $CallerPSBoundParameters.Remove('PipelineVariable')
    $null = $CallerPSBoundParameters.Remove('InformationVariable')
    $null = $CallerPSBoundParameters.Remove('InformationAction')
    $null = $CallerPSBoundParameters.Remove('AsJob')

    $PSSwaggerJobParameters = @{}
    $PSSwaggerJobParameters['ScriptBlock'] = $ScriptBlock

    # Required modules list    
    if ($CallerModule)
    {        
        $PSSwaggerJobParameters['RequiredModules'] = Get-RequiredModulesPath -ModuleInfo $CallerModule
    }

    $VerbosePresent = $false
    if (-not $CallerPSBoundParameters.ContainsKey('Verbose'))
    {
        if($VerbosePreference -in 'Continue','Inquire')
        {
            $CallerPSBoundParameters['Verbose'] = [System.Management.Automation.SwitchParameter]::Present
            $VerbosePresent = $true
        }
    }
    else
    {
        $VerbosePresent = $true
    }

    $DebugPresent = $false
    if (-not $CallerPSBoundParameters.ContainsKey('Debug'))
    {
        if($debugPreference -in 'Continue','Inquire')
        {
            $CallerPSBoundParameters['Debug'] = [System.Management.Automation.SwitchParameter]::Present
            $DebugPresent = $true
        }
    }
    else
    {
        $DebugPresent = $true
    }

    if (-not $CallerPSBoundParameters.ContainsKey('ErrorAction'))
    {
        $CallerPSBoundParameters['ErrorAction'] = $errorActionPreference
    }

    if(Test-Path variable:\errorActionPreference)
    {
        $errorAction = $errorActionPreference
    }
    else
    {
        $errorAction = 'Continue'
    }

    if ($CallerPSBoundParameters['ErrorAction'] -eq 'SilentlyContinue')
    {
        $errorAction = 'SilentlyContinue'
    }

    if($CallerPSBoundParameters['ErrorAction'] -eq 'Ignore')
    {
        $CallerPSBoundParameters['ErrorAction'] = 'SilentlyContinue'
        $errorAction = 'SilentlyContinue'
    }

    if ($CallerPSBoundParameters['ErrorAction'] -eq 'Inquire')
    {
        $CallerPSBoundParameters['ErrorAction'] = 'Continue'
        $errorAction = 'Continue'
    }

    if (-not $CallerPSBoundParameters.ContainsKey('WarningAction'))
    {
        $CallerPSBoundParameters['WarningAction'] = $warningPreference
    }

    if(Test-Path variable:\warningPreference)
    {
        $warningAction = $warningPreference
    }
    else
    {
        $warningAction = 'Continue'
    }

    if ($CallerPSBoundParameters['WarningAction'] -in 'SilentlyContinue','Ignore')
    {
        $warningAction = 'SilentlyContinue'
    }

    if ($CallerPSBoundParameters['WarningAction'] -eq 'Inquire')
    {
        $CallerPSBoundParameters['WarningAction'] = 'Continue'
        $warningAction = 'Continue'
    }

    if($CallerPSBoundParameters)
    {
        $PSSwaggerJobParameters['Parameters'] = $CallerPSBoundParameters
    }

    $job = Start-PSSwaggerJob @PSSwaggerJobParameters

    if($job)
    {
        if($AsJob)
        {
            $job
        }
        else
        {
            try
            {
                Receive-Job -Job $job -Wait -Verbose:$VerbosePresent -Debug:$DebugPresent -ErrorAction $errorAction -WarningAction $warningAction

                if($CallerPSCmdlet)
                {
                    $CallerPSCmdlet.InvokeCommand.HasErrors = $job.State -eq 'Failed'
                }
            }
            finally
            {
                if($job.State -ne "Suspended" -and $job.State -ne "Stopped")
                {
                    Get-Job -Id $job.Id -ErrorAction Ignore | Remove-Job -Force -ErrorAction Ignore
                }
                else
                {
                    $job
                }
            }
        }
    }
}

$PSSwaggerJobAssemblyPath = $null

if(('Microsoft.PowerShell.Commands.PSSwagger.PSSwaggerJob' -as [Type]) -and
   (Test-Path -Path [Microsoft.PowerShell.Commands.PSSwagger.PSSwaggerJob].Assembly.Location -PathType Leaf))
{
    # This is for re-import scenario.
    $PSSwaggerJobAssemblyPath = [Microsoft.PowerShell.Commands.PSSwagger.PSSwaggerJob].Assembly.Location
}
else
{
    $PSSwaggerJobFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'PSSwaggerNetUtilities.Code.ps1'
    if(Test-Path -Path $PSSwaggerJobFilePath -PathType Leaf)
    {
        $sig = Get-AuthenticodeSignature -FilePath $PSSwaggerJobFilePath
        if (('Valid' -ne $sig.Status) -and ('NotSigned' -ne $sig.Status)) {
            throw 'Failed to validate PSSwaggerNetUtilities.Code.ps1''s signature'
        }

        $PSSwaggerJobSourceString = Get-SignedCodeContent -Path $PSSwaggerJobFilePath | Out-String

        $RequiredAssemblies = @(
            [System.Management.Automation.PSCmdlet].Assembly.FullName,
            [System.ComponentModel.AsyncCompletedEventArgs].Assembly.FullName,
            [System.Linq.Enumerable].Assembly.FullName,
            [System.Collections.StructuralComparisons].Assembly.FullName,
			[System.Net.Http.HttpRequestMessage].Assembly.FullName
        )

		if ((Get-Variable -Name PSEdition -ErrorAction Ignore) -and ('Core' -eq $PSEdition)) {
			$module = Get-Module -Name AzureRM.Profile.NetCore.Preview -ListAvailable | 
						  Select-Object -First 1 -ErrorAction Ignore
		} else {
			$module = Get-Module -Name AzureRM.Profile -ListAvailable | 
						  Select-Object -First 1 -ErrorAction Ignore
		}
		
		if ($module) {
			$RequiredAssemblies += (Join-Path -Path "$($module.ModuleBase)" -ChildPath 'Microsoft.Rest.ClientRuntime.dll')
		}
		
        $TempPath = [System.IO.Path]::GetTempPath() + [System.IO.Path]::GetRandomFileName()
        $null = New-Item -Path $TempPath -ItemType Directory -Force
        $PSSwaggerJobAssemblyPath = Join-Path -Path $TempPath -ChildPath 'Microsoft.PowerShell.PSSwagger.Utility.dll'

        Add-Type -ReferencedAssemblies $RequiredAssemblies `
                 -TypeDefinition $PSSwaggerJobSourceString `
                 -OutputAssembly $PSSwaggerJobAssemblyPath `
                 -Language CSharp `
                 -WarningAction Ignore `
                 -IgnoreWarnings
    } 
}

if(Test-Path -LiteralPath $PSSwaggerJobAssemblyPath -PathType Leaf)
{
    # It is required to import the generated assembly into the module scope 
    # to register the PSSwaggerJobSourceAdapter with the PowerShell Job infrastructure.
    Import-Module -Name $PSSwaggerJobAssemblyPath
}

if(-not ('Microsoft.PowerShell.Commands.PSSwagger.PSSwaggerJob' -as [Type]))
{
    Write-Error -Message "Unable to add PSSwaggerJob type."
}

Import-Module -Name (Join-Path -Path "$PSScriptRoot" -ChildPath "PSSwaggerClientTracing.psm1")