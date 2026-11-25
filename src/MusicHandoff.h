// Source-shared protocol helpers for Muzika, Sixify and Tubie. Keep copies identical.
// Foundation-only and compatible with the legacy iOS SDK; no NSURLComponents dependency.
#import <Foundation/Foundation.h>
#include <math.h>

static inline NSString *MHNormalize(NSString *text)
{
    NSString *folded = [[(text ?: @"") stringByFoldingWithOptions:NSDiacriticInsensitiveSearch
        locale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]] lowercaseString];
    NSArray *parts = [folded componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *word in parts) if (word.length) [words addObject:word];
    return [words componentsJoinedByString:@" "];
}

static inline BOOL MHContains(NSString *text, NSString *phrase)
{
    if (!phrase.length) return NO;
    return [[NSString stringWithFormat:@" %@ ", text] rangeOfString:[NSString stringWithFormat:@" %@ ", phrase]].location != NSNotFound;
}

static inline BOOL MHMatches(NSString *title, NSString *artist, double seconds,
                            NSString *candidateTitle, NSString *candidateArtist, double candidateSeconds,
                            BOOL video)
{
    NSString *t = MHNormalize(title), *a = MHNormalize(artist);
    NSString *ct = MHNormalize(candidateTitle), *ca = MHNormalize(candidateArtist);
    if (t.length < 2 || a.length < 2 || !MHContains(ct, t)) return NO;
    if (!MHContains(ca, a) && !(video && MHContains(ct, a))) return NO;
    NSString *wanted = [NSString stringWithFormat:@"%@ %@", t, a];
    for (NSString *variant in @[@"cover", @"karaoke", @"instrumental", @"live", @"remix", @"sped", @"slowed"]) {
        if (MHContains(ct, variant) && !MHContains(wanted, variant)) return NO;
    }
    if (seconds > 0 && candidateSeconds > 0 && fabs(seconds - candidateSeconds) > MAX(8.0, seconds * 0.08)) return NO;
    return YES;
}

static inline BOOL MHValidID(NSString *value, NSUInteger length, NSString *allowed)
{
    return value.length == length && [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:allowed] invertedSet]].location == NSNotFound;
}

static inline NSString *MHYouTubeID(NSString *link)
{
    NSURL *url = [NSURL URLWithString:link ?: @""];
    NSString *host = [url.host lowercaseString], *video = nil;
    if (!host.length) return nil;
    if ([host isEqualToString:@"youtu.be"]) video = [url.path lastPathComponent];
    else if ([@[@"youtube.com", @"www.youtube.com", @"m.youtube.com", @"music.youtube.com"] containsObject:host]) {
        NSArray *parts = [url.path componentsSeparatedByString:@"/"];
        if (parts.count == 3 && [@[@"shorts", @"embed", @"live"] containsObject:[parts objectAtIndex:1]]) video = [parts objectAtIndex:2];
        else if ([url.path isEqualToString:@"/watch"]) {
            for (NSString *pair in [url.query componentsSeparatedByString:@"&"]) {
                if ([pair hasPrefix:@"v="]) video = [[pair substringFromIndex:2] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            }
        }
    }
    return MHValidID(video, 11, @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-") ? video : nil;
}

static inline NSString *MHSpotifyURI(NSString *link)
{
    NSString *identifier = nil;
    if ([link hasPrefix:@"spotify:track:"]) identifier = [link substringFromIndex:14];
    else {
        NSURL *url = [NSURL URLWithString:link ?: @""];
        if ([[url.host lowercaseString] isEqualToString:@"open.spotify.com"]) {
            NSMutableArray *parts = [NSMutableArray array];
            for (NSString *part in [url.path componentsSeparatedByString:@"/"]) if (part.length) [parts addObject:part];
            if (parts.count && [[parts objectAtIndex:0] hasPrefix:@"intl-"]) [parts removeObjectAtIndex:0];
            if (parts.count == 2 && [[parts objectAtIndex:0] isEqualToString:@"track"]) identifier = [parts objectAtIndex:1];
        }
    }
    return MHValidID(identifier, 22, @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") ? [@"spotify:track:" stringByAppendingString:identifier] : nil;
}

static inline double MHDuration(NSString *value)
{
    double seconds = [value doubleValue];
    return isfinite(seconds) ? MIN(86400.0, MAX(0.0, seconds)) : 0;
}
