#import "LTListenBrainzAuthViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "LTListenBrainzScrobbler.h"
#import "LTTheme.h"
#import "LTLog.h"
#import "qrcodegen/qrcodegen.h"

@interface LTListenBrainzAuthViewController ()
@property (nonatomic, strong) NSURL *authURL;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) UIImageView *qrView;
@end

@implementation LTListenBrainzAuthViewController

- (instancetype)initWithAuthURL:(NSURL *)url token:(NSString *)token {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _authURL = url;
        _token = token;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [LTTheme background];
    self.title = @"Authorize ListenBrainz";

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    BOOL shortScreen = (h < 520);            // 3GS / iPhone 4 (320x480)
    CGFloat top = shortScreen ? 8 : 20;
    CGFloat qrSize = shortScreen ? 200 : (h < 600 ? 210 : 240);

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, top, w-32, shortScreen ? 46 : 60)];
    label.text = @"Log in to ListenBrainz on another device, approve this request, then tap Done.";
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:shortScreen ? 12 : 14];
    label.textColor = [LTTheme text];
    label.backgroundColor = [UIColor clearColor];
    [self.view addSubview:label];

    CGFloat qrTop = top + (shortScreen ? 52 : 68);
    self.qrView = [[UIImageView alloc] initWithFrame:CGRectMake((w-qrSize)/2, qrTop, qrSize, qrSize)];
    self.qrView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.qrView];
    self.qrView.image = [self qrImageForString:self.authURL.absoluteString];

    CGFloat tvTop = qrTop + qrSize + 8;
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(16, tvTop, w-32, shortScreen ? 40 : 60)];
    tv.text = self.authURL.absoluteString;
    tv.font = [UIFont systemFontOfSize:11];
    tv.editable = NO;
    tv.backgroundColor = [UIColor clearColor];
    tv.textColor = [LTTheme secondaryText];
    [self.view addSubview:tv];

    CGFloat buttonH = shortScreen ? 38 : 44;
    CGFloat gap = shortScreen ? 6 : 12;
    CGFloat by = h - (3 * buttonH + 2 * gap) - (shortScreen ? 16 : 24);
    CGFloat minBy = tvTop + (shortScreen ? 40 : 60) + 8;
    if (by < minBy) by = minBy;

    UIButton *done = [UIButton buttonWithType:UIButtonTypeCustom];
    done.frame = CGRectMake(16, by, w-32, buttonH);
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.backgroundColor = [LTTheme fill];
    [done setTitleColor:[LTTheme text] forState:UIControlStateNormal];
    done.layer.cornerRadius = 6;
    [done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:done];

    UIButton *open = [UIButton buttonWithType:UIButtonTypeCustom];
    open.frame = CGRectMake(16, by + buttonH + gap, w-32, buttonH);
    [open setTitle:@"Open in Safari" forState:UIControlStateNormal];
    open.backgroundColor = [LTTheme fill];
    [open setTitleColor:[LTTheme text] forState:UIControlStateNormal];
    open.layer.cornerRadius = 6;
    [open addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:open];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake(16, by + 2*(buttonH + gap), w-32, buttonH);
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel setTitleColor:[LTTheme secondaryText] forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cancel];
}

- (UIImage *)qrImageForString:(NSString *)str {
    // CoreImage's CIQRCodeGenerator is iOS 8+, so we use the vendored Nayuki
    // encoder (pure C, MIT) instead. This works all the way back to iOS 4.
    if (!str.length) return nil;
    const char *text = [str UTF8String];
    if (!text) return nil;

    uint8_t tempBuffer[qrcodegen_BUFFER_LEN_FOR_VERSION(20)];
    uint8_t qrBuffer[qrcodegen_BUFFER_LEN_FOR_VERSION(20)];
    BOOL ok = qrcodegen_encodeText(text, tempBuffer, qrBuffer,
                                   qrcodegen_Ecc_MEDIUM, 1, 20,
                                   qrcodegen_Mask_AUTO, true);
    if (!ok) {
        LTLog(@"QR encode failed for %@", str);
        return nil;
    }

    int modules = qrcodegen_getSize(qrBuffer);
    const NSInteger quiet = 4;                 // required QR quiet zone
    NSInteger total = modules + quiet * 2;
    NSInteger scale = (NSInteger)ceilf(240.0f / (CGFloat)total);
    if (scale < 1) scale = 1;
    NSUInteger pixels = (NSUInteger)(total * scale);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, pixels, pixels, 8, pixels, cs, kCGImageAlphaNone);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;

    CGContextSetGrayFillColor(ctx, 1.0f, 1.0f);
    CGContextFillRect(ctx, CGRectMake(0, 0, pixels, pixels));
    CGContextSetGrayFillColor(ctx, 0.0f, 1.0f);
    for (int y = 0; y < modules; y++) {
        for (int x = 0; x < modules; x++) {
            if (qrcodegen_getModule(qrBuffer, x, y)) {
                CGRect r = CGRectMake((CGFloat)((x + quiet) * scale),
                                      (CGFloat)((y + quiet) * scale),
                                      (CGFloat)scale, (CGFloat)scale);
                CGContextFillRect(ctx, r);
            }
        }
    }

    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return img;
}

- (void)lt_dismissAnimated:(BOOL)animated {
    // dismissViewControllerAnimated:completion: is iOS 5+.
    if ([self respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        [self dismissViewControllerAnimated:animated completion:nil];
    } else {
        [self dismissModalViewControllerAnimated:animated];
    }
}

- (void)doneTapped {
    NSString *token = self.token;
    [self lt_dismissAnimated:YES];
    if (token.length) {
        [[LTListenBrainzScrobbler sharedScrobbler] fetchSessionForToken:token completion:^(BOOL ok, NSError *err) {
            NSString *title = ok ? @"Connected" : @"ListenBrainz";
            NSString *msg = ok ? @"Scrobbling to ListenBrainz is enabled." : (err.localizedDescription ?: @"Could not connect");
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:title
                                                        message:msg
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
            [a show];
        }];
    }
}

- (void)openTapped {
    if (self.authURL) [[UIApplication sharedApplication] openURL:self.authURL];
}

- (void)cancelTapped {
    [self lt_dismissAnimated:YES];
}

@end
