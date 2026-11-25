#import "S6HomeViewController.h"
#import "S6Cells.h"
#import "S6Router.h"
#import "S6Theme.h"
#import "S6Models.h"
#import "S6Catalog.h"
#import "S6Session.h"
#import "S6Common.h"

@interface S6HomeViewController ()
@property (nonatomic, strong) NSArray *shelves;    // NSDictionary {title, cards}
@property (nonatomic, strong) UILabel *greeting;
@end

@implementation S6HomeViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _shelves = [NSArray array];
        self.title = L(@"Home");
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerClass:[S6ShelfCell class] forCellReuseIdentifier:@"shelf"];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 64)];
    self.greeting = [[UILabel alloc] initWithFrame:CGRectMake(14, 16, 292, 36)];
    self.greeting.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.greeting.font = [[S6Theme shared] headerFont];
    self.greeting.textColor = [[S6Theme shared] primaryTextColor];
    self.greeting.backgroundColor = [UIColor clearColor];
    self.greeting.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
    self.greeting.shadowOffset = CGSizeMake(0, -1);
    [header addSubview:self.greeting];
    self.tableView.tableHeaderView = header;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged) name:S6SessionStateDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// (the view has no width yet in viewDidLoad on newer iOS: the greeting is placed once the table has one)
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat w = self.tableView.bounds.size.width;
    UIView *header = self.tableView.tableHeaderView;
    if (w > 0 && fabs(header.bounds.size.width - w) > 1) {
        header.frame = CGRectMake(0, 0, w, 64);
        self.greeting.frame = CGRectMake(14, 16, w - 28, 36);
        self.tableView.tableHeaderView = header;
    }
}

- (void)sessionChanged
{
    if ([S6Session shared].state == S6SessionStateReady && !self.shelves.count && !self.loading) [self reload];
}

- (NSString *)greetingText
{
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSHourCalendarUnit fromDate:[NSDate date]];
    if (c.hour >= 4 && c.hour < 12) return L(@"Good morning");
    if (c.hour >= 12 && c.hour < 18) return L(@"Good afternoon");
    return L(@"Good evening");
}

- (CGFloat)cardWidth { return S6IsPad() ? 150 : 120; }

- (void)load
{
    self.greeting.text = [self greetingText];
    if ([S6Session shared].state == S6SessionStateLoggedOut) { [self finishLoadingWithError:nil empty:YES emptyMessage:L(@"Nothing here yet.")]; return; }
    [self startLoading];
    __unsafe_unretained S6HomeViewController *weakSelf = self;
    [S6Catalog home:^(NSString *greeting, NSArray *sections, NSError *error) {
        S6HomeViewController *me = weakSelf;
        if (greeting.length) me.greeting.text = greeting;
        NSMutableArray *shelves = [NSMutableArray array];
        for (S6Shelf *s in sections) {
            NSMutableArray *cards = [NSMutableArray array];
            for (id item in s.items) {
                NSDictionary *card = S6CardFor(item);
                if (card) [cards addObject:card];
            }
            if (cards.count) [shelves addObject:@{ @"title": s.title ?: @"", @"cards": cards }];
        }
        me.shelves = shelves;
        [me finishLoadingWithError:shelves.count ? nil : error empty:!shelves.count emptyMessage:L(@"Nothing here yet.")];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)self.shelves.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [S6ShelfCell heightForCardWidth:[self cardWidth]];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    return S6SectionHeader(self.shelves[[(NSUInteger)section] objectForKey:@"title"], tableView.bounds.size.width);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 26; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6ShelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"shelf" forIndexPath:indexPath];
    [cell showItems:self.shelves[[(NSUInteger)indexPath.section] objectForKey:@"cards"] cardWidth:[self cardWidth]];
    cell.onSelect = ^(id item) { [S6Router openItem:item]; };
    return cell;
}

@end
