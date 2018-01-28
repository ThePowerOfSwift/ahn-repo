//
//  CppInterface.mm
//  sgfgrabber
//
//  Created by Andreas Hauenstein on 2017-10-21.
//  Copyright © 2017 AHN. All rights reserved.
//

// This class is the only place where Objective-C and C++ mix.
// All other files are either pure Obj-C or pure C++.

// Don't change the order of these two,
// and don't move them down
#import "Ocv.hpp"
#import <opencv2/imgcodecs/ios.h>

#import "Common.h"
#import "Globals.h"
#include "Helpers.hpp"

#import "AppDelegate.h"
#import "BlackWhiteEmpty.hpp"
#import "BlobFinder.hpp"
#import "Boardness.hpp"
#import "Clust1D.hpp"
#import "CppInterface.h"
#import "DrawBoard.hpp"

// Pyramid filter params
#define SPATIALRAD  5
#define COLORRAD    30
#define MAXPYRLEVEL 2

extern cv::Mat mat_dbg;
static BlackWhiteEmpty classifier;

@interface CppInterface()
//=======================
@property cv::Mat small_img; // resized image, in color, RGB
@property cv::Mat small_pyr; // resized image, in color, pyramid filtered
@property Points pyr_board; // Initial guess at board location

@property cv::Mat orig_img;     // Mat with image we are working on
@property cv::Mat small_zoomed;  // small, zoomed into the board
@property cv::Mat gray;  // Grayscale version of small
@property cv::Mat gray_threshed;  // gray with inv_thresh and dilation
@property cv::Mat gray_zoomed;   // Grayscale version of small, zoomed into the board
@property cv::Mat pyr_zoomed;    // zoomed version of small_pyr
@property cv::Mat pyr_gray;      // zoomed version of small_pyr, in gray
@property cv::Mat pyr_masked;    // pyr_gray with black stones masked out

@property cv::Mat gz_threshed; // gray_zoomed with inv_thresh and dilation
@property Contours cont; // Current set of contours
@property int board_sz; // board size, 9 or 19
@property Points stone_or_empty; // places where we suspect stones or empty
@property std::vector<cv::Vec2f> horizontal_lines;
@property std::vector<cv::Vec2f> vertical_lines;
@property std::vector<int> diagram; // The position we detected
@property Points2f corners;
@property Points2f corners_zoomed;
@property Points2f intersections;
@property Points2f intersections_zoomed;
@property double dy;
@property double dx;
@property std::vector<Points2f> boards; // history of board corners
@property cv::Mat white_templ;
@property cv::Mat black_templ;
@property cv::Mat empty_templ;
// History of frames. The one at the button press is often shaky.
@property std::vector<cv::Mat> imgQ;
// Remember most recent video frame with a Go board
@property cv::Mat last_frame_with_board;

@end

@implementation CppInterface
//=========================

//----------------------
- (instancetype)init
{
    self = [super init];
    if (self) {
        g_docroot = [getFullPath(@"") UTF8String];
        // Load template files
        cv::Mat tmat;
        NSString *fpath;
        
        fpath = findInBundle( @"white_templ", @"yml");
        cv::FileStorage fsw( [fpath UTF8String], cv::FileStorage::READ);
        fsw["white_template"] >> _white_templ;
        
        fpath = findInBundle( @"black_templ", @"yml");
        cv::FileStorage fsb( [fpath UTF8String], cv::FileStorage::READ);
        fsb["black_template"] >> _black_templ;
        
        fpath = findInBundle( @"empty_templ", @"yml");
        cv::FileStorage fse( [fpath UTF8String], cv::FileStorage::READ);
        fse["empty_template"] >> _empty_templ;
    }
    return self;
}

#pragma mark - Pipeline Helpers
//==================================

// Load image from file
//-------------------------------------------------------
- (void) load_img:(NSString *)fname dst:(cv::Mat &) dst
{
    UIImage *img = [UIImage imageNamed:fname];
    UIImageToMat(img, dst);
}

// Save current resized image to file.
// fname must have .png extension.
//---------------------------------------------
- (bool) save_small_img:(NSString *)fname
{
    cv::Mat m;
    cv::cvtColor( _small_img, m, CV_RGB2BGR);
    std::vector<int> compression_params;
    compression_params.push_back(CV_IMWRITE_PNG_COMPRESSION);
    compression_params.push_back(0);
    return cv::imwrite( [fname UTF8String], m);
}

