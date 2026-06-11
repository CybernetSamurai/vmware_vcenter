# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Move-VMDatastore {
    param (
        [Parameter(Mandatory)]
        [string]$folderName,

        [string]$defaultLocation = "ClusterSTVM"
    )

    # Retrieve migration target datastore
    $datastoreLocation = Read-Host -Prompt "[+] DATASTORE LOCATION [$defaultLocation]"
    if (-not $datastoreLocation) { $datastoreLocation = $defaultLocation }
    $target = Get-VMObjectList -ObjectType "Datastore" -FolderName $datastoreLocation
    if ($null -eq $target) { Return }

    # Prompt to continue
    If (-not (Wait-UserContinue -Message "[+] YOU SELECTED $($target.Name) ($($target.Id)) CONTINUE? [Y/N]")) { Return }

    # Choose list of potential VMs to migrate
    $VMLISTPARAMS = @{
        Folder     = $folderName
        PowerState = "*"
        OSFamily   = "*"
    }
    $vmList = New-VMList @VMLISTPARAMS
    If ($vmList.Count -eq 0) { Return }

    # Create mutable array to add migratable VMs to
    $vmMigration = [System.Collections.ArrayList]@()

    # Build list of migratable VMs by comparing datastore with target
    ForEach ($vm in $vmList) { If ($vm.DatastoreIdList -ne $target.Id) { $vmMigration.Add($vm) } }

    # Confirm Migration
    Write-Host "[+] VMS READY TO MIGRATE"
    $vmMigration | Format-Table -Property Name, PowerState, DatastoreIdList | Out-String | Write-Host
    If (Wait-UserContinue -Message "[+] MIGRATE $($vmMigration.Count) VMS TO DATASTORE '$($target.Name)'? [Y/N]") { Return }

    # Migrate VMs in parallel
    $vmMigration | ForEach-Object -Parallel {
        Try {
            Import-Module VMware.VimAutomation.Core
            $SERVERPARAMS = @{
                Server  = $using:DefaultVIServer.Name
                Session = $using:DefaultVIServer.SessionId
            }
            Connect-VIServer @SERVERPARAMS | Out-Null

            # If VM is powered on, shut it down first
            If ($_.PowerState -eq "PoweredOn") {
                Write-Host "[+] SHUTTING DOWN '$($_.Name)'"
                Stop-VM -VM $_ -Confirm:$false | Out-Null
                Start-Sleep -Seconds 10
            }

            # Migrate VM storage to target datastore
            Write-Host "[+] MOVING '$($_.Name)' STORAGE TO '$($using:target.Name)'"
            Move-VM -VM $_ -Datastore $using:target | Out-Null
        } Catch {
            Write-Host $_.Exception.Message
            Write-Host -ForegroundColor Yellow "[+] AN UNEXPECTED ERROR OCCURRED."
        }
    } -ThrottleLimit 10

    # Tasks Finished
    Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Convert-VMPowerState {
    Param (
        [Parameter(Mandatory)]
        [string]$folder,

        [Parameter(Mandatory)]
        [ValidateSet("PowerOn","PowerOff")]
        [string]$action,

        [array]$vmList
    ) 

    # Find all VMs currently powered on
    If ($vmList -eq $null) {
        $vmList = If ($action -eq "PowerOn") {
            New-VMList -PowerState:"PoweredOff" -Folder:$folder
        } Else {
            New-VMList -PowerState:"PoweredOn" -Folder:$folder
        }
    }

    # Exit if list returns empty
    If ($vmList.Count -eq 0) { Return }

    # Change VM powerstate in parallel
    $vmList | ForEach-Object -Parallel {
        Try {
            If ($using:action -eq "PowerOn") {
                Write-Host -NoNewLine "[+] STARTING VM: "
                Write-Host -ForegroundCOlor Green "$($_.Name)"
                Start-VM -VM $_ -Confirm:$false | Out-Null
            } Else {
                Write-Host -NoNewLine "[+] STOPPING VM: "
                Write-Host -ForegroundColor Green "$($_.Name)"
		        Stop-VM -VM $_ -Confirm:$false | Out-Null
            }
        } Catch {
            Write-Host -ForegroundColor Red "[+] ERROR MESSAGE: $($_.Exception.Message)"
            Write-Host -ForegroundColor Yellow "[+] AN UNEXPECTED ERROR HAS OCCURRED. IS THE NETWORK ONLINE?"
        }
    } -ThrottleLimit 10

    # Tasks Finished
    $actionMessage = $action -eq "PowerOn" ? "STARTED" : "SHUTDOWN"
    Write-Host -NoNewLine "`r`n[+] ALL VMS IN THE FOLDER "
    Write-Host -NoNewLine -ForegroundColor Green "'$folder' "
    Write-Host "HAVE BEEN $actionMessage."

    # Prompt to continue
	Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Update-VM {
    Param (
        [Parameter(Mandatory)]
        [string]$folder,

        [array]$vmList
    )
    # Select List of MICROSOFT WINDOWS VMs to Update
    $VMPARAMS = @{
        Folder     = $folder
        PowerState = "*"
        OSFamily   = "*"
    }
    If ($vmList -eq $null) { $vmList = New-VMList @VMPARAMS }

    # Exit if list returns empty
    If ($vmList.Count -eq 0) { Return }

    # Update VMs
	$vmList | ForEach-Object -Parallel {
        Try {
            #Import-Module \\cybernas\Internal\Scripts\vLab_VMware\Custom_Modules\Get-VMToolsStatus.psm1 -Force
            Import-Module VMware.VimAutomation.Core -Force
            $SERVERPARAMS = @{
                Server  = $using:DefaultVIServer.Name
                Session = $using:DefaultVIServer.SessionId
            }
            Connect-VIServer @SERVERPARAMS | Out-Null
            $vm = $_

            # Power On VM if necessary
            If ($vm.PowerState -eq "PoweredOff") {
                Write-Host -NoNewLine "[+] STARTING VM: "
                Write-Host -ForegroundColor Green "$($vm.Name)"
                Start-VM -VM $vm -Confirm:$false | Out-Null

                # Wait until VM is powered on and VMware Tools is running (with retries)
                $maxWaitTime = 300  # 5 minutes
                $waitTime = 0
                While ($vm.PowerState -ne "PoweredOn" -and (Get-VMToolsStatus -Name $vm.Name).Status -ne "toolsOk") {
                    Start-Sleep -Seconds 5 
                    $waitTime += 5
                    If ($waitTime -ge $maxWaitTime) {
                        Write-Host -ForegroundColor Yellow "[+] Timeout reached while waiting for VM to be ready. Moving on..."
                        Return
                    }

                    # Re-fetch VM to check power state and Tools status
                    $vm = Get-VM -Name $vm.Name  
                }
            }

            #Write-Host -ForegroundColor Green "True"
            If ((Get-VMToolsStatus -Name $vm.Name).UpgradeStatus -eq "guestToolsSupportedOld") {
                Write-Host -NoNewLine "[+] UPDATING VM: "
                Write-Host -ForegroundColor Green "$($vm.Name)"
                Update-Tools -VM $vm | Out-Null
            }
        } Catch {
            Write-Host -ForegroundColor Yellow "[+] ERROR MESSAGE: $($_.Exception.Message)"
            Write-Host -ForegroundColor Yellow "[+] AN UNEXPECTED ERROR HAS OCCURRED. IS THE NETWORK ONLINE?"
        }
	} -ThrottleLimit 10

    # Tasks Finished
	Write-Host -NoNewLine "`r`n[+] ALL VMS IN THE FOLDER "
    Write-Host -NoNewLine -ForegroundColor Green "$folder "
    Write-Host "HAVE BEEN UPDATED."

    # Prompt to Continue
	Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function New-VMList {
    Param (
        [Parameter(Mandatory)]
        [ValidateSet("*","PoweredOn","PoweredOff")]
        [string]$powerState,

        [Parameter(Mandatory)]
        [string]$folder,

        [ValidateSet("*","windowsGuest","linuxGuest")]
        [string]$OSFamily = "*"
    )

    $listReady = $false

    # Keep Prompting User until List is Confirmed
    Do {
        # Filter for VMs to include
        $filterInclude = Read-Host -Prompt "[+] VM INCLUDE FILTER (enter for *)"
	    If (-not $filterInclude) { $filterInclude = "*" }

        # Filter for VMs to exclude
	    $filterExclude = Read-Host -Prompt "[+] VM EXCLUDE FILTER (enter for N/A)"

        # Generate List of VMs
        Write-Host "[+] FETCHING VMS IN '$folder'..."
	    $vmList = Get-VM -Location $folder | Where-Object {
	        $_.PowerState -like $powerState -and
		    $_.Name -like $filterInclude -and
		    $_.Name -notlike $filterExclude 
	    }

        # Filter List by OS
        $vmList = $vmList | Where-Object { (Get-VMGuest -VM $_).GuestFamily -like $OSFamily }

        # Print list to terminal
        $vmList | Select-Object -Property Name, PowerState | Format-Table | Out-String | Write-Host

        # Ask user to continue)
		$answer = Read-Host -Prompt "[+] PROCEED WITH SELECTED MACHINES IN $folder? [Y(es), N(o), Q(uit)]"
		Switch ($answer.ToUpper()) {
			Y { $listReady = $true }
			N { Continue }
			default { Return }
		}

    } Until($listReady)

    Return $vmList
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Remove-vLabVMs {
    Param (
        [Parameter(Mandatory)]
        [string]$folder,

        [string]$cluster = "ClusterSTVM"
    )

    # Is folder empty
    If (-not $folder) {
        Write-Warning "[+] FOLDER PARAMETER IS MISSING OR INVALID"
        Return
    }

    # Warning message
    Write-Host -ForegroundColor Yellow "[+] WARNING: THIS SCRIPT IS INTENDED TO BE USED AT THE END OF THE SEMESTER TO DESTORY VMS"
    Write-Host -ForegroundColor Yellow "[+] THIS ACTION IS IRREVERSIBLE"

    # Prompt to continue
    If (-not (Wait-UserContinue -Message "[+] DELETE VMS FOR THE COURSE '$folder'? [Y/N]")) { Return }

    # Fetch list of VMs to delete
    Write-Host "[+] THIS SCRIPT ONLY DELETES VMS THAT ARE POWERED OFF"
    $vmList = New-VMList -Folder $folder -PowerState "PoweredOff"
    $totalVMs = $vmList.Count

    Write-Host -NoNewLine "[+] DELETING "
    Write-Host -NoNewLine -ForegroundColor Green "'$totalVMs' "
    Write-Host -NoNewLine "VMS FROM LOCATION "
    Write-Host -ForegroundColor Green "'$folder'"
    Write-Host "    -----------------------------------------------------------------"
    Write-Host -ForegroundColor Yellow "    QUANTITY:      $totalVMs"
    Write-Host -ForegroundColor Yellow "    LOCATION:      $folder"
    Write-Host -ForegroundColor Yellow "    RESOURCE POOL: $cluster"
    Write-Host "    -----------------------------------------------------------------"

    # Prompt to continue
    If (-not (Wait-UserContinue)) { Return }

    # Delete VMs in parallel
    $vmList | Foreach-Object -Parallel {
        Remove-VM -VM $_ -DeletePermanently -Confirm:$false
        Write-Host -NoNewLine "[+] DELETING VM: "
        Write-Host -ForegroundColor Green "$($_.Name)"
    } -ThrottleLimit 10

    # Finished
    Write-Host "[+] TASKS COMPLETED."
    Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function New-vLabVMs {
    Param (
        [Parameter(Mandatory)]
        [string]$folder,

        [string]$cluster = "vcenter.yc-cnt.edu",

        [string]$datastore = "vCenter_SSD_VMstore2"
    )
    
    # Is folder empty
    If (-not $folder) {
        Write-Host "[+] Folder parameter is missing or invalid"
        Return
    }

    # Active Directory user account paths
    $ldapPath = "OU=${folder},OU=vLab_Students,OU=CT_Students,DC=YC-CNT,DC=EDU"
    $ldapPathAlt = "OU=${folder},OU=Dual_Enrollment,OU=vLab_Students,OU=CT_Students,DC=YC-CNT,DC=EDU"

    # Calculate the maximum number of VMs that can be made (no greater than number of users in AD)
    $ADPARAMS = @{
        SearchBase  = $ldapPath
        Filter      = "*"
        ErrorAction = "SilentlyContinue"
    }
    Try {
        Write-Host -NoNewLine "[+] SEARCHING FOR USERS UNDER "
        Write-Host -ForegroundColor Green "'${ldapPath}'..."
        $classUsers = Get-ADUser @ADPARAMS
    } Catch {
        Write-Host -ForegroundColor Yellow "[+] NO USERS FOUND"
    }

    # Check alternate OU path if no users found
    If ($classUsers.Count -eq 0) {
        Try {
            Write-Host -NoNewLine "[+] SEARCHING FOR USERS UNDER "
            Write-Host -ForegroundColor Green "'${ldapPathAlt}'..."
            $ADPARAMS.SearchBase = $ldapPathAlt
            $classUsers = Get-ADUser @ADPARAMS
        } Catch {
            Write-Host -ForegroundColor Yellow "[+] NO USERS FOUND"
        }
    }

    # Exit if still no users found
    If ($classUsers.Count -eq 0) {
        Write-Host -NoNewLine -ForegroundColor Red "[+] NO USERS FOUND IN FOR COURSE "
        Write-Host -ForegroundColor Green "'${folder}'"
        Return
    }
    Write-Host "[+] FOUND $($classUsers.Count) USERS FOR COURSE '$folder'"
    Write-Host "[+] -----------------------------------------------------------------"
    $maxVMs = $classUsers.Count

    # Prompt to continue 
    If (-not (Wait-UserContinue -Message "[+] CREATE VMS FOR THE COURSE '$folder'? [Y/N]")) { Return }

    # Select VM Template to use
    $template = Get-VMObjectList -ObjectType "Template" -FolderName $folder
    if ($null -eq $template) { Return }
    $osName = ($template -Split '_')[-1]

    # Prompt to continue
    If (-not (Wait-UserContinue -Message "[+] SELECTED TEMPLATE '$template'. CONTINUE? [Y/N]")) { Return }

    # Validate number of VMs and start number
    [int]$totalVMs = Read-Host -Prompt "[+] HOW MANY VMS SHOULD BE MADE? (1-${maxVMs})"
    [int]$startNum = Read-Host -Prompt "[+] WHAT IS THE START NUMBER? (1-${maxVMs})"

    $endNum = $totalVMs + $startNum - 1
    if ($endNum -gt $maxVMs -OR $endNum -lt 1 ) {
        Write-Warning -Message "[+] INVALID NUMBER OF VMS"
        Return
    }

    # Create an array to hold background jobs
    $maxJobs = 10
    $jobs = @()

    Write-Host -NoNewLine "[+] CREATING "
    Write-Host -NoNewLine -ForegroundColor Green "'$totalVMs' "
    Write-Host -NoNewLine "VMS STARTING AT "
    Write-Host -NoNewLine -ForegroundColor Green "'$startNum' "
    Write-Host -NoNewLine "WITH THE FOLLOWING ATTRIBUTES"
    Write-Host "    -----------------------------------------------------------------"
    Write-Host -ForegroundColor Yellow "    QUANTITY:      $totalVMs"
    Write-Host -ForegroundColor Yellow "    STARTING AT:   $startNum"
    Write-Host -ForegroundColor Yellow "    LOCATION:      $folder"
    Write-Host -ForegroundColor Yellow "    TEMPLATE:      $template"
    Write-Host -ForegroundColor Yellow "    RESOURCE POOL: $cluster"
    Write-Host -ForegroundColor Yellow "    DATASTORE:     $datastore"
    Write-Host "    -----------------------------------------------------------------"

    # User prompt to continue 
    If (-not (Wait-UserContinue)) { Return }

    # Create VMs in parallel
    for($i=$startNum; $i -le $endNum; $i++) {
        # format vm identifier ex "00", "01", etc
	    $vmNumber = "{0:00}" -f $i
	    $vmName = $folder + $osName + "-" + $vmNumber
	    $username = "YC-CNT\" + $folder + "-" + $vmNumber

        # Spawn threads
        $jobs += Start-Job -Name "Spawn $vmName" -ScriptBlock {
            Import-Module VMware.VimAutomation.Cis.Core
            Import-Module VMware.VimAutomation.Core
            Import-Module ActiveDirectory
            Set-PowerCLIConfiguration -DisplayDeprecationWarnings:$false -Scope Session -Confirm:$false | Out-Null

            try {
                Connect-VIServer -Server $using:DefaultVIServer.Name -Session $using:DefaultVIServer.SessionId | Out-Null

	            # Create new VM
                $vmTemplate = Get-Template -Name $using:template.Name
                $NEWVMPARAMS = @{
                    Name              = $using:vmName
                    Template          = $vmTemplate
                    ResourcePool      = $using:cluster
                    Datastore         = $using:datastore
                    DiskStorageFormat = "Thin"
                    Location          = $using:folder
                }
		        New-VM @NEWVMPARAMS | Out-Null
		        Write-Host -NoNewLine "[+] CREATED VM "
                Write-Host -ForegroundColor Green "$using:vmName"

                # Set user permissions
                $PERMISSIONPARAMS = @{
                    Principal = $using:username
                    Role      = "Virtual Machine console user"
                    Propagate = $false
                }
	            Get-VM $using:vmName | New-VIPermission @PERMISSIONPARAMS | Out-Null
                Write-Host -NoNewLine "[+] SETTING USER PERMISSIONS: "
                Write-Host -ForegroundColor Green "'$using:username'"

            } catch {
                Write-Warning -Message "An unexpected error occurred."
                Write-Warning -Message $Error[0]
            }
        }

        # Log program status
        Write-Host -ForegroundColor Yellow "    - Thread started"

        # Check and throttle to 10 threads}
        while (($jobs | Where-Object { $_.State -eq "Running" }).Count -ge $maxJobs) {

            # Log program status
            Write-Host -ForegroundCOlor Magenta "[+] CURRENT BUFFER FULL"
            Write-Host -ForegroundColor Magenta "[+] WAITING FOR THREADS TO COMPLETE..."
            
            # Process only running jobs
            $runningJobs = $jobs | Where-Object { $_.State -eq "Running" }
            $runningJobs | ForEach-Object {
                if (Get-Job -Id $_.Id) {
                    Receive-Job -Wait -Job $_
                    Remove-Job -Id $_.Id -Force
                }
            }
        }
    }

    # Wait for remaining jobs to complete and clean up
    while ($jobs.Count -gt 0) {
        # Remove missing jobs from the array before processing
        $jobs = $jobs | Where-Object { Get-Job -Id $_.Id -ErrorAction SilentlyContinue }

        # Process remaining jobs
        $jobs | Where-Object { Get-Job -Id $_.Id } | ForEach-Object {
            Receive-Job -Wait -Job $_
            Remove-Job -Id $_.Id -Force
        }
    }

    # Finished
    Write-Host "[+] TASKS COMPLETED."
    Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# -------------------------------------------------------------------------------
# -------------------------------------------------------------------------------
Function Get-VMObjectList {
    Param (
        [Parameter(Mandatory)]
        [ValidateSet("Template","Datastore")]
        [string]$objectType,

        [Parameter(Mandatory)]
        [string]$folderName
    )

    # Set folder type based on object type
    if ($objectType -eq "Template") {
        $folderType = "VM"
    } else {
        $folderType = "Datastore"
    }

    # Validate folder name exists
    $FOLDERPARAMS = @{
        Name   = $folderName
        Type   = $folderType
        ErrorAction = "SilentlyContinue"
    }
    If (-not (Get-Folder @FOLDERPARAMS)) {
        Write-Host "[+] CANNOT FIND FOLDER '$folderName'"
        Return
    }

    $objectType = $objectType.ToUpper()
    Write-Host -NoNewLine "[+] FETCHING AVAILABLE ${objectType}S FOR "
    Write-Host -ForegroundColor Green "'$folderName'..."
    # Make list of available templates    
    if ($objectType -eq "Template") {
        # Filter (ex CNT110_Template_Win10, etc)
        $templateFilter = $folderName + "_Template_*"
        $objectList = Get-Template -Name $templateFilter -ErrorAction SilentlyContinue
    
    # Make list of available datastores
    } ElseIf ($objectType -eq "Datastore") {
        $objectList = Get-Datastore -Location $folderName -ErrorAction SilentlyContinue
    }

    # Check if no objects found
    If ($objectList.Count -eq 0) {
        Write-Host -NoNewLine "[+] NO ${objectType}S FOR "
        Write-Host -NoNewLine -ForegroundColor Green "'$folderName' "
        Write-Host "FOUND"
        Return
    }

    # Print list of objects to screen
    Write-Host "[+] AVAILABLE ${objectType}S:"
    Write-Host -ForegroundColor Yellow "    0) Quit"
    $count = 1
    $objectList | ForEach-Object {
        Write-Host -ForegroundColor Yellow "    $count) $_"
        $count++
    }

    # Select object to use
    $minOption = 0
    $maxOption = $count - 1
    Do {
        $selection = Read-Host -Prompt "[+] SELECT ${objectType} TO USE (0 to Quit)"
    } Until($selection -in $minOption..$maxOption)

    # Quit program if user selects zero
    If ($selection -eq 0) { Return }

    # Tasks finished
    Return $objectList[$selection - 1]
}