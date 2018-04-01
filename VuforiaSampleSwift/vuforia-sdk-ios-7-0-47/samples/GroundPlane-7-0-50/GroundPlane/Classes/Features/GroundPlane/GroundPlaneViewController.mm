/*===============================================================================
Copyright (c) 2017 PTC Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other
countries.
===============================================================================*/

#import "GroundPlaneViewController.h"
#import "GroundPlaneAppDelegate.h"
#import <Vuforia/CameraDevice.h>
#import <Vuforia/DataSet.h>
#import <Vuforia/ObjectTracker.h>
#import <Vuforia/PositionalDeviceTracker.h>
#import <Vuforia/SmartTerrain.h>
#import <Vuforia/Trackable.h>
#import <Vuforia/TrackerManager.h>
#import <Vuforia/Vuforia.h>

#import "UnwindMenuSegue.h"
#import "PresentMenuSegue.h"
#import "SampleAppMenuViewController.h"

@interface GroundPlaneViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *ARViewPlaceholder;

@end

@implementation GroundPlaneViewController

@synthesize tapGestureRecognizer, vapp, eaglView;

typedef NS_ENUM(NSInteger, UIModes) {
    INTERACTIVE_MODE,
    MID_AIR_MODE,
    FURNITURE_MODE
};

- (CGRect)getCurrentARViewFrame
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    return screenBounds;
}

- (void)loadView
{
    [super loadView];
    
    // Custom initialization
    self.title = @"Ground Plane";
    
    if (self.ARViewPlaceholder != nil) {
        [self.ARViewPlaceholder removeFromSuperview];
        self.ARViewPlaceholder = nil;
    }
    
    continuousAutofocusEnabled = YES;
    enableProductScaling = NO;
    self.mInstructionsState = InstructionsStates::UNDEFINED;
    
    vapp = [[SampleApplicationSession alloc] initWithDelegate:self];
    
    CGRect viewFrame = [self getCurrentARViewFrame];
    
    eaglView = [[GroundPlaneEAGLView alloc] initWithFrame:viewFrame appSession:vapp andUIUpdater: self];
    [eaglView setBackgroundColor:UIColor.clearColor];
    [eaglView setUserInteractionEnabled:YES];
    
    [self.view addSubview:eaglView];
    [self.view sendSubviewToBack:eaglView];

    GroundPlaneAppDelegate *appDelegate = (GroundPlaneAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.glResourceHandler = eaglView;
    
    // double tap used to also trigger the menu
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(doubleTapGestureAction:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];
    
    // a single tap will position the model
    tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(performTap:)];
    if (doubleTap != NULL) {
        [tapGestureRecognizer requireGestureRecognizerToFail:doubleTap];
    }
    
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeGestureAction:)];
    [swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
    [self.view addGestureRecognizer:swipeRight];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dismissARViewController)
                                                 name:@"kDismissARViewController"
                                               object:nil];
    
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGestureAction:)];
    [self.view addGestureRecognizer:pinch];
    pinch.delegate = self;
    
    UIRotationGestureRecognizer *rotation = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(rotationGestureAction:)];
    [self.view addGestureRecognizer:rotation];
    rotation.delegate = self;
    
    // we use the iOS notification to pause/resume the AR when the application goes (or come back from) background
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(pauseAR)
     name:UIApplicationWillResignActiveNotification
     object:nil];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(resumeAR)
     name:UIApplicationDidBecomeActiveNotification
     object:nil];
    
    // initialize AR
    [vapp initAR:Vuforia::GL_20 orientation:[[UIApplication sharedApplication] statusBarOrientation]];

    // show loading animation while AR is being initialized
    [self showLoadingAnimation];
}

- (void) pauseAR {
    [self resetGroundPlaneAppStateAndStopTrackers];
    
    NSError * error = nil;
    if (![vapp pauseAR:&error]) {
        NSLog(@"Error pausing AR:%@", [error description]);
    }
}

- (void) resumeAR {
    NSError * error = nil;
    if(! [vapp resumeAR:&error]) {
        NSLog(@"Error resuming AR:%@", [error description]);
    }
    
    [self resumeGroundPlaneAppTrackers];
    
    [eaglView updateRenderingPrimitives];
}


