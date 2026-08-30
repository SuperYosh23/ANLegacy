#import "LTWebExporter.h"
#import "LTPlaylistStore.h"
#import "LTModel.h"
#import "LTYouTubeClient.h"
#import "LTLog.h"

#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *const kWebDataMarker = @"<!--WEB_DATA-->";

@implementation LTWebExporter

+ (instancetype)sharedExporter {
    static LTWebExporter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

#pragma mark - Public async API

- (void)exportWithSelectedPlaylists:(NSArray *)playlistIdentifiers
                         completion:(void (^)(NSString *, NSError *))completion {
    NSArray *selected = playlistIdentifiers ?: @[];
    __weak LTWebExporter *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        LTWebExporter *strongSelf = weakSelf;
        NSError *error = nil;
        NSString *outDir = [strongSelf buildExportWithSelected:selected error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(outDir, error);
        });
    });
}

#pragma mark - Art

- (NSString *)md5HexOfString:(NSString *)string {
    if (!string.length) return @"";
    const char *cStr = [string UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:(CC_MD5_DIGEST_LENGTH * 2)];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

- (NSString *)cachedArtFileForURL:(NSString *)url {
    if (!url.length) return nil;
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSString *path = [[store artDirectory]
        stringByAppendingPathComponent:[[self md5HexOfString:url] stringByAppendingString:@".jpg"]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    return nil;
}

// Fetches artwork from the network (background-thread only) and writes a JPEG
// into the export art directory. Returns the destination file path, or nil.
- (NSString *)fetchArtIntoDirectory:(NSString *)artDir fromURL:(NSString *)urlString counter:(NSInteger)counter {
    if (!urlString.length) return nil;
    NSString *resolved = [[LTYouTubeClient sharedClient] highResThumbnailURL:urlString];
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:resolved]
                                         options:NSDataReadingUncached
                                           error:nil];
    if (!data.length) return nil;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return nil;
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.85);
    if (!jpeg) return nil;
    NSString *name = [NSString stringWithFormat:@"art%ld.jpg", (long)counter];
    NSString *path = [artDir stringByAppendingPathComponent:name];
    if ([jpeg writeToFile:path atomically:YES]) return name;
    return nil;
}

- (void)writeBlankArtTo:(NSString *)path {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(96, 96), NO, 1.0);
    [[UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0] setFill];
    UIRectFill(CGRectMake(0, 0, 96, 96));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *data = UIImageJPEGRepresentation(img, 0.85);
    [data writeToFile:path atomically:YES];
}

#pragma mark - Build (background thread)

