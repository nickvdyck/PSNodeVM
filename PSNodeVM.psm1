﻿#---------------------------------------------------------
# PSNodeVM Functions
#---------------------------------------------------------
function Install-Node 
{
    [CmdletBinding()]
    Param
    (
        [ValidatePattern("^[\d]+\.[\d]+.[\d]+$|latest")]
        [ValidateScript({(Get-NodeVersion -ListOnline) -contains "v$($_)" -or $_ -eq "latest" })]
        [String]$Version = "latest"
    )

    Begin
    {   
        $config = Get-PSNodeConfig
        $versionCopy = @{$true="latest"; $false="v$($Version)"}[$Version -eq "latest"]        

        $nodeUri = "$($config.NodeWeb)$($versionCopy)/$($config.OSArch)/$($nodeExe)"
        $installPath = "$($config.NodeHome)$($versionCopy)\"
        $outFile = "$($installPath)$($nodeExe)"
    }
    Process
    {
        Write-Verbose "Starting install for node version: $versionCopy"

        if((Test-Path $installPath) -eq $false){
            Write-Verbose "The path $installPath does not exist yet. Creating path ..."
            New-Item $installPath -ItemType Directory | Out-Null
        }    

        Fetch-HTTP -Uri $nodeUri -OutFile $outFile
        Write-Verbose "Download complete file saved at: $outFile"
    }
}

function Update-Node
{
    Install-Node
}

function Set-NodeVersion
{
}

function Get-NodeVersion
{
    [CmdletBinding(DefaultParameterSetName="InstalledVersions")]
    Param
    (
        [Parameter(ParameterSetName="InstalledVersions")]
        [Switch]$ListInstalled,
        [Parameter(Mandatory=$false,ParameterSetName="OnlineVersions")]
        [Switch]$ListOnline      
    )
    
    $config = Get-PSNodeConfig
    
    if($PSCmdlet.ParameterSetName -eq "InstalledVersions")
    {
        Write-Verbose "ParemeterSetName == InstalledVersions"
        if($ListInstalled -eq $true){
            $Output =  [Array]((ls "$($config.NodeHome)" -Directory -Filter "v*").Name)
            $Output += "latest -> $(node -v)"
        }
        else{
            $Output = (node -v)
        }
    }
    elseif($PSCmdlet.ParameterSetName -eq "OnlineVersions")
    {
        Write-Verbose "ParemeterSetName == OnlineVersions"

        if($script:nodeVersions.Count -eq 0)
        {
            Write-Verbose "Getting all node versions from $($config.NodeWeb)"
            $script:nodeVersions = @()

            $nodeVPage = (Fetch-HTTP -Uri "$($config.NodeWeb)").Content        
        
            $regex = '<a\s*href="(?<NodeV>(?:v[\d]{1,3}(?:.[\d]{1,3}){2})|(?:latest))\/\s*"\s*>'

            Write-Verbose "Cachinge response in nodeVersions global script variable"
            foreach($nodeVersion in ([regex]::Matches($nodeVPage, $regex))){
                $script:nodeVersions += $nodeVersion.Groups["NodeV"].Value      
            }
        }

        Write-Verbose "Output cached node versions array!"
        $Output = $script:nodeVersions 
    }

    Write-Output $Output
}

function Start-Node{
    
    [CmdletBinding()]
    Param
    (
        [ValidatePattern("^[\d]+\.[\d]+.[\d]+$|latest")]
        [ValidateScript({(Get-NodeVersion -ListInstalled) -contains "v$($_)" -or $_ -eq "latest" })]
        [String]$Version="latest",
        [String]$Params
    )

    $nodeVersion = @{$true="latest"; $false="v$Version"}[$Version -eq "latest"]

    ."$((Get-PSNodeConfig).NodeHome)$($nodeVersion)\node.exe" $($Params -split " ")
}

function Install-Npm
{
   $config = Get-PSNodeConfig

   if((Test-Path "$($config.NodeHome)node_modules\npm\bin\npm-cli.js") -eq $false)
   {
        $npmInfo = (ConvertFrom-Json -InputObject (Fetch-HTTP $config.NPMWeb)) 
        
        $tgzFile = "npm-$($npmINfo.'dist-tags'.latest).tgz"
        $tarFile = "npm-$($npmINfo.'dist-tags'.latest).tar"
        
        Fetch-HTTP "$($config.NPMWeb)/-/$tgzFile" -OutFile "$($config.NodeHome)$tgzFile"
        # https://registry.npmjs.org/npm/-/npm-1.4.10.tgz
        
        (7zip x "$($config.NodeHome)$tgzFile" -o"$($config.NodeHome)" -y) | Out-Null
        (7zip x "$($config.NodeHome)$tarFile" -o"$($config.NodeHome)node_modules" -y) | Out-Null

        Rename-Item "$($config.NodeHome)node_modules\package" "npm"

        Write-Verbose "Copy $PSScriptRoot\Config\npmrc to $($config.NodeHome)node_modules\npm"
        Copy-Item "$PSScriptRoot\Config\npmrc" "$($config.NodeHome)node_modules\npm"

        Write-Verbose "Clean up home folder:"
        
        Write-Verbose "Remove: $($config.NodeHome)$tgzFile" 
        Remove-Item "$($config.NodeHome)$tgzFile"
        
        Write-Verbose "Remove: $($config.NodeHome)$tarFile"
        Remove-Item "$($config.NodeHome)$tarFile"             
   }
}

