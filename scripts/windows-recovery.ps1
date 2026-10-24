# Run locally on the remote Windows PC. Windows PowerShell 5.1 or PowerShell 7.
# This configures native crash recovery; it installs no agent, task or listener.
[CmdletBinding()]
param(
    [ValidateSet('check','install','recover','disable','uninstall')][string]$Action = 'check',
    [Parameter(Mandatory=$true)][Guid]$DesktopID
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This recovery kit is for Windows.' }
if (-not ('Telynd.ServicePolicy' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WindowsServicePolicy.cs') }
$ServiceName = 'chromoting'
$Store = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TelyndRecovery'
$Ledger = Join-Path $Store 'chromoting.json'
$Admins = [Security.Principal.SecurityIdentifier]'S-1-5-32-544'
$System = [Security.Principal.SecurityIdentifier]'S-1-5-18'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open PowerShell as administrator for this action. No changes made.'
    }
}
function Assert-ProtectedPath([string]$Path, [switch]$ParentOnly) {
    # Follow no reparse points. Only Administrators, SYSTEM and TrustedInstaller
    # may own a path or receive write access anywhere in its ancestry.
    $item = Get-Item -LiteralPath $Path -Force
    $leaf = -not $ParentOnly
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not accepted.' }
        $acl = Get-Acl -LiteralPath $item.FullName
        $trusted = @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted) { throw 'Untrusted file owner.' }
        $write = [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        if ($leaf) { $write = $write -bor [Security.AccessControl.FileSystemRights]::Write }
        foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
            # InheritOnly rights do not apply to this item (e.g. C:\ child creation).
            if (($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $write) -ne 0 -and $rule.IdentityReference.Value -notin $trusted) { throw "Unsafe permissions at $($item.FullName): $($rule.IdentityReference.Value) $($rule.FileSystemRights)." }
        }
        if ($item -is [IO.FileInfo]) { $item = $item.Directory } else { $item = $item.Parent }
        $leaf = $false
    }
}
function Get-ChromeInstallRoots {
    return @([Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('ProgramFilesX86')) | Where-Object { $_ }
}
function Get-ChromeHost {
    $service = Get-CimInstance Win32_Service -Filter "Name='chromoting'"
    if ($null -eq $service) { return $null }
    # Fail closed on unquoted paths, extra launchers, unexpected service accounts
    # and any executable outside the Google Chrome Remote Desktop installation.
    if ($service.PathName -notmatch '^"([^"\r\n]+\\remoting_host\.exe)"(?:\s+.*)?$' -or $service.StartName -ne 'LocalSystem') { throw 'Unrecognised Chrome host service.' }
    $exe = [IO.Path]::GetFullPath($Matches[1])
    $roots = @(Get-ChromeInstallRoots)
    if (-not ($roots | Where-Object { $exe.StartsWith((Join-Path $_ 'Google\Chrome Remote Desktop\'),[StringComparison]::OrdinalIgnoreCase) })) { throw 'Unexpected Chrome host executable location.' }
    Assert-ProtectedPath $exe
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -notin @('Google LLC','Google Inc')) { throw 'Chrome host signature is not trusted.' }
    # Service configuration itself must not be mutable by ordinary users.
    # Windows PowerShell 5.1's -LiteralPath registry lookup depends on the
    # current provider. This fixed path has no wildcard characters.
    $key = Get-Acl -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\chromoting'
    if ($key.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @($Admins.Value,$System.Value)) { throw 'Untrusted service configuration owner.' }
    foreach ($rule in $key.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and ($rule.RegistryRights -band ([Security.AccessControl.RegistryRights]::SetValue -bor [Security.AccessControl.RegistryRights]::CreateSubKey -bor [Security.AccessControl.RegistryRights]::Delete -bor [Security.AccessControl.RegistryRights]::ChangePermissions -bor [Security.AccessControl.RegistryRights]::TakeOwnership)) -ne 0 -and $rule.IdentityReference.Value -notin @($Admins.Value,$System.Value)) { throw 'Chrome service configuration is writable by another identity.' }
    }
    $descriptor=New-Object Security.AccessControl.RawSecurityDescriptor([Telynd.ServicePolicy]::Security($ServiceName))
    if ($descriptor.Owner.Value -notin @($Admins.Value,$System.Value) -or $null -eq $descriptor.DiscretionaryAcl) { throw 'Untrusted service security descriptor.' }
    foreach ($ace in $descriptor.DiscretionaryAcl) {
        if ($ace -is [Security.AccessControl.QualifiedAce] -and $ace.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed -and
            ($ace.AccessMask -band 0x500D0002) -ne 0 -and $ace.SecurityIdentifier.Value -notin @($Admins.Value,$System.Value)) { throw 'Another identity can modify the Chrome service.' }
    }
    return $service
}
function Policy-JSON($Policy) {
    # SCM normalises absent/empty command strings. Compare the semantic policy
    # with fixed field order across native objects and deserialised ledgers.
    return ([ordered]@{Reset=[uint32]$Policy.Reset;Reboot=[string]$Policy.Reboot;Command=[string]$Policy.Command;Actions=@($Policy.Actions | ForEach-Object { [ordered]@{Type=[int]$_.Type;Delay=[uint32]$_.Delay} })} | ConvertTo-Json -Depth 8 -Compress)
}
function Convert-Policy($Value) {
    $p = New-Object Telynd.FailurePolicy
    $p.Reset = [uint32]$Value.Reset
    if ($null -ne $Value.Reboot) { $p.Reboot = [string]$Value.Reboot }
    if ($null -ne $Value.Command) { $p.Command = [string]$Value.Command }
    $p.Actions = @($Value.Actions | ForEach-Object { $a=New-Object Telynd.FailureAction; $a.Type=[int]$_.Type; $a.Delay=[uint32]$_.Delay; $a })
    return $p
}
function Read-Ledger {
    if (-not (Test-Path -LiteralPath $Ledger)) { return $null }
    Assert-ProtectedPath $Store; Assert-ProtectedPath $Ledger
    if ((Get-Item -LiteralPath $Ledger).Length -gt 16384) { throw 'Oversized recovery ledger.' }
    $data = Get-Content -Raw -LiteralPath $Ledger | ConvertFrom-Json
    if ($data.schemaVersion -ne 1 -or $data.service -ne $ServiceName -or $data.state -notin @('prepared','installed','disabled')) { throw 'Unrecognised recovery ledger.' }
    return $data
}
function Save-Ledger($Data) {
    # The private directory ACL is set before any ledger is written. This file
    # contains no credentials. Prepared state survives a failed SCM update.
    $temp = Join-Path $Store ([Guid]::NewGuid().ToString()+'.tmp')
    try {
        $stream = [IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $bytes=[Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Depth 10)); $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        # Windows PowerShell coerces $null to an empty string for CLR string
        # parameters. NullString requests no backup path (not an invalid "").
        if (Test-Path -LiteralPath $Ledger) { [IO.File]::Replace($temp,$Ledger,[NullString]::Value) } else { [IO.File]::Move($temp,$Ledger) }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}

# check is read-only, including when Chrome or the ledger is missing.
$lock = $null
try {
    if ($Action -ne 'check') {
        Assert-Administrator
        if (-not (Test-Path -LiteralPath $Store)) {
            Assert-ProtectedPath (Split-Path $Store) -ParentOnly
            # CreateDirectory with its final ACL avoids a writable creation window.
            $acl = New-Object Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true,$false); $acl.SetOwner($Admins)
            foreach ($sid in @($Admins,$System)) { $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))) }
            $dir = New-Object IO.DirectoryInfo($Store)
            if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::Create($dir,$acl) } else { $dir.Create($acl) }
        }
        Assert-ProtectedPath $Store
        $lockPath = Join-Path $Store 'operation.lock'
        if (Test-Path -LiteralPath $lockPath) { Assert-ProtectedPath $lockPath }
        $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    }
    $hostService = Get-ChromeHost
    $ledgerUnreadable=$false
    try { $data = Read-Ledger }
    catch [System.UnauthorizedAccessException] {
        if ($Action -ne 'check') { throw }
        $data=$null; $ledgerUnreadable=$true
    }
    $outcome = 'checked'
    $policy = $null
    if ($null -ne $hostService) { $policy = [Telynd.ServicePolicy]::Read($ServiceName) }
    if ($Action -ne 'check') {
        if ($null -eq $hostService) { throw 'Chrome Remote Desktop is not installed.' }
        if ($null -ne $data -and $data.image -ne $hostService.PathName) { throw 'Chrome host changed since setup. Review before modifying its recovery policy.' }
        if ($Action -eq 'install') {
            if ($hostService.StartMode -ne 'Auto' -or $hostService.State -ne 'Running') { throw 'Enable and connect to the Chrome host before installing crash recovery.' }
            if ($null -eq $data) {
                $desired = Convert-Policy $policy
                $desired.Reset=86400
                $desired.Actions=@(@{Type=1;Delay=60000},@{Type=1;Delay=120000},@{Type=0;Delay=0}) | ForEach-Object { $a=New-Object Telynd.FailureAction; $a.Type=$_.Type; $a.Delay=$_.Delay; $a }
                $data=[pscustomobject]@{schemaVersion=1;service=$ServiceName;image=$hostService.PathName;state='prepared';original=$policy;desired=$desired}
                Save-Ledger $data
            }
            $current = Policy-JSON $policy
            if ($current -ne (Policy-JSON $data.original) -and $current -ne (Policy-JSON $data.desired)) { throw 'Failure actions changed outside Telynd. Nothing overwritten.' }
            [Telynd.ServicePolicy]::Write($ServiceName,(Convert-Policy $data.desired))
            if ((Policy-JSON ([Telynd.ServicePolicy]::Read($ServiceName))) -ne (Policy-JSON $data.desired)) { throw 'Crash recovery read-back failed; prepared ledger preserved.' }
            $data.state='installed'; Save-Ledger $data; $outcome='installed'
        } elseif ($Action -in @('disable','uninstall')) {
            if ($null -eq $data) { throw 'No owned recovery policy was found.' }
            $current = Policy-JSON $policy
            if ($current -ne (Policy-JSON $data.original) -and $current -ne (Policy-JSON $data.desired)) { throw 'Failure actions have drifted. Nothing overwritten.' }
            [Telynd.ServicePolicy]::Write($ServiceName,(Convert-Policy $data.original))
            if ((Policy-JSON ([Telynd.ServicePolicy]::Read($ServiceName))) -ne (Policy-JSON $data.original)) { throw 'Original policy restoration could not be verified.' }
            $data.state='disabled'; Save-Ledger $data; $outcome='disabled'
            if ($Action -eq 'uninstall') { Remove-Item -LiteralPath $Ledger; $data=$null; $outcome='uninstalled' }
        } else {
            if ($null -eq $data -or $data.state -ne 'installed' -or (Policy-JSON $policy) -ne (Policy-JSON $data.desired)) { throw 'Crash recovery ownership is not verified.' }
            $outcome='unchanged'
            if ($hostService.StartMode -eq 'Auto' -and $hostService.State -eq 'Stopped') { Start-Service -Name $ServiceName; $outcome='started' }
        }
        $hostService = Get-ChromeHost
        $policy = [Telynd.ServicePolicy]::Read($ServiceName)
    }
    $installation='missing'; $service='missing'; $enablement='unknown'; $scope='unavailable'
    if ($null -ne $hostService) {
        # Google's StopDaemon uses Manual (demand start), not Disabled. Only
        # its explicit automatic mode permits a Telynd-requested start.
        $scope='crash-only'; $enablement=switch ($hostService.StartMode) { 'Auto' {'enabled'} 'Manual' {'disabled'} 'Disabled' {'disabled'} default {'unknown'} }
        $service=switch ($hostService.State) { 'Running' {'running'} 'Stopped' {'stopped'} default {'transitioning'} }
    }
    if ($null -ne $data) {
        $installation='drift'
        if ($null -ne $hostService -and $data.image -eq $hostService.PathName) {
            if ($data.state -eq 'installed' -and (Policy-JSON $policy) -eq (Policy-JSON $data.desired)) { $installation='verified' }
            elseif ($data.state -eq 'disabled' -and (Policy-JSON $policy) -eq (Policy-JSON $data.original)) { $installation='disabled' }
            elseif ($data.state -eq 'prepared') { $installation='partial' }
        }
    }
    if ($ledgerUnreadable) { $installation='unknown' }
    [ordered]@{schemaVersion=1;desktopID=$DesktopID.ToString();platform='windows';osVersion=[Environment]::OSVersion.Version.ToString();architecture=$env:PROCESSOR_ARCHITECTURE;checkedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();service=$service;enablement=$enablement;installation=$installation;recovery=$scope;permissions='unknown';outcome=$outcome} | ConvertTo-Json -Compress
} finally { if ($null -ne $lock) { $lock.Dispose() } }
