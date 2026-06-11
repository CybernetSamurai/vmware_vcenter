# START/STOP VMS
# -------------------------------------------------------------------------------
function Convert-VMPowerState {
    param (
        [Parameter(Mandatory)]
        [string]$folder,

        [Parameter(Mandatory)]
        [ValidateSet("PowerOn","PowerOff")]
        [string]$action = "PowerOn",

        [array]$vmList
    ) 

    # Find all VMs currently powered on
    if ($vmList -eq $null) {
        $vmList = if ($action -eq "PowerOn") {
            New-VMList -PowerState:"PoweredOff" -Folder:$folder
        } else {
            New-VMList -PowerState:"PoweredOn" -Folder:$folder
        }
    }

    # Exit if list returns empty
    if ($vmList.Count -eq 0) { Return }

    # Change VM powerstate in parallel
    $vmList | ForEach-Object -Parallel {
        try {
            if ($using:action -eq "PowerOn") {
                Write-Host -NoNewLine "[+] STARTING VM: "
                Write-Host -ForegroundCOlor Green "$($_.Name)"
                Start-VM -VM $_ -Confirm:$false | Out-Null
            } else {
                Write-Host -NoNewLine "[+] STOPPING VM: "
                Write-Host -ForegroundColor Green "$($_.Name)"
		        Stop-VM -VM $_ -Confirm:$false | Out-Null
            }
        } catch {
            Write-Host -ForegroundColor Red "[+] ERROR MESSAGE: $($_.Exception.Message)"
            Write-Host -ForegroundColor Yellow "[+] AN UNEXPECTED ERROR HAS OCCURRED. IS THE NETWORK ONLINE?"
        }
    } -ThrottleLimit 10

    # Tasks Finished
    $actionMessage = if ($action -eq "PowerOn") { "STARTED" } else { "SHUTDOWN" }
    Write-Host -NoNewLine "`r`n[+] ALL VMS IN THE FOLDER "
    Write-Host -NoNewLine -ForegroundColor Green "'$folder' "
    Write-Host "HAVE BEEN $actionMessage."

    # Prompt to continue
	Read-Host -Prompt "[+] PRESS ANY KEY TO CONTINUE..." | Out-Null
}

# UPDATE VMWARE TOOLS
# -------------------------------------------------------------------------------
function Update-VM {
    param (
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
    if($vmList -eq $null) { $vmList = New-VMList @VMPARAMS }

    # Exit if list returns empty
    if ($vmList.Count -eq 0) { Return }

    # Update VMs
	$vmList | ForEach-Object -Parallel {
        try {
            Import-Module \\cybernas\Internal\Scripts\vLab_VMware\Custom_Modules\Get-VMToolsStatus.psm1 -Force
            Connect-VIServer -Server $using:DefaultVIServer.Name -Session $using:DefaultVIServer.SessionId
            $vm = $_

            # Power On VM if necessary
            if($($vm.PowerState) -eq "PoweredOff") {
                #
                Write-Host -NoNewLine "[+] STARTING VM: "
                Write-Host -ForegroundColor Green "$($vm.Name)"
                Start-VM -VM $vm -Confirm:$false | Out-Null

                # Wait until VM is powered on and VMware Tools is running (with retries)
                $maxWaitTime = 300  # 5 minutes
                $waitTime = 0
                while ($vm.PowerState -ne "PoweredOn" -and (Get-VMToolsStatus -Name $vm.Name).Status -ne "toolsOk") {
                    Start-Sleep -Seconds 5 
                    $waitTime += 5
                    if ($waitTime -ge $maxWaitTime) {
                        Write-Host -ForegroundColor Yellow "[+] Timeout reached while waiting for VM to be ready. Moving on..."
                        Return
                    }

                    # Re-fetch VM to check power state and Tools status
                    $vm = Get-VM -Name $vm.Name  
                }
            }

            #Write-Host -ForegroundColor Green "True"
            if ((Get-VMToolsStatus -Name $vm.Name).UpgradeStatus -eq "guestToolsSupportedOld") {
                Write-Host -NoNewLine "[+] UPDATING VM: "
                Write-Host -ForegroundColor Green "$($vm.Name)"
                Update-Tools -VM $vm | Out-Null
            }
        } catch {
            Write-Host -ForegroundColor Red "[+] ERROR MESSAGE: $($_.Exception.Message)"
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

# GENERATE VM LIST
# -------------------------------------------------------------------------------
function New-VMList {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("*","PoweredOn","PoweredOff")]
        [string]$powerState = "*",

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
	    if (-not $filterInclude) { $filterInclude = "*" }

        # Filter for VMs to exclude
	    $filterExclude = Read-Host -Prompt "[+] VM EXCLUDE FILTER (enter for N/A)"

        # Generate List of VMs
	    $vmList = Get-VM -Location $folder | Where-Object {
	        $_.PowerState -like $powerState -and
		    $_.Name -like $filterInclude -and
		    $_.Name -notlike $filterExclude 
	    }

        # Filter List by OS
        $vmList = $vmList | Where-Object { (Get-VMGuest -VM $_).GuestFamily -like $OSFamily }

        # Print list to terminal
        $vmList | Select-Object -Property Name, PowerState | Format-Table | Out-String | Write-Host

        # Ask user to continue
		$answer = Read-Host -Prompt "[+] PROCEED WITH SELECTED MACHINES IN $folder? [Y(es), N(o), Q(uit)]"
		switch ($answer.ToUpper()) {
			Y { $listReady = $true }
			N { Continue }
			default { Return }
		}

    } Until($listReady)

    Return $vmList
}