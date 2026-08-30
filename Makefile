TARGET = iphone:clang:9.3:6.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LegacyMusic
LegacyMusic_FILES = main.m \
	LTAppDelegate.m \
	LTModel.m \
	LTYouTubeClient.m \
	LTTabBarController.m \
	LTHomeViewController.m \
	LTSettingsViewController.m \
	LTGraphics.m \
	LTSearchViewController.m \
	LTTrackListViewController.m \
	LTArtistViewController.m \
	LTPlayerViewController.m \
	LTPlayerController.m \
	LTQueueViewController.m \
	LTPlaylistStore.m \
	LTPlaylistPicker.m \
	LTSyncServer.m \
	LTWirelessSync.m \
	LTLocalPlaylistDetailViewController.m \
	LTMediaCell.m \
	LTHeaderView.m \
	LTCustomActionSheet.m \
	LTTransitionSettings.m \
	LTTransitionSpeedViewController.m \
	LTWebExporter.m \
	LTPlaylistSelectViewController.m \
	LTLibraryViewController.m \
	LTLibrarySongsViewController.m \
	LTSpinnerView.m
LegacyMusic_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore MediaPlayer
LegacyMusic_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-objc-interface-ivars
LegacyMusic_LDFLAGS =

include $(THEOS_MAKE_PATH)/application.mk
