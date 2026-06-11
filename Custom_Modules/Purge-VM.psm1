function Delete-VM {
    param (
        [string]$folder,
        [string]$cluster = "ClusterSTVM"
    )

    # Is folder empty
    if (-not $folder) {
        Write-Warning "[+] FOLDER PARAMETER IS MISSING OR INVALID"
        return
    }

    # User prompt to continue
    Write-Host -ForegroundColor Yellow "[+] WARNING: THIS SCRIPT IS INTENDED TO BE USED AT THE END OF THE SEMESTER TO DESTORY VMS"
    Write-Host -ForegroundColor Yellow "[+] THIS ACTION IS IRREVERSIBLE"
    [string]$answer = Read-Host -Prompt "[+] DELETE VMS FOR THE COURSE '$folder'? [Y/N]"
    switch($answer.ToUpper()) {
        Y { Continue }
        default { Return }
    }

    # Connect to vLab
    $VCENTER = @{
        Server  = $global:DefaultVIServer.Name
        Session = $global:DefaultVIServer.SessionId
    }
    Connect-VIServer @VCENTER

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
    Write-Host -ForegroundColor Yellow "    ETA:           $estimatedTime"
    Write-Host "    -----------------------------------------------------------------"

    # User prompt to continue 
    $answer = Read-Host -Prompt "[+] CONTINUE? [Y/N]"
    switch($answer.ToUpper()) {
        Y { Continue }
        default { Return }
    }

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