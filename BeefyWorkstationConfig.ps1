########
# Configure
########
$DisabledExecutableFileTypes = @(
    'batfile',
    'cmdfile',
    'comfile',
    'htafile',
    'inffile',
    'JobObject',
    'JSEFile',
    'JSFile',
    'Microsoft.PowerShellConsole.1',
    'Microsoft.PowerShellData.1',
    'Microsoft.PowerShellModule.1',
    'Microsoft.PowerShellScript.1',
    'Microsoft.PowerShellXMLData.1',
    'regfile',
    'scrfile',
    'scriptletfile',
    'SHCmdFile',
    'VBEFile',
    'VBSFile',
    'VisualStudio.vb.14.0',
    'Windows.CompositeFont',
    'WSFFile',
    'WSHFile'
)

$DisabledWindowsOptionalFeatures = @(
    #'MicrosoftWindowsPowerShellV2', # Including PowerShell 2 features causes multiple failures of DSC.
    #'MicrosoftWindowsPowerShellV2Root',
    'SMB1Protocol-Client',
    'SMB1Protocol-Server',
    'SMB1Protocol'
)

$DisabledServices = @(
    'iphlpsvc',
    'NetTcpPortSharing',
    'RemoteRegistry'
)

$HardenPerUser = {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad' -Name 'WpadOverride' -Value 1  -Force

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideDrivesWithNoMedia' -Value 0
    Set-ItemProperty -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explore' -Name 'HidePeopleBar' -Value 1

    Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0
}

$Configuration =
@{
    AllNodes =
    @(
        # Default data. DO NOT MODIFY.
        @{
            NodeName                        = '*'
            ConfigurationModeFrequencyMins  = 90
            DisabledExecutableFileTypes     = $DisabledExecutableFileTypes
            DisabledWindowsOptionalFeatures = $DisabledWindowsOptionalFeatures
            DisabledServices                = $DisabledServices
            EnforceExecutableFileTypes      = $true
            EnforceWindowsOptionalFeatures  = $true
            EnforceServices                 = $true
            EnforceWindowsUpdate            = $true
            EnforceEventLog                 = $true
            EnforcePowerShellLogging        = $true
            EnforceIEESC                    = $true
            EnforceNBTCPIP                  = $true
            EnforceDeviceGuard              = $true
        },
        
        # Node 'localhost'. OVERRIDE HERE. Pattern on above.
        @{
            NodeName                        = 'localhost'
            EnforceDeviceGuard              = $false # Default to off, as on prevents some virtualization software from working.
        }
    )
}


########
# DSC Configuration
########
[DSCLocalConfigurationManager()]
Configuration BeefyWorkstationConfigLCM
{
    Node localhost
    {
        Settings
        {
            ConfigurationMode              = 'ApplyAndAutoCorrect'
            ConfigurationModeFrequencyMins = $Configuration.AllNodes[0].ConfigurationModeFrequencyMins
            StatusRetentionTimeInDays      = 10
        }
    }
}