- (NSString *)buildExportWithSelected:(NSArray *)selectedIdentifiers error:(NSError **)error {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSBundle *bundle = [NSBundle mainBundle];

    NSString *templatePath = [bundle pathForResource:@"web_template" ofType:@"html"];
    if (!templatePath || ![fm fileExistsAtPath:templatePath]) {
        if (error) *error = [NSError errorWithDomain:@"LTWebExporter" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Web template missing from app bundle."}];
        return nil;
    }
    NSString *template = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:nil];

    NSString *outDir = [[store baseDirectory] stringByAppendingPathComponent:@"web-export"];
    if ([fm fileExistsAtPath:outDir]) [fm removeItemAtPath:outDir error:nil];
    if (![fm createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    NSString *audioDir = [outDir stringByAppendingPathComponent:@"audio"];
    NSString *artDir = [outDir stringByAppendingPathComponent:@"art"];
    [fm createDirectoryAtPath:audioDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:artDir withIntermediateDirectories:YES attributes:nil error:nil];
    [self writeBlankArtTo:[artDir stringByAppendingPathComponent:@"blank.jpg"]];

    NSMutableDictionary *artMap = [NSMutableDictionary dictionary]; // thumbnailURL -> art filename
    NSInteger artCounter = 0;
    NSMutableArray *playlistDicts = [NSMutableArray array];
    NSInteger totalTracks = 0;
    NSInteger fetchedArt = 0;

    for (LTLocalPlaylist *playlist in store.playlists) {
        // Only export playlists the user selected.
        if (selectedIdentifiers.count &&
            ![selectedIdentifiers containsObject:playlist.identifier.length ? playlist.identifier : [NSNull null]]) {
            continue;
        }

        NSMutableArray *trackDicts = [NSMutableArray array];
        BOOL firstDownloadedArtAssigned = NO;
        NSString *fallbackArt = nil;

        for (LTTrack *track in playlist.tracks) {
            NSString *audioPath = [store existingLocalFilePathForVideoId:track.videoId];
            if (!audioPath.length) continue;

            NSString *ext = [audioPath pathExtension].length ? [audioPath pathExtension] : @"m4a";
            NSString *audioName = [NSString stringWithFormat:@"%@.%@", track.videoId, ext];
            [fm copyItemAtPath:audioPath
                        toPath:[audioDir stringByAppendingPathComponent:audioName]
                         error:nil];
            totalTracks += 1;

            // Artwork: reuse shared art, else cached file, else fetch from network.
            NSString *artFile = nil;
            NSString *mapKey = track.thumbnailURL ?: @"";
            if (mapKey.length && artMap[mapKey]) {
                artFile = artMap[mapKey];
            } else {
                NSString *cached = [self cachedArtFileForURL:track.thumbnailURL];
                if (cached) {
                    artCounter += 1;
                    NSString *srcExt = [cached pathExtension].length ? [cached pathExtension] : @"jpg";
                    artFile = [NSString stringWithFormat:@"art%ld.%@", (long)artCounter, srcExt];
                    [fm copyItemAtPath:cached toPath:[artDir stringByAppendingPathComponent:artFile] error:nil];
                    if (mapKey.length) artMap[mapKey] = artFile;
                } else if (track.thumbnailURL.length) {
                    artCounter += 1;
                    NSString *name = [self fetchArtIntoDirectory:artDir fromURL:track.thumbnailURL counter:artCounter];
                    if (name) {
                        artFile = name;
                        if (mapKey.length) artMap[mapKey] = name;
                        fetchedArt += 1;
                    }
                }
            }
            if (!firstDownloadedArtAssigned && artFile) {
                firstDownloadedArtAssigned = YES;
                fallbackArt = artFile;
            }

            NSMutableDictionary *td = [NSMutableDictionary dictionary];
            if (track.title.length) td[@"title"] = track.title;
            if (track.artist.length) td[@"artist"] = track.artist;
            if (track.album.length) td[@"album"] = track.album;
            td[@"file"] = [@"audio/" stringByAppendingString:audioName];
            if (artFile) td[@"art"] = [@"art/" stringByAppendingString:artFile];
            if (track.duration > 0) td[@"duration"] = @(track.duration);
            [trackDicts addObject:td];
        }

        NSString *coverRef = nil;
        if (playlist.coverPath.length && [fm fileExistsAtPath:playlist.coverPath]) {
            artCounter += 1;
            NSString *srcExt = [playlist.coverPath pathExtension].length ? [playlist.coverPath pathExtension] : @"jpg";
            NSString *coverName = [NSString stringWithFormat:@"art%ld.%@", (long)artCounter, srcExt];
            [fm copyItemAtPath:playlist.coverPath toPath:[artDir stringByAppendingPathComponent:coverName] error:nil];
            coverRef = [@"art/" stringByAppendingString:coverName];
        } else if (fallbackArt) {
            coverRef = [@"art/" stringByAppendingString:fallbackArt];
        }

        NSMutableDictionary *pd = [NSMutableDictionary dictionary];
        pd[@"name"] = playlist.name.length ? playlist.name : @"Untitled";
        if (coverRef) pd[@"cover"] = coverRef;
        pd[@"tracks"] = trackDicts;
        if (trackDicts.count) [playlistDicts addObject:pd];
    }

    NSDictionary *root = @{ @"playlists": playlistDicts };
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
    if (!json) return nil;
    NSString *dataJS = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *script = [NSString stringWithFormat:@"<script>window.WEB_DATA = %@;</script>", dataJS];

    if ([template rangeOfString:kWebDataMarker].location == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"LTWebExporter" code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"Template marker not found."}];
        return nil;
    }
    NSString *outputHTML = [template stringByReplacingOccurrencesOfString:kWebDataMarker withString:script];
    NSString *outPath = [outDir stringByAppendingPathComponent:@"index.html"];
    if (![outputHTML writeToFile:outPath atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;

    LTLog(@"WEBEXPORT created AN Mini at %@ playlists=%d tracks=%d artFetched=%d",
          outDir, (int)playlistDicts.count, (int)totalTracks, (int)fetchedArt);
    return outDir;
}

@end
