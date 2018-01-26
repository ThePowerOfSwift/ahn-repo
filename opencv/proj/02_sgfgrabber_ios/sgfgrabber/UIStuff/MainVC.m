//
//  MainVC.m
//  sgfgrabber
//
//  Created by Andreas Hauenstein on 2017-10-20.
//  Copyright © 2017 AHN. All rights reserved.
//

#import "MainVC.h"
#import "UIViewController+LGSideMenuController.h"

#import "Globals.h"
#import "CppInterface.h"

//==========================
@interface MainVC ()
@property UIImageView *cameraView;
// Data
@property UIImage *img; // The current image

@property UIImage *imgVideoBtn;
@property UIImage *imgPhotoBtn;

// State
@property int debugstate;
@end

//=========================
@implementation MainVC

//----------------
- (id)init
{
    self = [super init];
    if (self) {
        self.title = @"SgfGrabber";
        self.view.backgroundColor = BGCOLOR;
        self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Menu"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showLeftView)];
    }
    return self;
} // init()

//----------------------
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.frameExtractor = [FrameExtractor new];
    self.cppInterface = [CppInterface new];
    self.frameExtractor.delegate = self;
    //self.frame_grabber_on = YES;
    self.debugstate = 0;
}

//----------------------------------
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

// Allocate UI elements.
//----------------------------------------------------------------------
- (void) loadView
{
    self.view = [UIView new];
    UIView *v = self.view;
    v.autoresizesSubviews = NO;
    v.opaque = YES;
    v.backgroundColor = BGCOLOR;

    // Camera View
    self.cameraView = [UIImageView new];
    self.cameraView.contentMode = UIViewContentModeScaleAspectFit;
    [v addSubview:self.cameraView];
    
    // Label for various info
    UILabel *l = [UILabel new];
    l.hidden = false;
    l.text = @"";
    l.backgroundColor = BGCOLOR;
    [v addSubview:l];
    self.lbBottom = l;
    
    // Small label for numbers and such
    UILabel *sl = [UILabel new];
    sl.hidden = false;
    sl.text = @"";
    sl.backgroundColor = BGCOLOR;
    [v addSubview:sl];
    self.lbSmall = sl;
    
//    // Debug slider
//    UISlider *s = [UISlider new];
//    self.sldDbg = s;
//    s.minimumValue = 0;
//    s.maximumValue = 16;
//    [s addTarget:self action:@selector(sldDbg:) forControlEvents:UIControlEventValueChanged];
//    s.backgroundColor = RGB (0xf0f0f0);
//    [v addSubview:s];
//    self.sldDbg.hidden = false;
    
    // Button for video or image
    self.btnCam = [self addButtonWithTitle:@"" callback:@selector(btnCam:)];
    self.imgPhotoBtn = [UIImage imageNamed:@"photo_icon.png"];
    self.imgVideoBtn = [UIImage imageNamed:@"video_icon.png"];
    [self.btnCam setBackgroundImage:self.imgVideoBtn forState:UIControlStateNormal];
    self.lbBottom.text = @"Point the camera at a Go board";
} // loadView()

//----------------------------------------------------------------------
- (void) viewWillAppear:(BOOL) animated
{
    [super viewWillAppear: animated];
    [self doLayout];
}

//-------------------------------
- (BOOL)prefersStatusBarHidden
{
    return YES;
}

// Layout
//=========

// Put UI elements into the right place
//----------------------------------------------------------------------
- (void) doLayout
{
    //float W = SCREEN_WIDTH;
    float H = SCREEN_HEIGHT;
    UIView *v = self.view;
    CGRect bounds = v.bounds;
    bounds.origin.y = g_app.navVC.navigationBar.frame.size.height;
    bounds.size.height = H - bounds.origin.y;
    v.bounds = bounds;

    CGRect camFrame = v.bounds;
    camFrame.origin.y = g_app.navVC.navigationBar.frame.size.height;
    self.cameraView.frame = camFrame;
    self.cameraView.hidden = NO;
    //int bottomOfCam = camFrame.origin.y + camFrame.size.height;

    // Camera button
    [self.btnCam setBackgroundImage:self.imgPhotoBtn forState:UIControlStateNormal];
    if ([g_app.menuVC videoMode]) {
        [self.btnCam setBackgroundImage:self.imgVideoBtn forState:UIControlStateNormal];
    }
    
    // Info Label
    self.lbBottom.textAlignment = NSTextAlignmentCenter;

    // Small Label
    self.lbSmall.textAlignment = NSTextAlignmentLeft;
} // doLayout

// Position camera button and labels when first image comes in.
// We don't know the image size until we get one.
//---------------------------------------------------
- (void) positionButtonAndLabels
{
    static bool called = false;
    if (called) return;
    called = true;
    
    // Get lower edge of image
    float W = self.view.frame.size.width;
    float H = self.view.frame.size.height;
    CGRect imgRect = AVMakeRectWithAspectRatioInsideRect(_cameraView.image.size, _cameraView.bounds);
    int bottomOfImg = _cameraView.frame.origin.y + imgRect.origin.y + imgRect.size.height;
    
    // Position camera button
    int r = 70;
    self.btnCam.frame = CGRectMake( W/2 - r/2, bottomOfImg - 1.1 * r, r , r);
    CALayer *layer = self.btnCam.layer;
    layer.backgroundColor = [[UIColor clearColor] CGColor];
    layer.borderColor = [[UIColor clearColor] CGColor];
    
    // Info label
    int lbHeight = 55;
    int lbY = bottomOfImg + (H - bottomOfImg)/2.0;
    self.lbBottom.frame = CGRectMake( 0, lbY, W , lbHeight);
    
    // Small label
    int slbHeight = 35;
    self.lbSmall.frame = CGRectMake( W/100, bottomOfImg, W/3 , slbHeight);
    
} // showCameraButton