-(void)resetGroundPlaneAppStateAndStopTrackers
{
    [eaglView resetGroundPlaneStateAndAnchors];
    [self setModesUI:INTERACTIVE_MODE];
    [self setInstructionsState:POINT_TO_GROUND];
    [self setMidAirModeEnabled:NO];
    
    [self doStopTrackers];
}


-(void)resumeGroundPlaneAppTrackers
{
    [self doStartTrackers];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.showingMenu = NO;
    
    // Do any additional setup after loading the view.
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.view addGestureRecognizer:tapGestureRecognizer];
    [self setInstructionsState:self.mInstructionsState];
}

- (void)viewWillDisappear:(BOOL)animated
{
    // on iOS 7, viewWillDisappear may be called when the menu is shown
    // but we don't want to stop the AR view in that case
    if (self.showingMenu) {
        return;
    }
    
    [vapp stopAR:nil];
    
    // Be a good OpenGL ES citizen: now that Vuforia is paused and the render
    // thread is not executing, inform the root view controller that the
    // EAGLView should finish any OpenGL ES commands
    [self finishOpenGLESCommands];
    
    GroundPlaneAppDelegate *appDelegate = (GroundPlaneAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.glResourceHandler = nil;
    
    [super viewWillDisappear:animated];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    [self handleRotation:interfaceOrientation];
}

- (void) handleRotation:(UIInterfaceOrientation)interfaceOrientation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // ensure overlay size and AR orientation is correct for screen orientation
        [self handleARViewRotation: interfaceOrientation];
        [vapp  changeOrientation: interfaceOrientation];
        [eaglView changeOrientation: interfaceOrientation];
    });
}

