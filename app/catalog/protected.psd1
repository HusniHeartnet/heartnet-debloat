# Things Heartnet Debloat must NEVER change. tests\Test-Catalog.ps1 fails if any catalog
# target matches an entry here. Names are exact (case-insensitive). Task paths are prefixes.
@{
    Services = @(
        # security
        'WinDefend', 'WdNisSvc', 'WdBoot', 'WdFilter', 'Sense', 'SecurityHealthService', 'wscsvc', 'SgrmBroker',
        'webthreatdefsvc', 'webthreatdefusersvc', 'MpsSvc', 'BFE', 'mpssvc', 'EFS', 'KeyIso', 'SamSs', 'VaultSvc',
        # updates and servicing
        'wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'BITS', 'DoSvc', 'TrustedInstaller', 'CryptSvc', 'InstallService',
        # core system
        'RpcSs', 'RpcEptMapper', 'DcomLaunch', 'Winmgmt', 'EventLog', 'Schedule', 'ProfSvc', 'Power', 'PlugPlay',
        'AppXSvc', 'ClipSVC', 'StateRepository', 'TokenBroker', 'wlidsvc', 'Themes', 'UserManager', 'CoreMessagingRegistrar',
        # network (incl. VPN)
        'Dnscache', 'NlaSvc', 'nsi', 'Dhcp', 'WlanSvc', 'Netman', 'netprofm', 'LanmanWorkstation', 'WinHttpAutoProxySvc',
        'Tailscale', 'WireGuardManager', 'OpenVPNService', 'RasMan', 'IKEEXT',
        # audio, GPU, hotkeys
        'Audiosrv', 'AudioEndpointBuilder', 'NVDisplay.ContainerLocalSystem', 'AMD External Events Utility',
        'LenovoFnAndFunctionKeys', 'ArmouryCrateService',
        # virtualization (other apps depend on it)
        'vmcompute', 'vmms', 'HvHost', 'LxssManager', 'WslService',
        # opt-in only, never in the default catalog
        'WSearch'
    )
    Appx = @(
        'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI',
        'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.StartMenuExperienceHost', 'Microsoft.AAD.BrokerPlugin',
        'Microsoft.AccountsControl', 'Microsoft.XboxGameCallableUI', 'Microsoft.GamingServices', 'Microsoft.WindowsTerminal',
        'Microsoft.WindowsNotepad', 'Microsoft.Windows.Photos', 'Microsoft.Paint', 'Microsoft.ScreenSketch',
        'NVIDIACorp.NVIDIAControlPanel', 'RealtekSemiconductorCorp.RealtekAudioControl', 'AdvancedMicroDevicesInc-2.AMDRadeonSoftware',
        'E0469640.LenovoUtility', 'Claude'
    )
    TaskPaths = @(
        '\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\', '\Microsoft\Windows\Windows Defender\',
        '\Microsoft\Windows\WaaSMedic\', '\Microsoft\Windows\ExploitGuard\'
    )
    # Startup entries that are shown but never offered (system tray of Windows Security, driver helpers,
    # input method, VPN). Any startup exe under Windows\System32 or the DriverStore is protected too.
    StartupExe = @(
        'SecurityHealthSystray.exe', 'ctfmon.exe', 'RtkAudUService64.exe', 'RAVCpl64.exe', 'RAVBg64.exe', 'RtkNGUI64.exe',
        'igfxEM.exe', 'igfxHK.exe', 'igfxTray.exe', 'ETDCtrl.exe', 'SynTPEnh.exe', 'tailscale-ipn.exe', 'openvpn-gui.exe'
    )
    RegPathPrefixes = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender', 'HKLM:\SOFTWARE\Microsoft\Windows Defender',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    )
}
