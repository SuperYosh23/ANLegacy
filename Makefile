# No explicit SDK/deployment in TARGET so the per-arch values below apply.
# arm64 stays on the iOS 11.2 SDK: newer SDKs auto-link AVFAudio (iOS 14+) and
# other new symbols, which makes the app fail to launch on iOS 11-13.
# The notched/letterbox fix (bumping the Mach-O SDK field to 18.0 + adding a
# launch storyboard) is applied to the .ipa by make_modern_ipa.py instead.
# armv7 stays on the iOS 9.3 SDK for iOS 6-10.
TARGET = iphone:clang
ARCHS = armv7 arm64
SDKVERSION_arm64 = 11.2
SDKVERSION_armv7 = 9.3
TARGET_OS_DEPLOYMENT_VERSION_arm64 = 11.0
TARGET_OS_DEPLOYMENT_VERSION_armv7 = 6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LegacyMusic
# Capital R, and it must be this exact directory. Setting this replaces Theos'
# default resource dir rather than adding to it, so pointing it at a lowercase
# "resources" silently stopped every file in Resources/ from being bundled -
# including Resources/Info.plist, which is where the app's Info.plist comes
# from. That is what left Settings reporting a stale version number.
LegacyMusic_RESOURCE_DIRS = Resources
LegacyMusic_FILES = main.m \
	LTAppDelegate.m \
	LTModel.m \
	LTYouTubeClient.m \
	LTTabBarController.m \
	LTSplitContainerViewController.m \
	LTHomeViewController.m \
	LTSettingsViewController.m \
	LTSpotifyImportViewController.m \
	LTSpotifyConnectViewController.m \
	LTArtworkBackground.m \
	LTGraphics.m \
	LTHaptics.m \
	LTHapticStrengthViewController.m \
	LTLog.m \
	LTAppIcon.m \
	LTSleepTimer.m \
	LTLyricsOffsetViewController.m \
	LTLyricsPaperView.m \
	LTLyricsSettings.m \
	LTPlaylistPeekViewController.m \
	LTStationPeekViewController.m \
	LTPeekCoordinator.m \
	LTArtworkPeekViewController.m \
	LTLucideIcons.m \
	LTSearchViewController.m \
	LTTrackListViewController.m \
	LTArtistViewController.m \
	LTArtistSongsViewController.m \
	LTPlayerViewController.m \
	LTPlayerController.m \
	LTQueueViewController.m \
	LTPlaylistStore.m \
	LTListenBrainzScrobbler.m \
	LTListenBrainzAuthViewController.m \
	LTDownloadQueueViewController.m \
	LTPlaylistPicker.m \
	LTSongMenu.m \
	LTSyncServer.m \
	LTP2PSync.m \
	LTLocalPlaylistDetailViewController.m \
	LTSmartPlaylistDetailViewController.m \
	LTStationDetailViewController.m \
	LTSeedSearchViewController.m \
	LTMediaCell.m \
	LTTextUtils.m \
	LTTheme.m \
	LTThemedTableView.m \
	LTCardControls.m \
	LTCardNavBar.m \
	LTWebServer.m \
	LTWebAPI.m \
	LTWebShellViewController.m \
	LTThemePickerViewController.m \
	LTSafeArea.m \
	LTSimpleCell.m \
	LTHeaderView.m \
	LTCustomActionSheet.m \
	LTTransitionSettings.m \
	LTTransitionSpeedViewController.m \
	LTRecentsTileSizeViewController.m \
	LTOneHandedMode.m \
	LTOneHandedModeViewController.m \
	LTAppTabBar.m \
	LTWebExporter.m \
	LTPlaylistSelectViewController.m \
	LTLibraryViewController.m \
	LTLibrarySongsViewController.m \
	LTSpinnerView.m \
	LTStatsViewController.m \
	LTStatsDetailViewController.m \
	LTDebugMenuViewController.m \
	LTDebugSettings.m \
	LTiPodViewController.m
LegacyMusic_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore MediaPlayer WebKit CoreImage
LegacyMusic_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-objc-interface-ivars -Isrc -Isrc/Net -Isrc/Spotify -Isrc/Audio -Isrc/UI -Isrc/Util -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library
LegacyMusic_LDFLAGS = -Wl,-U,_memcpy -Wl,-U,__Unwind_Resume -lz

# Sixify (spotify-ios6) protocol sources — MIT licensed, see THIRD-PARTY-NOTICES.
LegacyMusic_FILES += $(wildcard src/*.m) \
                    $(wildcard src/Spotify/*.m) $(wildcard src/Spotify/*.c) \
                    $(wildcard src/Net/*.m) $(wildcard src/Net/*.c) \
                    $(wildcard src/Util/*.m) $(wildcard src/Util/*.c) \
                    $(wildcard src/Audio/*.m) $(wildcard src/Audio/*.c) \
                    vendor/mbedtls_glue.c vendor/s6_stb_vorbis.c vendor/qrcodegen/qrcodegen.c \
                    $(wildcard vendor/mbedtls/library/*.c)

# WebKit is weak-linked on purpose. The framework itself has existed since
# iOS 2 (it used to hold UIWebView), but WKWebView only arrived in iOS 8, so
# _OBJC_CLASS_$_WKWebView is undefined on iOS 6 and 7. Linking it strongly
# would leave that symbol undefined and the app would fail to launch - before
# main(), with no crash report to look at. The modern themes are gated to iOS 9+,
# so the class is only ever touched where it exists.
LegacyMusic_LDFLAGS += -weak_framework WebKit

include $(THEOS_MAKE_PATH)/application.mk
