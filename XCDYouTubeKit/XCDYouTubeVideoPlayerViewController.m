//
//  Copyright (c) 2013-2015 Cédric Luthi. All rights reserved.
//

#import "XCDYouTubeVideoPlayerViewController.h"

#import "XCDYouTubeClient.h"

#import <objc/runtime.h>

NSString *const XCDMoviePlayerPlaybackDidFinishErrorUserInfoKey = @"error"; // documented in -[MPMoviePlayerController initWithContentURL:]

NSString *const XCDYouTubeVideoPlayerViewControllerDidReceiveMetadataNotification = @"XCDYouTubeVideoPlayerViewControllerDidReceiveMetadataNotification";
NSString *const XCDMetadataKeyTitle = @"Title";
NSString *const XCDMetadataKeySmallThumbnailURL = @"SmallThumbnailURL";
NSString *const XCDMetadataKeyMediumThumbnailURL = @"MediumThumbnailURL";
NSString *const XCDMetadataKeyLargeThumbnailURL = @"LargeThumbnailURL";

NSString *const XCDYouTubeVideoPlayerViewControllerDidReceiveVideoNotification = @"XCDYouTubeVideoPlayerViewControllerDidReceiveVideoNotification";
NSString *const XCDYouTubeVideoUserInfoKey = @"Video";

@interface XCDYouTubeVideoPlayerViewController ()<NSURLConnectionDelegate>
@property (nonatomic, weak) id<XCDYouTubeOperation> videoOperation;
@property (nonatomic, assign, getter = isEmbedded) BOOL embedded;
@property (nonatomic, assign) BOOL checkURL;
@property (nonatomic, strong) NSURLConnection *urlConnection;
@property (nonatomic, strong) NSURL *currentStreamURL;
@end

@implementation XCDYouTubeVideoPlayerViewController

/*
 * MPMoviePlayerViewController on iOS 7 and earlier
 * - (id) init
 *        `-- [super init]
 *
 * - (id) initWithContentURL:(NSURL *)contentURL
 *        |-- [self init]
 *        `-- [self.moviePlayer setContentURL:contentURL]
 *
 * MPMoviePlayerViewController on iOS 8 and later
 * - (id) init
 *        `-- [self initWithContentURL:nil]
 *
 * - (id) initWithContentURL:(NSURL *)contentURL
 *        |-- [super init]
 *        `-- [self.moviePlayer setContentURL:contentURL]
 */
#pragma mark -NSURLConnectionDelegate methods
- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse *)response
{
	NSLog(@"Did Receive Response %@", response);
	
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
	if ([httpResponse respondsToSelector:@selector(statusCode)]&&(long)[httpResponse statusCode] < 299) {
	
		self.moviePlayer.contentURL = self.currentStreamURL;
		
	} else {
	
		if (self.checkURL) {
			
			[self stopWithError:[NSError errorWithDomain:@"XC" code:[httpResponse statusCode] userInfo:nil]];
			
		} else {
			
			self.checkURL = YES;
			[self forceVideoIdentifier];
		}
	}
	
	[connection cancel];
}

- (instancetype) init
{
	return [self initWithVideoIdentifier:nil];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype) initWithContentURL:(NSURL *)contentURL
{
	@throw [NSException exceptionWithName:NSGenericException reason:@"Use the `initWithVideoIdentifier:` method instead." userInfo:nil];
}

- (instancetype) initWithVideoIdentifier:(NSString *)videoIdentifier
{
	if ([[[UIDevice currentDevice] systemVersion] integerValue] >= 8)
		self = [super initWithContentURL:nil];
	else
		self = [super init];
	
	if (!self)
		return nil;
	
	// See https://github.com/0xced/XCDYouTubeKit/commit/cadec1c3857d6a302f71b9ce7d1ae48e389e6890
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
	self.checkURL = NO;
	if (videoIdentifier)
		self.videoIdentifier = videoIdentifier;
	
	return self;
}


#pragma clang diagnostic pop

#pragma mark - Public

- (NSArray *) preferredVideoQualities
{
	if (!_preferredVideoQualities)
		_preferredVideoQualities = @[ XCDYouTubeVideoQualityHTTPLiveStreaming, @(XCDYouTubeVideoQualityHD720), @(XCDYouTubeVideoQualityMedium360), @(XCDYouTubeVideoQualitySmall240) ];
	
	return _preferredVideoQualities;
}

