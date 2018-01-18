//
//  LeftViewController.m
//  LGSideMenuControllerDemo
//

#import "Globals.h"
#import "LeftViewController.h"
#import "LeftViewCell.h"
#import "TopViewController.h"
#import "UIViewController+LGSideMenuController.h"

@interface LeftViewController ()

@property (strong, nonatomic) NSArray *titlesArray;

@end

@implementation LeftViewController

//----------
- (id)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.titlesArray = @[@"Edit Test Cases"
                             ,@"Run Test Cases"
                             ];

        self.view.backgroundColor = [UIColor clearColor];

        [self.tableView registerClass:[LeftViewCell class] forCellReuseIdentifier:@"cell"];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        self.tableView.contentInset = UIEdgeInsetsMake(44.0, 0.0, 44.0, 0.0);
        self.tableView.showsVerticalScrollIndicator = NO;
        self.tableView.backgroundColor = [UIColor clearColor];
    }
    return self;
}
//-------------------------------
- (BOOL)prefersStatusBarHidden
{
    return YES;
}
//--------------------------------------------
- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}
//-----------------------------------------------------------
- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation
{
    return UIStatusBarAnimationFade;
}
#pragma mark - UITableViewDataSource
//-----------------------------------------------------------------
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}
//------------------------------------------------------------------------------------------
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.titlesArray.count;
}
//------------------------------------------------------------------------------------------------------
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    LeftViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];

    cell.textLabel.text = self.titlesArray[indexPath.row];
    //cell.separatorView.hidden = (indexPath.row <= 3 || indexPath.row == self.titlesArray.count-1);
    //cell.userInteractionEnabled = (indexPath.row != 1 && indexPath.row != 3);

    return cell;
}
#pragma mark - UITableViewDelegate
//-----------------------------------------------------------------------------------------------
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath.row == 1 || indexPath.row == 3) ? 22.0 : 44.0;
}
//--------------------------------------------------------------------------------------------
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    TopViewController *topViewController = (TopViewController *)self.sideMenuController;
    NSString *menuItem = _titlesArray[indexPath.row];
//    if ([menuItem hasPrefix:@"Edit Test Cases"]) {
//        [g_app.mainVC mnuSaveAsTestCase];
//    }
    if ([menuItem hasPrefix:@"Edit Test Cases"]) {
        [g_app.mainVC mnuEditTestCases];
    }
//
//    UIViewController *viewController = [UIViewController new];
//    viewController.view.backgroundColor = [UIColor whiteColor];
//    viewController.title = self.titlesArray[indexPath.row];
//
//    UINavigationController *navigationController = (UINavigationController *)topViewController.rootViewController;
//    [navigationController pushViewController:viewController animated:YES];
    
    [topViewController hideLeftViewAnimated:YES completionHandler:nil];
}

@end
