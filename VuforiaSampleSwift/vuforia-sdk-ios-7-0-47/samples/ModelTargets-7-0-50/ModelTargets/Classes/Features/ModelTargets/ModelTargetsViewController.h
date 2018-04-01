/*===============================================================================
Copyright (c) 2016-2017 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import "ModelTargetsEAGLView.h"
#import "SampleApplicationSession.h"
#import "SampleAppMenuViewController.h"
#import <Vuforia/DataSet.h>

@interface ModelTargetsViewController : UIViewController <SampleApplicationControl, SampleAppMenuDelegate> {
    
    Vuforia::DataSet*  dataSetCurrent;
    
    // menu options
    BOOL continuousAutofocusEnabled;
}

-(IBAction) resetTracking:(id)sender;

@property (nonatomic, strong) ModelTargetsEAGLView* eaglView;
@property (nonatomic, strong) UITapGestureRecognizer * tapGestureRecognizer;
@property (nonatomic, strong) SampleApplicationSession * vapp;

@property (nonatomic, readwrite) BOOL showingMenu;

@end
