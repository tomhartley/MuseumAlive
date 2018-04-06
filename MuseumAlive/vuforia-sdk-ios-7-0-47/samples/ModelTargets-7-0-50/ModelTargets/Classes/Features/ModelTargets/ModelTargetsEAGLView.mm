/*===============================================================================
Copyright (c) 2016-2017 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <sys/time.h>
#import <GLKit/GLKit.h>

#import <Vuforia/Vuforia.h>
#import <Vuforia/Image.h>
#import <Vuforia/State.h>
#import <Vuforia/Tool.h>
#import <Vuforia/Renderer.h>
#import <Vuforia/TrackableResult.h>
#import <Vuforia/VideoBackgroundConfig.h>
#import <Vuforia/ModelTarget.h>
#import <Vuforia/GuideView.h>

#import "ModelTargetsEAGLView.h"
#import "Texture.h"
#import "SampleApplicationUtils.h"
#import "SampleApplicationShaderUtils.h"
#import "Cube.h"
#import "Quad.h"


//******************************************************************************
// *** OpenGL ES thread safety ***
//
// OpenGL ES on iOS is not thread safe.  We ensure thread safety by following
// this procedure:
// 1) Create the OpenGL ES context on the main thread.
// 2) Start the Vuforia camera, which causes Vuforia to locate our EAGLView and start
//    the render thread.
// 3) Vuforia calls our renderFrameVuforia method periodically on the render thread.
//    The first time this happens, the defaultFramebuffer does not exist, so it
//    is created with a call to createFramebuffer.  createFramebuffer is called
//    on the main thread in order to safely allocate the OpenGL ES storage,
//    which is shared with the drawable layer.  The render (background) thread
//    is blocked during the call to createFramebuffer, thus ensuring no
//    concurrent use of the OpenGL ES context.
//
//******************************************************************************


namespace {
    // --- Data private to this unit ---

    // Teapot texture filenames
    const char* textureFilenames[] = {
        "Diffuse.jpg",
    };
    
}


@interface ModelTargetsEAGLView (PrivateMethods)

- (void)initShaders;
- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;

@end


@implementation ModelTargetsEAGLView

@synthesize vapp = vapp;

// Used in the calculation and rendering of the guide view
// showing the user where to view the object to recognize it
int guideViewHandle;

// You must implement this method, which ensures the view's underlying layer is
// of type CAEAGLLayer
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


//------------------------------------------------------------------------------
#pragma mark - Lifecycle

- (id)initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *) app
{
    self = [super initWithFrame:frame];
    
    if (self) {
        vapp = app;
        // Enable retina mode if available on this device
        if (YES == [vapp isRetinaDisplay]) {
            [self setContentScaleFactor:[UIScreen mainScreen].nativeScale];
        }
        
        // Load the augmentation textures
        for (int i = 0; i < kNumAugmentationTextures; ++i) {
            augmentationTexture[i] = [[Texture alloc] initWithImageFile:[NSString stringWithCString:textureFilenames[i] encoding:NSASCIIStringEncoding]];
        }

        // Create the OpenGL ES context
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        // The EAGLContext must be set for each thread that wishes to use it.
        // Set it the first time this method is called (on the main thread)
        if (context != [EAGLContext currentContext]) {
            [EAGLContext setCurrentContext:context];
        }
        
        // Generate the OpenGL ES texture and upload the texture data for use
        // when rendering the augmentation
        for (int i = 0; i < kNumAugmentationTextures; ++i) {
            GLuint textureID;
            glGenTextures(1, &textureID);
            [augmentationTexture[i] setTextureID:textureID];
            glBindTexture(GL_TEXTURE_2D, textureID);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, [augmentationTexture[i] width], [augmentationTexture[i] height], 0, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)[augmentationTexture[i] pngData]);
        }

        sampleAppRenderer = [[SampleAppRenderer alloc]initWithSampleAppRendererControl:self deviceMode:Vuforia::Device::MODE_AR stereo:false nearPlane:0.01 farPlane:10.0];
        
        [self loadModelNamed:@"Lander"];
        [self initShaders];
        
        // we initialize the rendering method of the SampleAppRenderer
        [sampleAppRenderer initRendering];
        
        guideViewHandle = -1;
    }
    
    return self;
}


- (void)setDatasetForGuideView:(Vuforia::DataSet *)dataset;
{
    mDataset = dataset;
}

- (CGSize)getCurrentARViewBoundsSize
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGSize viewSize = screenBounds.size;
    
    viewSize.width *= [UIScreen mainScreen].nativeScale;
    viewSize.height *= [UIScreen mainScreen].nativeScale;
    return viewSize;
}


- (void)dealloc
{
    [self deleteFramebuffer];
    
    // Tear down context
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }

    for (int i = 0; i < kNumAugmentationTextures; ++i) {
        augmentationTexture[i] = nil;
    }
}


- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  The render loop has
    // been stopped, so we now make sure all OpenGL ES commands complete before
    // we (potentially) go into the background
    if (context) {
        [EAGLContext setCurrentContext:context];
        glFinish();
    }
}


- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Free easily
    // recreated OpenGL ES resources
    [self deleteFramebuffer];
    glFinish();
}


- (void) loadModelNamed:(NSString *)modelName {
    KTMModel = [[Modelv3d alloc] init];
    [KTMModel loadModel:modelName];
}

- (void) updateRenderingPrimitives
{
    [sampleAppRenderer updateRenderingPrimitives];
}

- (void) changeOrientation:(UIInterfaceOrientation) ARViewOrientation
{
    self.mARViewOrientation = ARViewOrientation;
    [self updateRenderingPrimitives];
}


//------------------------------------------------------------------------------
#pragma mark - UIGLViewProtocol methods

// Draw the current frame using OpenGL
//
// This method is called by Vuforia when it wishes to render the current frame to
// the screen.
//
// *** Vuforia will call this method periodically on a background thread ***
- (void)renderFrameVuforia
{
    if (! vapp.cameraIsStarted) {
        return;
    }
    
    [sampleAppRenderer renderFrameVuforia];
}

- (void) renderFrameWithState:(const Vuforia::State&) state
                projectMatrix:(Vuforia::Matrix44F&) projectionMatrix
              vbProjectMatrix:(Vuforia::Matrix44F&) vbProjectionMatrix
{
    [self setFramebuffer];
    
    // Clear colour and depth buffers
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
 
    // Render video background and retrieve tracking state
    [sampleAppRenderer renderVideoBackground];
    
    glEnable(GL_DEPTH_TEST);
    // We must detect if background reflection is active and adjust the culling direction.
    // If the reflection is active, this means the pose matrix has been reflected as well,
    // therefore standard counter clockwise face culling will result in "inside out" models.
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    // assuming there is only one Model Target trackable in dataSetOt1
    Vuforia::ModelTarget * modelTarget = nullptr;
    for(int i = 0; i < mDataset->getNumTrackables(); ++i)
    {
        auto trackable = mDataset->getTrackable(i);
        if (trackable->isOfType(Vuforia::ModelTarget::getClassType()))
        {
            modelTarget = static_cast<Vuforia::ModelTarget *>(trackable);
            break;
        }
    }
    
    assert(modelTarget != nullptr);
    Vuforia::Vec2F scale;
    
    if ( mDataset &&
        modelTarget->getGuideView(0) &&
        modelTarget->getGuideView(0)->getImage()) {
        
        // We only need to do this calculation once
        const Vuforia::Image *textureImage= modelTarget->getGuideView(0)->getImage();
        
        if(guideViewHandle == -1)
        {
            guideViewHandle = SampleApplicationUtils::createTexture(const_cast<Vuforia::Image *>(textureImage));
        }
        
        float guideViewAspectRatio = (float)modelTarget->getGuideView(0)->getImage()->getWidth() / modelTarget->getGuideView(0)->getImage()->getHeight();
        float cameraAspectRatio = (float)self.frame.size.width / self.frame.size.height;
        
        // doing this calculatio in world space, at an assumed camera near plane distance of 0.01f;
        // this is also what the Unity rendering code does
        float planeDistance = 0.01f;
        float fieldOfView = Vuforia::CameraDevice::getInstance().getCameraCalibration().getFieldOfViewRads().data[1];
        float nearPlaneHeight = 2.0f * planeDistance * tanf(fieldOfView * 0.5f);
        float nearPlaneWidth = nearPlaneHeight * cameraAspectRatio;
        
        float planeWidth;
        float planeHeight;
        
        int guideViewSign = (0.0f < (guideViewAspectRatio - 1.0f)) - ((guideViewAspectRatio - 1.0f) < 0.0f);
        int cameraSign = (0.0f < (cameraAspectRatio - 1.0f)) - ((cameraAspectRatio - 1.0f) < 0.0f);
        
        if (guideViewSign == cameraSign)
        {
            // Scale the guide view to fit the horizontal fov,
            // while preserving the aspect ratio of the image.
            planeWidth = nearPlaneWidth;
            planeHeight = planeWidth / guideViewAspectRatio;
        }
        else if (cameraAspectRatio < 1.0f) // guideview landscape, camera portrait
        {
            // scale so that the long side of the camera (height)
            // is the same length as guideview width
            planeWidth = nearPlaneHeight;
            planeHeight = planeWidth / guideViewAspectRatio;
            
        }
        else // guideview portrait, camera landscape
        {
            // scale so that the long side of the camera (width)
            // is the same length as guideview height
            planeHeight = nearPlaneWidth;
            planeWidth = planeHeight * guideViewAspectRatio;
        }
        
        // normalize world space plane sizes into view space again
        scale = Vuforia::Vec2F(planeWidth / nearPlaneWidth, -planeHeight / nearPlaneHeight);
    }
    
    if( state.getNumTrackableResults() == 0 ) {
        const int matrixSize = 16; //4x4 matrix
        float modelMatrix[matrixSize];
        SampleApplicationUtils::setIdentityMatrix(modelMatrix);
        
        Vuforia::Vec4F color = Vuforia::Vec4F(1.0f, 1.0f, 1.0f, 1.0f);
        
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);

        float orthoProjMatrix[matrixSize];
        SampleApplicationUtils::setOrthoMatrix(-1.f, 1.f, -1.f, 1.f, 0, 1, orthoProjMatrix);
        
        [self renderPlaneTexturedWithProjectionMatrix:orthoProjMatrix MVP:modelMatrix Scale:scale Colour:color andTextureHandle:guideViewHandle];
         
        glEnable(GL_CULL_FACE);
        glEnable(GL_DEPTH_TEST);
        
        SampleApplicationUtils::checkGlError("Render Frame, no trackables");
        
    }
    else {
        for (int i = 0; i < state.getNumTrackableResults(); ++i) {
            // Get the trackable
            const Vuforia::TrackableResult* result = state.getTrackableResult(i);
            
            Vuforia::Matrix44F modelViewMatrix = Vuforia::Tool::convertPose2GLMatrix(result->getPose());
            
            // OpenGL 2
            Vuforia::Matrix44F modelViewProjection;
            
            SampleApplicationUtils::multiplyMatrix(&projectionMatrix.data[0], &modelViewMatrix.data[0], &modelViewProjection.data[0]);
            
            glUseProgram(shaderProgramID);
            
            glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)KTMModel.vertices);
            glVertexAttribPointer(normalHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)KTMModel.normals);
            glVertexAttribPointer(textureCoordHandle, 2, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)KTMModel.texCoords);
            
            glEnableVertexAttribArray(vertexHandle);
            glEnableVertexAttribArray(normalHandle);
            glEnableVertexAttribArray(textureCoordHandle);
            
            // Choose the texture based on the target name
            int targetIndex = 0;
            
            glActiveTexture(GL_TEXTURE0);
            
            glBindTexture(GL_TEXTURE_2D, augmentationTexture[targetIndex].textureID);
            
            glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewProjection.data[0]);
            glUniformMatrix4fv(mvMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewMatrix.data[0]);
            
            GLKMatrix4 mvMatrix = GLKMatrix4MakeWithArray(modelViewMatrix.data);
            bool isInvertible;
            GLKMatrix4 normalMatrix = GLKMatrix4InvertAndTranspose ( mvMatrix, &isInvertible );
            glUniformMatrix4fv(normalMatrixHandle, 1, GL_FALSE, normalMatrix.m);
            
            glUniform4f(lightPositionHandle, 0.2f, 1.0f, -0.5f, 1.0f);
            glUniform4f(lightColorHandle, 0.8f, 0.8f, 0.8f, 1.0f);
            
            GLfloat groupDiffuseColors[] = {0.64f, 0.64f, 0.64f, 1.0f};
            glUniform4fv(objMtlGroupDiffuseColorsHandle, 1, groupDiffuseColors);
            
            glUniform1i(texSampler2DHandle, 0 /*GL_TEXTURE0*/);
            
            glDrawArrays(GL_TRIANGLES, 0, (int)KTMModel.nbVertices);
            
            glDisableVertexAttribArray(vertexHandle);
            glDisableVertexAttribArray(normalHandle);
            glDisableVertexAttribArray(textureCoordHandle);
            
            SampleApplicationUtils::checkGlError("EAGLView renderFrameVuforia");
        }
    }
    
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    
    [self presentFramebuffer];
}

