#import "LTSongMenu.h"
#import "LTPlaylistStore.h"
#import "LTPlaylistPicker.h"
#import "LTPlayerController.h"
#import "LTModel.h"
#import "LTTransitionSettings.h"

#define kLTSongMenuSheetTag 9001

@interface LTSongMenu ()
@property (nonatomic, unsafe_unretained) UIViewController *presentingController;
@property (nonatomic, strong) LTTrack *pendingTrack;
@end

@implementation LTSongMenu

- (void)presentForTrack:(LTTrack *)track fromViewController:(UIViewController *)viewController {
    self.presentingController = viewController;
    self.pendingTrack = track;
    NSString *lastOption = [[LTPlaylistStore sharedStore] isTrackDownloaded:track] ? @"Remove Download" : @"Add to Download Queue";
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:track.title
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Add to Queue", @"Add to Playlist...", lastOption, nil];
    sheet.tag = kLTSongMenuSheetTag;
    [sheet showInView:viewController.view];
}

- (void)showPlaylistPickerForTrack:(LTTrack *)track {
    __unsafe_unretained LTSongMenu *weakSelf = self;
    [LTPlaylistPicker presentFromViewController:self.presentingController
                                     panelTitle:track.title
                                      onPicked:^(LTLocalPlaylist *playlist) {
        // Use the captured track, not self.pendingTrack: the picker is presented
        // asynchronously, and pendingTrack can be replaced while it is up.
        [LTPlaylistStore addTrack:track
                       toPlaylist:playlist
                    confirmingFrom:weakSelf.presentingController
                       completion:^(BOOL added) {
            if (added) [weakSelf showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
            weakSelf.pendingTrack = nil;
        }];
    } onCreateNew:^(NSString *name) {
        LTLocalPlaylist *playlist = [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
        // A playlist that was just created is empty, so nothing can duplicate.
        if (playlist) {
            [LTPlaylistStore addTrack:track toPlaylist:playlist confirmingFrom:nil completion:nil];
            [weakSelf showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
        }
        weakSelf.pendingTrack = nil;
    }];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag != kLTSongMenuSheetTag) return;
    if (buttonIndex == 0) {
        [[LTPlayerController sharedController] enqueueTracks:@[self.pendingTrack]];
        [self showToast:@"Added to queue"];
        self.pendingTrack = nil;
    } else if (buttonIndex == 1) {
        [self showPlaylistPickerForTrack:self.pendingTrack];
    } else if (buttonIndex == 2) {
        LTTrack *track = self.pendingTrack;
        self.pendingTrack = nil;
        if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
            [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[track]];
            [self showToast:@"Removed download"];
        } else {
            [[LTPlaylistStore sharedStore] enqueueDownloads:@[track]];
            [self showToast:@"Added to download queue"];
        }
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 200 && buttonIndex == 1) {
        NSString *name = [[alertView textFieldAtIndex:0] text];
        LTLocalPlaylist *playlist = [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
        if (playlist && self.pendingTrack) {
            [[LTPlaylistStore sharedStore] addTrack:self.pendingTrack toPlaylist:playlist];
            [self showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
        }
    }
    self.pendingTrack = nil;
}

- (void)showToast:(NSString *)text {
    UIViewController *vc = self.presentingController;
    if (!vc) return;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 220, 36)];
    label.center = CGPointMake(vc.view.bounds.size.width / 2.0f, vc.view.bounds.size.height - 80);
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75f];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:13];
    label.layer.cornerRadius = 6.0f;
    label.clipsToBounds = YES;
    label.text = text;
    [vc.view addSubview:label];
    [LTTransitionSettings animateWithDuration:1.4 delay:1.0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ label.alpha = 0.0f; }
                     completion:^(BOOL finished) { [label removeFromSuperview]; }];
}

@end
