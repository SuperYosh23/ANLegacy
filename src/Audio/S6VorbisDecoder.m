#import "S6VorbisDecoder.h"
#import "S6AudioFile.h"
#import "S6Common.h"

#define STB_VORBIS_HEADER_ONLY
#define STB_VORBIS_NO_STDIO
#include "stb_vorbis.c"

static const NSUInteger S6OggStart = 0xa7;            // Spotify's own packet ends here
static const NSUInteger S6GainOffset = 144;           // 4 little-endian floats: track gain, track peak, album gain, album peak

@interface S6VorbisDecoder ()
@property (nonatomic) int sampleRate;
@property (nonatomic) int channels;
@property (nonatomic) float trackGainDb;
@property (nonatomic) float trackPeak;
@property (nonatomic) uint64_t frame;
@property (nonatomic) BOOL atEnd;
@property (nonatomic) BOOL starved;
@end

@implementation S6VorbisDecoder {
    S6AudioFile *_file;
    stb_vorbis *_vorbis;
    NSUInteger _pos;              // the next byte to hand to the decoder
    NSUInteger _dataStart;        // after the Vorbis headers
    float **_outputs;             // the last decoded frame (owned by stb_vorbis)
    int _outSamples;
    int _outIndex;
}

- (instancetype)initWithFile:(S6AudioFile *)file
{
    if ((self = [super init])) {
        _file = file;
        _trackPeak = 1;
    }
    return self;
}

- (void)dealloc
{
    if (_vorbis) stb_vorbis_close(_vorbis);
}