//---------------------------------------------------
- (UIButton*) addButtonWithTitle: (NSString *) title
                        callback: (SEL) callback
{
    UIView *parent = self.view;
    id target = self;
    
    UIButton *b = [[UIButton alloc] init];
    [b.layer setBorderWidth:1.0];
    [b.layer setBorderColor:[RGB (0x202020) CGColor]];
    b.backgroundColor = RGB (0xf0f0f0);
    b.frame = CGRectMake(0, 0, 72, 44);
    [b setTitle: title forState: UIControlStateNormal];
    [b setTitleColor: WHITE forState: UIControlStateNormal];
    [b addTarget:target action:callback forControlEvents: UIControlEventTouchUpInside];
    [parent addSubview: b];
    return b;
} // addButtonWithTitle

// Button etc callbacks
//=========================

// Tapping on the screen
//----------------------------------------------------------------
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    if ([g_app.menuVC debugMode]) {
        [self debugFlow:false];
    }
    if ([g_app.menuVC demoMode]) {
        [self debugFlow:false];
    }
    else if ([g_app.menuVC videoMode]) {
        //[self btnCam:nil];
    }
} // touchesBegan()

//// Slider for Debugging
////-----------------------------------
//- (void) sldDbg:(id) sender
//{
//    int tt = [self.sldDbg value];
//    self.lbDbg.text = nsprintf( @"%d", tt);
//}

// Camera button press
//-----------------------------
- (void) btnCam:(id)sender
{
    if ([g_app.menuVC videoMode]) {
        //g_app.saveDiscardVC.photo = [self.cameraView.image copy];
        g_app.saveDiscardVC.photo = [_cppInterface get_last_frame_with_board];
        g_app.saveDiscardVC.sgf = [g_app.mainVC.cppInterface get_sgf];
        [g_app.navVC pushViewController:g_app.saveDiscardVC animated:YES];
    } // videoMode
    else if ([g_app.menuVC photoMode]) {
        g_app.saveDiscardVC.photo = [_cppInterface process_best_frame];
        g_app.saveDiscardVC.sgf = [g_app.mainVC.cppInterface get_sgf];
        [g_app.navVC pushViewController:g_app.saveDiscardVC animated:YES];
    } // photoMode
} // btnCam

// FrameExtractorDelegate protocol
//=====================================

//-----------------------------------------------
- (void)captured:(UIImage *)image
{
    if ([g_app.menuVC debugMode]) {
        //self.frame_grabber_on = NO;
        [self.frameExtractor suspend];
        return;
    } // debugMode
    else if ([g_app.menuVC photoMode]) {
        [self.cameraView setImage:image];
        _img = image;
        [_cppInterface qImg:_img];
    } // photoMode
    else if ([g_app.menuVC videoMode]) {
        [self.frameExtractor suspend];
        UIImage *processedImg = [self.cppInterface real_time_flow:image];
        self.img = processedImg;
        [self.cameraView setImage:self.img];
        [self positionButtonAndLabels];
        [self.frameExtractor resume];
    } // videoMode
} // captured()

// LGSideMenuController Callbacks
//==================================

//---------------------
- (void)showLeftView
{
    [self.sideMenuController showLeftViewAnimated:YES completionHandler:nil];
}

//------------------------
- (void)showRightView
{
    [self.sideMenuController showRightViewAnimated:YES completionHandler:nil];
}

// Other
//============

// Debugging helper, shows individual processing stages.
// Called when entering debug mode, and on screen tap in debug mode.
//---------------------------------------------------------------------
- (void) debugFlow:(bool)reset
{
    if (reset) _debugstate = 0;
    UIImage *img;
    while(1) {
        switch (_debugstate) {
            case 0:
                _debugstate++;
                //self.frame_grabber_on = NO;
                [self.frameExtractor suspend];
                img = [self.cppInterface f00_blobs];
                [self.cameraView setImage:img];
                break;
            case 1:
                img = [self.cppInterface f01_vert_lines];
                if (!img) { _debugstate=2; continue; }
                [self.cameraView setImage:img];
                break;
            case 2:
                img = [self.cppInterface f02_horiz_lines];
                if (!img) { _debugstate=3; continue; }
                [self.cameraView setImage:img];
                break;
            case 3:
                _debugstate++;
                img = [self.cppInterface f03_corners];
                [self.cameraView setImage:img];
                break;
            case 4:
                _debugstate++;
                img = [self.cppInterface f04_zoom_in];
                [self.cameraView setImage:img];
                break;
            case 5:
                _debugstate++;
                img = [self.cppInterface f05_dark_places];
                [self.cameraView setImage:img];
                break;
            case 6:
                _debugstate++;
                img = [self.cppInterface f06_mask_dark];
                [self.cameraView setImage:img];
                break;
            case 7:
                _debugstate++;
                img = [self.cppInterface f07_white_holes];
                [self.cameraView setImage:img];
                break;
            case 8:
                _debugstate++; continue; // skip;
                //                img = [self.cppInterface f08_features];
                //                if (!img) { _sliderstate=9; continue; }
                //                [self.cameraView setImage:img];
                break;
            case 9:
                _debugstate++;
                img = [self.cppInterface f09_classify];
                [self.cameraView setImage:img];
                break;
            default:
                _debugstate=0;
                continue;
        } // switch
        break;
    } // while(1)
} // debugFlow()

@end
