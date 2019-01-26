<#
##############################################
                Overview
##############################################

This Cmdlet determines what changesets are candidates for merging/promotion/pushing.

##############################################
            One-Time Setup Instructions
##############################################

1) Find and replace all "DevOpsProject" with the name of the project on which you are working.

2) In order to make sure TF.exe knows which collection to query, run this and authenticate to Azure DevOps:
    "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\TF.exe" workspaces /collection:https://dev.azure.com/MyOrganization

After authenticating, you should get this back:

    Collection: https://dev.azure.com/MyOrganization/
    Workspace Owner        Computer  Comment
    --------- ------------ --------- --------------------------------------------------
    MCADAG-02 Dag Calafell MCADAG-02


##############################################
                Usage
##############################################

# Import this function
. '.\Azure DevOps Source Control.ps1'

# Example 1: Get candidates to promote from one branch to another
Get-DevOpsCandidates "$/DevOpsProject/DaxDevMca1" "$/DevOpsProject/Trunk"

# Example 2: Save output as CSV
[string[]]$devBranches = "$/DevOpsProject/dev1", "$/DevOpsProject/dev2", "$/DevOpsProject/dev3", "$/DevOpsProject/dev4", "$/DevOpsProject/dev5", "$/DevOpsProject/dev6", "$/DevOpsProject/dev7", "$/DevOpsProject/dev8", "$/DevOpsProject/dev9", "$/DevOpsProject/dev10", "$/DevOpsProject/dev11", "$/DevOpsProject/dev12"
[string]$promoteToBranch = "$/DevOpsProject/Trunk"

$CandidateChangeSets = Get-DevOpsCandidates $devBranches $promoteToBranch
$CandidateChangeSets | Format-Table *
$CandidateChangeSets | Export-Csv -NoTypeInformation -Path "$env:USERPROFILE\Desktop\Promotion Candidates for Trunk.csv"

#>

Function Get-DevOpsCandidates {

    [CmdletBinding(SupportsShouldProcess=$False, SupportsPaging=$False)]
    Param(
     
        [Parameter(Position=0, ValueFromPipeline=$True, Mandatory=$True)]
        [ValidateCount(1,99)]
        [Alias("From")]
        [string[]]$FromBranches,

        [Parameter(Position=1, ValueFromPipeline=$True, Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [Alias("To")]
        [string[]]$ToBranch,

        [Parameter()]
        [AllowNull()]
        [string[]]$tf_exe_fullpath
    )
 
    if ([String]::IsNullOrEmpty($tf_exe_fullpath))
    {
        $tf_exe_fullpath = "$env:ProgramFiles (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\TF.exe"
    }

    # Validate file exists
    if (-not [System.IO.File]::Exists($tf_exe_fullpath))
    {
        Write-Error "stderr: $stderr"
    }
    else
    {
        $tf_exe = [System.IO.Path]::GetFileName($tf_exe_fullpath)
        $workDir = [System.IO.Path]::GetDirectoryName($tf_exe_fullpath)
        $CandidateChangeSets = @()

        ForEach ($branch in $fromBranches) {
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = "$workDir\$tf_exe"
            $pinfo.WorkingDirectory = $workDir
            $pinfo.RedirectStandardError = $true
            $pinfo.RedirectStandardOutput = $true
            $pinfo.UseShellExecute = $false
            $pinfo.CreateNoWindow = $true
            $pinfo.Arguments = "merge /candidate /recursive $branch $promoteToBranch"

            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null
            $p.WaitForExit()
            if ($p.ExitCode -eq 0) {
                $stdout = $p.StandardOutput.ReadToEnd()

                $ccc = foreach ($line in $($stdout -split "`r`n")) {
                    if ($line -cmatch '(\d+\*?)\s+(.{17}) (.{10}) (.{1,40})') {
                        [PSCustomObject]@{
                            Changeset    = $matches[1]
                            User         = $matches[2].Trim()
                            Date         = [DateTime]::Parse($matches[3].Trim())
                            Comment      = $matches[4].Trim()
                            FromBranch   = $branch
                            ToBranch     = $promoteToBranch
                            ChangesetURL = ("https://dev.azure.com/mcaconnectv1/DevOpsProject/_versionControl/changeset/" + $matches[1].Replace("*",""))
                        }
                    } else {
                        if ($stdout -notlike "There are no changes to merge*" -and $stdout -notlike "Changeset User*" -and $stdout -notlike "--------- -*")
                        {
                            Write-Error $line
                        }
                    }
                }

                $CandidateChangeSets += $ccc
            }
            else {
                $stderr = $p.StandardError.ReadToEnd()
                Write-Error "stderr: $stderr"
            }
        }
    }

    $CandidateChangeSets
}
