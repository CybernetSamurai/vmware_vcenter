#Import-Module \\cybernas\Internal\Scripts\vLab_VMware\Custom_Modules\Change-Folder.ps1

# Move Existing VMs to new datastore location
# ----------------------------------------------------------------------
function Migrate-VMDatastore {
    param (
        [string]$folder
    )

    # Retrieve migration target info (clear name and vSphere ID)
    $targetDatastore = User-SelectVMDatastore
    [string]$answer = Read-Host -Prompt "[+] YOU SELECTED $($targetDatastore.Name) ($($targetDatastore.MoRef)) CONTINUE? [Y/N]"
    switch($answer.ToUpper()) {
        Y {Continue}
        Default {Return}
    }

    # Choose list of potential VMs to migrate
    $vmlist = New-VMList -Folder $folder | Get-View | Select-Object -Property Name,Datastore,RunTime

    # Create mutable array to add migratable VMs to
    $vmMigration = [System.Collections.ArrayList]@()

    # Build list of migratable VMs by comparing source datastore with target
    Foreach ($vm in $vmlist) {
        if($($vm.Datastore) -ne $targetDatastore.MoRef) {
            $vmMigration.Add($vm)
        }
    }

    # Migrate VM storage to target
    Write-Host "[+] VMS READY TO MIGRATE"
    $vmMigration | Format-Table
    $answer = Read-Host -Prompt "[+] MIGRATE $($vmMigration.Count) VMS TO DATASTORE $($targetDatastore.Name) ($($targetDatastore.MoRef))? [Y/N]"
    switch($answer.ToUpper()) {
        Y {Continue}
        Default {Return}
    }
    foreach ($vm in $vmMigration) {
        try {
            Write-Host "[+] MOVING '$($vm.Name)' STORAGE TO '$($targetDatastore.Name)'"
            if($vm.RunTime.PowerState -eq "PoweredOn") {
                Write-Host -ForegroundColor Yellow "[+] SHUTTING DOWN '$($vm.Name)'"
                Stop-VM -VM $vm.Name -Confirm:$false
                Start-Sleep -Seconds 10
                Write-Host -ForegroundColor Yellow "[+] MOVING '$($vm.Name)' STORAGE TO '$($targetDatastore.Name)'"
                Move-VM -VM $vm.Name -Datastore $targetDatastore.Name
                Write-Host -ForegroundColor Yellow "[+] STARTTING DOWN '$($vm.Name)'"
                Start-VM -VM $vm.Name -Confirm:$false
            } else {
                Move-VM -VM $vm.Name -Datastore $targetDatastore.Name
            }
        } catch {
            Write-Warning -Message $Error[0]
            Write-Warning -Message "An unexpected error occurred."
        }
    }
    Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# USER SELECTS DATASTORE TO MIGRATE TO
# ----------------------------------------------------------------------
function User-SelectVMDatastore {

    # set datastore location
    [string]$defaultDatastoreFolder = "ClusterSTVM"

    while(-not $continue) {
        
        # user prompt to choose datastore folder
        [string]$datastoreFolder = Read-Host -Prompt "[+] DATASTORE LOCATION [$defaultDatastoreFolder]"
        if (-not $datastoreFolder) {$datastoreFolder = $defaultDatastoreFolder}

        # Check if datastore exists
        if (Check-Folder -Folder $datastoreFolder -Type Datastore) {
            $continue = $true
        } else {
            Write-Host "[+] CANNOT FIND DATASTORE LOCATION '$folder'"
        }
    }

    # list available datastores
    Write-Host "[+] AVAILABLE DATASTORES:"
    try {
        $datastoreList = Get-Datastore -Location $datastoreFolder | Get-View | Select-Object Name,MoRef
    } catch {
        Write-Warning $Error[0]
    }

    if(-not $datastoreList) { Write-Host "[+] NO DATASTORES FOR '$datastoreFolder' FOUND" }

    # print list to screen
    Write-Host -ForegroundColor Yellow "    0) Quit"
    [int]$increment = 1
    foreach($datastore in $datastoreList) {
        Write-Host -ForegroundColor Yellow "    $increment) $($datastore.Name)"
        $increment++
    }

    # Select datastore to use
    [int]$minOption = 0
    [int]$maxOption = $increment
    Do {
        $selection = Read-Host -Prompt "`r`n[+] SELECT DATASTORE TO USE"
    } Until($selection -in $minOption..$maxOption)

    # Quit program if user selects zero
    if($selection -eq 0) { Return }

    Return $datastoreList[$selection - 1]
}