- (void) handleARViewRotation:(UIInterfaceOrientation)interfaceOrientation
{
    // Retrieve up-to-date view frame.
    // Note that, while on iOS 7 and below, the frame size does not change
    // with rotation events,
    // on the contray, on iOS 8 the frame size is orientation-dependent,
    // i.e. width and height get swapped when switching from
    // landscape to portrait and vice versa.
    // This requires that the latest (current) view frame is retrieved.
    CGRect viewBounds = [[UIScreen mainScreen] bounds];
    
    int smallerSize = MIN(viewBounds.size.width, viewBounds.size.height);
    int largerSize = MAX(viewBounds.size.width, viewBounds.size.height);
    
    if (interfaceOrientation == UIInterfaceOrientationPortrait ||
        interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)
    {
        NSLog(@"AR View: Rotating to Portrait");
        
        CGRect viewBounds;
        viewBounds.origin.x = 0;
        viewBounds.origin.y = 0;
        viewBounds.size.width = smallerSize;
        viewBounds.size.height = largerSize;
        
        [eaglView setFrame:viewBounds];
    }
    else if (interfaceOrientation == UIInterfaceOrientationLandscapeLeft ||
             interfaceOrientation == UIInterfaceOrientationLandscapeRight)
    {
        NSLog(@"AR View: Rotating to Landscape");
        
        CGRect viewBounds;
        viewBounds.origin.x = 0;
        viewBounds.origin.y = 0;
        viewBounds.size.width = largerSize;
        viewBounds.size.height = smallerSize;
        
        [eaglView setFrame:viewBounds];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  Inform the EAGLView
    [eaglView finishOpenGLESCommands];
}

- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Inform the EAGLView
    [eaglView freeOpenGLESResources];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (IBAction)resetTracking:(id)sender
{
    [self resetGroundPlaneAppStateAndStopTrackers];
    [self resumeGroundPlaneAppTrackers];
}


-(IBAction) setInteractiveMode:(id)sender
{
    [eaglView setInteractiveMode];
    [self setModesUI:INTERACTIVE_MODE];
}


-(IBAction) setFurnitureMode:(id)sender
{
    [eaglView setFurnitureMode];
    [self setModesUI:FURNITURE_MODE];
}


-(IBAction) setMidAirMode:(id)sender
{
    if([eaglView getAnchorResultsCount] > 0)
    {
        [eaglView setMidAirMode];
        [self setModesUI:MID_AIR_MODE];
    }
}


- (void) setModesUI:(UIModes)mode
{
    NSString *interactiveImageString = mode != INTERACTIVE_MODE ? @"astroButton" : @"astroButtonPressed";
    NSString *midAirImageString = mode != MID_AIR_MODE ? @"droneButton" : @"droneButtonPressed";
    NSString *furnitureImageString = mode != FURNITURE_MODE ? @"furnitureButton" : @"furnitureButtonPressed";
    NSString *modeTitle;
    NSString *modeImageString;

    switch (mode) {
        case INTERACTIVE_MODE:
            modeTitle = @"Ground Plane";
            modeImageString = @"anchorStageIcon";
            break;
        case FURNITURE_MODE:
            modeTitle = @"Product Placement";
            modeImageString = @"contentPlacementIcon";
            break;
        case MID_AIR_MODE:
            modeTitle = @"Mid-Air";
            modeImageString = @"midAirIcon";
            break;
        default:
            modeTitle = @"";
            modeImageString = @"";
            break;
    }
    
    [self.interactiveModeButton setImage:[UIImage imageNamed:interactiveImageString] forState:UIControlStateNormal];
    [self.midAirModeButton setImage:[UIImage imageNamed:midAirImageString] forState:UIControlStateNormal];
    [self.furnitureModeButton setImage:[UIImage imageNamed:furnitureImageString] forState:UIControlStateNormal];
    [self.currentModeLabel setText:modeTitle];
    [self.currentModeImage setImage:[UIImage imageNamed:modeImageString]];
}

-(void) setInstructionsState:(InstructionsStates)instructionsState
{
    if(self.mInstructionsState != instructionsState)
    {
        
        NSString *instruction;
        BOOL hideInstructions = NO;
        
        switch (instructionsState) {
            case POINT_TO_GROUND:
                instruction = @"Point device towards the ground";
                break;
                
            case TAP_TO_PLACE:
                instruction = @"Touch anywhere on screen";
                break;
                
            case GESTURES_INSTRUCTIONS:
                instruction = @"Use 1 finger to move\nUse 2 fingers to rotate";
                break;
                
            case PRODUCT_PLACEMENT:
            default:
                instruction = @"";
                hideInstructions = YES;
                break;
        }
        
        [self.instructionView setHidden:hideInstructions];
        [self.instructionLabel setText:instruction];
        self.mInstructionsState = instructionsState;
    }
}

-(void) setMidAirModeEnabled:(BOOL)enable
{
    [self.midAirModeButton setUserInteractionEnabled:enable];
    [self.midAirModeButton setAlpha:enable ? 1.0f : .5f];
}

#pragma mark - loading animation

- (void) showLoadingAnimation {
    CGRect indicatorBounds;
    CGRect mainBounds = [[UIScreen mainScreen] bounds];
    int smallerBoundsSize = MIN(mainBounds.size.width, mainBounds.size.height);
    int largerBoundsSize = MAX(mainBounds.size.width, mainBounds.size.height);
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown ) {
        indicatorBounds = CGRectMake(smallerBoundsSize / 2 - 12,
                                     largerBoundsSize / 2 - 12, 24, 24);
    }
    else {
        indicatorBounds = CGRectMake(largerBoundsSize / 2 - 12,
                                     smallerBoundsSize / 2 - 12, 24, 24);
    }
    
    UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc]
                                                  initWithFrame:indicatorBounds];
    
    loadingIndicator.tag  = 1;
    loadingIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    [eaglView addSubview:loadingIndicator];
    [loadingIndicator startAnimating];
}

- (void) hideLoadingAnimation {
    UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[eaglView viewWithTag:1];
    [loadingIndicator removeFromSuperview];
}


#pragma mark - SampleApplicationControl

