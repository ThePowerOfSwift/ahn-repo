//
//  GrabFuncs.mm
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
#import "AppDelegate.h"
#import "Globals.h"
#import "CppInterface.h"
//#import "LineFinder.hpp"
//#import "LineFixer.hpp"
#import "BlackWhiteEmpty.hpp"
#import "BlobFinder.hpp"
#import "Clust1D.hpp"
#import "DrawBoard.hpp"
#import "Boardness.hpp"

// Pyramid filter params
#define SPATIALRAD  5
#define COLORRAD    30
//#define COLORRAD    15
#define MAXPYRLEVEL 2
//#define MAXPYRLEVEL 1

extern cv::Mat mat_dbg;

@interface CppInterface()
//=======================
@property cv::Mat small; // resized image, in color, RGB
@property cv::Mat small_pyr; // resized image, in color, pyramid filtered
@property Points pyr_board; // Initial guess at board location

@property cv::Mat small_zoomed;  // small, zoomed into the board
@property cv::Mat gray;  // Grayscale version of small
@property cv::Mat gray_threshed;  // gray with inv_thresh and dilation
@property cv::Mat gray_zoomed;   // Grayscale version of small, zoomed into the board

@property cv::Mat gz_threshed; // gray_zoomed with inv_thresh and dilation
@property cv::Mat m;     // Mat with image we are working on
@property Contours cont; // Current set of contours
@property int board_sz; // board size, 9 or 19
@property Points stone_or_empty; // places where we suspect stones or empty
@property std::vector<cv::Vec2f> horizontal_lines;
@property std::vector<cv::Vec2f> vertical_lines;
@property Points2f corners;
@property Points2f corners_zoomed;
@property Points2f intersections;
@property Points2f intersections_zoomed;
@property float dy;
@property float dx;
//@property LineFinder finder;
@property std::vector<Points2f> boards; // history of board corners
@property cv::Mat white_templ;
@property cv::Mat black_templ;
@property cv::Mat empty_templ;
@property std::vector<int> diagram; // The position we detected


@end

@implementation CppInterface
//=========================

