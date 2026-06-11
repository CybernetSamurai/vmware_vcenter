# Build new vm based on selected template
# -----------------------------------------------------------------------
function Create-VM {
    param (
        [string]$folder,
        [string]$cluster = "ClusterSTVM",
        [string]$datastore = "Flash_Data_Store"
    )
    
    # Is folder empty
    if (-not $folder) {
        Write-Host "[+] Folder parameter is missing or invalid"
        return
    }

    # Calculate tne maximum number of VMs that can be made (no greater than number of users in AD)
    $numClassUsers = Get-ADUser -SearchBase "OU=$folder, OU=vLab_Students,OU=CT_Students, DC=YC-CNT, DC=EDU" -Filter *
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
    [int] $numVMs = Read-Host -Prompt "[+] HOW MANY VMS SHOULD BE MADE? (1-$maxVMs)"
    [int] $startNum = Read-Host -Prompt "[+] WHAT IS THE START NUMBER? (1-$maxVMs)"

    $endNum = $numVMs + $startNum - 1
    if ($endNum -gt $maxVMs -OR $endNum -lt 1 ) {
        Write-Warning -Message "[+] INVALID NUMBER OF VMS"
        Return
    }

    Write-Host "[+] CREATING '$numVMs' VMS STARTING AT '$startNum' WITH THE FOLLOWING ATTRIBUTES"
    Write-Host "    -----------------------------------------------------------------"
    Write-Host -ForegroundColor Yellow "    QUANTITY:      $numVMs"
    Write-Host -ForegroundColor Yellow "    STARTING AT:   $startNum"
    Write-Host -ForegroundColor Yellow "    LOCATION:      $folder"
    Write-Host -ForegroundColor Yellow "    TEMPLATE:      $template"
    Write-Host -ForegroundColor Yellow "    RESOURCE POOL: $cluster"
    Write-Host -ForegroundColor Yellow "    DATASTORE:     $datastore"
    Write-Host "    -----------------------------------------------------------------"

    # User prompt to continue 
    $answer = Read-Host -Prompt "[+] CONTINUE? [Y/N]"
    switch($answer.ToUpper()) {
        Y { Continue }
        default { Return }
    }

    # Create VMs
    for($i=$startNum; $i -le $endNum; $i++) {
        # format vm identifier ex "00", "01", etc
	    $vmNumber = "{0:00}" -f $i
	    $vmName = $folder + $osName + "-" + $vmNumber
	    $username = "YC-CNT\" + $folder + "-" + $vmNumber

        try {
	        # create the new VM and put it in a folder
		    Write-Host "[+] CREATING VM '$vmName' IN CLUSTER '$cluster'"
		    New-VM -Name $vmName -Template $template -ResourcePool $cluster -Datastore $datastore -DiskStorageFormat thin -Location $folder

            # set user permissions
            Write-Host "[+] SETTING USER '$username' PERMISSIONS"
	        Get-VM $vmName | New-VIPermission -Principal $username -Role "Virtual Machine console user" -Propagate $false
        } catch {
            Write-Warning -Message "An unexpected error occurred."
            Write-Warning -Message $Error[0]
        }
    }
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