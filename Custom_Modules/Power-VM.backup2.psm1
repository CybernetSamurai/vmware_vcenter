# POWER/STARTUP VMS
# -------------------------------------------------------------------------------
function Power-VM {
    param (
        [string]$folder,
        $vmList
    )

    # Find all VMs currently powered off
    if($vmList -eq $null) {
        $vmList = Generate-VMList -PowerState "PoweredOff" -Folder $folder
    }

    # Create an array to hold background jobs and other variables
    $totalVMs = $vmList.Count
    $completedVMs = 0
    $maxJobs = 10
    $jobs = @()

    # Power On VMs in Parallel
	foreach ($vm in $vmList) {
        $jobs += Start-Job -Name "Start $($vm.Name)" -ScriptBlock {
            param (
                $vmName
            )
            Set-PowerCLIConfiguration -DisplayDeprecationWarnings:$false -Scope Session -Confirm:$false | Out-Null

            try {
                Connect-VIServer -Server $using:DefaultVIServer.Name -Session $using:DefaultVIServer.SessionId | Out-Null
                $vm = Get-VM -Name $vmName
                Start-VM -VM $vm -Confirm:$false | Out-Null
                Write-Host -NoNewLine "[+] STARTING VM: "
                Write-Host -ForegroundColor Green "$vmName"
            } catch {
                Write-Warning $Error[0]
                Write-Warning $Error[0].Exception.GetType().FullName
                Write-Warning -Message "An unexpected error occurred starting '$vmName'"
            }
        } -ArgumentList $vm.Name

        Write-Host -ForegroundColor Yellow "    - Thread started"

        # Check and throttle to 10 threads
        while (($jobs | Where-Object { $_.State -eq "Running" }).Count -ge $maxJobs) {
            Write-Host -ForegroundColor Magenta "[+] WAITING FOR THREADS TO COMPLETE..."
            #Wait-Job -Job $jobs
            $jobs | Where-Object { $_.State -eq "Running" } | ForEach-Object {
                Receive-Job -Wait -Job $_
            }
        }
    }

    # Wait for remaining jobs to complete and clean up
    $jobs | ForEach-Object {
        Receive-Job -Wait -AutoRemoveJob -Job $_
    }

    # Finished
	Write-Host "`r`n[+] ALL VMS IN THE FOLDER '$folder' HAVE BEEN POWERED ON."
	Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# STOP/SHUTDOWN VMS
# -------------------------------------------------------------------------------
function Shutdown-VM {
    param (
        [string]$folder,
        $vmList
    )
    # Find all VMs currently powered on
    if($vmList -eq $null) {
        $vmList = Generate-VMList -PowerState "PoweredOn" -Folder $folder
    }

    # Power Off VMs
	foreach ($vm in $vmList) {
        try {
            Write-Host ("[+] STOPPING VM: $($vm.Name)")
		    Stop-VM -VM $vm -Confirm:$false
        } catch {
            Write-Warning -Message "An unexpected error has occurred. Is the network online?"
        }
	}
	Write-Host "`r`n[+] ALL VMS IN THE FOLDER '$folder' HAVE BEEN SHUTDOWN."
	Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# UPDATE VMWARE TOOLS
# -------------------------------------------------------------------------------
function Update-VM {
    param (
        [string]$folder,
        $vmList
    )
    # Select List of VMs to Update
    if($vmList -eq $null) {
        $vmList = Generate-VMList -Folder $folder
    }

    # Update VMs
	foreach ($vm in $vmList) {
        try {
            # Power On VM if necessary
            if($($vm.PowerState) -eq "PoweredOff") {
                Write-Host "[+] STARTING VM: $($vm.Name)"
                Start-VM -VM $vm -Confirm:$false
                Start-Sleep -Seconds 40
            }
		    Write-Host "[+] UPDATING VM: $($vm.Name)"
            Update-Tools -VM $vm
        } catch {
            Write-Warning -Message "An unexpected error occurred. Is the network online?"
        }
	}
	Write-Host "`r`n[+] ALL VMS IN THE FOLDER $folder HAVE BEEN UPDATED."
	Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# GENERATE VM LIST
# -------------------------------------------------------------------------------
function Generate-VMList {
    param (
        [string]$powerState = "*",
        [string]$folder
    )

    DO {
        # Filter for VMs to include
        [string]$filterInclude = Read-Host -Prompt "[+] VM INCLUDE FILTER (enter for *)"
	    if(-not $filterInclude) { $filterInclude = "*" }

        # Filter for VMs to exclude
	    [string]$filterExclude = Read-Host -Prompt "[+] VM EXCLUDE FILTER (enter for N/A)"

        # Generate List of VMs
	    $vmList = Get-VM -Location $folder | Where-Object {
	        $_.PowerState -like $powerState -and
		    $_.Name -like $filterInclude -and
		    $_.Name -notlike $filterExclude 
	    }

        # Print list to terminal
        Write-Host ($vmList | Select-Object -Property Name, PowerState | Format-Table | Out-String)

        # Ask user to continue
		$answer = Read-Host -Prompt "[+] PROCEED WITH SELECTED MACHINES IN $folder? [Y(es), N(o), Q(uit)]"
		switch($answer.ToUpper()) {
			Y {$listReady = $true}
			N {Continue}
			default {Return}
		}
    } Until($listReady)

    return $vmList
}