// Initialize the application trackers
- (bool) doInitTrackers {
    // Initialize positional device and smart terrain trackers
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    
    Vuforia::DeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*>
            (trackerManager.initTracker(Vuforia::PositionalDeviceTracker::getClassType()));
    
    if (deviceTracker == nullptr)
    {
        NSLog(@"Failed to start DeviceTracker.");
        return false;
    }
    
    Vuforia::Tracker* smartTerrain = trackerManager.initTracker(Vuforia::SmartTerrain::getClassType());
    if (smartTerrain == nullptr)
    {
        NSLog(@"Failed to start SmartTerrain.");
        return false;
    }

    return true;
}

// load the data associated to the trackers
- (bool) doLoadTrackersData {
    return YES;
}

// start the application trackers
- (bool) doStartTrackers {
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* deviceTracker = trackerManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType());
    if (deviceTracker == nullptr || !deviceTracker->start())
    {
        NSLog(@"Failed to start DeviceTracker");
        return false;
    }
    NSLog(@"Successfully started DeviceTracker");
    
    Vuforia::Tracker* smartTerrain = trackerManager.getTracker(Vuforia::SmartTerrain::getClassType());
    if (smartTerrain == nullptr || !smartTerrain->start())
    {
        NSLog(@"Failed to start SmartTerrain");
        
        // We stop the device tracker since there was an error starting Smart Terrain one
        deviceTracker->stop();
        NSLog(@"Stopped DeviceTracker tracker due to failure to start SmartTerrain");
        
        return false;
    }
    NSLog(@"Successfully started SmartTerrain");
    
    return true;
}

// callback called when the initailization of the AR is done
- (void) onInitARDone:(NSError *)initError {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[eaglView viewWithTag:1];
      [loadingIndicator removeFromSuperview];
    });
    
    if (initError == nil) {
        NSError * error = nil;
        [vapp startAR:Vuforia::CameraDevice::CAMERA_DIRECTION_BACK error:&error];
        
        [eaglView updateRenderingPrimitives];

        // by default, we try to set the continuous auto focus mode
        continuousAutofocusEnabled = Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_CONTINUOUSAUTO);
        
    } else {
        NSLog(@"Error initializing AR:%@", [initError description]);
        dispatch_async( dispatch_get_main_queue(), ^{
            
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                            message:[initError localizedDescription]
                                                           delegate:self
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        });
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kDismissARViewController" object:nil];
}

- (void)dismissARViewController
{
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [self.navigationController popToRootViewControllerAnimated:NO];
}

- (void)configureVideoBackgroundWithViewWidth:(float)viewWidth andHeight:(float)viewHeight andCameraMode:(Vuforia::CameraDevice::MODE)cameraMode
{
    [eaglView configureVideoBackgroundWithViewWidth:(float)viewWidth andHeight:(float)viewHeight andCameraMode:cameraMode];
}

- (void) onVuforiaUpdate: (Vuforia::State *) state
{
}

- (bool) doStopTrackers {
    // Stop the tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* deviceTracker = trackerManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType());
    Vuforia::Tracker* smartTerrain = trackerManager.getTracker(Vuforia::SmartTerrain::getClassType());
    BOOL succesfullyStoppedTrackers = YES;
    
    if (smartTerrain != nullptr) {
        smartTerrain->stop();
        NSLog(@"INFO: successfully stopped smartTerrain tracker");
    } else {
        NSLog(@"ERROR: failed to get the smartTerrain tracker from the tracker manager");
        succesfullyStoppedTrackers = NO;
    }
    
    if (deviceTracker != nullptr) {
        deviceTracker->stop();
        NSLog(@"INFO: successfully stopped deviceTracker tracker");
    } else {
        NSLog(@"ERROR: failed to get the deviceTracker tracker from the tracker manager");
        succesfullyStoppedTrackers = NO;
    }
    
    return succesfullyStoppedTrackers;
}

- (bool) doUnloadTrackersData {
    return YES;
}

- (bool) doDeinitTrackers {
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    trackerManager.deinitTracker(Vuforia::SmartTerrain::getClassType());
    trackerManager.deinitTracker(Vuforia::PositionalDeviceTracker::getClassType());
    return YES;
}

