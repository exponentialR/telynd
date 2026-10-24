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
$exe=Join-Path $root 'fixture.exe'
$counter=Join-Path $root 'starts'
$crash=Join-Path $root 'crash'
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
    & sc.exe create $service binPath= ('"'+$exe+'"') start= demand | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Fixture registration failed'
    Start-Service $service
    Copy-Item "$PSScriptRoot/../scripts/WindowsServicePolicy.cs" $root
    # Adapt only the fixed service/store and Google identity provider in a copy.
    # Real SCM, native policy marshal/read/write, ACLs and ledger code remain.
    $source=Get-Content -Raw "$PSScriptRoot/../scripts/windows-recovery.ps1"
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Production PowerShell syntax errors'
    $fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ChromeHost'},$true)
    $replacement="function Get-ChromeHost { return Get-CimInstance Win32_Service -Filter `"Name='TelyndRecoveryFixture'`" }"
    $source=$source.Remove($fn.Extent.StartOffset,$fn.Extent.EndOffset-$fn.Extent.StartOffset).Insert($fn.Extent.StartOffset,$replacement)
    $source=$source.Replace("`$ServiceName = 'chromoting'","`$ServiceName = 'TelyndRecoveryFixture'")
    $source=$source.Replace("`$Store = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'TelyndRecovery'","`$Store = '"+$root.Replace("'","''")+"\owned'")
    $script=Join-Path $root 'windows-recovery.ps1'; Set-Content -LiteralPath $script -Value $source -Encoding UTF8
    $id='00000000-0000-0000-0000-000000000001'
    $before=& $script -Action check -DesktopID $id | ConvertFrom-Json
    Assert ($before.installation -eq 'missing') 'Expected missing installation'
    Assert (-not (Test-Path (Join-Path $root 'owned'))) 'Check mutated filesystem'
    $original=[Telynd.ServicePolicy]::Read($service) | ConvertTo-Json -Depth 8 -Compress
    $installed=& $script -Action install -DesktopID $id | ConvertFrom-Json
    Assert ($installed.installation -eq 'verified') 'Install read-back failed'
    $null=& $script -Action install -DesktopID $id
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
    Stop-Service $service -ErrorAction SilentlyContinue
    & sc.exe delete $service | Out-Null
    Remove-Item -LiteralPath $root -Recurse -Force
}