//----------------------
- (instancetype)init
{
    self = [super init];
    if (self) {
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
//---------------------------------------------
void load_img( NSString *fname, cv::Mat &m)
{
    UIImage *img = [UIImage imageNamed:fname];
    UIImageToMat(img, m);
}

// Reject board if opposing lines not parallel
// or adjacent lines not at right angles
//-----------------------------------------------------
bool board_valid( Points2f board, const cv::Mat &img)
{
    float screenArea = img.rows * img.cols;
    if (board.size() != 4) return false;
    float area = cv::contourArea(board);
    if (area / screenArea > 0.95) return false;
    if (area / screenArea < 0.20) return false;

    float par_ang1   = (180.0 / M_PI) * angle_between_lines( board[0], board[1], board[3], board[2]);
    float par_ang2   = (180.0 / M_PI) * angle_between_lines( board[0], board[3], board[1], board[2]);
    float right_ang1 = (180.0 / M_PI) * angle_between_lines( board[0], board[1], board[1], board[2]);
    float right_ang2 = (180.0 / M_PI) * angle_between_lines( board[0], board[3], board[3], board[2]);
    //float horiz_ang   = (180.0 / M_PI) * angle_between_lines( board[0], board[1], cv::Point(0,0), cv::Point(1,0));
    //NSLog(@"%f.2, %f.2, %f.2, %f.2", par_ang1,  par_ang2,  right_ang1,  right_ang2 );
    //if (abs(horiz_ang) > 20) return false;
    if (abs(par_ang1) > 10) return false;
    if (abs(par_ang2) > 10) return false;
    if (abs(right_ang1 - 90) > 10) return false;
    if (abs(right_ang2 - 90) > 10) return false;
    return true;
}

// Apply inverse thresh and dilate grayscale image.
//---------------------------------------------------------
void thresh_dilate( const cv::Mat &img, cv::Mat &dst, int thresh = 8)
{
    cv::adaptiveThreshold( img, dst, 255, cv::ADAPTIVE_THRESH_MEAN_C, cv::THRESH_BINARY_INV,
                          5 /* 11 */ ,  // neighborhood_size
                          thresh);  // threshold
    cv::Mat element = cv::getStructuringElement( cv::MORPH_RECT, cv::Size(3,3));
    cv::dilate( dst, dst, element );
}

#pragma mark - Processing Pipeline for debugging
//=================================================

//--------------------------
- (UIImage *) f00_blobs: (std::vector<cv::Mat>)imgQ
{
    _board_sz=19;
    g_app.mainVC.lbDbg.text = @"00";
    
#define FFILE
#ifdef FFILE
    load_img( @"board03.jpg", _m);
    cv::rotate(_m, _m, cv::ROTATE_90_CLOCKWISE);
    resize( _m, _small, 350);
    cv::cvtColor( _small, _small, CV_RGBA2RGB); // Yes, RGB not BGR
#else
    // Camera
    //-----------
    // Pick best frame from Q
    cv::Mat best;
    int maxBlobs = -1E9;
    int bestidx = -1;
    ILOOP (SZ(imgQ) - 1) { // ignore newest frame
        _small = imgQ[i];
        cv::cvtColor( _small, _gray, cv::COLOR_RGB2GRAY);
        thresh_dilate( _gray, _gray_threshed);
        _stone_or_empty.clear();
        BlobFinder::find_empty_places( _gray_threshed, _stone_or_empty); // has to be first
        BlobFinder::find_stones( _gray, _stone_or_empty);
        _stone_or_empty = BlobFinder::clean( _stone_or_empty);
        if (SZ(_stone_or_empty) > maxBlobs) {
            maxBlobs = SZ(_stone_or_empty);
            best = _small;
            bestidx = i;
        }
    }
    PLOG("best idx %d\n", bestidx);
    // Reproces the best one
    _small = best;
#endif
    cv::cvtColor( _small, _gray, cv::COLOR_RGB2GRAY);
    thresh_dilate( _gray, _gray_threshed);
    _stone_or_empty.clear();
    BlobFinder::find_empty_places( _gray_threshed, _stone_or_empty); // has to be first
    BlobFinder::find_stones( _gray, _stone_or_empty);
    _stone_or_empty = BlobFinder::clean( _stone_or_empty);

    cv::pyrMeanShiftFiltering( _small, _small_pyr, SPATIALRAD, COLORRAD, MAXPYRLEVEL );

    // Show results
    cv::Mat drawing = _small_pyr.clone();
    draw_points( _stone_or_empty, drawing, 2, cv::Scalar( 255,0,0));
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f00_blobs()



// Thin down vertical Hough lines
//----------------------------------
- (UIImage *) f02_vert_lines
{
    g_app.mainVC.lbDbg.text = @"03";
    _vertical_lines = homegrown_vert_lines( _stone_or_empty);
    
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _gray, drawing, cv::COLOR_GRAY2RGB);
    get_color(true);
    ISLOOP( _vertical_lines) {
        //if (i<400) continue;
        draw_polar_line( _vertical_lines[i], drawing, cv::Scalar(255,0,0));
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f03_vert_lines()

// Replace close clusters of vert lines by their average.
//-----------------------------------------------------------------------------------
void dedup_vertical_lines( std::vector<cv::Vec2f> &lines, const cv::Mat &img)
{
    // Cluster by x in the middle
    const float wwidth = 32.0;
    const float middle_y = img.rows / 2.0;
    const int min_clust_size = 0;
    auto Getter =  [middle_y](cv::Vec2f line) { return x_from_y( middle_y, line); };
    auto vert_line_cuts = Clust1D::cluster( lines, wwidth, Getter);
    std::vector<std::vector<cv::Vec2f> > clusters;
    Clust1D::classify( lines, vert_line_cuts, min_clust_size, Getter, clusters);
    
    // Average the clusters into single lines
    lines.clear();
    ISLOOP (clusters) {
        auto &clust = clusters[i];
        double theta = vec_avg( clust, [](cv::Vec2f line){ return line[1]; });
        double rho   = vec_avg( clust, [](cv::Vec2f line){ return line[0]; });
        cv::Vec2f line( rho, theta);
        lines.push_back( line);
    }
}

// Replace close clusters of horiz lines by their average.
//-----------------------------------------------------------------------------------
void dedup_horiz_lines( std::vector<cv::Vec2f> &lines, const cv::Mat &img)
{
    // Cluster by y in the middle
    const float wwidth = 32.0;
    const float middle_x = img.cols / 2.0;
    const int min_clust_size = 0;
    auto Getter =  [middle_x](cv::Vec2f line) { return y_from_x( middle_x, line); };
    auto horiz_line_cuts = Clust1D::cluster( lines, wwidth, Getter);
    std::vector<std::vector<cv::Vec2f> > clusters;
    Clust1D::classify( lines, horiz_line_cuts, min_clust_size, Getter, clusters);
    
    // Average the clusters into single lines
    lines.clear();
    ISLOOP (clusters) {
        auto &clust = clusters[i];
        double theta = vec_avg( clust, [](cv::Vec2f line){ return line[1]; });
        double rho   = vec_avg( clust, [](cv::Vec2f line){ return line[0]; });
        cv::Vec2f line( rho, theta);
        lines.push_back( line);
    }
}

// Cluster vertical Hough lines to remove close duplicates.
//------------------------------------------------------------
- (UIImage *) f03_vert_lines_2
{
    g_app.mainVC.lbDbg.text = @"04";
    dedup_vertical_lines( _vertical_lines, _gray);
    
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _gray, drawing, cv::COLOR_GRAY2RGB);
    get_color(true);
    ISLOOP( _vertical_lines) {
        draw_polar_line( _vertical_lines[i], drawing, get_color());
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
}

// Find the change per line in rho and theta and synthesize the whole bunch
// starting at the middle. Replace synthesized lines with real ones if close enough.
//----------------------------------------------------------------------------------
void fix_vertical_lines( std::vector<cv::Vec2f> &lines, const cv::Mat &img)
{
    const float middle_y = img.rows / 2.0;
    const float width = img.cols;
    
    auto rhos   = vec_extract( lines, [](cv::Vec2f line) { return line[0]; } );
    auto thetas = vec_extract( lines, [](cv::Vec2f line) { return line[1]; } );
    auto xes    = vec_extract( lines, [middle_y](cv::Vec2f line) { return x_from_y( middle_y, line); });
    auto d_rhos   = vec_delta( rhos);
    auto d_thetas = vec_delta( thetas);
    auto d_rho   = vec_median( d_rhos);
    auto d_theta = vec_median( d_thetas);
    
    // Find a line close to the middle where theta is close to median theta
    float med_theta = vec_median(thetas);
    PLOG( "med v theta %.2f\n", med_theta);
    int half = SZ(lines)/2;
    if (SZ(lines) % 2 == 0) half--;  // 5 -> 2; 4 -> 1
    float EPS = PI / 180;
    cv::Vec2f med_line(0,0);
    ILOOP (half+1) {
        PLOG( "theta %.2f\n", thetas[half+i]);
        if (fabs( med_theta - thetas[half+i]) < EPS) {
            med_line = lines[half+i];
            PLOG("match at %d\n", i);
            break;
        }
        PLOG( "theta %.2f\n", thetas[half-i]);
        if (fabs( med_theta - thetas[half-i]) < EPS) {
            med_line = lines[half-i];
            PLOG("match at %d\n", i);
            break;
        }
    }
    if (med_line[0] == 0) { // found none
        lines.clear();
        return;
    }
    
    // Interpolate the rest
    std::vector<cv::Vec2f> synth_lines;
    synth_lines.push_back(med_line);
    float rho, theta;
    // If there is a close line, use it. Else interpolate.
    const float X_THRESH = 3; //6;
    const float THETA_THRESH = PI / 180;
    // Lines to the right
    rho = med_line[0];
    theta = med_line[1];
    ILOOP(100) {
        if (!i) continue;
        rho += d_rho;
        theta += d_theta;
        float x = x_from_y( middle_y, cv::Vec2f( rho, theta));
        int close_idx = vec_closest( xes, x);
        if (fabs( x - xes[close_idx]) < X_THRESH &&
            fabs( theta - thetas[close_idx]) < THETA_THRESH)
        {
            rho   = lines[close_idx][0];
            theta = lines[close_idx][1];
        }
        if (rho == 0) break;
        cv::Vec2f line( rho,theta);
        if (x_from_y( middle_y, line) > width) break;
        synth_lines.push_back( line);
    }
    // Lines to the left
    rho = med_line[0];
    theta = med_line[1];
    ILOOP(100) {
        if (!i) continue;
        rho -= d_rho;
        theta -= d_theta;
        float x = x_from_y( middle_y, cv::Vec2f( rho, theta));
        int close_idx = vec_closest( xes, x);
        if (fabs( x - xes[close_idx]) < X_THRESH &&
            fabs( theta - thetas[close_idx]) < THETA_THRESH)
        {
            rho   = lines[close_idx][0];
            theta = lines[close_idx][1];
        }
        if (rho == 0) break;
        cv::Vec2f line( rho,theta);
        if (x_from_y( middle_y, line) < 0) break;
        synth_lines.push_back( line);
    }
    std::sort( synth_lines.begin(), synth_lines.end(),
              [middle_y](cv::Vec2f line1, cv::Vec2f line2) {
                  return x_from_y( middle_y, line1) < x_from_y( middle_y, line2);
              });
    
    lines = synth_lines;
} // fix_vertical_lines()

// Find the median distance between vert lines for given y.
// We use that to find the adjacent horizontal lines next to y.
// The idea is that on a grid, horizontal and vertical spacing are the same,
// and if we know one, we know the other.
//-----------------------------------------------------------------------------
float hspace_at_y( float y, const std::vector<cv::Vec2f> &vert_lines)
{
    std::vector<float> dists;
    Point2f prev;
    ISLOOP (vert_lines) {
        cv::Vec4f seg = polar2segment( vert_lines[i]);
        Point2f p = intersection( seg, cv::Vec4f( 0, y, 1000, y));
        if (i) {
            float d = cv::norm( p - prev);
            dists.push_back( d);
        }
        prev = p;
    }
    float res = vec_median( dists);
    return res;
} // hspace_at_y()

// Find the change per line in rho and theta and synthesize the whole bunch
// starting at the middle. Replace synthesized lines with real ones if close enough.
//---------------------------------------------------------------------------------------------
void fix_horiz_lines( std::vector<cv::Vec2f> &lines_, const std::vector<cv::Vec2f> &vert_lines,
                     const cv::Mat &img) //@@@
{
    const float middle_x = img.cols / 2.0;
    const float height = img.rows;
    
    // Convert hlines to clines (center y + angle)
    std::vector<cv::Vec2f> lines;
    ISLOOP (lines_) {
        lines.push_back( polar2cangle( lines_[i], middle_x));
    }
    
    auto rhos   = vec_extract( lines, [](cv::Vec2f line) { return line[0]; } );
    auto thetas = vec_extract( lines, [](cv::Vec2f line) { return line[1]; } );
    auto d_rhos   = vec_delta( rhos);
    
    // Find a line close to the middle where theta is close to median theta
    float med_theta = vec_median(thetas);
    PLOG( "med h theta %.2f\n", med_theta);
    int half = SZ(lines)/2;
    if (SZ(lines) % 2 == 0) half--;  // 5 -> 2; 4 -> 1
    float EPS = PI / 180;
    cv::Vec2f med_line(0,0); int med_idx = 0;
    ILOOP (half+1) {
        PLOG( "theta %.2f\n", thetas[half+i]);
        if (fabs( med_theta - thetas[half+i]) < EPS) {
            med_idx = half+i;
            med_line = lines[med_idx];
            PLOG("match at %d\n", i);
            break;
        }
        PLOG( "theta %.2f\n", thetas[half-i]);
        if (fabs( med_theta - thetas[half-i]) < EPS) {
            med_idx = half-i;
            med_line = lines[med_idx];
            PLOG("match at %d\n", i);
            break;
        }
    } // ILOOP
    if (med_line[0] == 0) { // found none
        lines.clear();
        return;
    }
    // Interpolate the rest
    float hvrat = 1.0; float d_rho = 0;
    std::vector<cv::Vec2f> synth_lines;
    synth_lines.push_back(med_line);
    float rho, theta;
    
    // If there is a close line, use it. Else interpolate.
    const float Y_THRESH = 3; // 6;
    const float THETA_THRESH = PI / 180;
    // Lines below
    d_rho   = vec_median( d_rhos);
    if (med_idx+1 < SZ(lines)) {
        d_rho = fabs( med_line[0] - lines[med_idx+1][0]);
    }
    if (hspace_at_y( med_line[0], vert_lines) > 0) {
        hvrat = d_rho / hspace_at_y( med_line[0], vert_lines);
    }

    rho = med_line[0];
    theta = med_line[1];
    ILOOP(100) {
        if (!i) continue;
        float d_rho = hvrat * hspace_at_y( rho, vert_lines);
        PLOG( "below %d d_rho %.2f\n", i, d_rho);
        rho += d_rho;
        int close_idx = vec_closest( rhos, rho);
        if (fabs( rho - rhos[close_idx]) < Y_THRESH &&
            fabs( theta - thetas[close_idx]) < THETA_THRESH)
        {
            rho   = lines[close_idx][0];
            theta = lines[close_idx][1];
        }
        if (rho > height) break;
        cv::Vec2f line( rho,theta);
        synth_lines.push_back( line);
    }
    // Lines above
    d_rho   = vec_median( d_rhos);
    if (med_idx > 0) {
        d_rho = fabs( med_line[0] - lines[med_idx-1][0]);
    }
    if (hspace_at_y( med_line[0], vert_lines) > 0) {
        hvrat = d_rho / hspace_at_y( med_line[0], vert_lines);
    }

    rho = med_line[0];
    theta = med_line[1];
    ILOOP(100) {
        if (!i) continue;
        float d_rho = hvrat * hspace_at_y( rho, vert_lines);
        PLOG( "above %d d_rho %.2f\n", i, d_rho);
        rho -= d_rho;
        int close_idx = vec_closest( rhos, rho);
        if (fabs( rho - rhos[close_idx]) < Y_THRESH &&
            fabs( theta - thetas[close_idx]) < THETA_THRESH)
        {
            PLOG( "above repl %d\n", i);
            rho   = lines[close_idx][0];
            theta = lines[close_idx][1];
        }
        if (rho < 0) break;
        cv::Vec2f line( rho,theta);
        synth_lines.push_back( line);
    } // ILOOP
    std::sort( synth_lines.begin(), synth_lines.end(),
              [](cv::Vec2f line1, cv::Vec2f line2) {
                  return line1[0] < line2[0];
              });
    lines_.clear();
    ISLOOP (synth_lines) { lines_.push_back( cangle2polar( synth_lines[i], middle_x)); }
} // fix_horiz_lines()


// Find vertical line parameters
//---------------------------------
- (UIImage *) f04_vert_params
{
    g_app.mainVC.lbDbg.text = @"05";
    fix_vertical_lines( _vertical_lines, _gray);
    
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _gray, drawing, cv::COLOR_GRAY2RGB);
    get_color(true);
    ISLOOP( _vertical_lines) {
        draw_polar_line( _vertical_lines[i], drawing, get_color());
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f05_vert_params()

// Convert horizontal (roughly) polar line to a pair
// y_at_middle, angle
//--------------------------------------------------------------
cv::Vec2f polar2cangle( const cv::Vec2f pline, float middle_x)
{
    cv::Vec2f res;
    float y_at_middle = y_from_x( middle_x, pline);
    float angle;
    angle = -(pline[1] - PI/2);
    res = cv::Vec2f( y_at_middle, angle);
    return res;
}

// Convert a pair (y_at_middle, angle) to polar
//---------------------------------------------------------------
cv::Vec2f cangle2polar( const cv::Vec2f cline, float middle_x)
{
    cv::Vec2f res;
    cv::Vec4f seg( middle_x, cline[0], middle_x + 1, cline[0] - tan(cline[1]));
    res = segment2polar( seg);
    return res;
}

//-----------------------------
- (UIImage *) f05_horiz_lines
{
    g_app.mainVC.lbDbg.text = @"02";
    
    _horizontal_lines = homegrown_horiz_lines( _stone_or_empty);
    dedup_horiz_lines( _horizontal_lines, _gray);
    fix_horiz_lines( _horizontal_lines, _vertical_lines, _gray);
    
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _gray, drawing, cv::COLOR_GRAY2RGB);
    get_color( true);
    ISLOOP (_horizontal_lines) {
        cv::Scalar col = get_color();
        draw_polar_line( _horizontal_lines[i], drawing, col);
    }
    //draw_polar_line( ratline, drawing, cv::Scalar( 255,128,64));
    UIImage *res = MatToUIImage( drawing);
    return res;
}

//--------------------------------------------------------
int count_points_on_line( cv::Vec2f line, Points pts)
{
    int res = 0;
    for (auto p:pts) {
        float d = fabs(dist_point_line( p, line));
        if (d < 0.75) {
            res++;
        }
    }
    return res;
}

// Find a vertical line thru pt which hits a lot of other points
// PRECONDITION: allpoints must be sorted by y
//------------------------------------------------------------------
cv::Vec2f find_vert_line_thru_point( const Points &allpoints, cv::Point pt)
{
    // Find next point below.
    //const float RHO_EPS = 10;
    const float THETA_EPS = 10 * PI / 180;
    int maxhits = -1;
    cv::Vec2f res;
    for (auto p: allpoints) {
        if (p.y <= pt.y) continue;
        Points pts = { pt, p };
        //cv::Vec2f newline = fit_pline( pts);
        cv::Vec2f newline = segment2polar( cv::Vec4f( pt.x, pt.y, p.x, p.y));
        if (fabs(newline[1]) < THETA_EPS ) {
            int nhits = count_points_on_line( newline, allpoints);
            if (nhits > maxhits) {
                maxhits = nhits;
                res = newline;
            }
        }
    }
    //PLOG( "maxhits:%d\n", maxhits);
    //int tt = count_points_on_line( res, allpoints);
    return res;
} // find_vert_line_thru_point()

// Find a horiz line thru pt which hits a lot of other points
// PRECONDITION: allpoints must be sorted by x
//------------------------------------------------------------------
cv::Vec2f find_horiz_line_thru_point( const Points &allpoints, cv::Point pt)
{
    // Find next point to the right.
    //const float RHO_EPS = 10;
    const float THETA_EPS = 5 * PI / 180;
    int maxhits = -1;
    cv::Vec2f res = {0,0};
    for (auto p: allpoints) {
        if (p.x <= pt.x) continue;
        Points pts = { pt, p };
        //cv::Vec2f newline = fit_pline( pts);
        cv::Vec2f newline = segment2polar( cv::Vec4f( pt.x, pt.y, p.x, p.y));
        if (fabs( fabs( newline[1]) - PI/2) < THETA_EPS ) {
            int nhits = count_points_on_line( newline, allpoints);
            if (nhits > maxhits) {
                maxhits = nhits;
                res = newline;
            }
        }
    }
    return res;
} // find_horiz_line_thru_point()

// Homegrown method to find vertical line candidates, as a replacement
// for thinning Hough lines.
//-----------------------------------------------------------------------------
std::vector<cv::Vec2f> homegrown_vert_lines( Points pts)
{
    std::vector<cv::Vec2f> res;
    // Find points in quartile with lowest y
    std::sort( pts.begin(), pts.end(), [](Point2f p1, Point2f p2) { return p1.y < p2.y; } );
    Points top_points( SZ(pts)/4);
    std::copy_n ( pts.begin(), SZ(pts)/4, top_points.begin() );
    // For each point, find a line that hits many other points
    for (auto tp: top_points) {
        cv::Vec2f newline = find_vert_line_thru_point( pts, tp);
        if (newline[0] != 0) {
            res.push_back( newline);
        }
    }
    return res;
} // homegrown_vert_lines()

// Homegrown method to find horizontal line candidates
//-----------------------------------------------------------------------------
std::vector<cv::Vec2f> homegrown_horiz_lines( Points pts)
{
    std::vector<cv::Vec2f> res;
    // Find points in quartile with lowest x
    std::sort( pts.begin(), pts.end(), [](Point2f p1, Point2f p2) { return p1.x < p2.x; } );
    Points left_points( SZ(pts)/4);
    std::copy_n ( pts.begin(), SZ(pts)/4, left_points.begin() );
    // For each point, find a line that hits many other points
    for (auto tp: left_points) {
        cv::Vec2f newline = find_horiz_line_thru_point( pts, tp);
        if (newline[0] != 0) {
            res.push_back( newline);
        }
    }
    return res;
} // homegrown_horiz_lines()


// Among the largest two in m1, choose the on where m2 is larger
//------------------------------------------------------------------
cv::Point tiebreak( const cv::Mat &m1, const cv::Mat &m2)
{
    cv::Mat tmp = m1.clone();
    double m1min, m1max;
    cv::Point m1minloc, m1maxloc;
    cv::minMaxLoc( tmp, &m1min, &m1max, &m1minloc, &m1maxloc);
    cv::Point largest = m1maxloc;
    tmp.at<uint8_t>(largest) = 0;
    cv::minMaxLoc( tmp, &m1min, &m1max, &m1minloc, &m1maxloc);
    cv::Point second = m1maxloc;
    
    cv::Point res = largest;
    if (m2.at<uint8_t>(second) > m2.at<uint8_t>(largest)) {
        res = second;
    }
    return res;
} // tiebreak

// Use horizontal and vertical lines to find corners such that the board best matches the points we found
//-----------------------------------------------------------------------------------------------------------
Points2f find_corners( const Points blobs, std::vector<cv::Vec2f> &horiz_lines, std::vector<cv::Vec2f> &vert_lines, 
                     const Points2f &intersections, const cv::Mat &img, const cv::Mat &threshed, int board_sz = 19)
{
    if (SZ(horiz_lines) < 3 || SZ(vert_lines) < 3) return Points2f();
    
    Boardness bness( intersections, blobs, img, board_sz, horiz_lines, vert_lines);
    cv::Mat &edgeness = bness.edgeness();
    cv::Mat &blobness = bness.blobness();
    //float edgeweight = 0.0, blobweight = 1.0;
    //cv::Mat both = mat_sumscale( edgeness, blobness, edgeweight, blobweight);
    //cv::Point min_loc, max_loc;
    //double mmin, mmax;
    //cv::minMaxLoc(both, &mmin, &mmax, &min_loc, &max_loc);
    cv::Mat &both = blobness;
    cv::Point max_loc = tiebreak( blobness, edgeness);

    cv::Point tl = max_loc;
    cv::Point tr( tl.x + board_sz-1, tl.y);
    cv::Point br( tl.x + board_sz-1, tl.y + board_sz-1);
    cv::Point bl( tl.x, tl.y + board_sz-1);
    
    // Return the board lines only
    horiz_lines = vec_slice( horiz_lines, max_loc.y, board_sz);
    vert_lines  = vec_slice( vert_lines, max_loc.x, board_sz);
    
    // Mark corners for visualization
    mat_dbg = bness.m_pyrpix.clone();
    mat_dbg.at<cv::Vec3b>( pf2p(tl)) = cv::Vec3b( 255,0,0);
    mat_dbg.at<cv::Vec3b>( pf2p(br)) = cv::Vec3b( 255,0,0);
    cv::resize( mat_dbg, mat_dbg, img.size(), 0,0, CV_INTER_NN);

    auto isec2pf = [&both, &intersections](cv::Point p) { return p2pf( intersections[p.y*both.cols + p.x]); };
    Points2f corners = { isec2pf(tl), isec2pf(tr), isec2pf(br), isec2pf(bl) };
    return corners;
} // find_corners()

// Get intersections of two sets of lines
//-------------------------------------------------------------------
Points2f get_intersections( const std::vector<cv::Vec2f> &hlines,
                           const std::vector<cv::Vec2f> &vlines)
{
    Points2f res;
    RSLOOP( hlines) {
        cv::Vec2f hl = hlines[r];
        CSLOOP( vlines) {
            cv::Vec2f vl = vlines[c];
            Point2f pf = intersection( hl, vl);
            res.push_back( pf);
        }
    }
    return res;
}

// Find the corners
//----------------------------
- (UIImage *) f06_corners
{
    g_app.mainVC.lbDbg.text = @"06";

    auto intersections = get_intersections( _horizontal_lines, _vertical_lines);
    //auto crosses = find_crosses( _gray_threshed, intersections);
    _corners.clear();
    do {
        if (SZ( _horizontal_lines) > 45) break;
        if (SZ( _horizontal_lines) < 5) break;
        if (SZ( _vertical_lines) > 35) break;
        if (SZ( _vertical_lines) < 5) break;
        _corners = find_corners( _stone_or_empty, _horizontal_lines, _vertical_lines,
                                intersections, _small_pyr, _gray_threshed );
    } while(0);
    
    // Show results
    //cv::Mat drawing = _small_pyr.clone();
    //cv::Mat drawing; cv::cvtColor( mat_dbg, drawing, cv::COLOR_GRAY2RGB);
    //mat_dbg.convertTo( mat_dbg, CV_8UC1);
    //cv::cvtColor( mat_dbg, drawing, cv::COLOR_GRAY2RGB);
    //float alpha = 0.5;
    //cv::addWeighted( _small, alpha, drawing, 1-alpha, 0, drawing);
    //draw_points( _corners, drawing, 3, cv::Scalar(255,0,0));
    UIImage *res = MatToUIImage( mat_dbg);
    return res;
} // f06_corners()

// Unwarp the square defined by corners
//------------------------------------------------------------------------
void zoom_in( const cv::Mat &img, const Points2f &corners, cv::Mat &dst, cv::Mat &M)
{
    int marg = img.cols / 20;
    // Target square for transform
    Points2f square = {
        cv::Point( marg, marg),
        cv::Point( img.cols - marg, marg),
        cv::Point( img.cols - marg, img.cols - marg),
        cv::Point( marg, img.cols - marg) };
    M = cv::getPerspectiveTransform(corners, square);
    cv::warpPerspective(img, dst, M, cv::Size( img.cols, img.rows));
}

// Zoom in
//----------------------------
- (UIImage *) f07_zoom_in
{
    g_app.mainVC.lbDbg.text = @"07";
    cv::Mat threshed;
    cv::Mat dst;
    if (SZ(_corners) == 4) {
        cv::Mat M;
        zoom_in( _gray,  _corners, _gray_zoomed, M);
        zoom_in( _small, _corners, _small_zoomed, M);
        cv::perspectiveTransform( _corners, _corners_zoomed, M);
        thresh_dilate( _gray_zoomed, _gz_threshed, 4);
    }
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _gray_zoomed, drawing, cv::COLOR_GRAY2RGB);
    UIImage *res = MatToUIImage( drawing);
    return res;
}

// Repeat whole process 01 to 06 on the zoomed in version
//-----------------------------------------------------------
- (UIImage *) f08_show_threshed
{
    g_app.mainVC.lbDbg.text = @"08";
    _corners = _corners_zoomed;
    
    // Show results
    cv::Mat drawing;
//    int s = 2*BlackWhiteEmpty::RING_R+1;
//    cv::Rect re( 100, 100, s, s);
//    BlackWhiteEmpty::ringmask().copyTo( _gz_threshed( re));
    cv::cvtColor( _gz_threshed, drawing, cv::COLOR_GRAY2RGB);
    //cv::cvtColor( _hue_zoomed, drawing, cv::COLOR_GRAY2RGB);
    draw_points( _corners, drawing, 3, cv::Scalar(255,0,0));
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f08_repeat_on_zoomed()

// Intersections on zoomed from corners
//----------------------------------------
- (UIImage *) f09_intersections
{
    g_app.mainVC.lbDbg.text = @"09";
    
    if (SZ(_corners_zoomed) == 4) {
        get_intersections_from_corners( _corners_zoomed, _board_sz, _intersections_zoomed, _dx, _dy);
    }
    
    // Show results
    cv::Mat drawing;
    cv::cvtColor( _gray_zoomed, drawing, cv::COLOR_GRAY2RGB);
    draw_points( _intersections_zoomed, drawing, 1, cv::Scalar(255,0,0));
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f09_intersections()

// Visualize features, one per intersection.
//------------------------------------------------------------------------------------------------------
void viz_feature( const cv::Mat &img, const Points2f &intersections, const std::vector<float> features,
                 cv::Mat &dst, const float multiplier = 255)
{
    dst = cv::Mat::zeros( img.size(), img.type());
    ISLOOP (intersections) {
        auto pf = intersections[i];
        float feat = features[i];
        auto hood = make_hood( pf, 5, 5);
        if (check_rect( hood, img.rows, img.cols)) {
            dst( hood) = fmin( 255, feat * multiplier);
        }
    }
} // viz_feature()

// Visualize some features
//---------------------------
- (UIImage *) f10_features
{
    g_app.mainVC.lbDbg.text = @"10";
    static int state = 0;
    std::vector<float> feats;
    cv::Mat drawing;
    int r;

    switch (state) {
        case 0:
        {
            r=11;
            BlackWhiteEmpty::get_feature( _gz_threshed, _intersections_zoomed, r,
                                         BlackWhiteEmpty::sum_feature, feats);
            viz_feature( _gz_threshed, _intersections_zoomed, feats, drawing, 1);
            break;
        }
        default:
            state = 0;
            return NULL;
    } // switch
    state++;
    
    // Show results
    cv::cvtColor( drawing, drawing, cv::COLOR_GRAY2RGB);
    //cv::cvtColor( mat_dbg, drawing, cv::COLOR_GRAY2RGB);
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f10_features()

// Translate a bunch of points
//----------------------------------------------------------------
void translate_points( const Points2f &pts, int dx, int dy, Points2f &dst)
{
    dst = Points2f(SZ(pts));
    ISLOOP (pts) {
        dst[i] = Point2f( pts[i].x + dx, pts[i].y + dy);
    }
}

//------------------------------------------------------------------------------------------------------
std::vector<int> classify( const Points2f &intersections_, const cv::Mat &img, const cv::Mat &threshed,
                          float dx, float dy,
                          int TIMEBUFSZ = 1)
{
    Points2f intersections;
    std::vector<std::vector<int> > diagrams;
    // Wiggle the regions a little.
    translate_points( intersections_, 0, 0, intersections);
    float match_quality;
    diagrams.push_back( BlackWhiteEmpty::classify( img, threshed,
                                                  intersections, match_quality));
    //    intersections = translate_points( intersections_, -1, 0);
    //    diagrams.push_back( BlackWhiteEmpty::classify( gray_normed,
    //                                                  intersections, match_quality));
    
    // Vote across wiggle
    std::vector<int> diagram; // vote result
    ISLOOP( diagrams[0]) {
        std::vector<int> votes(4,0);
        for (auto d:diagrams) {
            int idx = d[i];
            votes[idx]++;
        }
        int winner = argmax( votes);
        int tt = 42;
        diagram.push_back( winner);
        tt = 43;
    }
    // Vote across time
    static std::vector<std::vector<int> > timevotes(19*19);
    assert( SZ(diagram) <= 19*19);
    ISLOOP (diagram) {
        ringpush( timevotes[i], diagram[i], TIMEBUFSZ);
    }
    ISLOOP (timevotes) {
        std::vector<int> counts( BlackWhiteEmpty::DONTKNOW, 0); // index is bwe
        for (int bwe: timevotes[i]) { ++counts[bwe]; }
        int winner = argmax( counts);
        diagram[i] = winner;
    }
    
    return diagram;
} // classify()

// Classify intersections into black, white, empty
//-----------------------------------------------------------
- (UIImage *) f11_classify
{
    g_app.mainVC.lbDbg.text = @"11";
    if (SZ(_corners_zoomed) != 4) { return MatToUIImage( _gray); }
    
    std::vector<int> diagram;
    if (_small_zoomed.rows > 0) {
        //cv::Mat gray_blurred;
        //cv::GaussianBlur( _gray_zoomed, gray_blurred, cv::Size(5, 5), 2, 2 );
        diagram = classify( _intersections_zoomed, _gray_zoomed, _gz_threshed, _dx, _dy, 1);
    }
    
    // Show results
    cv::Mat drawing;
    DrawBoard drb( _gray_zoomed, _corners_zoomed[0].y, _corners_zoomed[0].x, _board_sz);
    drb.draw( diagram);
    //cv::cvtColor( _gray_zoomed, drawing, cv::COLOR_GRAY2RGB);
    cv::cvtColor( _gray_zoomed, drawing, cv::COLOR_GRAY2RGB);

    int dx = ROUND( _dx/4.0);
    int dy = ROUND( _dy/4.0);
    ISLOOP (diagram) {
        cv::Point p(ROUND(_intersections_zoomed[i].x), ROUND(_intersections_zoomed[i].y));
        cv::Rect rect( p.x - dx,
                      p.y - dy,
                      2*dx + 1,
                      2*dy + 1);
        cv::rectangle( drawing, rect, cv::Scalar(0,0,255,255));
        if (diagram[i] == BlackWhiteEmpty::BBLACK) {
            draw_point( p, drawing, 2, cv::Scalar(0,255,0,255));
        }
        else if (diagram[i] == BlackWhiteEmpty::WWHITE) {
            draw_point( p, drawing, 5, cv::Scalar(255,0,0,255));
        }
    }
    UIImage *res = MatToUIImage( drawing);
    return res;
} // f11_classify()

// Save small crops around intersections for inspection
//-------------------------------------------------------------------------------
void save_intersections( const cv::Mat img,
                        const Points &intersections, int delta_v, int delta_h)
{
    ILOOP( intersections.size())
    {
        int x = intersections[i].x;
        int y = intersections[i].y;
        int dx = round(delta_h/2.0); int dy = round(delta_v/2.0);
        cv::Rect rect( x - dx, y - dy, 2*dx+1, 2*dy+1 );
        if (0 <= rect.x &&
            0 <= rect.width &&
            rect.x + rect.width <= img.cols &&
            0 <= rect.y &&
            0 <= rect.height &&
            rect.y + rect.height <= img.rows)
        {
            const cv::Mat &hood( img(rect));
            NSString *fname = nsprintf(@"hood_%03d.jpg",i);
            fname = getFullPath( fname);
            cv::imwrite( [fname UTF8String], hood);
        }
    } // ILOOP
} // save_intersections()

// Find all intersections from corners and boardsize
//--------------------------------------------------------------------------------
template <typename Points_>
void get_intersections_from_corners( const Points_ &corners, int boardsz, // in
                                    Points_ &result, float &delta_h, float &delta_v) // out
{
    if (corners.size() != 4) return;
    
    cv::Point2f tl = corners[0];
    cv::Point2f tr = corners[1];
    cv::Point2f br = corners[2];
    cv::Point2f bl = corners[3];
    
    std::vector<float> left_x;
    std::vector<float> left_y;
    std::vector<float> right_x;
    std::vector<float> right_y;
    ILOOP (boardsz) {
        left_x.push_back(  tl.x + i * (bl.x - tl.x) / (float)(boardsz-1));
        left_y.push_back(  tl.y + i * (bl.y - tl.y) / (float)(boardsz-1));
        right_x.push_back( tr.x + i * (br.x - tr.x) / (float)(boardsz-1));
        right_y.push_back( tr.y + i * (br.y - tr.y) / (float)(boardsz-1));
    }
    std::vector<float> top_x;
    std::vector<float> top_y;
    std::vector<float> bot_x;
    std::vector<float> bot_y;
    ILOOP (boardsz) {
        top_x.push_back( tl.x + i * (tr.x - tl.x) / (float)(boardsz-1));
        top_y.push_back( tl.y + i * (tr.y - tl.y) / (float)(boardsz-1));
        bot_x.push_back( bl.x + i * (br.x - bl.x) / (float)(boardsz-1));
        bot_y.push_back( bl.y + i * (br.y - bl.y) / (float)(boardsz-1));
    }
    delta_v = (bot_y[0] - top_y[0]) / (boardsz -1);
    delta_h = (right_x[0] - left_x[0]) / (boardsz -1);
    
    result = Points_();
    RLOOP (boardsz) {
        CLOOP (boardsz) {
            cv::Point2f p = intersection( cv::Point2f( left_x[r], left_y[r]), cv::Point2f( right_x[r], right_y[r]),
                                         cv::Point2f( top_x[c], top_y[c]), cv::Point2f( bot_x[c], bot_y[c]));
            result.push_back(p);
        }
    }
} // get_intersections_from_corners()

#pragma mark - Real time implementation
//========================================

// f00_*, f01_*, ... all in one go
//--------------------------------------------
- (UIImage *) real_time_flow:(UIImage *) img
{
    _board_sz = 19;
    cv::Mat drawing;
    bool pyr_filtered = false;

    do {
        static std::vector<Points> boards; // Some history for averaging
        UIImageToMat( img, _m, false);
        resize( _m, _small, 350);
        cv::cvtColor( _small, _small, CV_RGBA2RGB);
        cv::cvtColor( _small, _gray, cv::COLOR_RGB2GRAY);
        thresh_dilate( _gray, _gray_threshed);
        
        // Find stones and intersections
        _stone_or_empty.clear();
        BlobFinder::find_empty_places( _gray_threshed, _stone_or_empty); // has to be first
        BlobFinder::find_stones( _gray, _stone_or_empty);
        _stone_or_empty = BlobFinder::clean( _stone_or_empty);
        if (SZ(_stone_or_empty) < 0.8 * SQR(_board_sz)) break;

        // Break if not straight
        float theta = direction( _gray, _stone_or_empty) - PI/2;
        if (fabs(theta) > 4 * PI/180) break;
        
        // Find vertical lines
        _vertical_lines = homegrown_vert_lines( _stone_or_empty);
        dedup_vertical_lines( _vertical_lines, _gray);
        fix_vertical_lines( _vertical_lines, _gray);
        if (SZ( _vertical_lines) > 40) break;
        if (SZ( _vertical_lines) < 5) break;
        
        // Find horiz lines
        _horizontal_lines = homegrown_horiz_lines( _stone_or_empty);
        dedup_horiz_lines( _horizontal_lines, _gray);
        fix_horiz_lines( _horizontal_lines, _vertical_lines, _gray);
        //PLOG( "HLINES:%d\n", SZ(_horizontal_lines));
        if (SZ( _horizontal_lines) > 40) break;
        if (SZ( _horizontal_lines) < 5) break;

        // Find corners
        _intersections = get_intersections( _horizontal_lines, _vertical_lines);
        cv::pyrMeanShiftFiltering( _small, _small_pyr, SPATIALRAD, COLORRAD, MAXPYRLEVEL );
        pyr_filtered = true;
        _corners.clear();
        if (SZ(_horizontal_lines) && SZ(_vertical_lines)) {
            _corners = find_corners( _stone_or_empty, _horizontal_lines, _vertical_lines,
                                    _intersections, _small_pyr, _gray_threshed);
        }
        if (!board_valid( _corners, _gray)) break;
        // Use median border coordinates to prevent flicker
        //const int BORDBUFLEN = 1;
        //ringpush( _boards, _corners, BORDBUFLEN);
        //Points2f med_board = med_quad( _boards);
        //_corners = med_board;

        _intersections = get_intersections( _horizontal_lines, _vertical_lines);
        
        // Zoom in
        cv::Mat M;
        zoom_in( _gray,  _corners, _gray_zoomed, M);
        zoom_in( _small, _corners, _small_zoomed, M);
        cv::perspectiveTransform( _corners, _corners_zoomed, M);
        cv::perspectiveTransform( _intersections, _intersections_zoomed, M);
        thresh_dilate( _gray_zoomed, _gz_threshed);

        // Classify
        const int TIME_BUF_SZ = 10;
        _diagram = classify( _intersections_zoomed, _gray_zoomed, _gz_threshed, _dx, _dy, TIME_BUF_SZ);
    } while(0);
    
    cv::Mat *canvas;
    if (pyr_filtered) {
        canvas = &_small_pyr;
    }
    else {
        canvas = &_small;
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

#define SHOW_CLASS
#ifdef SHOW_CLASS
        // Show classification result
        ISLOOP (_diagram) {
            cv::Point p(ROUND(_intersections[i].x), ROUND(_intersections[i].y));
            if (_diagram[i] == BlackWhiteEmpty::BBLACK) {
                draw_point( p, *canvas, 5, cv::Scalar(255,0,0,255));
            }
            else if (_diagram[i] == BlackWhiteEmpty::WWHITE) {
                draw_point( p, *canvas, 5, cv::Scalar(0,255,0,255));
            }
        }
        ISLOOP (_intersections) {
            draw_point( _intersections[i], *canvas, 2, cv::Scalar(0,0,255,255));
        }
#else
        // Show one feature for debugging
        ISLOOP (diagram) {
            cv::Point p(ROUND(_intersections[i].x), ROUND(_intersections[i].y));
            //int feat = BWE_sigma[i];
            //int feat = BWE_sum[i];
            //int feat = BWE_crossness_new[i];
            //int feat = BWE_brightness[i];
            int feat = BWE_white_templ_feat[i];
            draw_point( p, img, 5, cm_penny_lane( feat));
        }
#endif
    }
    UIImage *res = MatToUIImage( *canvas);
    //UIImage *res = MatToUIImage( drawing);
    return res;
} // findBoard()


@end





