-(void)renderPlaneTexturedWithProjectionMatrix:(float *)projectionMatrix MVP:(float *)modelViewMatrix Scale:(Vuforia::Vec2F)scale Colour:(Vuforia::Vec4F)colour andTextureHandle:(int)textureHandle
{
    float modelViewProjectionMatrix[16];
    float scaledModelMatrixArray[16];
    
    for(int i=0; i<16; i++) {
        scaledModelMatrixArray[i] = modelViewMatrix[i];
    }
    
    SampleApplicationUtils::scalePoseMatrix(scale.data[0], scale.data[1], 1.0, scaledModelMatrixArray);
    SampleApplicationUtils::multiplyMatrix(projectionMatrix, scaledModelMatrixArray, modelViewProjectionMatrix);
    
    //glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textureHandle);
    
    glEnableVertexAttribArray(planeVertexHandle);
    glVertexAttribPointer(planeVertexHandle, 3, GL_FLOAT, false, 0, quadVertices);
    
    glEnableVertexAttribArray(planeTextureCoordHandle);
    glVertexAttribPointer(planeTextureCoordHandle, 2, GL_FLOAT, false, 0, quadTexCoords);
    
    glUseProgram(planeShaderProgramID);
    glUniformMatrix4fv(planeMvpMatrixHandle, 1, false, modelViewProjectionMatrix);
    glUniform4f(planeColorHandle, colour.data[0], colour.data[1], colour.data[2], colour.data[3]);
    glUniform1i(planeTexSampler2DHandle, 0);
    
    // Draw
    glDrawElements(GL_TRIANGLES, kNumQuadIndices, GL_UNSIGNED_SHORT, quadIndices);
    
    // disable input data structures
    
    glDisableVertexAttribArray(planeTextureCoordHandle);
    glDisableVertexAttribArray(planeVertexHandle);
    glUseProgram(0);
    
    glBindTexture(GL_TEXTURE_2D, 0);
    
    glDisable(GL_BLEND);
}