// Save current diagram to file as sgf
//-----------------------------------------------------------------------
- (bool) save_current_sgf:(NSString *)fname withTitle:(NSString *)title
{
    auto sgf = generate_sgf( [title UTF8String], _diagram);
    std::ofstream ofs;
    ofs.open( [fname UTF8String]);
    ofs << sgf;
    ofs.close();
    return ofs.good();
}

// Get current diagram as sgf
//----------------------------------
- (NSString *) get_sgf
{
    return @(generate_sgf( "", self.diagram).c_str());
}

// Queue image frames. The newest one is often shaky.
//-----------------------------------------------------
- (void)qImg:(UIImage *)img
{
    cv::Mat m;
    UIImageToMat( img, m);
    resize( m, m, IMG_WIDTH);
    cv::cvtColor( m, m, CV_RGBA2RGB); // Yes, RGBA not BGR
    ringpush( _imgQ , m, 4); // keep 4 frames
}

#pragma mark - Processing Pipeline for debugging
//=================================================

//--------------------------
- (UIImage *) f00_blobs
{
    _board_sz=19;
    g_app.mainVC.lbBottom.text = @"Tap the screen";
    _vertical_lines.clear();
    _horizontal_lines.clear();
    //int sldVal = g_app.mainVC.sldDbg.value;
    NSString *fullfname;
    if ([g_app.menuVC demoMode]) {
        fullfname = findInBundle(@"demo", @".png");
    }
    else {
        NSString *fname = nsprintf( @"%@/%@", @TESTCASE_FOLDER, g_app.editTestCaseVC.selectedTestCase);
        fullfname = getFullPath( fname);
    }
    UIImage *img = [UIImage imageWithContentsOfFile:fullfname];
    UIImageToMat( img, _orig_img);
    
    resize( _orig_img, _small_img, IMG_WIDTH);
    cv::cvtColor( _small_img, _small_img, CV_RGBA2RGB); // Yes, RGBA not BGR
    cv::cvtColor( _small_img, _gray, cv::COLOR_RGB2GRAY);
    thresh_dilate( _gray, _gray_threshed);
    _stone_or_empty.clear();
    BlobFinder::find_empty_places( _gray_threshed, _stone_or_empty); // has to be first
    BlobFinder::find_stones( _gray, _stone_or_empty);
    _stone_or_empty = BlobFinder::clean( _stone_or_empty);
    
    cv::pyrMeanShiftFiltering( _small_img, _small_pyr, SPATIALRAD, COLORRAD, MAXPYRLEVEL );
    
    // Show results
    cv::Mat drawing = _small_img.clone();
    draw_points( _stone_or_empty, drawing, 2, cv::Scalar( 255,0,0));
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f00_blobs()

// Convert sgf string to UIImage 
//----------------------------------------
+ (UIImage *) sgf2img:(NSString *)sgf
{
    if (!sgf) sgf = @"";
    cv::Mat m;
    draw_sgf( [sgf UTF8String], m, IMG_WIDTH);
    UIImage *res = MatToUIImage( m);
    return res;
}

// Find vertical grid lines
//----------------------------------
- (UIImage *) f01_vert_lines
{
    static int state = 0;
    if (!SZ(_vertical_lines)) state = 0;
    cv::Mat drawing;
    static std::vector<cv::Vec2f> all_vert_lines;
    
    switch (state) {
        case 0:
        {
            g_app.mainVC.lbBottom.text = @"verts";
            _vertical_lines = homegrown_vert_lines( _stone_or_empty);
            all_vert_lines = _vertical_lines;
            break;
        }
        case 1:
        {
            g_app.mainVC.lbBottom.text = @"dedup";
            dedup_verticals( _vertical_lines, _gray);
            break;
        }
        case 2:
        {
            g_app.mainVC.lbBottom.text = @"filter";
            filter_vert_lines( _vertical_lines);
            break;
        }
        case 3:
        {
            g_app.mainVC.lbBottom.text = @"fix";
            const double x_thresh = 4.0;
            fix_vertical_lines( _vertical_lines, all_vert_lines, _gray, x_thresh);
            break;
        }
        default:
            state = 0;
            return NULL;
    } // switch
    state++;
    
    // Show results
    cv::cvtColor( _gray, drawing, cv::COLOR_GRAY2RGB);
    get_color(true);
    ISLOOP( _vertical_lines) {
        draw_polar_line( _vertical_lines[i], drawing, get_color());
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f01_vert_lines()

// Find horizontal grid lines
//-----------------------------
- (UIImage *) f02_horiz_lines
{
    static int state = 0;
    if (!SZ(_horizontal_lines)) state = 0;

    cv::Mat drawing;
    
    switch (state) {
        case 0:
        {
            g_app.mainVC.lbBottom.text = @"horizontals";
            _horizontal_lines = homegrown_horiz_lines( _stone_or_empty);
            break;
        }
        case 1:
        {
            g_app.mainVC.lbBottom.text = @"dedup";
            dedup_horizontals( _horizontal_lines, _gray);
            break;
        }
        case 2:
        {
            g_app.mainVC.lbBottom.text = @"filter";
            filter_horiz_lines( _horizontal_lines);
            break;
        }
        case 3:
        {
            g_app.mainVC.lbBottom.text = @"fix";
            fix_horiz_lines( _horizontal_lines, _vertical_lines, _gray);
            break;
        }
        default:
            state = 0;
            return NULL;
    } // switch
    state++;
    
    // Show results
    cv::cvtColor( _gray, drawing, cv::COLOR_GRAY2RGB);
    get_color( true);
    ISLOOP (_horizontal_lines) {
        cv::Scalar col = get_color();
        draw_polar_line( _horizontal_lines[i], drawing, col);
    }
    //draw_polar_line( ratline, drawing, cv::Scalar( 255,128,64));
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f02_horiz_lines()


// Find the corners
//----------------------------
- (UIImage *) f03_corners
{
    g_app.mainVC.lbBottom.text = @"find corners";
    
    _intersections = get_intersections( _horizontal_lines, _vertical_lines);
    _corners.clear();
    do {
        if (SZ( _horizontal_lines) > 55) break;
        if (SZ( _horizontal_lines) < 5) break;
        if (SZ( _vertical_lines) > 55) break;
        if (SZ( _vertical_lines) < 5) break;
        _corners = find_corners( _stone_or_empty, _horizontal_lines, _vertical_lines,
                                _intersections, _small_pyr, _gray_threshed );
        // Intersections for only the board lines
        _intersections = get_intersections( _horizontal_lines, _vertical_lines);
    } while(0);
    
    UIImage *res = MatToUIImage( mat_dbg);
    return res;
} // f03_corners()

// Zoom in
//----------------------------
- (UIImage *) f04_zoom_in
{
    g_app.mainVC.lbBottom.text = @"zoom";
    cv::Mat threshed;
    cv::Mat dst;
    if (SZ(_corners) == 4) {
        cv::Mat M;
        zoom_in( _gray,  _corners, _gray_zoomed, M);
        zoom_in( _small_img, _corners, _small_zoomed, M);
        zoom_in( _small_pyr, _corners, _pyr_zoomed, M);
        cv::cvtColor( _pyr_zoomed, _pyr_gray, cv::COLOR_RGB2GRAY);
        cv::perspectiveTransform( _corners, _corners_zoomed, M);
        cv::perspectiveTransform( _intersections, _intersections_zoomed, M);
        fill_outside_with_average_gray( _gray_zoomed, _corners_zoomed);
        fill_outside_with_average_rgb( _small_zoomed, _corners_zoomed);
        fill_outside_with_average_rgb( _pyr_zoomed, _corners_zoomed);
        
        thresh_dilate( _gray_zoomed, _gz_threshed, 4);
    }
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _gz_threshed, drawing, cv::COLOR_GRAY2RGB);
    ISLOOP (_intersections_zoomed) {
        Point2f p = _intersections_zoomed[i];
        draw_square( p, 3, drawing, cv::Scalar(255,0,0));
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f04_zoom_in()

// Dark places to find B stones
//-----------------------------------------------------------
- (UIImage *) f05_dark_places
{
    g_app.mainVC.lbBottom.text = @"adaptive dark";
    //_corners = _corners_zoomed;
    
    cv::Mat dark_places;
    //cv::GaussianBlur( _gray_zoomed, dark_places, cv::Size(9,9),0,0);
    //cv::adaptiveThreshold( dark_places, dark_places, 255, CV_ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY_INV, 51, 50);
    cv::adaptiveThreshold( _pyr_gray, dark_places, 255, CV_ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY_INV, 51, 50);
    // Show results
    cv::Mat drawing;
    cv::cvtColor( dark_places, drawing, cv::COLOR_GRAY2RGB);
    ISLOOP (_intersections_zoomed) {
        Point2f p = _intersections_zoomed[i];
        draw_square( p, 3, drawing, cv::Scalar(255,0,0));
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f05_dark_places()

// Replace dark places with average to make white dynamic threshold work
//-----------------------------------------------------------------------
- (UIImage *) f06_mask_dark
{
    g_app.mainVC.lbBottom.text = @"hide dark";
    
    uint8_t mean = cv::mean( _pyr_gray)[0];
    cv::Mat black_places;
    cv::adaptiveThreshold( _pyr_gray, black_places, mean, CV_ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY_INV, 51, 50);
    _pyr_masked = _pyr_gray.clone();
    // Copy over if not zero
    _pyr_masked.forEach<uint8_t>( [&black_places](uint8_t &v, const int *p)
                                 {
                                     int row = p[0]; int col = p[1];
                                     if (auto p = black_places.at<uint8_t>( row,col)) {
                                         v = p;
                                     }
                                 });
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _pyr_masked, drawing, cv::COLOR_GRAY2RGB);
    ISLOOP (_intersections_zoomed) {
        Point2f p = _intersections_zoomed[i];
        draw_square( p, 3, drawing, cv::Scalar(255,0,0));
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f06_mask_dark()


// Find White places
//-------------------------------
- (UIImage *) f07_white_holes
{
    g_app.mainVC.lbBottom.text = @"adaptive bright";
    
    // The White stones become black holes, all else is white
    int nhood_sz =  25;
    double thresh = -32;
    cv::Mat white_holes;
    cv::adaptiveThreshold( _pyr_masked, white_holes, 255, cv::ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY_INV,
                          nhood_sz, thresh);
    
    // Show results
    cv::Mat drawing;
    cv::cvtColor( white_holes, drawing, cv::COLOR_GRAY2RGB);
    ISLOOP (_intersections_zoomed) {
        Point2f p = _intersections_zoomed[i];
        draw_square( p, 3, drawing, cv::Scalar(255,0,0));
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f07_white_holes()

// Visualize some features
//---------------------------
- (UIImage *) f08_features
{
    g_app.mainVC.lbBottom.text = @"brightness";
    static int state = 0;
    std::vector<double> feats;
    cv::Mat drawing;
    
    switch (state) {
        case 0:
        {
            // Gray mean
            const int r = 4;
            const int yshift = 0;
            const bool dontscale = false;
            classifier.get_feature( _pyr_gray, _intersections_zoomed, r,
                                   [](const cv::Mat &hood) { return cv::mean(hood)[0]; },
                                   feats, yshift, dontscale);
            viz_feature( _pyr_gray, _intersections_zoomed, feats, drawing, 1);
            break;
        }
        default:
            state = 0;
            return NULL;
    } // switch
    state++;
    
    // Show results
    cv::cvtColor( drawing, drawing, cv::COLOR_GRAY2RGB);
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f08_features()


// Classify intersections into black, white, empty
//-----------------------------------------------------------
- (UIImage *) f09_classify
{
    g_app.mainVC.lbBottom.text = @"classify";
    if (SZ(_corners_zoomed) != 4) { return MatToUIImage( _gray); }
    
    //std::vector<int> diagram;
    if (_small_zoomed.rows > 0) {
        //cv::Mat gray_blurred;
        //cv::GaussianBlur( _gray_zoomed, gray_blurred, cv::Size(5, 5), 2, 2 );
        const int TIME_BUF_SZ = 1;
        _diagram = classifier.frame_vote( _intersections_zoomed, _pyr_zoomed, _gray_zoomed, TIME_BUF_SZ);
    }
    fix_diagram( _diagram, _intersections, _small_img);
    
    // Show results
    cv::Mat drawing;
    //DrawBoard drb( _gray_zoomed, _corners_zoomed[0].y, _corners_zoomed[0].x, _board_sz);
    //drb.draw( _diagram);
    cv::cvtColor( _gray_zoomed, drawing, cv::COLOR_GRAY2RGB);
    
    Points2f dummy;
    get_intersections_from_corners( _corners_zoomed, _board_sz, dummy, _dx, _dy);
    int dx = ROUND( _dx/4.0);
    int dy = ROUND( _dy/4.0);
    ISLOOP (_diagram) {
        cv::Point p(ROUND(_intersections_zoomed[i].x), ROUND(_intersections_zoomed[i].y));
        cv::Rect rect( p.x - dx,
                      p.y - dy,
                      2*dx + 1,
                      2*dy + 1);
        cv::rectangle( drawing, rect, cv::Scalar(0,0,255,255));
        if (_diagram[i] == BBLACK) {
            draw_point( p, drawing, 2, cv::Scalar(0,255,0,255));
        }
        else if (_diagram[i] == WWHITE) {
            draw_point( p, drawing, 5, cv::Scalar(255,0,0,255));
        }
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f09_classify()


#pragma mark - Real time implementation
//========================================

// Recognize position in image. Result goes into _diagram.
// Returns true on success.
//----------------------------------------------------------------------------------------------
- (bool)recognize_position:(UIImage *)img timeVotes:(int)timeVotes breakIfBad:(bool)breakIfBad
{
    _board_sz = 19;
    bool success = false;
    do {
        UIImageToMat( img, _orig_img, false);
        resize( _orig_img, _small_img, IMG_WIDTH);
        cv::cvtColor( _small_img, _small_img, CV_RGBA2RGB);
        cv::cvtColor( _small_img, _gray, cv::COLOR_RGB2GRAY);
        thresh_dilate( _gray, _gray_threshed);
        
        // Find stones and intersections
        _stone_or_empty.clear();
        BlobFinder::find_empty_places( _gray_threshed, _stone_or_empty); // has to be first
        BlobFinder::find_stones( _gray, _stone_or_empty);
        _stone_or_empty = BlobFinder::clean( _stone_or_empty);
        if (breakIfBad && SZ(_stone_or_empty) < 0.8 * SQR(_board_sz)) break;
        
        // Break if not straight
        double theta = direction( _gray, _stone_or_empty) - PI/2;
        if (breakIfBad && fabs(theta) > 4 * PI/180) break;
        
        // Find vertical lines
        _vertical_lines = homegrown_vert_lines( _stone_or_empty);
        std::vector<cv::Vec2f> all_vert_lines = _vertical_lines;
        dedup_verticals( _vertical_lines, _gray);
        filter_vert_lines( _vertical_lines);
        const int x_thresh = 4.0;
        fix_vertical_lines( _vertical_lines, all_vert_lines, _gray, x_thresh);
        if (breakIfBad && SZ( _vertical_lines) > 55) break;
        if (breakIfBad && SZ( _vertical_lines) < 5) break;
        
        // Find horiz lines
        _horizontal_lines = homegrown_horiz_lines( _stone_or_empty);
        dedup_horizontals( _horizontal_lines, _gray);
        filter_horiz_lines( _horizontal_lines);
        fix_horiz_lines( _horizontal_lines, _vertical_lines, _gray);
        if (breakIfBad && SZ( _horizontal_lines) > 55) break;
        if (breakIfBad && SZ( _horizontal_lines) < 5) break;
        
        // Find corners
        _intersections = get_intersections( _horizontal_lines, _vertical_lines);
        cv::pyrMeanShiftFiltering( _small_img, _small_pyr, SPATIALRAD, COLORRAD, MAXPYRLEVEL );
        _corners.clear();
        if (SZ(_horizontal_lines) && SZ(_vertical_lines)) {
            _corners = find_corners( _stone_or_empty, _horizontal_lines, _vertical_lines,
                                    _intersections, _small_pyr, _gray_threshed);
        }
        // Intersections for only the board lines
        _intersections = get_intersections( _horizontal_lines, _vertical_lines);
        if (breakIfBad && !board_valid( _corners, _gray)) {
            break;
        }
        // Zoom in
        cv::Mat M;
        zoom_in( _gray,  _corners, _gray_zoomed, M);
        zoom_in( _small_pyr, _corners, _pyr_zoomed, M);
        cv::perspectiveTransform( _corners, _corners_zoomed, M);
        cv::perspectiveTransform( _intersections, _intersections_zoomed, M);
        fill_outside_with_average_gray( _gray_zoomed, _corners_zoomed);
        fill_outside_with_average_rgb( _pyr_zoomed, _corners_zoomed);
        
        // Classify
        _diagram = classifier.frame_vote( _intersections_zoomed, _pyr_zoomed, _gray_zoomed, timeVotes);
        fix_diagram( _diagram, _intersections, _small_img);
        
        // Copy diagram to NSMutableArray
        NSMutableArray *res = [NSMutableArray new];
        ISLOOP (_diagram) {
            [res addObject:@(_diagram[i])];
        }
        success = true;
    } while(0);
    return success;
} // recognize_position()

// Entry point for video mode, on each frame
//--------------------------------------------
- (UIImage *) video_mode:(UIImage *) img
{
    static std::vector<Points> boards; // Some history for averaging
    cv::Mat drawing;
    bool success = [self recognize_position:img timeVotes:10 breakIfBad:YES];

    // Draw real time results on screen
    //------------------------------------
    cv::Mat *canvas;
    canvas = &_small_img;
    
    static std::vector<cv::Vec2f> old_hlines, old_vlines;
    static Points2f old_corners, old_intersections;
    if (!success) {
        _horizontal_lines = old_hlines;
        _vertical_lines = old_vlines;
        _corners = old_corners;
        _intersections = old_intersections;
    }
    else {
        old_hlines = _horizontal_lines;
        old_vlines = _vertical_lines;
        old_corners = _corners;
        old_intersections = _intersections;
        _last_frame_with_board = _small_img.clone();
    }
    
    if (SZ(_corners) == 4) {
        draw_line( cv::Vec4f( _corners[0].x, _corners[0].y, _corners[1].x, _corners[1].y),
                  *canvas, cv::Scalar( 255,0,0,255));
        draw_line( cv::Vec4f( _corners[1].x, _corners[1].y, _corners[2].x, _corners[2].y),
                  *canvas, cv::Scalar( 255,0,0,255));
        draw_line( cv::Vec4f( _corners[2].x, _corners[2].y, _corners[3].x, _corners[3].y),
                  *canvas, cv::Scalar( 255,0,0,255));
        draw_line( cv::Vec4f( _corners[3].x, _corners[3].y, _corners[0].x, _corners[0].y),
                  *canvas, cv::Scalar( 255,0,0,255));
        
        // One horiz and vert line
        draw_polar_line( _horizontal_lines[SZ(_horizontal_lines)/2], *canvas, cv::Scalar( 255,255,0,255));
        draw_polar_line( _vertical_lines[SZ(_vertical_lines)/2], *canvas, cv::Scalar( 255,255,0,255));
        
        // Show classification result
        ISLOOP (_diagram) {
            cv::Point p(ROUND(_intersections[i].x), ROUND(_intersections[i].y));
            if (_diagram[i] == BBLACK) {
                draw_point( p, *canvas, 5, cv::Scalar(255,0,0,255));
            }
            else if (_diagram[i] == WWHITE) {
                draw_point( p, *canvas, 5, cv::Scalar(0,255,0,255));
            }
        }
        ISLOOP (_intersections) {
            draw_point( _intersections[i], *canvas, 2, cv::Scalar(0,0,255,255));
        }
    } // if (SZ(corners) == 4)
    
    UIImage *res = MatToUIImage( *canvas);
    //UIImage *res = MatToUIImage( drawing);
    return res;
} // video_mode()

// Get most recent frame with a Go board
//----------------------------------------
- (UIImage *) get_last_frame_with_board
{
    UIImage *res;
    if (_last_frame_with_board.cols) {
        res = MatToUIImage( _last_frame_with_board);
    }
    else {
        res = MatToUIImage( _small_img);
    }
    return res;
}

// Photo Mode. Find the best frame in the queue and process it.
//--------------------------------------------------------------
- (UIImage *) photo_mode
{
    // Pick best frame from Q
    cv::Mat best;
    int maxBlobs = -1E9;
    int bestidx = -1;
    ILOOP (SZ(_imgQ) - 1) { // ignore newest frame
        _small_img = _imgQ[i];
        cv::cvtColor( _small_img, _gray, cv::COLOR_RGB2GRAY);
        thresh_dilate( _gray, _gray_threshed);
        _stone_or_empty.clear();
        BlobFinder::find_empty_places( _gray_threshed, _stone_or_empty); // has to be first
        BlobFinder::find_stones( _gray, _stone_or_empty);
        _stone_or_empty = BlobFinder::clean( _stone_or_empty);
        if (SZ(_stone_or_empty) > maxBlobs) {
            maxBlobs = SZ(_stone_or_empty);
            best = _small_img;
            bestidx = i;
        }
    }
    UIImage *img = MatToUIImage( best);
    [self recognize_position:img timeVotes:1 breakIfBad:NO];
    return img;
} // photo_mode()

// Detect position on image and count erros
//------------------------------------------------------------
- (int) runTestImg:(UIImage *)img withSgf:(NSString *)sgf
{
    if (![self recognize_position:img timeVotes:1 breakIfBad:NO]) {
        return -1;
    }
    auto correct_diagram = sgf2vec([sgf UTF8String]);
    auto &detected_diagram = _diagram;
    assert( SZ(detected_diagram) == SZ(correct_diagram));
    int errcount = 0;
    ISLOOP (correct_diagram) {
        if (correct_diagram[i] != detected_diagram[i]) {
            errcount++;
        }
    }
    return errcount;
} // runTestImg()


@end





























