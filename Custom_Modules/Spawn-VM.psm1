# Build new vm based on selected template
# -----------------------------------------------------------------------
function Create-VM {
    param (
        [Parameter(Mandatory)]
        [string]$folder,
        [string]$cluster = "ClusterSTVM",
        [string]$datastore = "Flash_Data_Store"
    )
    
    # Is folder empty
    if (-not $folder) {
        Write-Host "[+] Folder parameter is missing or invalid"
        return
    }

    # Active Directory user account paths
    $ldapPath = "OU=$folder,OU=vLab_Students,OU=CT_Students,DC=YC-CNT,DC=EDU"
    $ldapPathAlt = "OU=$folder,OU=Dual_Enrollment,OU=vLab_Students,OU=CT_Students,DC=YC-CNT,DC=EDU"

    # Calculate the maximum number of VMs that can be made (no greater than number of users in AD)
    $numClassUsers = Get-ADUser -SearchBase $ldapPath -Filter *
    [int]$maxVMs = $numClassUsers.Count

    # User prompt to continue 
    [string]$answer = Read-Host -Prompt "[+] CREATE VMS FOR THE COURSE '$folder'? [Y/N]"
    switch($answer.ToUpper()) {
        Y { Continue }
        default { Return }
    }

    # Select VM Template to use
    $template = User-SelectVMTemplate -Folder $folder
    if ($template -eq $null) { Return }
    $osName = ($template -Split '_')[-1]

    # User prompt to continue
    $answer = Read-Host "[+] SELECTED TEMPLATE '$template'. CONTINUE? [Y/N]"
    switch($answer.ToUpper()) {
        Y { Continue }
        default { Return }
    }

    # Validate number of VMs and start number
    [int] $totalVMs = Read-Host -Prompt "[+] HOW MANY VMS SHOULD BE MADE? (1-$maxVMs)"
    [int] $startNum = Read-Host -Prompt "[+] WHAT IS THE START NUMBER? (1-$maxVMs)"

    $endNum = $totalVMs + $startNum - 1
    if ($endNum -gt $maxVMs -OR $endNum -lt 1 ) {
        Write-Warning -Message "[+] INVALID NUMBER OF VMS"
        Return
    }

    # Create an array to hold background jobs and other variables
    $completedVMs = 0
    $maxJobs = 10
    $jobs = @()
    $startTime = Get-Date
    $avgJobTime = 180
    $estimatedSeconds = [math]::Floor(480 * ($totalVms % 10))
    $estimatedTime = [timespan]::FromSeconds($estimatedSeconds).ToString()

    Write-Host "[+] CREATING '$totalVMs' VMS STARTING AT '$startNum' WITH THE FOLLOWING ATTRIBUTES"
    Write-Host "    -----------------------------------------------------------------"
    Write-Host -ForegroundColor Yellow "    QUANTITY:      $totalVMs"
    Write-Host -ForegroundColor Yellow "    STARTING AT:   $startNum"
    Write-Host -ForegroundColor Yellow "    LOCATION:      $folder"
    Write-Host -ForegroundColor Yellow "    TEMPLATE:      $template"
    Write-Host -ForegroundColor Yellow "    RESOURCE POOL: $cluster"
    Write-Host -ForegroundColor Yellow "    DATASTORE:     $datastore"
    Write-Host -ForegroundColor Yellow "    ETA:           $estimatedTime"
    Write-Host "    -----------------------------------------------------------------"

    # User prompt to continue 
    $answer = Read-Host -Prompt "[+] CONTINUE? [Y/N]"
    switch($answer.ToUpper()) {
        Y { Continue }
        default { Return }
    }

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
		        New-VM -Name $using:vmName -Template $vmTemplate `
                    -ResourcePool $using:cluster `
                    -Datastore $using:datastore `
                    -DiskStorageFormat thin `
                    -Location $using:folder | Out-Null
		        Write-Host -NoNewLine "[+] CREATED VM "
                Write-Host -ForegroundColor Green "$using:vmName"

                # Set user permissions
	            Get-VM $using:vmName | New-VIPermission `
                    -Principal $using:username `
                    -Role "Virtual Machine console user" `
                    -Propagate $false | Out-Null
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

# Generate a List of VM Templates and Select one to use
# -----------------------------------------------------------------------
function User-SelectVMTemplate {
    param (
        [string]$folder
    )

    # List available templates
    [string]$templateFilter = $folder + "_Template_*"
    Write-Host "[+] FETCHING AVAILABLE TEMPLATES FOR '$folder'..."
    try {
        $templateList = Get-Template -Name $templateFilter
    } catch {
        Write-Warning -Message "[+] Error fetching templates: $_"
        return
    }

    # Check if no templates found
    if(-not $templateList) {
        Write-Warning "[+] NO TEMPLATES FOR '$folder' FOUND"
        return
    }

    # Print list of templates to screen
    Write-Host "[+] AVAILABLE TEMPLATES:"
    Write-Host "    0) Quit"
    $increment = 1
    foreach ($template in $templateList) {
        Write-Host "    $increment) $template"
        $increment++
    }
    Write-Host

    # Select template to use
    [int]$minOption = 0
    [int]$maxOption = $increment
    $templateSelect = -1

    Do {
        $templateSelect = Read-Host -Prompt "[+] SELECT TEMPLATE TO USE (0 to Quit)"
    } Until($templateSelect -in $minOption..$maxOption)

    # Quit program if user selects zero
    if($templateSelect -eq 0) { Return }

    Return $templateList[$templateSelect - 1]
}