- (void) setVideoIdentifier:(NSString *)videoIdentifier
{
	if ([videoIdentifier isEqual:self.videoIdentifier])
		return;
	
	_videoIdentifier = [videoIdentifier copy];
	
	[self.videoOperation cancel];
	[self forceVideoIdentifier];
}

- (void)forceVideoIdentifier {
	
	[[XCDYouTubeClient defaultClient] setUseCheat:self.checkURL];
	self.videoOperation = [[XCDYouTubeClient defaultClient] getVideoWithIdentifier:self.videoIdentifier completionHandler:^(XCDYouTubeVideo *video, NSError *error)
						   {
							   if (video)
							   {
								   NSURL *streamURL = nil;
								   for (NSNumber *videoQuality in self.preferredVideoQualities)
								   {
									   streamURL = video.streamURLs[videoQuality];
									   if (streamURL)
									   {
										   [self startVideo:video streamURL:streamURL];
										   break;
									   }
								   }
								   
								   if (!streamURL)
								   {
									   NSError *noStreamError = [NSError errorWithDomain:XCDYouTubeVideoErrorDomain code:XCDYouTubeErrorNoStreamAvailable userInfo:nil];
									   [self stopWithError:noStreamError];
								   }
							   }
							   else
							   {
								   [self stopWithError:error];
							   }
						   }];
}

- (void) presentInView:(UIView *)view
{
	static const void * const XCDYouTubeVideoPlayerViewControllerKey = &XCDYouTubeVideoPlayerViewControllerKey;
	
	self.embedded = YES;
	
	self.moviePlayer.controlStyle = MPMovieControlStyleEmbedded;
	self.moviePlayer.view.frame = CGRectMake(0.f, 0.f, view.bounds.size.width, view.bounds.size.height);
	self.moviePlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	if (![view.subviews containsObject:self.moviePlayer.view])
		[view addSubview:self.moviePlayer.view];
	//objc_setAssociatedObject(view, XCDYouTubeVideoPlayerViewControllerKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Private

- (void) startVideo:(XCDYouTubeVideo *)video streamURL:(NSURL *)streamURL
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	NSMutableDictionary *userInfo = [NSMutableDictionary new];
	if (video.title)
		userInfo[XCDMetadataKeyTitle] = video.title;
	if (video.smallThumbnailURL)
		userInfo[XCDMetadataKeySmallThumbnailURL] = video.smallThumbnailURL;
	if (video.mediumThumbnailURL)
		userInfo[XCDMetadataKeyMediumThumbnailURL] = video.mediumThumbnailURL;
	if (video.largeThumbnailURL)
		userInfo[XCDMetadataKeyLargeThumbnailURL] = video.largeThumbnailURL;
	
	[[NSNotificationCenter defaultCenter] postNotificationName:XCDYouTubeVideoPlayerViewControllerDidReceiveMetadataNotification object:self userInfo:userInfo];
#pragma clang diagnostic pop
	
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:streamURL
														  cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
													  timeoutInterval:10];
	
	[request setHTTPMethod: @"GET"];
	self.currentStreamURL = streamURL;
	if (streamURL) {
		self.urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];

	} else {
		
		[self stopWithError:[NSError errorWithDomain:@"XC" code:401 userInfo:nil]];
	}

}

- (void) stopWithError:(NSError *)error
{
	NSDictionary *userInfo = @{ MPMoviePlayerPlaybackDidFinishReasonUserInfoKey: @(MPMovieFinishReasonPlaybackError),
	                            XCDMoviePlayerPlaybackDidFinishErrorUserInfoKey: error };
	[[NSNotificationCenter defaultCenter] postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:self.moviePlayer userInfo:userInfo];
	
	if (self.isEmbedded)
		[self.moviePlayer.view removeFromSuperview];
	else
		[self.presentingViewController dismissMoviePlayerViewControllerAnimated];
}

#pragma mark - UIViewController

- (void) viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	if (![self isBeingPresented])
		return;
	
	self.moviePlayer.controlStyle = MPMovieControlStyleFullscreen;
	[self.moviePlayer play];
}

- (void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	if (![self isBeingDismissed])
		return;
	
	[self.videoOperation cancel];
}

@end
