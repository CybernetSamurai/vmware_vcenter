# Change current folder
# -------------------------------------------------------------------------------
function Change-Folder {

    Do {
        $newFolder = Read-Host -Prompt "[+] NEW FOLDER NAME"
        $exists = Check-Folder -Folder $newFolder -Server $global:server.Name -Cluster $global:cluster -Type VM
    } Until($exists)

	return $newFolder
}

# Validate Folder Exists
# -------------------------------------------------------------------------------
function Check-Folder {
    param (
        [string]$folder,
        [string]$type
    )

    try {
        Get-Folder -Name $folder -Server $global:server.Name -Type $type
    } catch {
        Write-Warning -Message $Error[0]
        Write-Warning -Message "An error occurred. Check your spelling?"
        return 0
    }
    return 1
}

# User Prompt To Continue
# -------------------------------------------------------------------------------
function Prompt-UserContinue {
    param (
        [string]$message = "[+] CONTINUE? [Y/N]"
    )

    $answer = Read-Host $message
    switch($answer.ToUpper()) {
        Y {Return 1}
        default {Return 0}
    }
}