Configuration BeefyWorkstationConfig
{
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDsc -ModuleVersion '6.0.0.0'
    Import-DscResource -ModuleName xSystemSecurity
    Import-DscResource -ModuleName xWindowsUpdate
    Import-DscResource -ModuleName xWinEventLog

    Node $AllNodes.NodeName
    {
        ScheduledTask ConsistencyCheck
        {
            TaskName                = 'BeefyWorkstationConfig ConsistencyCheck'
            TaskPath                = '\BeefyWorkstationConfig'
            ActionExecutable        = [System.Environment]::ExpandEnvironmentVariables( '%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe' )
            ActionArguments         = '-Exec Bypass -NoP -Win Hidden -C "Invoke-CimMethod -Namespace ''root/Microsoft/Windows/DesiredStateConfiguration'' -ClassName ''MSFT_DscTimer'' -Name ''StartDscTimer''"'
            ScheduleType            = 'AtStartup'
            RunLevel                = 'Highest'
            AllowStartIfOnBatteries = $True
            DisallowDemandStart     = $True
            MultipleInstances       = 'IgnoreNew'
        }
    }

    #### Base OS
    Node $AllNodes.Where{ $_.EnforceExecutableFileTypes }.NodeName
    {
        # Force executable file types listed in configuration to open via edit command by default.
        $Node.DisabledExecutableFileTypes.ForEach({
            Registry $_
            {
                Ensure    = 'Present'
                Key       = ( 'HKEY_CLASSES_ROOT\{0}\shell' -f $_ )
                ValueName = '(Default)'
                ValueData = 'edit'
            }
        })
    }

    Node $AllNodes.Where{ $_.EnforceWindowsOptionalFeatures }.NodeName
    {
        # Disable / remove Windows Optional Features listed in configuration.
        $Node.DisabledWindowsOptionalFeatures.ForEach({
            WindowsOptionalFeature $_
            {
                Ensure    = 'Disable'
                Name      =  $_
            }
        })
    }

    Node $AllNodes.Where{ $_.EnforceServices }.NodeName
    {
        # Stop / Disable risky Services
        $Node.DisabledServices.ForEach({
            Service $_
            {
                State       = 'Stopped'
                StartupType = 'Disabled'
                Name        =  $_
            }
        })
    }

    Node $AllNodes.Where{ $_.EnforceWindowsUpdate }.NodeName
    {
        # Force Windows Update to be enabled and install Security and Important updates.
        xWindowsUpdateAgent WindowsUpdate
        {
            Category         = @( 'Security', 'Important', 'Optional' )
            Notifications    = 'ScheduledInstallation'
            Source           = 'MicrosoftUpdate' # Or WindowsUpdate for Windows-only
            UpdateNow        = $false
            IsSingleInstance = 'Yes'
        }
    }

    Node $AllNodes.Where{ $_.EnforceEventLog }.NodeName
    {
        # Set event log sizes
        xWinEventLog EventLogApplication
        {
            LogName            = 'Application'
            IsEnabled          = $true
            LogMode            = 'Circular'
            MaximumSizeInBytes = 32mb
        }
        xWinEventLog EventLogSystem
        {
            LogName            = 'System'
            IsEnabled          = $true
            LogMode            = 'Circular'
            MaximumSizeInBytes = 32mb
        }
        xWinEventLog EventLogSecurity
        {
            LogName            = 'Security'
            IsEnabled          = $true
            LogMode            = 'Circular'
            MaximumSizeInBytes = 196mb
        }
    }

    Node $AllNodes.Where{ $_.EnforcePowerShellLogging }.NodeName
    {
        Registry EnableScriptBlockLogging
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
            ValueName = 'EnableScriptBlockLogging'
            ValueData = 1
        }
        Registry EnableModuleLogging
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
            ValueName = 'EnableModuleLogging'
            ValueData = 1
        }
        Registry EnableModuleLoggingModules
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames '
            ValueName = '*'
            ValueData = '*'
        }
    }

    Node $AllNodes.Where{ $_.IEESC }.NodeName
    {
        # Force enable IE ESC.
        xIEEsc IEESCAdministrators
        {
            UserRole = 'Administrators'
            IsEnabled = $true
        }
        xIEEsc IEESCUsers
        {
            UserRole = 'Users'
            IsEnabled = $true
        }
    }

    #### Network
    # Aggregate actions over all adapters blindly rather than trying to generate a list of adapters and configs at compile time.
    Node $AllNodes.Where{ $_.EnforceNBTCPIP }.NodeName
    {
        Script NetBIOSOverTCPIP
        {
            GetScript = {
                @{ 'Result' = [System.Convert]::ToBoolean( ( Get-CimInstance -ClassName 'Win32_NetworkAdapterConfiguration' | Select-Object -ExpandProperty 'TcpipNetbiosOptions' | Where-Object { ( $_ -ne $null ) -and ( $_ -ne 2 ) } | Measure-Object -Sum ).Sum ).ToString() }
            }

            SetScript = {
                Get-CimInstance -ClassName 'Win32_NetworkAdapterConfiguration' | Invoke-CimMethod -MethodName 'SetTcpipNetbios' -Arguments @{ 'TcpipNetbiosOptions' = 2 } | Out-Null
            }

            TestScript = {
                -not [System.Convert]::ToBoolean( ( Get-CimInstance -ClassName 'Win32_NetworkAdapterConfiguration' | Select-Object -ExpandProperty 'TcpipNetbiosOptions' | Where-Object { ( $_ -ne $null ) -and ( $_ -ne 2 ) } | Measure-Object -Sum ).Sum )
            }
        }
    }

    #### OS Protection
    Node $AllNodes.Where{ $_.EnforceDeviceGuard }.NodeName
    {
        Registry NoDriveTypeAutoRun
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
            ValueName = 'Enabled'
            ValueType = 'Dword'
            ValueData = 1
        }
    }

    #### Untoggable items.
    Node $AllNodes.NodeName
    {
        #### GUI
        # Force enable UAC. UAC prompts for credentials rather than consent. (Anti-Rubber Ducky)
        Registry ConsentPromptBehaviorAdmin
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            ValueName = 'ConsentPromptBehaviorAdmin'
            ValueType = 'Dword'
            ValueData = 1
        }
        Registry ConsentPromptBehaviorUser
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            ValueName = 'ConsentPromptBehaviorUser'
            ValueType = 'Dword'
            ValueData = 1
        }

        # Disable AutoRun
        Registry NoDriveTypeAutoRun
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
            ValueName = 'NoDriveTypeAutoRun'
            ValueType = 'Dword'
            ValueData = 255
        }

        # Disable Cortana Start menu web search.
        Registry AllowCortana
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            ValueName = 'AllowCortana'
            ValueType = 'Dword'
            ValueData = 0
        }
        Registry DisableWebConnectedSearch
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            ValueName = 'ConnectedSearchUseWeb'
            ValueType = 'Dword'
            ValueData = 0
        }
        Registry DisableWebSearch
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            ValueName = 'DisableWebSearch'
            ValueType = 'Dword'
            ValueData = 1
        }

        # Enable Ctrl+Alt+Del
        Registry DisableCad
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            ValueName = 'DisableCad'
            ValueType = 'Dword'
            ValueData = 0
        }

        # Disable untrsuted fonts
        Registry MitigationOptions
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel'
            ValueName = 'MitigationOptions'
            ValueType = 'Qword'
            ValueData = 1000000000000
        }

        #### Network
        # Disable "Delivery Optimization" P2P Windows Updates
        Registry DownloadMode
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'
            ValueName = 'DownloadMode'
            ValueType = 'Dword'
            ValueData = 0
        }

        # Disable DCOM
        Registry EnableDCOM
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Ole'
            ValueName = 'EnableDCOM'
            ValueData = 'N'
        }
        Registry DCOMProtocols
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Rpc'
            ValueName = 'DCOM Protocols'
            ValueData = ''
        }

        # Force NTLMv2 only
        Registry LmCompatibilityLevel
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa'
            ValueName = 'LmCompatibilityLevel'
            ValueType = 'Dword'
            ValueData = 5
        }

        # Disable WDigest
        Registry UseLogonCredential
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
            ValueName = 'UseLogonCredential'
            ValueType = 'Dword'
            ValueData = 0
        }

        # Disable WPAD Service
        Service WinHttpAutoProxySvc
        {
            Ensure      = 'Present'
            Name        = 'dmwappushservice'
            StartupType = 'Disabled'
            State       = 'Stopped'
        }

        #### Privacy
        # Disable Telemetry
        Registry AllowTelemetry
        {
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            ValueName = 'AllowTelemetry'
            ValueType = 'Dword'
            ValueData = 0
        }

        # Disable Telemetry Service
        Service dmwappushservice
        {
            Ensure      = 'Present'
            Name        = 'dmwappushservice'
            StartupType = 'Disabled'
            State       = 'Stopped'
        }

        #### Per-User scripts. *SHOULD* be safe, assuming SYSTEM creates this directory first.
        File HardenPerUserDirectory
        {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = [System.Environment]::ExpandEnvironmentVariables( '%ALLUSERSPROFILE%\HardenWindows10' )
        }
        File HardenPerUserScript
        {
            DependsOn       = '[File]HardenPerUserDirectory'
            Ensure          = 'Present'
            Type            = 'File'
            DestinationPath = [System.Environment]::ExpandEnvironmentVariables( '%ALLUSERSPROFILE%\HardenWindows10\HardenWindows10PerUser.ps1' )
            Contents        = $HardenPerUser.toString()
        }
        Registry HardenPerUserScript
        {
            DependsOn = '[File]HardenPerUserScript'
            Ensure    = 'Present'
            Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            ValueName = 'HardenWindows10'
            ValueData = '{0} -Exec Bypass -NonI -NoP -Win Hidden -File "{1}"' -f @( ( Get-Command -Name powershell.exe ).Path, [System.Environment]::ExpandEnvironmentVariables( '%ALLUSERSPROFILE%\HardenWindows10\HardenWindows10PerUser.ps1' )  )
        }
    }
}
