#import "LTTransitionSpeedViewController.h"
#import "LTTransitionSettings.h"

@interface LTTransitionSpeedViewController ()
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *fastLabel;
@property (nonatomic, strong) UILabel *slowLabel;
@end

@implementation LTTransitionSpeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Transition Speed";
    self.view.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];

    CGFloat width = self.view.bounds.size.width;
    CGFloat pad = 20.0f;

    // Description
    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(pad, 20, width - pad * 2, 40)];
    desc.text = @"How fast in-app transitions play. Lower = faster.";
    desc.font = [UIFont systemFontOfSize:14];
    desc.textColor = [UIColor lightGrayColor];
    desc.numberOfLines = 0;
    desc.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:desc];

    // Current value
    self.valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 70, width - pad * 2, 30)];
    self.valueLabel.text = [NSString stringWithFormat:@"%.1fx", [LTTransitionSettings speedMultiplier]];
    self.valueLabel.font = [UIFont boldSystemFontOfSize:22];
    self.valueLabel.textColor = [UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f];
    self.valueLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.valueLabel];

    // Slider with end labels
    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(pad, 120, width - pad * 2, 30)];
    self.slider.minimumValue = 0.5f;
    self.slider.maximumValue = 2.0f;
    self.slider.value = [LTTransitionSettings speedMultiplier];
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.slider];

    self.fastLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 158, width / 2.0f - pad, 20)];
    self.fastLabel.text = @"Slower";
    self.fastLabel.font = [UIFont systemFontOfSize:14];
    self.fastLabel.textColor = [UIColor whiteColor];
    self.fastLabel.textAlignment = NSTextAlignmentLeft;
    [self.view addSubview:self.fastLabel];

    self.slowLabel = [[UILabel alloc] initWithFrame:CGRectMake(width / 2.0f, 158, width / 2.0f - pad, 20)];
    self.slowLabel.text = @"Faster";
    self.slowLabel.font = [UIFont systemFontOfSize:14];
    self.slowLabel.textColor = [UIColor whiteColor];
    self.slowLabel.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:self.slowLabel];
}

- (void)sliderChanged:(UISlider *)slider {
    [LTTransitionSettings setSpeedMultiplier:slider.value];
    self.valueLabel.text = [NSString stringWithFormat:@"%.1fx", slider.value];
}

@end