- (void)configureVideoBackgroundWithViewWidth:(float)viewWidth andHeight:(float)viewHeight andCameraMode:(Vuforia::CameraDevice::MODE)cameraMode
{
    [self deleteFramebuffer];
    [sampleAppRenderer configureVideoBackgroundWithViewWidth:viewWidth andHeight:viewHeight andCameraMode:cameraMode];
}

//------------------------------------------------------------------------------
#pragma mark - OpenGL ES management

- (void)initShaders
{
    shaderProgramID = [SampleApplicationShaderUtils createProgramWithVertexShaderFileName:@"DiffuseLight.vertsh"
                                                   fragmentShaderFileName:@"DiffuseLight.fragsh"];

    if (0 < shaderProgramID) {
        vertexHandle = glGetAttribLocation(shaderProgramID, "vertexPosition");
        normalHandle = glGetAttribLocation(shaderProgramID, "vertexNormal");
        textureCoordHandle = glGetAttribLocation(shaderProgramID, "vertexTexCoord");
        mvpMatrixHandle = glGetUniformLocation(shaderProgramID, "u_mvpMatrix");
        mvMatrixHandle = glGetUniformLocation(shaderProgramID,"u_mvMatrix");
        normalMatrixHandle = glGetUniformLocation(shaderProgramID,"u_normalMatrix");
        lightPositionHandle = glGetUniformLocation(shaderProgramID,"u_lightPos");
        lightColorHandle = glGetUniformLocation(shaderProgramID,"u_lightColor");
        texSampler2DHandle  = glGetUniformLocation(shaderProgramID,"texSampler2D");
        objMtlGroupDiffuseColorsHandle = glGetUniformLocation(shaderProgramID, "u_groupDiffuseColors");
        
    }
    else {
        NSLog(@"Could not initialise augmentation shader");
    }

    planeShaderProgramID = [SampleApplicationShaderUtils createProgramWithVertexShaderFileName:@"Simple.vertsh"
                                                                   fragmentShaderFileName:@"SimpleTexturedColor.fragsh"];
    
    if (0 < planeShaderProgramID) {
        planeVertexHandle = glGetAttribLocation(planeShaderProgramID, "vertexPosition");
        planeNormalHandle = glGetAttribLocation(planeShaderProgramID, "vertexNormal");
        planeTextureCoordHandle = glGetAttribLocation(planeShaderProgramID, "vertexTexCoord");
        planeMvpMatrixHandle = glGetUniformLocation(planeShaderProgramID, "modelViewProjectionMatrix");
        planeTexSampler2DHandle  = glGetUniformLocation(planeShaderProgramID,"texSampler2D");
        planeColorHandle = glGetUniformLocation(planeShaderProgramID,"color");
    }
    else {
        NSLog(@"Could not initialise viewpoint shader");
    }
}


- (void)createFramebuffer
{
    if (context) {
        // Create default framebuffer object
        glGenFramebuffers(1, &defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        GLint framebufferWidth;
        GLint framebufferHeight;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    }
}


- (void)deleteFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
        if (defaultFramebuffer) {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
    }
}


- (void)setFramebuffer
{
    // The EAGLContext must be set for each thread that wishes to use it.  Set
    // it the first time this method is called (on the render thread)
    if (context != [EAGLContext currentContext]) {
        [EAGLContext setCurrentContext:context];
    }
    
    if (!defaultFramebuffer) {
        // Perform on the main thread to ensure safe memory allocation for the
        // shared buffer.  Block until the operation is complete to prevent
        // simultaneous access to the OpenGL context
        [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
}


- (BOOL)presentFramebuffer
{
    // setFramebuffer must have been called before presentFramebuffer, therefore
    // we know the context is valid and has been set for this (render) thread
    
    // Bind the colour render buffer and present it
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    
    return [context presentRenderbuffer:GL_RENDERBUFFER];
}



@end
