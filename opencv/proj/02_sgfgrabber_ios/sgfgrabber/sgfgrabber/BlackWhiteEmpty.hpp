//
//  BlackWhiteEmpty.hpp
//  sgfgrabber
//
//  Created by Andreas Hauenstein on 2017-11-16.
//  Copyright © 2017 AHN. All rights reserved.
//

// Classify board intersection into Black, White, Empty

#ifndef BlackWhiteEmpty_hpp
#define BlackWhiteEmpty_hpp

#include <iostream>
#include "Common.hpp"
#include "Ocv.hpp"

class BlackWhiteEmpty
//=====================
{
public:
    enum { BBLACK=-1, EEMPTY=0, WWHITE=1, DONTKNOW=2 };
    
    //----------------------------------------------------------------------------------
    inline static std::vector<int> classify( const cv::Mat &img, // small, color
                                            const Points2f &intersections,
                                            float dx, // approximate dist between lines
                                            float dy)
    {
        std::vector<int> res(SZ(intersections), DONTKNOW);
        cv::Mat gray;
        cv::cvtColor( img, gray, cv::COLOR_BGR2GRAY);
        
        // Compute features for each board intersection
        std::vector<float> black_features;
        get_black_features( gray, intersections, dx, dy, black_features);
        std::vector<float> empty_features;
        get_empty_features( gray, intersections, dx, dy, empty_features);

        // Black stones
        float minelt = *(std::min_element( black_features.begin(), black_features.end(),
                                          [](float a, float b){ return a < b; } )) ;
        float bthresh = minelt * 2.5; // larger means more Black stones
        ISLOOP( black_features) {
            if (black_features[i] < bthresh) {
                res[i] = BBLACK;
            }
        }
        
        // Empty places
        float maxelt = *(std::max_element( empty_features.begin(), empty_features.end(),
                                         [](float a, float b){ return a < b; } )) ;
        float ethresh = maxelt / 2.5; // Larger denom means more empty spaces
        ISLOOP( empty_features) {
            if (empty_features[i] > ethresh && res[i] != BBLACK) {
                res[i] = EEMPTY;
            }
        }
        
        // White places
        ISLOOP (res) {
            if (res[i] != BBLACK && res[i] != EEMPTY) {
                res[i] = WWHITE;
            }
        }
        
        return res;
    } // classify()
    
private:
    // Average pixel value around center of each intersection is black indicator.
    //---------------------------------------------------------------------------------
    inline static void get_black_features( const cv::Mat &img, // gray
                                          const Points2f &intersections,
                                          float dx_, float dy_,
                                          std::vector<float> &res )
    {
        int dx = ROUND( dx_/4.0);
        int dy = ROUND( dy_/4.0);
        
        res.clear();
        ISLOOP (intersections) {
            cv::Point p(ROUND(intersections[i].x), ROUND(intersections[i].y));
            cv::Rect rect( p.x - dx, p.y - dy, 2*dx+1, 2*dy+1 );
            if (0 <= rect.x &&
                0 <= rect.width &&
                rect.x + rect.width <= img.cols &&
                0 <= rect.y &&
                0 <= rect.height &&
                rect.y + rect.height <= img.rows)
            {
                cv::Mat hood = cv::Mat( img, rect);
                float area = hood.rows * hood.cols;
                cv::Scalar ssum = cv::sum( hood);
                float brightness = ssum[0] / area;
                res.push_back( brightness);
            }
        } // for intersections
    } // get_black_features()

    // If there are contours, it's probably empty
    //----------------------------------------------------------------------------------------
    inline static void get_empty_features( const cv::Mat &img, // gray
                                          const Points2f &intersections,
                                          float dx_, float dy_,
                                          std::vector<float> &res )
    {
        int dx = ROUND( dx_/4.0);
        int dy = ROUND( dy_/4.0);
        
        cv::Mat edges;
        cv::Canny( img, edges, 30, 70);
        
        ISLOOP (intersections) {
            cv::Point p(ROUND(intersections[i].x), ROUND(intersections[i].y));
            cv::Rect rect( p.x - dx, p.y - dy, 2*dx+1, 2*dy+1 );
            if (0 <= rect.x &&
                0 <= rect.width &&
                rect.x + rect.width <= img.cols &&
                0 <= rect.y &&
                0 <= rect.height &&
                rect.y + rect.height <= img.rows)
            {
                cv::Mat hood = cv::Mat( edges, rect);
                float area = hood.rows * hood.cols;
                cv::Scalar ssum = cv::sum( hood);
                float crossness = ssum[0] / area;
                res.push_back( crossness);
            }
        } // for intersections
    } // get_empty_features()
}; // class BlackWhiteEmpty
    

#endif /* BlackWhiteEmpty_hpp */
