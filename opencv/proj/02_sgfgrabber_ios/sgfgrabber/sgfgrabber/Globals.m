//
//  Globals.m
//  sgfgrabber
//
//  Created by Andreas Hauenstein on 2017-11-15.
//  Copyright © 2017 AHN. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Globals.h"

UIFont *g_fntBtn;
AppDelegate *g_app;

// Init globals. Called from Appdelegate.
//----------------------------------------
void g_init()
{
    g_fntBtn = [UIFont fontWithName:@"HelveticaNeue" size: 20];
    //#define APP ((AppDelegate*) [NSApplication sharedApplication].delegate)
}




