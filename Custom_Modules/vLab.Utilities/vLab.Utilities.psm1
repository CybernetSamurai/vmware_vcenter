# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Resize-VMDisk {
    Param (
        [Parameter(Mandatory)]
        [string]$folder
    )

    # Generate List of VMs
    $VMPARAMS = @{
        Folder     = $folder
        PowerState = "*"
        OSFamily   = "*"
    }
    if($null -eq $vmList) { $vmList = New-VMList @VMPARAMS }

    # Exit if list returns empty
    if ($vmList.Count -eq 0) { Return }

    $newDiskSize = Read-Host -Prompt "[+] NEW DISK SIZE (GB): "

    $vmList | ForEach-Object -Parallel {
        # Process VMs
        $hardDiskNumber = "Hard Disk 1"
        $vmDisk = Get-HardDisk -VM $_ | Where-Object {$_.Name -eq $hardDiskNumber}
        $oldDiskSize = $vmDisk.CapacityGB
        $vmSnapshot = Get-Snapshot -VM $_

        # Delete Snapshots if exist
        $SNAPSHOTPARAMS = @{
            Snapshot       = $vmSnapshot
            RemoveChildren = $true
            Confirm        = $false
        }
        if ($vmSnapshot) {
            Write-Host -NoNewLine "[+] DELETING SNAPSHOTS FOR "
            Write-Host -ForegroundColor Green "$($_.Name)"
            Remove-Snapshot @SNAPSHOTPARAMS
            $vmDisk = Get-HardDisk -VM $_ 
        }

        # Resize Disk
        Write-Host -NoNewLine "[+] RESIZING '$($_.Name)' DISK: $oldDiskSize GB -> $using:newDiskSize GB"
        $RESIZEPARAMS = @{
            HardDisk   = $vmDisk
            CapacityGB = $using:newDiskSize
            Confirm    = $false
        }
        Set-HardDisk @RESIZEPARAMS

    } -ThrottleLimit 10

    # Prompt to Continue
    Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Update-VMFolder {
    $exists = 0
    Do {
        $newFolder = Read-Host -Prompt "[+] NEW FOLDER NAME"
        $VALIDATEPARAMS = @{
            Folder = $newFolder
            Type = "VM"
        }
        $exists = Confirm-FolderExists @VALIDATEPARAMS
    } Until ($exists)

	Return $newFolder
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Confirm-FolderExists {
    Param (
        [Parameter(Mandatory)]
        [string]$folder,

        [Parameter(Mandatory)]
        [string]$type
    )

    Try {
        $FOLDERPARAMS = @{
            Name = $folder
            Type = $type
        }
        Get-Folder @FOLDERPARAMS | Out-Null
    } Catch {
        #Write-Host $_.Exception.Message
        Write-Host -ForegroundColor Yellow "[+] AN ERROR OCCURRED. CHECK YOUR SPELLING?"
        Return 0
    }
    Return 1
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Wait-UserContinue {
    Param (
        [string]$message = "[+] CONTINUE? [Y/N]"
    )

    $answer = Read-Host $message
    Switch ($answer.ToUpper()) {
        Y { Return 1 }
        default { Return 0 }
    }
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Get-VMToolsStatus {
<#
.SYNOPSIS
    This will check the status of the VMware vmtools status.
    Properties include Name, Status, UpgradeStatus and Version
 
.NOTES
    Name: Get-VMToolsStatus
    Author: theSysadminChannel
    Version: 1.0
    DateCreated: 2020-Sep-1
 
.LINK
    https://thesysadminchannel.com/powercli-check-vmware-tools-status/ -
 
.EXAMPLE
    Please refer to the -Online version
    help Get-VMToolsStatus -Online
 
#>
 
    [CmdletBinding()]
    param(
        [Parameter(
            Position=0,
            ParameterSetName="NonPipeline"
        )]
        [Alias("VM", "ComputerName", "VMName")]
        [string[]]  $Name,
 
 
        [Parameter(
            Position=1,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            ParameterSetName="Pipeline"
            )]
        [PSObject[]]  $InputObject
    )
 
    BEGIN {
        if (-not $Global:DefaultVIServer) {
            Write-Error "Unable to continue.  Please connect to a vCenter Server." -ErrorAction Stop
        }
 
        #Verifying the object is a VM
        if ($PSBoundParameters.ContainsKey("Name")) {
            $InputObject = Get-VM $Name
        }
 
        $i = 1
        $Count = $InputObject.Count
    }
 
    PROCESS {
        if (($null -eq $InputObject.VMHost) -and ($null -eq $InputObject.MemoryGB)) {
            Write-Error "Invalid data type. A virtual machine object was not found" -ErrorAction Stop
        }
 
        foreach ($Object in $InputObject) {
            try {
                [PSCustomObject]@{
                    Name = $Object.name
                    Status = $Object.ExtensionData.Guest.ToolsStatus
                    UpgradeStatus = $Object.ExtensionData.Guest.ToolsVersionStatus2
                    Version = $Object.ExtensionData.Guest.ToolsVersion
                }
            } catch {
                Write-Error $_.Exception.Message
 
            } finally {
                if ($PSBoundParameters.ContainsKey("Name")) {
                    $PercentComplete = ($i/$Count).ToString("P")
                    Write-Progress -Activity "Processing VM: $($Object.Name)" -Status "$i/$count : $PercentComplete Complete" -PercentComplete $PercentComplete.Replace("%","")
                    $i++
                } else {
                    Write-Progress -Activity "Processing VM: $($Object.Name)" -Status "Completed: $i"
                    $i++
                }
            }
        }
    }
 
    END {}
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Start-PowerCLIJob {

    param(
        [parameter(mandatory=$True)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl]$DefaultVIServer,

        [PSCredential]$userCred,

        [string]$JobName,

        [parameter(mandatory=$True)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList,

        [psobject]$InputObject,

        [string[]]$Modules = "VMware.VimAutomation.Core"
    )

    $ScriptBlockPrepend = {
        import-module $using:Modules | out-null;
        Set-PowerCLIConfiguration -DisplayDeprecationWarnings:$false -Scope Session -confirm:$False | out-null;
        Connect-ViServer -Server $using:DefaultVIServer.name -Session $using:DefaultVIServer.SessionId | out-null;
    }

    $ScriptBlock = [ScriptBlock]::Create($ScriptBlockPrepend.ToString() + $ScriptBlock.ToString())

    $params = @{scriptblock=$ScriptBlock}
    if ($JobName) {$params.Add('name',$JobName)}
    if ($ArgumentList) {$params.Add('ArgumentList',$ArgumentList)}
    if ($InputObject) {$params.Add('InputObject',$InputObject)}

    Start-Job @params
}