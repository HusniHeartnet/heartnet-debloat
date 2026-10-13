# Heartnet Debloat - item catalog (data only, no code).
#
# Each item:
#   Id       unique id; text comes from lang files: <Id>.title / <Id>.desc / <Id>.tradeoff
#   Cat      category id (see lang: cat.<Cat>)
#   Risk     Low (checked by default) | Optional | Experimental
#   Requires optional list of conditions (see Test-HDRequirement in core\Scan.ps1)
#   Guards   optional list of safety checks (see Get-HDGuard in core\Scan.ps1)
#   Targets  what the item changes. Names are always EXACT (no regex, no wildcards).
#     @{ T='Appx';     Name='<package name>' }                         remove for current user
#     @{ T='Service';  Name='<service name>' }                         set to Disabled
#     @{ T='Task';     Path='\Folder\'; Name='<task>' }                disable (Name omitted = every task in folder + subfolders)
#     @{ T='Task';     Name='<task>' }                                 disable, task may live in any folder
#     @{ T='Reg';      Path='HKCU:\...'; Name='<value>'; Value=0; Kind='DWord' }
#     @{ T='Win32App'; DisplayName='<exact Add/Remove Programs name>' } uninstall with official uninstaller
#     @{ T='BtRadio' }                                                 the Bluetooth radio device(s) only
#
# Targets of type Appx/Service/Task/Win32App/BtRadio are "anchors": an item that has anchors
# is only shown as present when at least one anchor exists on the PC.

