# POWER/STARTUP VMS (experimental / not currently in production)
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
    $startTime = Get-Date

    # Power On VMs in Parallel
	foreach ($vm in $vmList) {
        $jobs += Start-Job -Name "Start $($vm.Name)" -ScriptBlock {
            param (
                $vmName
            )

            # Splatting powerCLI config
            $CLIConfig = @{
                DisplayDeprecationWarning = $false
                Scope                     = Session
                Confirm                   = $false
            }
            Set-PowerCLIConfiguration @CLIConfig | Out-Null

            try {
                Connect-VIServer -Server $using:DefaultVIServer.Name -Session $using:DefaultVIServer.SessionId | Out-Null
                $vm = Get-VM -Name $vmName
                Start-VM -VM $vm -Confirm:$false | Out-Null
                Write-Host -NoNewLine "[+] STARTING VM: "
                Write-Host -ForegroundColor Green "$vmName"
            } catch {
                Write-Warning -Message "Error starting VM '$vmName': $($_.Exception.Message)"
            }
        } -ArgumentList $vm.Name

        Write-Host -ForegroundColor Yellow "    - Thread started"

        # Check and throttle to 10 threads
        while (($jobs | Where-Object { $_.State -eq "Running" }).Count -ge $maxJobs) {
            # Update Progress bar
            $completedVMs = ($jobs | Where-Object { $_.State -eq "Completed" }).Count
            $percentComplete = [math]::Min(100, [math]::Round(($completedVMs / $totalVMs) * 100, 2))

            # Estimated time remaining
            $elapsedTime = (Get-Date) - $startTime
            $avgJobTime = if ($completedVMs -gt 0) { $elapsedTime.TotalSeconds / $completedVMs } else { 0 }
            $remainingTime = ($totalVMs - $completedVMs) * $avgJobTime
            $eta = (Get-Date).AddSeconds($remainingTime)  # Estimated completion time

            Write-Progress -Activity "Powering On VMs" `
                -Status "$completedVMs / $totalVMs completed - ETA: $(($eta).ToString('HH:mm:ss'))" `
                -PercentComplete $percentComplete

            Start-Sleep -Seconds 2  # Short pause to avoid excessive updates

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
            $completedVMs++
            Remove-Job -Id $_.Id -Force
        }

        # Update progress and ETA
        $percentComplete = [math]::Min(100, [math]::Round(($completedVMs / $totalVMs) * 100, 2))
        $elapsedTime = (Get-Date) - $startTime
        $avgJobTime = if ($completedVMs -gt 0) { $elapsedTime.TotalSeconds / $completedVMs } else { 0 }
        $remainingTime = ($totalVMs - $completedVMs) * $avgJobTime
        $eta = (Get-Date).AddSeconds($remainingTime)

        Write-Progress -Activity "Powering On VMs" `
                       -Status "$completedVMs / $totalVMs completed - ETA: $(($eta).ToString('HH:mm:ss'))" `
                       -PercentComplete $percentComplete
    }

    # Hide the progress bar after completion
    Write-Progress -Activity "Powering On VMs" -Completed

    # Finished
	Write-Host "`r`n[+] ALL VMS IN THE FOLDER '$folder' HAVE BEEN POWERED ON."
	Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# START/STOP VMS
# -------------------------------------------------------------------------------
function Change-VMPowerState {
    param (
        [Parameter(Mandatory)]
        [string]$folder,

        $vmList,

        [Parameter(Mandatory)]
        [ValidateSet("PowerOn","PowerOff")]
        [string]$action = "PowerOn"
    )

    # Validate PowerState parameter
    if ($action -notin @("PowerOn", "PowerOff")) {
        Write-Warning -Message "[+] INVALID PARAMETER, MUST BE 'PowerOn' OR 'PowerOff'"
        Return
    }

    # Find all VMs currently powered on
    if ($vmList -eq $null -and $action -eq "PowerOn") {
        $vmList = Generate-VMList -PowerState:"PoweredOff" -Folder:$folder
    } else {
        $vmList = Generate-VMList -PowerState:"PoweredOn" -Folder:$folder
    }

    

    # Power Off VMs
	foreach ($vm in $vmList) {
        try {
            if ($action -eq "PowerOn") {
                Write-Host -NoNewLine "[+] STARTING VM: "
                Write-Host -ForegroundCOlor Green "$($vm.Name)"
                Start-VM -VM $vm -Confirm:$false | Out-Null
            } else {
                Write-Host -NoNewLine "[+] STOPPING VM: "
                Write-Host -ForegroundColor Green "$($vm.Name)"
		        Stop-VM -VM $vm -Confirm:$false | Out-Null
            }
        } catch {
            Write-Warning -Message "An unexpected error has occurred. Is the network online?"
        }
	}

    # Task finished
    #if ($action -eq "PowerOn") {
	#    Write-Host -NoNewLine "`r`n[+] ALL VMS IN THE FOLDER "
    #    Write-Host -NoNewLine -ForegroundColor Green "'$folder' "
    #    Write-Host "HAVE BEEN STARTED."
    #} else {
    #    Write-Host -NoNewLine "`r`n[+] ALL VMS IN THE FOLDER "
    #    Write-Host -NoNewLine -ForegroundColor Green "'$folder' "
    #    Write-Host "HAVE BEEN SHUTDOWN."
    #}

    # Tasks Finished
    $actionMessage = if ($action -eq "PowerOn") { "STARTED" } else { "SHUTDOWN" }
    Write-Host -NoNewLine "`r`n[+] ALL VMS IN THE FOLDER "
    Write-Host -NoNewLine -ForegroundColor Green "'$folder' "
    Write-Host "HAVE BEEN $actionMessage."
    Write-Host "Debug:" # $($vmList.GetType())"
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
        [string]$powerState = "*", # 'PoweredOn' or 'PoweredOff'
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