static float S6LEFloat(const uint8_t *p)
{
    uint32_t v = (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    float f;
    memcpy(&f, &v, 4);
    return f;
}

- (BOOL)open:(NSError **)error
{
    NSUInteger want = S6OggStart + 8192;
    for (int round = 0; round < 40; round++) {
        [_file waitForBytes:want timeout:15];
        NSUInteger avail = _file.available;
        if (_file.error && avail < want && _file.finished) break;
        if (avail <= S6OggStart) {
            if (_file.finished) break;
            continue;
        }
        const uint8_t *bytes = _file.bytes;
        if (avail >= S6GainOffset + 16) {
            float gain = S6LEFloat(bytes + S6GainOffset);
            float peak = S6LEFloat(bytes + S6GainOffset + 4);
            if (isfinite(gain) && fabsf(gain) < 60) self.trackGainDb = gain;
            if (isfinite(peak) && peak > 0 && peak < 10) self.trackPeak = peak;
        }
        int used = 0, err = 0;
        stb_vorbis *v = stb_vorbis_open_pushdata(bytes + S6OggStart, (int)(avail - S6OggStart), &used, &err, NULL);
        if (v) {
            _vorbis = v;
            stb_vorbis_info info = stb_vorbis_get_info(v);
            self.sampleRate = (int)info.sample_rate;
            self.channels = info.channels;
            _pos = S6OggStart + (NSUInteger)used;
            _dataStart = _pos;
            return YES;
        }
        if (err != VORBIS_need_more_data || _file.finished) {
            if (error) *error = S6MakeError(S6ErrorPlayback, [NSString stringWithFormat:L(@"The song could not be decoded (Vorbis error %d)."), err]);
            return NO;
        }
        want = avail + 32768;
    }
    if (error) *error = _file.error ?: S6MakeError(S6ErrorPlayback, L(@"The song did not download."));
    return NO;
}

static inline int16_t S6Clamp16(float v)
{
    if (v > 32767.f) return 32767;
    if (v < -32768.f) return -32768;
    return (int16_t)v;
}

- (NSInteger)readFrames:(int16_t *)out max:(NSUInteger)maxFrames gain:(float)gain
{
    if (!_vorbis) return -1;
    self.starved = NO;
    NSUInteger produced = 0;
    float scale = 32767.f * gain;
    while (produced < maxFrames) {
        if (_outIndex < _outSamples) {
            NSUInteger n = MIN((NSUInteger)(_outSamples - _outIndex), maxFrames - produced);
            float *l = _outputs[0] + _outIndex;
            float *r = _outputs[self.channels > 1 ? 1 : 0] + _outIndex;
            int16_t *o = out + produced * 2;
            for (NSUInteger i = 0; i < n; i++) {
                o[2 * i] = S6Clamp16(l[i] * scale);
                o[2 * i + 1] = S6Clamp16(r[i] * scale);
            }
            _outIndex += (int)n;
            produced += n;
            self.frame += n;
            continue;
        }
        NSUInteger avail = _file.available;
        int channels = 0, samples = 0;
        float **outputs = NULL;
        int used = avail > _pos ? stb_vorbis_decode_frame_pushdata(_vorbis, _file.bytes + _pos, (int)MIN(avail - _pos, (NSUInteger)INT_MAX), &channels, &outputs, &samples) : 0;
        if (used == 0 && samples == 0) {
            if (_file.finished && avail >= _file.length) {
                self.atEnd = YES;
                break;
            }
            if (_file.finished && _file.error) return produced ? (NSInteger)produced : -1;
            // the download is behind: wait a little for it, then report what there is
            if (![_file waitForBytes:MIN(avail + 16384, _file.length ?: avail + 16384) timeout:0.5]) {
                if (_file.available == avail) { self.starved = YES; break; }
            }
            continue;
        }
        _pos += (NSUInteger)used;
        if (samples > 0) {
            _outputs = outputs;
            _outSamples = samples;
            _outIndex = 0;
        }
    }
    return (NSInteger)produced;
}

- (BOOL)seekToFrame:(uint64_t)target
{
    if (!_vorbis) return NO;
    NSUInteger length = _file.length;
    if (!length || !self.totalFrames) return NO;
    double fraction = MIN(1.0, MAX(0.0, (double)target / (double)self.totalFrames));
    // a little before the spot: the frames up to it are decoded and dropped, so the position is exact
    double back = MIN(fraction, 2.0 * (self.sampleRate ?: 44100) / (double)self.totalFrames);
    NSUInteger byte = _dataStart + (NSUInteger)((fraction - back) * (double)(length - _dataStart));
    if (byte < _dataStart) byte = _dataStart;
    if (byte >= length) byte = length - 1;
    if (![_file waitForBytes:MIN(byte + 65536, length) timeout:20] && _file.available <= byte) return NO;
    stb_vorbis_flush_pushdata(_vorbis);
    _pos = byte;
    _outSamples = 0;
    _outIndex = 0;
    self.atEnd = NO;
    // decode until frames come out again, then find out where that is
    for (int i = 0; i < 200; i++) {
        NSUInteger avail = _file.available;
        int channels = 0, samples = 0;
        float **outputs = NULL;
        int used = avail > _pos ? stb_vorbis_decode_frame_pushdata(_vorbis, _file.bytes + _pos, (int)(avail - _pos), &channels, &outputs, &samples) : 0;
        if (used == 0 && samples == 0) {
            if (_file.finished) break;
            [_file waitForBytes:avail + 32768 timeout:5];
            continue;
        }
        _pos += (NSUInteger)used;
        if (samples > 0) {
            _outputs = outputs;
            _outSamples = samples;
            _outIndex = 0;
            int next = stb_vorbis_get_sample_offset(_vorbis);
            self.frame = next >= samples ? (uint64_t)(next - samples) : (uint64_t)(fraction * (double)self.totalFrames);
            break;
        }
    }
    // drop what lies before the target
    if (self.frame < target && target - self.frame < (uint64_t)(10 * (self.sampleRate ?: 44100))) {
        int16_t scratch[4096 * 2];
        while (self.frame < target) {
            NSUInteger want = (NSUInteger)MIN((uint64_t)4096, target - self.frame);
            NSInteger got = [self readFrames:scratch max:want gain:0];
            if (got <= 0) break;
        }
    }
    return YES;
}

@end