function Create-NodeCommand
{
    Param
    (
        [String]$Name,
        [String]$Folder=$Name
    ) 
    "node `$PSScriptRoot\node_modules\$Folder\bin\$Name `$args" | Out-File "$($env:APPDATA)\npm\$Name.ps1" -Force
}

#---------------------------------------------------------
# Node and npm shorthand commands
#---------------------------------------------------------
function node
{
    #Split $args variable to different string -> otherwise $args will be interpreted as one parameter
    ."$((Get-PSNodeConfig).NodeHome)latest\node.exe" $($args -split " ")
}

function npm 
{  
    node "$((Get-PSNodeConfig).NodeHome)node_modules\npm\bin\npm-cli.js" $args
}

#---------------------------------------------------------
#PSNodeJSManager Functions
#---------------------------------------------------------
function Get-PSNodeConfig
{
    #will always return the global config object
    if($script:config -eq $null)
    {
        $script:config = (Import-PSNodeJSManagerConfig).PSNodeJSManager
    }

    Write-Output $script:config
}

function Import-PSNodeJSManagerConfig
{
    $fileName = "PSNodeJSManagerConfig.xml"
    $path = @{$true="$PSScriptRoot\..\$fileName"; $false="$PSScriptRoot\$fileName"}[(Test-Path "$PSScriptRoot\..\$fileName")]
    
    $config = ([xml](Get-Content $path)) 

    Write-Output $config
}

function Setup-PSNodeJSManagerEnvironment
{
    [CmdletBinding()]
    Param()

    Write-Verbose "Get configuration object"
    $config = Get-PSNodeConfig
    Write-Verbose $config

    Write-Verbose "Checking NodeHome path: $($config.NodeHome)"
    if(!(Test-Path $config.NodeHome))
    {
        Write-Verbose "Home Path not set: creating new home folder: $($config.NodeHome)"
        New-Item -Path $config.NodeHome -ItemType Directory | Out-Null
    }

    Write-Verbose "Install latest node version!"
    Install-Node

    Write-Verbose "Install latest npm version to $($config.NodeHome)node_modules\npm"
    Install-NPM

    Write-Verbose "Check if global npm repo is in path: $($env:APPDATA)\npm"
    #Add global npm repo to path-> this all installed modules will still be available
    $path = (([System.Environment]::GetEnvironmentVariable("PATH", "Process")) -split ";")

    if($path -notcontains "$($env:APPDATA)\npm")
    {
        Write-Verbose "Global npm repo not in path!"

        $userString = ([System.Environment]::GetEnvironmentVariable("PATH", "User"))        
        $userPath = @{$true=@(); $false=($userString -split ";")}[$userString -eq $null -or $userString -eq ""]        
        $userPath += "$($env:APPDATA)\npm"
        [System.Environment]::SetEnvironmentVariable("PATH", ($userPath -join ";"), "User");
        
        Write-Verbose "Update path"
        $env:PATH = "$([System.Environment]::GetEnvironmentVariable("PATH", "Machine"))"
        $env:PATH += ";$([System.Environment]::GetEnvironmentVariable("PATH", "User"))"
    }
    else
    {
        Write-Verbose "Global npm repo already in path!"
    }
}

#---------------------------------------------------------
# Helper functions
#---------------------------------------------------------
function Fetch-HTTP
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, Position=0)]
        [String]$Uri,
        [Parameter(Mandatory=$false, Position=1)]
        [String]$OutFile
    )

    if($env:HTTP_PROXY -eq $null){
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile
    }
    else{
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -Proxy $env:HTTP_PROXY
    }
}

function Get-CPUArchitecture
{
   $arch = (@{
                $true="x64";
                $false="";
            }[(Get-CimInstance Win32_OperatingSystem).OSARchitecture -eq "64-bit"])
            
   Write-Output $arch
}

#---------------------------------------------------------
# Set global module variables | TO-DO find better implementation
#---------------------------------------------------------
(Get-PSNodeConfig).OSArch = [string](Get-CPUArchitecture)

$nodeExe = "node.exe"
$nodeVersions = @()

#---------------------------------------------------------
# Testing functions only |Remove on live
#---------------------------------------------------------


#---------------------------------------------------------
# Aliases
#---------------------------------------------------------
Set-Alias -Name 7zip -Value "$($env:ProgramFiles)\7-Zip\7z.exe"

#-------------------------------------------------
# Export global functions values and aliases
#---------------------------------------------------------
Export-ModuleMember -Function Install-Node
Export-ModuleMember -Function Update-Node
Export-ModuleMember -Function Set-Node
Export-ModuleMember -Function Start-Node
Export-ModuleMember -Function Get-NodeVersion
Export-ModuleMember -Function Set-NodeVersion
Export-ModuleMember -Function Create-NodeCommand

Export-ModuleMember -Function Setup-PSNodeJSManagerEnvironment

Export-ModuleMember -Function Install-NPM
Export-ModuleMember -Function Get-CPUArchitecture
Export-ModuleMember -Function Get-PSNodeConfig

Export-ModuleMember -Function npm
Export-ModuleMember -Function node

#---------------------------------------------------------