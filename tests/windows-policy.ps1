# Disposable GitHub Windows runner only. Never run against a personal host.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:TELYND_DISPOSABLE_WINDOWS -ne '1') { throw 'Disposable runner opt-in required.' }
function Assert($condition,[string]$message) { if (-not $condition) { throw $message } }
$root=Join-Path $env:ProgramFiles ('TelyndFixture-'+[Guid]::NewGuid())
$service='TelyndRecoveryFixture'
if (Get-Service $service -ErrorAction SilentlyContinue) { throw 'Refusing to replace an existing service.' }
$null=New-Item -ItemType Directory $root
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
$acl.SetOwner([Security.Principal.SecurityIdentifier]'S-1-5-32-544')
foreach ($sid in @('S-1-5-18','S-1-5-32-544')) { $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(([Security.Principal.SecurityIdentifier]$sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))) }
Set-Acl -LiteralPath $root -AclObject $acl
$googleFolder=Join-Path $root 'Google/Chrome Remote Desktop'
$null=New-Item -ItemType Directory $googleFolder
$exe=Join-Path $googleFolder 'remoting_host.exe'
$counter=Join-Path $googleFolder 'starts'
$crash=Join-Path $googleFolder 'crash'
$fixtureSource=@'
using System;
using System.IO;
using System.ServiceProcess;
using System.Threading;
class Fixture : ServiceBase {
  Timer timer;
  static string Folder=AppDomain.CurrentDomain.BaseDirectory;
  Fixture(){ServiceName="TelyndRecoveryFixture";}
  protected override void OnStart(string[] args){
    File.AppendAllText(Path.Combine(Folder,"starts"),"start\n");
    timer=new Timer(_=>{var path=Path.Combine(Folder,"crash"); if(File.Exists(path)){File.Delete(path);Environment.Exit(99);}},null,200,200);
  }
  protected override void OnStop(){timer.Dispose();}
  static void Main(){ServiceBase.Run(new Fixture());}
}
'@
try {
    # Use the installed .NET Framework compiler so the fixture is an executable
    # under both Windows PowerShell 5.1 and PowerShell 7.
    $sourceFile=Join-Path $root 'fixture.cs'
    Set-Content -LiteralPath $sourceFile -Value $fixtureSource -Encoding UTF8
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:winexe /reference:System.ServiceProcess.dll ("/out:"+$exe) $sourceFile
    Assert ($LASTEXITCODE -eq 0) 'Fixture compilation failed'
    # Use an API rather than sc.exe's legacy native argument quoting: Windows
    # PowerShell can otherwise strip the quotes that protect Program Files.
    $null=New-Service -Name $service -BinaryPathName ('"'+$exe+'"') -StartupType Automatic
    Start-Service $service
    Copy-Item "$PSScriptRoot/../scripts/WindowsServicePolicy.cs" $root
    # Keep Get-ChromeHost and its security decisions intact. Only substitute
    # the synthetic installation root/signature and fixed service/store names.
    # Real executable ancestry, registry ACL and service DACL checks still run.
    $source=Get-Content -Raw "$PSScriptRoot/../scripts/windows-recovery.ps1"
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Production PowerShell syntax errors'
    $fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ChromeInstallRoots'},$true)
    $replacement="function Get-ChromeInstallRoots { return '"+$root.Replace("'","''")+"' }"
    $source=$source.Remove($fn.Extent.StartOffset,$fn.Extent.EndOffset-$fn.Extent.StartOffset).Insert($fn.Extent.StartOffset,$replacement)
    $source=$source.Replace("Name='chromoting'","Name='TelyndRecoveryFixture'")
    $source=$source.Replace('Services\chromoting','Services\TelyndRecoveryFixture')
    $source=$source.Replace("`$ServiceName = 'chromoting'","`$ServiceName = 'TelyndRecoveryFixture'")
    $source=$source.Replace("`$Store = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TelyndRecovery'","`$Store = '"+$root.Replace("'","''")+"\owned'")
    $script=Join-Path $root 'windows-recovery.ps1'; Set-Content -LiteralPath $script -Value $source -Encoding UTF8
    # This fixture is unsigned. Replace the external signature query, never
    # the validator, and exercise both acceptance and rejection below.
    $global:TelyndFixtureSignatureStatus='Valid'; $global:TelyndFixtureSignaturePublisher='Google LLC'
    function Get-AuthenticodeSignature {
        param([string]$LiteralPath)
        Assert ($LiteralPath -eq $exe) 'Unexpected executable signature query'
        $cert=New-Object PSObject
        $cert | Add-Member NoteProperty Publisher $global:TelyndFixtureSignaturePublisher
        $cert | Add-Member ScriptMethod GetNameInfo { param($kind,$issuer) return $this.Publisher }
        return [pscustomobject]@{Status=$global:TelyndFixtureSignatureStatus;SignerCertificate=$cert}
    }
    $id='00000000-0000-0000-0000-000000000001'
    Write-Host 'Validating the protected synthetic host'
    $before=& $script -Action check -DesktopID $id | ConvertFrom-Json
    Assert ($before.installation -eq 'missing') 'Expected missing installation'
    Assert (-not (Test-Path (Join-Path $root 'owned'))) 'Check mutated filesystem'
    function Assert-CheckRefused([string]$message) {
        $refused=$false; try { $null=& $script -Action check -DesktopID $id } catch { $refused=$true }
        Assert $refused $message
    }
    function Set-FixtureConfig($arguments) {
        $result=Invoke-CimMethod -InputObject (Get-CimInstance Win32_Service -Filter "Name='TelyndRecoveryFixture'") -MethodName Change -Arguments $arguments
        Assert ($result.ReturnValue -eq 0) 'Fixture service configuration update failed'
    }
    foreach ($status in @('NotSigned','HashMismatch','UnknownError')) {
        $global:TelyndFixtureSignatureStatus=$status
        Assert-CheckRefused 'Invalid executable signature accepted'
    }
    $global:TelyndFixtureSignatureStatus='Valid'; $global:TelyndFixtureSignaturePublisher='Other Publisher'
    Assert-CheckRefused 'Foreign publisher accepted'
    $global:TelyndFixtureSignaturePublisher='Google LLC'
    # Refuse executable substitution, launchers and unexpected service accounts.
    foreach ($path in @($exe, ('"'+$root+'\other.exe"'), ('"'+$root+'\remoting_host.exe"'))) {
        Set-FixtureConfig @{PathName=$path}
        Assert-CheckRefused 'Unsafe service executable accepted'
    }
    Set-FixtureConfig @{PathName=('"'+$exe+'"');StartName='NT AUTHORITY\LocalService'}
    Assert-CheckRefused 'Unexpected service account accepted'
    Set-FixtureConfig @{StartName='LocalSystem'}
    $exeAcl=Get-Acl -LiteralPath $exe
    $unsafeExeAcl=Get-Acl -LiteralPath $exe
    $unsafeExeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(([Security.Principal.SecurityIdentifier]'S-1-5-11'),'Write','Allow')))
    Set-Acl -LiteralPath $exe -AclObject $unsafeExeAcl
    Assert-CheckRefused 'Writable executable accepted'
    Set-Acl -LiteralPath $exe -AclObject $exeAcl
    $registryPath='HKLM:\SYSTEM\CurrentControlSet\Services\TelyndRecoveryFixture'
    $registryAcl=Get-Acl -Path $registryPath
    $unsafeRegistryAcl=Get-Acl -Path $registryPath
    $unsafeRegistryAcl.AddAccessRule((New-Object Security.AccessControl.RegistryAccessRule(([Security.Principal.SecurityIdentifier]'S-1-5-11'),'SetValue','Allow')))
    Set-Acl -Path $registryPath -AclObject $unsafeRegistryAcl
    Assert-CheckRefused 'Writable service registry accepted'
    # RegistrySecurity persists only sections marked modified; passing the
    # untouched Get-Acl snapshot back to Set-Acl silently leaves our test ACE.
    $restoreRegistryAcl=New-Object Security.AccessControl.RegistrySecurity
    $restoreRegistryAcl.SetSecurityDescriptorSddlForm($registryAcl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access),[Security.AccessControl.AccessControlSections]::Access)
    Set-Acl -Path $registryPath -AclObject $restoreRegistryAcl
    $serviceSddl=[Telynd.ServicePolicy]::Security($service)
    $unsafeSddl=New-Object Security.AccessControl.RawSecurityDescriptor($serviceSddl)
    $unsafeSddl.DiscretionaryAcl.InsertAce(0,(New-Object Security.AccessControl.CommonAce([Security.AccessControl.AceFlags]::None,[Security.AccessControl.AceQualifier]::AccessAllowed,2,([Security.Principal.SecurityIdentifier]'S-1-5-11'),$false,$null)))
    & sc.exe sdset $service ($unsafeSddl.GetSddlForm([Security.AccessControl.AccessControlSections]::Access)) | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Unsafe fixture service DACL update failed'
    Assert-CheckRefused 'Writable service DACL accepted'
    $restoreSddl=New-Object Security.AccessControl.RawSecurityDescriptor($serviceSddl)
    & sc.exe sdset $service ($restoreSddl.GetSddlForm([Security.AccessControl.AccessControlSections]::Access)) | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Fixture service DACL restoration failed'
    Write-Host 'Validating restored host permissions and policy lifecycle'
    $original=[Telynd.ServicePolicy]::Read($service) | ConvertTo-Json -Depth 8 -Compress
    Assert (([Telynd.ServicePolicy]::Security($service)).Contains('D:')) 'Native service security descriptor was not returned'
    $installed=& $script -Action install -DesktopID $id | ConvertFrom-Json
    Assert ($installed.installation -eq 'verified') 'Install read-back failed'
    $null=& $script -Action install -DesktopID $id
    # Google deliberately stops a host by setting demand (CIM Manual). Do not
    # restart it or advertise enabled recovery even with our valid ledger.
    Stop-Service $service
    foreach ($mode in @('demand','disabled')) {
        & sc.exe config $service start= $mode | Out-Null
        Assert ($LASTEXITCODE -eq 0) 'Fixture disablement update failed'
        $report=& $script -Action recover -DesktopID $id | ConvertFrom-Json
        Assert ($report.enablement -eq 'disabled' -and $report.outcome -eq 'unchanged') 'Intentional disablement ignored'
        Assert ((Get-Service $service).Status -eq 'Stopped') 'Intentionally stopped host restarted'
        $refused=$false; try { $null=& $script -Action install -DesktopID $id } catch { $refused=$true }
        Assert $refused 'Install accepted intentionally disabled host'
    }
    & sc.exe config $service start= auto | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Fixture enablement restoration failed'
    $report=& $script -Action recover -DesktopID $id | ConvertFrom-Json
    Assert ($report.outcome -eq 'started' -and $report.enablement -eq 'enabled') 'Automatic stopped host did not recover'
    # A ledger writable by ordinary users must be refused before using it.
    $ledgerPath=Join-Path $root 'owned/chromoting.json'
    $originalAcl=Get-Acl -LiteralPath $ledgerPath
    $unsafeAcl=Get-Acl -LiteralPath $ledgerPath
    $unsafeAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(([Security.Principal.SecurityIdentifier]'S-1-5-11'),'Write','Allow')))
    Set-Acl -LiteralPath $ledgerPath -AclObject $unsafeAcl
    $refused=$false; try { $null=& $script -Action check -DesktopID $id } catch { $refused=$true }
    Assert $refused 'Writable ledger was accepted'
    Set-Acl -LiteralPath $ledgerPath -AclObject $originalAcl
    $p=[Telynd.ServicePolicy]::Read($service)
    Assert ($p.Actions.Count -eq 3 -and $p.Actions[2].Type -eq 0) 'Retries not bounded'
    # Third-party drift must never be overwritten, including on uninstall.
    $p.Reset=1234; [Telynd.ServicePolicy]::Write($service,$p)
    $refused=$false; try { $null=& $script -Action uninstall -DesktopID $id } catch { $refused=$true }
    Assert $refused 'Uninstall overwrote third-party drift'
    $ledger=Get-Content -Raw (Join-Path $root 'owned/chromoting.json') | ConvertFrom-Json
    $desired=New-Object Telynd.FailurePolicy
    $desired.Reset=$ledger.desired.Reset; $desired.Reboot=$ledger.desired.Reboot; $desired.Command=$ledger.desired.Command
    $desired.Actions=@($ledger.desired.Actions | ForEach-Object { $a=New-Object Telynd.FailureAction; $a.Type=$_.Type; $a.Delay=$_.Delay; $a })
    [Telynd.ServicePolicy]::Write($service,$desired)
    $disabled=& $script -Action disable -DesktopID $id | ConvertFrom-Json
    Assert ($disabled.installation -eq 'disabled') 'Disable not recorded'
    Assert (([Telynd.ServicePolicy]::Read($service) | ConvertTo-Json -Depth 8 -Compress) -eq $original) 'Original policy not restored'
    $null=& $script -Action install -DesktopID $id
    $null=& $script -Action uninstall -DesktopID $id
    Assert (-not (Test-Path (Join-Path $root 'owned/chromoting.json'))) 'Ledger was not removed'
    Assert (([Telynd.ServicePolicy]::Read($service) | ConvertTo-Json -Depth 8 -Compress) -eq $original) 'Uninstall did not restore original policy'
    # Exercise real service failure/restart semantics with shorter test delays.
    $p=[Telynd.ServicePolicy]::Read($service); $p.Reset=86400
    $p.Actions=@(@{Type=1;Delay=1000},@{Type=1;Delay=1000},@{Type=0;Delay=0}) | ForEach-Object { $a=New-Object Telynd.FailureAction; $a.Type=$_.Type; $a.Delay=$_.Delay; $a }
    [Telynd.ServicePolicy]::Write($service,$p)
    Stop-Service $service
    Start-Sleep -Seconds 2
    Assert ((Get-Service $service).Status -eq 'Stopped') 'Orderly stop was restarted'
    Start-Service $service
    function Count-Starts { return @(Get-Content -LiteralPath $counter).Count }
    for ($attempt=0;$attempt -lt 3;$attempt++) {
        $count=Count-Starts
        Set-Content -LiteralPath $crash -Value crash
        $deadline=[DateTime]::UtcNow.AddSeconds(15)
        if ($attempt -lt 2) {
            while ((Count-Starts) -le $count -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
            Assert ((Count-Starts) -eq $count+1) 'Crash was not restarted exactly once'
        } else {
            while ((Get-Service $service).Status -ne 'Stopped' -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
            Start-Sleep -Seconds 2
            Assert ((Count-Starts) -eq $count) 'Crash retry limit failed'
        }
    }
    Write-Output 'Windows native policy, ledger restoration, drift refusal and bounded SCM recovery passed.'
} finally {
    Remove-Variable TelyndFixtureSignatureStatus,TelyndFixtureSignaturePublisher -Scope Global -ErrorAction SilentlyContinue
    Stop-Service $service -ErrorAction SilentlyContinue
    & sc.exe delete $service | Out-Null
    Remove-Item -LiteralPath $root -Recurse -Force
}