- (void)resetTrackers
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::PositionalDeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*>
    (trackerManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType()));
    Vuforia::SmartTerrain* smartTerrain = static_cast<Vuforia::SmartTerrain*>(trackerManager.getTracker(Vuforia::SmartTerrain::getClassType()));
    
    if (deviceTracker == nullptr || smartTerrain == nullptr)
    {
        NSLog(@"Failed to reset trackers, trackers not initialized");
        return;
    }
    
    deviceTracker->stop();
    // Anchor not valid any more after stop() call anchor poses should be discarded
    smartTerrain->stop();
    deviceTracker->start();
    smartTerrain->start();
}

- (void)performTap:(UITapGestureRecognizer *)sender
{
    [eaglView performTap];
}

- (void)autofocus:(UITapGestureRecognizer *)sender
{
    [self performSelector:@selector(cameraPerformAutoFocus) withObject:nil afterDelay:.4];
}

- (void)cameraPerformAutoFocus
{
    Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_TRIGGERAUTO);
    
    // After triggering an autofocus event,
    // we must restore the previous focus mode
    if (continuousAutofocusEnabled)
    {
        [self performSelector:@selector(restoreContinuousAutoFocus) withObject:nil afterDelay:2.0];
    }
}

- (void)restoreContinuousAutoFocus
{
    Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_CONTINUOUSAUTO);
}

- (void)doubleTapGestureAction:(UITapGestureRecognizer*)theGesture
{
    if (!self.showingMenu) {
        [self performSegueWithIdentifier: @"PresentMenu" sender: self];
    }
}

- (void)swipeGestureAction:(UISwipeGestureRecognizer*)gesture
{
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer{
    
    BOOL isPinchGesturePresent = [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] || [otherGestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]];
    BOOL isRotationGesturePresent = [gestureRecognizer isKindOfClass:[UIRotationGestureRecognizer class]] || [otherGestureRecognizer isKindOfClass:[UIRotationGestureRecognizer class]];

    if (isPinchGesturePresent && isRotationGesturePresent) {
        return YES;
    }
    return NO;
}

// Used to scale furniture in product placement mode
- (void)pinchGestureAction:(UIPinchGestureRecognizer*)gesture
{
    BOOL isGestureFinished = NO;

    if(gesture.state == UIGestureRecognizerStateEnded)
    {
        isGestureFinished = YES;
    }
    
    if(enableProductScaling)
        [eaglView scaleBy:gesture.scale andGestureFinished:isGestureFinished];
}

// Used to rotate furniture in product placement mode
- (void)rotationGestureAction:(UIRotationGestureRecognizer*)gesture
{
    BOOL isGestureFinished = NO;
    
    if(gesture.state == UIGestureRecognizerStateEnded)
    {
        isGestureFinished = YES;
    }
    
    [eaglView rotateBy:gesture.rotation andGestureFinished:isGestureFinished];
}

#pragma mark - menu delegate protocol implementation

- (BOOL) menuProcess:(NSString *)itemName value:(BOOL)value
{
    if ([@"Autofocus" isEqualToString:itemName]) {
        int focusMode = value ? Vuforia::CameraDevice::FOCUS_MODE_CONTINUOUSAUTO : Vuforia::CameraDevice::FOCUS_MODE_NORMAL;
        bool result = Vuforia::CameraDevice::getInstance().setFocusMode(focusMode);
        continuousAutofocusEnabled = value && result;
        return result;
    }

    return false;
}

- (void) menuDidExit
{
    self.showingMenu = NO;
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue isKindOfClass:[PresentMenuSegue class]]) {
        UIViewController *dest = [segue destinationViewController];
        if ([dest isKindOfClass:[SampleAppMenuViewController class]]) {
            self.showingMenu = YES;
            
            SampleAppMenuViewController *menuVC = (SampleAppMenuViewController *)dest;
            menuVC.menuDelegate = self;
            menuVC.sampleAppFeatureName = @"Ground Plane";
            menuVC.dismissItemName = @"About";
            menuVC.backSegueId = @"BackToGroundPlane";
            
            // initialize menu item values (ON / OFF)
            [menuVC setValue:continuousAutofocusEnabled forMenuItem:@"Autofocus"];
        }
    }
}

@end
