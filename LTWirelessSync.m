#import "LTWirelessSync.h"
#import "LTSyncServer.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"

static NSMutableArray *LTActiveSyncs;

@implementation LTWirelessSync {
    LTSyncServer *_server;
    UIAlertView *_waitingAlert;
}

+ (void)beginFromViewController:(UIViewController *)presenter {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ LTActiveSyncs = [NSMutableArray array]; });
    if (LTActiveSyncs.count) return; // already syncing
    LTWirelessSync *sync = [[LTWirelessSync alloc] init];
    [LTActiveSyncs addObject:sync]; // keeps the instance alive while running
    [sync runFromViewController:presenter];
}

- (void)runFromViewController:(UIViewController *)presenter {
    _server = [[LTSyncServer alloc] init];

    __weak LTWirelessSync *weakSelf = self;
    __block NSInteger lastMergedCount = -1;

    _server.requestHandler = ^NSData *(NSString *method, NSString *path, NSData *body, NSInteger *status) {
        LTPlaylistStore *store = [LTPlaylistStore sharedStore];
        if ([method isEqualToString:@"GET"] && [path hasPrefix:@"/api/playlists"]) {
            NSError *err = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:[store syncArrayRepresentation] options:0 error:&err];
            if (!json) { *status = 500; return nil; }
            *status = 200;
            return json;
        }
        if ([method isEqualToString:@"POST"] && [path hasPrefix:@"/api/playlists"]) {
            NSError *err = nil;
            NSArray *incoming = [NSJSONSerialization JSONObjectWithData:body options:0 error:&err];
            if (![incoming isKindOfClass:[NSArray class]]) { *status = 400; return nil; }
            NSInteger merged = [store mergeSyncArray:incoming];
            lastMergedCount = merged;
            NSDictionary *result = @{@"ok": @YES, @"merged": @(merged), @"playlists": [store syncArrayRepresentation]};
            NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:&err];
            *status = 200;
            return json ?: nil;
        }
        *status = 404;
        return nil;
    };

    _server.onConnectionFinished = ^(NSString *method, NSString *path) {
        if ([method isEqualToString:@"POST"] && [path hasPrefix:@"/api/playlists"] && lastMergedCount >= 0) {
            NSInteger merged = lastMergedCount;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishWithMergedCount:merged];
            });
        }
    };

    NSError *error = nil;
    if (![_server start:&error]) {
        [self finish];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Sync Failed"
                                                        message:error.localizedDescription ?: @"Could not start sync."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }

    _waitingAlert = [[UIAlertView alloc] initWithTitle:@"Waiting for Desktop…"
                                               message:@"Open audioNINJA on your computer and press Sync with Mobile."
                                              delegate:self
                                     cancelButtonTitle:@"Cancel"
                                     otherButtonTitles:nil];
    [_waitingAlert show];
}

- (void)finishWithMergedCount:(NSInteger)merged {
    NSString *title = merged == 1 ? @"1 playlist synced" : [NSString stringWithFormat:@"%ld playlists synced", (long)merged];
    NSString *message = @"All playlists from both devices are now on both devices.";
    [self finish];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)finish {
    [_waitingAlert dismissWithClickedButtonIndex:-1 animated:NO];
    _waitingAlert = nil;
    [_server stop];
    _server = nil;
    [LTActiveSyncs removeObject:self];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 0) [self finish]; // Cancel while waiting
}

@end
