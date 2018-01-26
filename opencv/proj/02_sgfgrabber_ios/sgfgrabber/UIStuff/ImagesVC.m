//
//  ImagesVC.m
//  sgfgrabber
//
//  Created by Andreas Hauenstein on 2018-01-17.
//  Copyright © 2018 AHN. All rights reserved.
//

// View Controller to export or delete saved images/diagrams

#import "Globals.h"
#import "ImagesVC.h"
#import "CppInterface.h"

#define ROWHEIGHT 140

// Table View Cell
//==================

@implementation ImagesCell
//-------------------------------------------------------------------------------------------------------
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        self.backgroundColor = [UIColor clearColor];
        
        self.textLabel.font = [UIFont boldSystemFontOfSize:16.0];
        self.textLabel.textColor = [UIColor whiteColor];
        self.textLabel.backgroundColor = [UIColor clearColor];
    }
    return self;
} // initWithStyle()

//------------------------
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect frame = self.frame;
    frame.size.height = ROWHEIGHT - 10;
    self.frame = frame;
}

//----------------------------------------------------------------
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    self.textLabel.alpha = highlighted ? 0.5 : 1.0;
}
@end // ImagesCell


// Table View Controller
//=========================

@interface ImagesVC ()
@property (strong, nonatomic) NSArray *titlesArray;
@property long selected_row;
//@property long highlighted_row;
@property UIDocumentInteractionController *documentController;
@end

@implementation ImagesVC

//----------
- (id)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.view.backgroundColor = [UIColor clearColor];
        
        [self.tableView registerClass:[ImagesCell class] forCellReuseIdentifier:@"cell"];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        self.tableView.showsVerticalScrollIndicator = NO;
        self.tableView.backgroundColor = [UIColor clearColor];
        //self.tableView.rowHeight = 150;
        [self loadTitlesArray];
    }
    return self;
}

//---------------------------------------
- (void)refresh
{
    [self loadTitlesArray];
    [self.tableView reloadData];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

// Find saved files and remember their names for display. One per row.
//----------------------------------------------------------------------
- (void) loadTitlesArray
{
    self.titlesArray = globFiles( @SAVED_FOLDER, @"", @".png");
    self.titlesArray = [[self.titlesArray reverseObjectEnumerator] allObjects];
    if (_selected_row >= [_titlesArray count]) {
        _selected_row = 0;
    }
    if ([_titlesArray count]) {
        self.selectedImageName = _titlesArray[_selected_row];
    }
}

//-------------------------------------------
- (void) viewWillAppear:(BOOL) animated
{
    [super viewWillAppear: animated];
    [self refresh];
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

// UITableViewDataSource
//========================

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
- (ImagesCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ImagesCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    [[cell subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSString *fname = self.titlesArray[indexPath.row];
    // Photo
    UIImageView *imgView1 = [[UIImageView alloc] initWithFrame:CGRectMake(40,20,70,70)];
    NSString *fullfname = getFullPath( nsprintf( @"%@/%@", @SAVED_FOLDER, fname));
    UIImage *img = [UIImage imageWithContentsOfFile:fullfname];
    imgView1.image = img;
    [cell addSubview: imgView1];
    // Diagram
    UIImageView *imgView2 = [[UIImageView alloc] initWithFrame:CGRectMake(140,20,70,70)];
    fullfname = changeExtension( fullfname, @".sgf");
    NSString *sgf = [NSString stringWithContentsOfFile:fullfname encoding:NSUTF8StringEncoding error:NULL];
    UIImage *sgfImg = [CppInterface sgf2img:sgf];
    imgView2.image = sgfImg;
    [cell addSubview: imgView2];
    // Name
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(40,70,250,70)];
    lb.text = fname;
    [cell addSubview:lb];
    //cell.backgroundColor = self.view.tintColor;
    cell.backgroundColor = [UIColor clearColor];
    if (indexPath.row == _selected_row) {
        cell.backgroundColor = self.view.tintColor;
    }
    return cell;
}

// UITableViewDelegate
//========================

//-----------------------------------------------------------------------------------------------
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return ROWHEIGHT;
} // heightForRowAtIndexPath()

// Click on saved image
//--------------------------------------------------------------------------------------------
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    _selected_row = indexPath.row;
    //_highlighted_row = _selected_row;
    [self.tableView reloadData];
    NSArray *choices = @[@"Export", @"Delete", @"Cancel"];
    choicePopup( choices, @"Action",
                ^(UIAlertAction *action) {
                    [self handleEditAction:action.title];
                });
} // didSelectRowAtIndexPath()

// Action Handlers
//==================

// Handle image edit action
//---------------------------------------------
- (void)handleEditAction:(NSString *)action
{
    if ([action hasPrefix:@"Export"]) {
        [self handleExportAction];
    }
    else if ([action hasPrefix:@"Delete"]) {
        NSString *fname = _titlesArray[_selected_row];
        fname = getFullPath( fname);
        choicePopup( @[@"Delete",@"Cancel"], @"Really?",
                    ^(UIAlertAction *action) {
                        [self handleDeleteAction:action.title];
                    });
    }
    else {}
} // handleEditAction()

// Delete current image
//---------------------------------------------
- (void)handleDeleteAction:(NSString *)action
{
    if (![action hasPrefix:@"Delete"]) return;
    // Delete png file
    NSString *fname = _titlesArray[_selected_row];
    rmFile( nsprintf( @"%@/%@", @SAVED_FOLDER, fname));
    // Delete sgf file
    fname = changeExtension( fname, @".sgf");
    rmFile( nsprintf( @"%@/%@", @SAVED_FOLDER, fname));
    [self refresh];
} // handleDeleteAction()

// Export sgf
//---------------------------
- (void)handleExportAction
{
    NSString *fname = _titlesArray[_selected_row];
    fname = changeExtension( fname, @".sgf");
    NSString *fullfname = getFullPath( nsprintf( @"%@/%@", @SAVED_FOLDER, fname));
    
    _documentController = [UIDocumentInteractionController
                           interactionControllerWithURL:[NSURL fileURLWithPath:fullfname]];
    [_documentController presentOptionsMenuFromRect:self.view.frame inView:self.view animated:YES];
} // handleExportAction()

// Other
//===========

// Name of selected png file
//----------------------------
- (NSString *)selectedFname
{
    NSString *res = _titlesArray[_selected_row];
    return res;
}

@end // ImagesVC





































