# Script acquired from github.com/vxav/Scripting/blob/master/Start-PowerCLIJobs.ps1
# Blog: vxav.fr/2017-08-08-easily-run-powercli-commands-as-jobs/

Function Start-PowerCLIJob {

    param(
        [parameter(mandatory=$True)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl]$DefaultVIServer,

        [PSCredential]$userCred,

        [string]$JobName,

        [parameter(mandatory=$True)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList,

        [psobject]$InputObject,

        [string[]]$Modules = "VMware.VimAutomation.Core"
    )

    $ScriptBlockPrepend = {
        import-module $using:Modules | out-null;
        Set-PowerCLIConfiguration -DisplayDeprecationWarnings:$false -Scope Session -confirm:$False | out-null;
        Connect-ViServer -Server $using:DefaultVIServer.name -Session $using:DefaultVIServer.SessionId | out-null;
    }

    $ScriptBlock = [ScriptBlock]::Create($ScriptBlockPrepend.ToString() + $ScriptBlock.ToString())

    $params = @{scriptblock=$ScriptBlock}
    if ($JobName) {$params.Add('name',$JobName)}
    if ($ArgumentList) {$params.Add('ArgumentList',$ArgumentList)}
    if ($InputObject) {$params.Add('InputObject',$InputObject)}

    Start-Job @params
}