@{
    Items = @(

        # ------------------------------------------------------------------ apps (Appx, current user)
        @{ Id = 'app.clipchamp';     Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Clipchamp.Clipchamp' }) }
        @{ Id = 'app.bingnews';      Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.BingNews' }) }
        @{ Id = 'app.bingweather';   Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.BingWeather' }) }
        @{ Id = 'app.bingsearch';    Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.BingSearch' }) }
        @{ Id = 'app.gethelp';       Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.GetHelp' }) }
        @{ Id = 'app.officehub';     Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.MicrosoftOfficeHub' }) }
        @{ Id = 'app.solitaire';     Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.MicrosoftSolitaireCollection' }) }
        @{ Id = 'app.people';        Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.People' }) }
        @{ Id = 'app.powerautomate'; Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.PowerAutomateDesktop' }) }
        @{ Id = 'app.devhome';       Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.Windows.DevHome' }) }
        @{ Id = 'app.feedbackhub';   Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.WindowsFeedbackHub' }) }
        @{ Id = 'app.maps';          Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.WindowsMaps' }) }
        @{ Id = 'app.zunevideo';     Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.ZuneVideo' }) }
        @{ Id = 'app.mixedreality';  Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.MixedReality.Portal' }) }
        @{ Id = 'app.widgets';       Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'MicrosoftWindows.Client.WebExperience' }) }
        @{ Id = 'app.dropboxoem';    Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'C27EB4BA.DropboxOEM' }) }
        @{ Id = 'app.mailcalendar';  Cat = 'apps'; Risk = 'Low'; Targets = @(@{ T = 'Appx'; Name = 'microsoft.windowscommunicationsapps' }) }

        @{ Id = 'app.copilot';       Cat = 'apps'; Risk = 'Optional'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.Copilot' }) }
        @{ Id = 'app.outlooknew';    Cat = 'apps'; Risk = 'Optional'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.OutlookForWindows' }) }
        @{ Id = 'app.todo';          Cat = 'apps'; Risk = 'Optional'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.Todos' }) }
        @{ Id = 'app.family';        Cat = 'apps'; Risk = 'Optional'; Targets = @(@{ T = 'Appx'; Name = 'MicrosoftCorporationII.MicrosoftFamily' }) }
        @{ Id = 'app.quickassist';   Cat = 'apps'; Risk = 'Optional'; Targets = @(@{ T = 'Appx'; Name = 'MicrosoftCorporationII.QuickAssist' }) }
        @{ Id = 'app.teams';         Cat = 'apps'; Risk = 'Optional'; Targets = @(
                @{ T = 'Appx'; Name = 'MicrosoftTeams' }
                @{ T = 'Appx'; Name = 'MSTeams' }) }
        @{ Id = 'app.whiteboard';    Cat = 'apps'; Risk = 'Optional'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.Whiteboard' }) }
        @{ Id = 'app.journal';       Cat = 'apps'; Risk = 'Optional'; Targets = @(@{ T = 'Appx'; Name = 'Microsoft.MicrosoftJournal' }) }
        @{ Id = 'app.phonelink';     Cat = 'apps'; Risk = 'Optional'; Targets = @(
                @{ T = 'Appx'; Name = 'Microsoft.YourPhone' }
                @{ T = 'Appx'; Name = 'MicrosoftWindows.CrossDevice' }) }

        # ------------------------------------------------------------------ ads & suggestions (HKCU)
        @{ Id = 'ads.cdm'; Cat = 'ads'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled';       Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled';     Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled';               Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled';          Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled';       Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled';  Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338387Enabled';  Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled';  Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled';  Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled';  Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled';  Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled';  Value = 0; Kind = 'DWord' }) }
        @{ Id = 'ads.start'; Cat = 'ads'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations';     Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Value = 0; Kind = 'DWord' }) }
        @{ Id = 'ads.tailored'; Cat = 'ads'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';               Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled';                   Value = 0; Kind = 'DWord' }) }
        @{ Id = 'ads.search'; Cat = 'ads'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDynamicSearchBoxEnabled';   Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsMSACloudSearchEnabled';     Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsAADCloudSearchEnabled';     Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer';             Name = 'DisableSearchBoxSuggestions'; Value = 1; Kind = 'DWord' }) }
        @{ Id = 'ads.softlanding'; Cat = 'ads'; Risk = 'Low'; Targets = @(@{ T = 'Task'; Path = '\SoftLanding\' }) }

        # ------------------------------------------------------------------ OEM: Lenovo (verified on LOQ 83JC)
        @{ Id = 'oem.lenovo.udc'; Cat = 'oem'; Risk = 'Low'; Requires = @('Vendor:LENOVO'); Targets = @(
                @{ T = 'Service'; Name = 'UDCService' }
                @{ T = 'Task';    Path = '\Lenovo\UDC\' }) }
        @{ Id = 'oem.lenovo.vantage'; Cat = 'oem'; Risk = 'Optional'; Requires = @('Vendor:LENOVO'); Targets = @(
                @{ T = 'Appx';     Name = 'E046963F.LenovoCompanion' }
                @{ T = 'Win32App'; DisplayName = 'Lenovo Vantage Service' }
                @{ T = 'Service';  Name = 'LenovoVantageService' }
                @{ T = 'Task';     Path = '\Lenovo\Vantage\' }) }
        @{ Id = 'oem.lenovo.imcontroller'; Cat = 'oem'; Risk = 'Experimental'; Requires = @('Vendor:LENOVO'); Targets = @(
                @{ T = 'Service'; Name = 'ImControllerService' }
                @{ T = 'Task';    Path = '\Lenovo\ImController\' }) }
        @{ Id = 'oem.lenovo.lenovonow';     Cat = 'oem'; Risk = 'Optional'; Requires = @('Vendor:LENOVO'); Targets = @(@{ T = 'Win32App'; DisplayName = 'Lenovo Now' }) }
        @{ Id = 'oem.lenovo.avatarmaster';  Cat = 'oem'; Risk = 'Optional'; Requires = @('Vendor:LENOVO'); Targets = @(@{ T = 'Win32App'; DisplayName = 'Lenovo AvatarMaster' }) }
        @{ Id = 'oem.lenovo.legionarena';   Cat = 'oem'; Risk = 'Optional'; Requires = @('Vendor:LENOVO'); Targets = @(@{ T = 'Win32App'; DisplayName = 'Legion Arena' }) }

        # ------------------------------------------------------------------ audio enhancer
        @{ Id = 'oem.nahimic'; Cat = 'oem'; Risk = 'Optional'; Targets = @(
                @{ T = 'Service'; Name = 'NahimicService' }
                @{ T = 'Task';    Name = 'NahimicTask32' }
                @{ T = 'Task';    Name = 'NahimicTask64' }
                @{ T = 'Appx';    Name = 'A-Volute.Nahimic' }) }

        # ------------------------------------------------------------------ Xbox
        @{ Id = 'xbox.bgrecord'; Cat = 'xbox'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'HistoricalCaptureEnabled'; Value = 0; Kind = 'DWord' }) }
        @{ Id = 'xbox.all'; Cat = 'xbox'; Risk = 'Optional'; Guards = @('XboxGames'); Targets = @(
                @{ T = 'Appx';    Name = 'Microsoft.GamingApp' }
                @{ T = 'Appx';    Name = 'Microsoft.XboxGamingOverlay' }
                @{ T = 'Appx';    Name = 'Microsoft.XboxGameOverlay' }
                @{ T = 'Appx';    Name = 'Microsoft.XboxSpeechToTextOverlay' }
                @{ T = 'Appx';    Name = 'Microsoft.Xbox.TCUI' }
                @{ T = 'Appx';    Name = 'Microsoft.XboxIdentityProvider' }
                @{ T = 'Service'; Name = 'XblAuthManager' }
                @{ T = 'Service'; Name = 'XblGameSave' }
                @{ T = 'Service'; Name = 'XboxNetApiSvc' }
                @{ T = 'Reg'; Path = 'HKCU:\System\GameConfigStore';                         Name = 'GameDVR_Enabled';            Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled';       Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\GameBar';                     Name = 'UseNexusForGameBarEnabled';  Value = 0; Kind = 'DWord' }) }
        @{ Id = 'xbox.gip'; Cat = 'xbox'; Risk = 'Optional'; Guards = @('XboxController'); Targets = @(@{ T = 'Service'; Name = 'XboxGipSvc' }) }

        # ------------------------------------------------------------------ telemetry & privacy
        @{ Id = 'tel.services'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Service'; Name = 'DiagTrack' }
                @{ T = 'Service'; Name = 'dmwappushservice' }) }
        @{ Id = 'tel.level'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry';                 Value = 1; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Value = 1; Kind = 'DWord' }) }
        @{ Id = 'tel.tasks'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Task'; Path = '\Microsoft\Windows\Application Experience\';               Name = 'MareBackup' }
                @{ T = 'Task'; Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' }
                @{ T = 'Task'; Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
                @{ T = 'Task'; Path = '\Microsoft\Windows\DiskDiagnostic\';                       Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
                @{ T = 'Task'; Path = '\Microsoft\Windows\Feedback\Siuf\';                        Name = 'DmClient' }
                @{ T = 'Task'; Path = '\Microsoft\Windows\Feedback\Siuf\';                        Name = 'DmClientOnScenarioDownload' }
                @{ T = 'Task'; Path = '\Microsoft\Windows\Windows Error Reporting\';              Name = 'QueueReporting' }
                @{ T = 'Task'; Path = '\Microsoft\Windows\Autochk\';                              Name = 'Proxy' }) }
        @{ Id = 'tel.wer'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Value = 1; Kind = 'DWord' }) }
        @{ Id = 'tel.input'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\InputPersonalization';                  Name = 'RestrictImplicitTextCollection'; Value = 1; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\InputPersonalization';                  Name = 'RestrictImplicitInkCollection';  Value = 1; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore'; Name = 'HarvestContacts';                Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Input\TIPC';                            Name = 'Enabled';                        Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Personalization\Settings';              Name = 'AcceptedPrivacyPolicy';          Value = 0; Kind = 'DWord' }) }
        @{ Id = 'tel.activity'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities';  Value = 0; Kind = 'DWord' }) }
        @{ Id = 'tel.feedback'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Value = 0; Kind = 'DWord' }) }
        @{ Id = 'tel.speech'; Cat = 'privacy'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKCU:\Control Panel\International\User Profile';                     Name = 'HttpAcceptLanguageOptOut'; Value = 1; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name = 'HasAccepted';             Value = 0; Kind = 'DWord' }) }

        # ------------------------------------------------------------------ system & performance
        @{ Id = 'sys.deliveryopt'; Cat = 'system'; Risk = 'Low'; Targets = @(
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Value = 0; Kind = 'DWord' }) }
        @{ Id = 'sys.edgebg'; Cat = 'system'; Risk = 'Low'; Requires = @('EdgeInstalled'); Targets = @(
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled';   Value = 0; Kind = 'DWord' }
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'BackgroundModeEnabled'; Value = 0; Kind = 'DWord' }) }
        @{ Id = 'sys.mapsbroker'; Cat = 'system'; Risk = 'Low'; Targets = @(@{ T = 'Service'; Name = 'MapsBroker' }) }
        @{ Id = 'sys.spooler'; Cat = 'system'; Risk = 'Optional'; Guards = @('PhysicalPrinter'); Targets = @(@{ T = 'Service'; Name = 'Spooler' }) }
        @{ Id = 'sys.faststartup'; Cat = 'system'; Risk = 'Optional'; Requires = @('HibernateAvailable'); Targets = @(
                @{ T = 'Reg'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Value = 0; Kind = 'DWord' }) }
        @{ Id = 'sys.sysmain'; Cat = 'system'; Risk = 'Experimental'; Guards = @('SystemDiskHdd'); Targets = @(@{ T = 'Service'; Name = 'SysMain' }) }
        @{ Id = 'sys.bgapps'; Cat = 'system'; Risk = 'Experimental'; Targets = @(
                @{ T = 'Reg'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; Name = 'LetAppsRunInBackground'; Value = 2; Kind = 'DWord' }) }
        @{ Id = 'sys.bluetooth'; Cat = 'system'; Risk = 'Experimental'; Guards = @('BtPairedDevices'); Targets = @(
                @{ T = 'BtRadio' }
                @{ T = 'Service'; Name = 'bthserv' }
                @{ T = 'Service'; Name = 'BTAGService' }
                @{ T = 'Service'; Name = 'BthAvctpSvc' }
                @{ T = 'Reg'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\BluetoothUserService'; Name = 'Start'; Value = 4; Kind = 'DWord' }) }
    )
}
