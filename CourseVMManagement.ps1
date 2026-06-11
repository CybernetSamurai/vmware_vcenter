# Clear Loaded Modules from Memory
# --------------------------------
Get-Module | Remove-Module -Force

# VMware PowerCLI
# ---------------
Import-Module VMware.VimAutomation.Core

# Active-Directory
# ----------------
Import-Module ActiveDirectory

# Custom Modules
# --------------
$customModulesPath = "\\path\to\Custom_Modules"
Import-Module $customModulesPath\vLab.Utilities\vLab.Utilities.psm1       -Force
Import-Module $customModulesPath\vLab.VMManagement\vLab.VMManagement.psm1 -Force

# Kill Script When Error is Found
# -------------------------------
$ErrorActionPreference = "Stop"

# Message of the Day
# ------------------
function Show-MOTD {
    $lastUpdated = "2025.04"
    $version = "v1.6.1"

    #Clear-Host
    Write-Host "+------------------------------------------+"
    Write-Host "|            Course VM Management          |"
    Write-Host "|                  $version                  |"
    Write-Host "+------------------------------------------+"
    Write-Host "| Last Updated: $lastUpdated              |"
    Write-Host "+------------------------------------------+"
}

# Clear Active vCenter Connections
# --------------------------------
#if ($global:DefaultVIServer) {
#	Disconnect-VIServer -Confirm:$false
#}

# Server Details
# --------------
function Get-ServerDetails {
    Write-Host "`r`nENTER SERVER DETAILS"

    # Default server values
    $defaultvCenter = "server.domain.org"
    $defaultCluster = "ClusterSTVM"
    $defaultVMFolder = "Course_VMs"

    $vCenterServer = Read-Host -Prompt "[+] VCENTER [$defaultvCenter]"
    $clusterName   = Read-Host -Prompt "[+] CLUSTER [$defaultCluster]"
    $folderName    = Read-Host -Prompt "[+] FOLDER [$defaultVMFolder]"

    $vCenterServer = if ([string]::IsNullOrWhiteSpace($vCenterServer)) { $defaultvCenter } else { $vCenterServer }
    $clusterName   = if ([string]::IsNullOrWhiteSpace($clusterName)) { $defaultCluster } else { $clusterName }
    $folderName    = if ([string]::IsNullOrWhiteSpace($folderName)) { $defaultVMFolder } else { $folderName }

    Return [System.Collections.ArrayList]@($vCenterServer, $clusterName, $folderName)
}

# Login Credentials
# -----------------
function Get-UserCredentials {
    # Ask user for credentials
    Write-Host "`r`nENTER DOMAIN CREDENTIALS"
    $domainUser = Read-Host -Prompt "[+] PRINCIPLE"
    $domainPass = Read-Host -Prompt "[+] PASSWORD" -AsSecureString

    # Create secure credential object
    $CREDOPTIONS = @{
        TypeName = "System.Management.Automation.PSCredential"
        ArgumentList = $domainUser,$domainPass
    }

    Return New-Object @CREDOPTIONS
}

# Connect to vCenter Server and Error Checking
# --------------------------------------------
try {
    Show-MOTD
    Write-Host -ForegroundColor Red "[+] THIS SCRIPT REQUIRES POWERSHELL 7"
    $serverInfo = Get-ServerDetails
    $creds = Get-UserCredentials

	$global:server = Connect-VIServer -Server $serverInfo[0] -Credential $creds
    #$global:cluster = Get-Cluster -Name $serverInfo[1] -Server $serverInfo[0]
	$global:folder = Get-Folder -Name $serverInfo[2] -Server $serverInfo[0] -Type VM
} catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidLogin] {
	Write-Warning -Message "`r`nInvlaid username or password. Did you specify domain?"
	Exit
} catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.ViServerConnectionException] {
	Write-Warning -Message "`r`nCould not find requested vCenter server."
	Exit
} catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException] {
	Write-Warning -Message "`r`nCould not find requested Folder and/or Cluster."
	Write-Warning -Message "Disconnecting from server."
	#Disconnect-VIServer -Confirm:$false
	Exit
} catch {
    Write-Warning $Error[0]
	Write-Warning $Error[0].Exception.GetType().FullName
    Write-Warning -Message "An unexpected error occurred..."
	Write-Warning -Message "Disconnecting from server."
	#Disconnect-VIServer -Confirm:$false
	Exit
}

# Menu Options
# ------------
$menuOptions = @{
    "0" = { Write-Host -ForegroundColor Yellow "Goodbye =^._.^=" }
    "1" = { Convert-VMPowerState -Folder $folder -Action "PowerOn" }
    "2" = { Convert-VMPowerState -Folder $folder -Action "PowerOff" }
    "3" = { Update-VM -Folder $folder }
    "4" = { Domain-VM }
    "5" = { $global:folder = Update-VMFolder }
    "6" = { New-vLabVMs -Folder $folder -Datastore "vCenter_SSD_VMstore2" }
    "7" = { Move-VMDatastore -Folder $folder -DefaultLocation "ClusterSTVM" }
    "8" = { Remove-vLabVMs -Folder $folder }
    "9" = { Resize-VMDisk -Folder $folder }
}

# Primary Control Center
# ----------------------
do {
    Show-MOTD
    Write-Host "USER: $($global:server.User)"
    Write-Host "PATH: $($global:server.Name)\${global:cluster}\${folder}`r`n"

	Write-Host "0) Quit"
	Write-Host "1) Power on VM(s)"
	Write-Host "2) Power off VM(s)"
	Write-Host "3) Update VMware Tools"
	Write-Host "4) Join YC-CNT.EDU Domain"
	Write-Host "5) Change Folder"
    Write-Host "6) Create New Course VMs"
    Write-Host "7) Migrate VM Datastore"
    Write-Host "8) Delete Course VMs"
    Write-Host "9) Resize VM HardDisk`r`n"

    # User select option
    $menuChoice = Read-Host -Prompt "[+] WHAT DO YOU WANT TO DO?"

    if ($menuOptions.ContainsKey($menuChoice)) {
        $menuOptions[$menuChoice].Invoke()
    }
} Until ($menuChoice -eq "0")

# Disconnect from vCenter Server
# ------------------------------
Disconnect-VIServer -Confirm:$false
