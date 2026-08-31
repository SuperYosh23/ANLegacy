#import "LTRecentsTileSizeViewController.h"
#import "LTHomeViewController.h"

@interface LTRecentsTileSizeViewController ()
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *smallLabel;
@property (nonatomic, strong) UILabel *largeLabel;
@end

@implementation LTRecentsTileSizeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Recents Tile Size";
    self.view.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];

    CGFloat width = self.view.bounds.size.width;
    CGFloat pad = 20.0f;

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(pad, 20, width - pad * 2, 40)];
    desc.text = @"Controls how large the Recently Played tiles appear on the Home tab.";
    desc.font = [UIFont systemFontOfSize:14];
    desc.textColor = [UIColor lightGrayColor];
    desc.backgroundColor = [UIColor clearColor];
    desc.numberOfLines = 0;
    desc.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:desc];

    self.valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 70, width - pad * 2, 30)];
    self.valueLabel.text = [self currentSizeText];
    self.valueLabel.font = [UIFont boldSystemFontOfSize:22];
    self.valueLabel.textColor = [UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f];
    self.valueLabel.backgroundColor = [UIColor clearColor];
    self.valueLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.valueLabel];

    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(pad, 120, width - pad * 2, 30)];
    self.slider.minimumValue = kHomeTileMinWidth;
    self.slider.maximumValue = kHomeTileMaxWidth;
    self.slider.value = [self currentSize];
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.slider];

    self.smallLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 158, width / 2.0f - pad, 20)];
    self.smallLabel.text = @"Small";
    self.smallLabel.font = [UIFont systemFontOfSize:14];
    self.smallLabel.textColor = [UIColor whiteColor];
    self.smallLabel.backgroundColor = [UIColor clearColor];
    self.smallLabel.textAlignment = NSTextAlignmentLeft;
    [self.view addSubview:self.smallLabel];

    self.largeLabel = [[UILabel alloc] initWithFrame:CGRectMake(width / 2.0f, 158, width / 2.0f - pad, 20)];
    self.largeLabel.text = @"Large";
    self.largeLabel.font = [UIFont systemFontOfSize:14];
    self.largeLabel.textColor = [UIColor whiteColor];
    self.largeLabel.backgroundColor = [UIColor clearColor];
    self.largeLabel.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:self.largeLabel];

    self.view.opaque = YES;
}

- (CGFloat)currentSize {
    CGFloat width = [[NSUserDefaults standardUserDefaults] floatForKey:@"LTHomeTileSize"];
    if (width < kHomeTileMinWidth || width > kHomeTileMaxWidth) {
        width = kHomeTileMinWidth;
    }
    return width;
}

- (NSString *)currentSizeText {
    return [NSString stringWithFormat:@"%.0f pt", [self currentSize]];
}

- (void)sliderChanged:(UISlider *)slider {
    [[NSUserDefaults standardUserDefaults] setFloat:slider.value forKey:@"LTHomeTileSize"];
    self.valueLabel.text = [NSString stringWithFormat:@"%.0f pt", slider.value];
}

@end