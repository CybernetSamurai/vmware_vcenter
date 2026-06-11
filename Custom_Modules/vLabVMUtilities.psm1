Function Resize-VMDisk {
    Param (
        $folder
    )

    # Generate List of VMs
    $VMPARAMS = @{
        Folder     = $folder
        PowerState = "*"
        OSFamily   = "*"
    }
    if($vmList -eq $null) { $vmList = New-VMList @VMPARAMS }

    # Exit if list returns empty
    if ($vmList.Count -eq 0) { Return }

    $newDiskSize = Read-Host -Prompt "[+] NEW DISK SIZE (GB): "

    $vmList | ForEach-Object -Parallel {
        # Process VMs
        $hardDiskNumber = "Hard Disk 1"
        $vmDisk = Get-HardDisk -VM $_ | Where {$_.Name -eq $hardDiskNumber}
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
        Write-Host -NoNewLine "[+] RESIZING DISK: "
        Write-Host -ForegroundColor Green "$oldDiskSize GB -> $using:newDiskSize GB"
        $RESIZEPARAMS = @{
            HardDisk   = $vmDisk
            CapacityGB = $using:newDiskSize
            Confirm    = $false
        }
        Set-HardDisk @RESIZEPARAMS

    } -ThrottleLimit 10

    # User Prompt to Continue
    Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}