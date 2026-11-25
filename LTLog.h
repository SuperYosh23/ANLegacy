#import <Foundation/Foundation.h>

// Writes one line to the app log (/tmp/legacymusic.log) and the system log.
// Implemented in LTLog.m.
//
// This is a real out-of-line function rather than a static inline: it is called
// from ~150 sites, many of them on gesture and timer paths, and it holds a file
// handle open. A static inline would duplicate that handle per translation unit.
// See LTLog.m for the cost notes and the LTLogDisabled kill switch.
void LTLog(NSString *format, ...);
