/*===============================================================================
 Copyright (c) 2017 PTC Inc. All Rights Reserved.
 
 Vuforia is a trademark of PTC Inc., registered in the United States and other
 countries.
 ===============================================================================*/

#import <UIKit/UIKit.h>
#import "SampleGLResourceHandler.h"

@interface GroundPlaneAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, weak) id<SampleGLResourceHandler> glResourceHandler;

@end

