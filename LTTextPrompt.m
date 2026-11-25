#import "LTTextPrompt.h"
#import <objc/runtime.h>

// Works under both ARC and MRC (the project is ARC overall).

static const void *kLTTextPromptDelegateKey = &kLTTextPromptDelegateKey;

@interface LTTextPromptAlertDelegate : NSObject <UIAlertViewDelegate>
@property (nonatomic, copy) void (^completion)(NSString *text, BOOL cancelled);
@end

@implementation LTTextPromptAlertDelegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (self.completion) {
        BOOL cancelled = (buttonIndex == alertView.cancelButtonIndex);
        NSString *text = nil;
        if (!cancelled && [alertView respondsToSelector:@selector(textFieldAtIndex:)]) {
            text = [[alertView textFieldAtIndex:0] text];
        }
        self.completion(text, cancelled);
    }
#if !__has_feature(objc_arc)
    [self release];
#endif
}
@end

@interface LTTextPromptController : UIViewController
@property (nonatomic, copy) NSString *promptTitle;
@property (nonatomic, copy) NSString *promptMessage;
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) void (^completion)(NSString *text, BOOL cancelled);
@property (nonatomic, strong) UITextField *textField;
@end

@implementation LTTextPromptController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.promptTitle ?: @"";
    self.view.backgroundColor = [UIColor colorWithWhite:0.93f alpha:1.0f];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }

    CGFloat width = self.view.bounds.size.width;
    CGFloat y = 20.0f;
    if (self.promptMessage.length) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, y, width - 40, 40)];
        label.text = self.promptMessage;
        label.font = [UIFont systemFontOfSize:14];
        label.textColor = [UIColor darkGrayColor];
        label.numberOfLines = 0;
        label.backgroundColor = [UIColor clearColor];
        [self.view addSubview:label];
        y += 48.0f;
#if !__has_feature(objc_arc)
        [label release];
#endif
    }

    self.textField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, width - 40, 30)];
    self.textField.borderStyle = UITextBorderStyleRoundedRect;
    self.textField.placeholder = self.placeholder;
    self.textField.text = self.initialText;
    self.textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    self.textField.autocorrectionType = UITextAutocorrectionTypeDefault;
    self.textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.textField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.textField];
#if !__has_feature(objc_arc)
    [self.textField release];
#endif

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];
#if !__has_feature(objc_arc)
    [self.navigationItem.leftBarButtonItem release];
    [self.navigationItem.rightBarButtonItem release];
#endif
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.textField becomeFirstResponder];
}

- (void)finishWithText:(NSString *)text cancelled:(BOOL)cancelled {
    if (self.completion) self.completion(text, cancelled);
    if ([self respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        [self dismissViewControllerAnimated:YES completion:NULL];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

- (void)cancelTapped { [self finishWithText:nil cancelled:YES]; }
- (void)doneTapped { [self finishWithText:self.textField.text cancelled:NO]; }
@end

@implementation LTTextPrompt

+ (void)presentIn:(UIViewController *)presenter
             title:(NSString *)title
           message:(NSString *)message
       placeholder:(NSString *)placeholder
       initialText:(NSString *)initialText
        completion:(void (^)(NSString *text, BOOL cancelled))completion {
    UIAlertView *probe = [[UIAlertView alloc] init];
    BOOL hasStyle = [probe respondsToSelector:@selector(setAlertViewStyle:)] &&
                    [probe respondsToSelector:@selector(textFieldAtIndex:)];
#if !__has_feature(objc_arc)
    [probe release];
#endif

    if (hasStyle) {
        LTTextPromptAlertDelegate *delegate = [[LTTextPromptAlertDelegate alloc] init];
        delegate.completion = completion;
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                        message:message
                                                       delegate:delegate
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"OK", nil];
        // UIAlertView's delegate is not retained; keep ours alive for the callback.
        objc_setAssociatedObject(alert, kLTTextPromptDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        UITextField *field = [alert textFieldAtIndex:0];
        field.placeholder = placeholder;
        field.text = initialText;
        [alert show];
#if !__has_feature(objc_arc)
        [delegate release];
        [alert release];
#endif
        return;
    }

    LTTextPromptController *vc = [[LTTextPromptController alloc] init];
    vc.promptTitle = title;
    vc.promptMessage = message;
    vc.placeholder = placeholder;
    vc.initialText = initialText;
    vc.completion = completion;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    UIViewController *host = presenter;
    if (!host) host = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    if ([host respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        [host presentViewController:nav animated:YES completion:NULL];
    } else {
        [host presentModalViewController:nav animated:YES];
    }
#if !__has_feature(objc_arc)
    [vc release];
    [nav release];
#endif
}

@end
