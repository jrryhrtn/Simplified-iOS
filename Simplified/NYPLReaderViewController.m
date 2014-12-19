#import "NYPLBook.h"
#import "NYPLBookLocation.h"
#import "NYPLConfiguration.h"
#import "NYPLJSON.h"
#import "NYPLMyBooksDownloadCenter.h"
#import "NYPLMyBooksRegistry.h"
#import "NYPLReaderSettingsView.h"
#import "NYPLReaderTOCViewController.h"
#import "NYPLReadium.h"
#import "NYPLRoundedButton.h"
#import "UIColor+NYPLColorAdditions.h"

#import "NYPLReaderViewController.h"

@interface NYPLReaderViewController ()
  <NYPLReaderSettingsViewDelegate, NYPLReaderTOCViewControllerDelegate, RDContainerDelegate,
   RDPackageResourceServerDelegate, UIPopoverControllerDelegate, UIScrollViewDelegate,
   UIWebViewDelegate>

@property (nonatomic) UIPopoverController *activePopoverController;
@property (nonatomic) BOOL bookIsCorrupt;
@property (nonatomic) NSString *bookIdentifier;
@property (nonatomic) RDContainer *container;
@property (nonatomic) BOOL interfaceHidden;
@property (nonatomic) BOOL mediaOverlayIsPlaying;
@property (nonatomic) NSInteger openPageCount;
@property (nonatomic) RDPackage *package;
@property (nonatomic) NSInteger pageInCurrentSpineItemCount;
@property (nonatomic) NSInteger pageInCurrentSpineItemIndex;
@property (nonatomic) BOOL pageProgressionIsLTR;
@property (nonatomic) BOOL paginationHasChanged;
@property (nonatomic) NYPLReaderSettingsView *readerSettingsViewPhone;
@property (nonatomic) RDPackageResourceServer *server;
@property (nonatomic) UIBarButtonItem *settingsBarButtonItem;
@property (nonatomic) BOOL shouldHideInterfaceOnNextAppearance;
@property (nonatomic) NSInteger spineItemIndex;
@property (nonatomic) UIWebView *webView;

@end

id argument(NSURL *const URL) {
  NSString *const s = URL.resourceSpecifier;
  
  NSRange const range = [s rangeOfString:@"/"];
  
  assert(range.location != NSNotFound);
  
  NSData *const data = [[[s substringFromIndex:(range.location + 1)]
                         stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                        dataUsingEncoding:NSUTF8StringEncoding];
  
  return NYPLJSONObjectFromData(data);
}

@implementation NYPLReaderViewController

- (void)applyCurrentStyles
{
  NSArray *const styles = [[NYPLReaderSettings sharedSettings] readiumStylesRepresentation];
  
  NSString *const stylesString = [[NSString alloc]
                                  initWithData:NYPLJSONDataFromObject(styles)
                                  encoding:NSUTF8StringEncoding];
  
  
  NSString *const javaScript =
  [NSString stringWithFormat:
   @"ReadiumSDK.reader.setBookStyles(%@);"
   @"document.body.style.backgroundColor = \"%@\";",
   stylesString,
   [[NYPLReaderSettings sharedSettings].backgroundColor javascriptHexString]];
  
  [self.webView stringByEvaluatingJavaScriptFromString:javaScript];
  
  self.webView.backgroundColor = [NYPLReaderSettings sharedSettings].backgroundColor;
  
  self.navigationController.navigationBar.barTintColor = self.webView.backgroundColor;
  
  switch([NYPLReaderSettings sharedSettings].colorScheme) {
    case NYPLReaderSettingsColorSchemeBlackOnSepia:
      // fallthrough
    case NYPLReaderSettingsColorSchemeBlackOnWhite:
      self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
      break;
    case NYPLReaderSettingsColorSchemeWhiteOnBlack:
      self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
      break;
  }
  
  self.activePopoverController.backgroundColor =
    [NYPLReaderSettings sharedSettings].backgroundColor;
}

- (void)applyCurrentSettings
{
  [self.webView stringByEvaluatingJavaScriptFromString:
   [NSString stringWithFormat:
    @"ReadiumSDK.reader.updateSettings(%@)",
    [[NSString alloc]
     initWithData:NYPLJSONDataFromObject([[NYPLReaderSettings sharedSettings]
                                          readiumSettingsRepresentation])
     encoding:NSUTF8StringEncoding]]];
}

#pragma mark NSObject

- (instancetype)initWithBookIdentifier:(NSString *const)bookIdentifier
{
  self = [super init];
  if(!self) return nil;
  
  if(!bookIdentifier) {
    @throw NSInvalidArgumentException;
  }
  
  self.title = [[NYPLMyBooksRegistry sharedRegistry]
                bookForIdentifier:bookIdentifier].title;
  
  self.bookIdentifier = bookIdentifier;
  
  @try {
    self.container = [[RDContainer alloc]
                      initWithDelegate:self
                      path:[[[NYPLMyBooksDownloadCenter sharedDownloadCenter]
                             fileURLForBookIndentifier:bookIdentifier]
                            path]];
  } @catch (...) {
    self.bookIsCorrupt = YES;
    [[[UIAlertView alloc]
      initWithTitle:NSLocalizedString(@"ReaderViewControllerCorruptTitle", nil)
      message:NSLocalizedString(@"ReaderViewControllerCorruptMessage", nil)
      delegate:nil
      cancelButtonTitle:nil
      otherButtonTitles:NSLocalizedString(@"OK", nil), nil]
     show];
  }
  
  self.package = self.container.firstPackage;
  self.server = [[RDPackageResourceServer alloc]
                 initWithDelegate:self
                 package:self.package
                 specialPayloadAnnotationsCSS:nil
                 specialPayloadMathJaxJS:nil];

  self.hidesBottomBarWhenPushed = YES;
  
  [[NYPLMyBooksRegistry sharedRegistry]
   setState:NYPLMYBooksStateUsed
   forIdentifier:bookIdentifier];
  
  return self;
}

#pragma mark UIViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.automaticallyAdjustsScrollViewInsets = NO;

  self.shouldHideInterfaceOnNextAppearance = YES;
  
  self.view.backgroundColor = [NYPLConfiguration backgroundColor];
  
  NYPLRoundedButton *const settingsButton = [NYPLRoundedButton button];
  [settingsButton setTitle:@"Aa" forState:UIControlStateNormal];
  [settingsButton sizeToFit];
  // We set a larger font after sizing because we want large text in a standard-size button.
  settingsButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:18];
  [settingsButton addTarget:self
                     action:@selector(didSelectSettings)
           forControlEvents:UIControlEventTouchUpInside];
  
  self.settingsBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:settingsButton];
  
  NYPLRoundedButton *const TOCButton = [NYPLRoundedButton button];
  TOCButton.bounds = settingsButton.bounds;
  [TOCButton setImage:[UIImage imageNamed:@"TOC"] forState:UIControlStateNormal];
  [TOCButton addTarget:self
                action:@selector(didSelectTOC)
      forControlEvents:UIControlEventTouchUpInside];
  
  UIBarButtonItem *const TOCBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:TOCButton];
  
  // |setBookIsCorrupt:| may have been called before we added these, so we need to set their
  // enabled status appropriately here too.
  self.navigationItem.rightBarButtonItems = @[TOCBarButtonItem, self.settingsBarButtonItem];
  if(self.bookIsCorrupt) {
    for(UIBarButtonItem *const item in self.navigationItem.rightBarButtonItems) {
      item.enabled = NO;
    }
  }
  
  self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
  self.webView.autoresizingMask = (UIViewAutoresizingFlexibleHeight |
                                   UIViewAutoresizingFlexibleWidth);
  self.webView.delegate = self;
  self.webView.scrollView.bounces = NO;
  self.webView.hidden = YES;
  self.webView.scrollView.delegate = self;
  [self.view addSubview:self.webView];
  
  NSURL *const readerURL = [[NSBundle mainBundle]
                            URLForResource:@"reader"
                            withExtension:@"html"];
  
  assert(readerURL);
  
  [self.webView loadRequest:[NSURLRequest requestWithURL:readerURL]];
}

- (BOOL)prefersStatusBarHidden
{
  return self.interfaceHidden;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation
{
  return UIStatusBarAnimationNone;
}

- (void)viewWillAppear:(BOOL)animated
{
  self.navigationItem.titleView = [[UIView alloc] init];

  [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
  if(self.shouldHideInterfaceOnNextAppearance) {
    self.shouldHideInterfaceOnNextAppearance = NO;
    self.interfaceHidden = YES;
  }

  [super viewDidAppear:animated];
}

- (void)willMoveToParentViewController:(__attribute__((unused)) UIViewController *)parent
{
  self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
  self.navigationController.navigationBar.barTintColor = nil;
}

#pragma mark UIWebViewDelegate

- (BOOL)
webView:(__attribute__((unused)) UIWebView *)webView
shouldStartLoadWithRequest:(NSURLRequest *const)request
navigationType:(__attribute__((unused)) UIWebViewNavigationType)navigationType
{
  if(self.bookIsCorrupt) {
    return NO;
  }
  
  if([request.URL.scheme isEqualToString:@"simplified"]) {
    NSArray *const components = [request.URL.resourceSpecifier componentsSeparatedByString:@"/"];
    NSString *const function = components[0];
    if([function isEqualToString:@"gesture-left"]) {
      [self.webView stringByEvaluatingJavaScriptFromString:@"ReadiumSDK.reader.openPageLeft()"];
    } else if([function isEqualToString:@"gesture-right"]) {
      [self.webView stringByEvaluatingJavaScriptFromString:@"ReadiumSDK.reader.openPageRight()"];
    } else if([function isEqualToString:@"gesture-center"]) {
      self.interfaceHidden = !self.interfaceHidden;
    } else {
      NYPLLOG(@"Ignoring unknown simplified function.");
    }
    return NO;
  }
  
  if([request.URL.scheme isEqualToString:@"readium"]) {
    NSArray *const components = [request.URL.resourceSpecifier componentsSeparatedByString:@"/"];
    NSString *const function = components[0];
    if([function isEqualToString:@"initialize"]) {
      [self readiumInitialize];
    } else if([function isEqualToString:@"pagination-changed"]) {
      [self readiumPaginationChangedWithDictionary:argument(request.URL)];
    } else if([function isEqualToString:@"media-overlay-status-changed"]) {
      NSDictionary *const dict = argument(request.URL);
      self.mediaOverlayIsPlaying = ((NSNumber *) dict[@"isPlaying"]).boolValue;
    } else if([function isEqualToString:@"settings-applied"]) {
      // Do nothing.
    } else {
      NYPLLOG(@"Ignoring unknown readium function.");
    }
    return NO;
  }
  
  return YES;
}

#pragma mark UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
  assert(popoverController == self.activePopoverController);
  
  self.activePopoverController = nil;
}

#pragma mark UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(__attribute__((unused)) UIScrollView *)scrollView
{
  return nil;
}

#pragma mark NYPLReaderTOCViewControllerDelegate

- (void)TOCViewController:(__attribute__((unused)) NYPLReaderTOCViewController *)controller
didSelectNavigationElement:(RDNavigationElement *)navigationElement
{
  [self.webView stringByEvaluatingJavaScriptFromString:
   [NSString stringWithFormat:@"ReadiumSDK.reader.openContentUrl('%@', '%@')",
    navigationElement.content,
    navigationElement.sourceHref]];
  
  if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
    [self.activePopoverController dismissPopoverAnimated:YES];
    self.interfaceHidden = YES;
  } else {
    self.shouldHideInterfaceOnNextAppearance = YES;
    [self.navigationController popViewControllerAnimated:YES];
  }
}

#pragma mark RDContainerDelegate

- (void)rdcontainer:(__attribute__((unused)) RDContainer *)container
     handleSdkError:(NSString *const)message
{
  NYPLLOG_F(@"Readium: %@", message);
}

#pragma mark RDPackageResourceServerDelegate

- (void)
rdpackageResourceServer:(__attribute__((unused)) RDPackageResourceServer *)packageResourceServer
executeJavaScript:(NSString *const)javaScript
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    [self.webView stringByEvaluatingJavaScriptFromString:javaScript];
  }];
}

#pragma mark NYPLReaderSettingsViewDelegate

- (void)readerSettingsView:(__attribute__((unused)) NYPLReaderSettingsView *)readerSettingsView
       didSelectBrightness:(CGFloat const)brightness
{
  [UIScreen mainScreen].brightness = brightness;
}

- (void)readerSettingsView:(__attribute__((unused)) NYPLReaderSettingsView *)readerSettingsView
      didSelectColorScheme:(NYPLReaderSettingsColorScheme const)colorScheme
{
  [NYPLReaderSettings sharedSettings].colorScheme = colorScheme;
  
  [self applyCurrentStyles];
}

- (void)readerSettingsView:(__attribute__((unused)) NYPLReaderSettingsView *)readerSettingsView
         didSelectFontSize:(NYPLReaderSettingsFontSize const)fontSize
{
  [NYPLReaderSettings sharedSettings].fontSize = fontSize;
  
  [self applyCurrentSettings];
}

- (void)readerSettingsView:(__attribute__((unused)) NYPLReaderSettingsView *)readerSettingsView
         didSelectFontFace:(NYPLReaderSettingsFontFace)fontFace
{
  NSString *fontFamily = nil;
  
  switch(fontFace) {
    case NYPLReaderSettingsFontFaceSans:
      fontFamily = @"HelveticaNeue";
      break;
    case NYPLReaderSettingsFontFaceSerif:
      fontFamily = @"Georgia";
      break;
  }
  
  [self.webView stringByEvaluatingJavaScriptFromString:
   [NSString stringWithFormat:
    @"window.frames[\"epubContentIframe\"].document.body.style.fontFamily = \"%@\"",
    fontFamily]];
  
  [NYPLReaderSettings sharedSettings].fontFace = fontFace;
}

#pragma mark -

- (void)setBookIsCorrupt:(BOOL const)bookIsCorrupt
{
  _bookIsCorrupt = bookIsCorrupt;
  
  for(UIBarButtonItem *const item in self.navigationItem.rightBarButtonItems) {
    item.enabled = !bookIsCorrupt;
  }
  
  // Show the interface so the user can get back out.
  if(bookIsCorrupt) {
    self.interfaceHidden = NO;
  }
}

- (void)setInterfaceHidden:(BOOL)interfaceHidden
{
  if(self.bookIsCorrupt && interfaceHidden) {
    // Hiding the UI would prevent the user from escaping from a corrupt book.
    return;
  }
  
  _interfaceHidden = interfaceHidden;
  
  self.navigationController.interactivePopGestureRecognizer.enabled = !interfaceHidden;
  
  self.navigationController.navigationBarHidden = self.interfaceHidden;
  
  if(self.interfaceHidden) {
    [self.readerSettingsViewPhone removeFromSuperview];
    self.readerSettingsViewPhone = nil;
  }
  
  [self setNeedsStatusBarAppearanceUpdate];
}

- (void)didSelectSettings
{
  if(self.readerSettingsViewPhone) {
    [self.readerSettingsViewPhone removeFromSuperview];
    self.readerSettingsViewPhone = nil;
    return;
  }
  
  NYPLReaderSettingsView *const readerSettingsView = [[NYPLReaderSettingsView alloc] init];
  readerSettingsView.delegate = self;
  readerSettingsView.colorScheme = [NYPLReaderSettings sharedSettings].colorScheme;
  readerSettingsView.fontSize = [NYPLReaderSettings sharedSettings].fontSize;
  readerSettingsView.fontFace = [NYPLReaderSettings sharedSettings].fontFace;
  
  if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
    UIViewController *const viewController = [[UIViewController alloc] init];
    viewController.view = readerSettingsView;
    viewController.preferredContentSize = viewController.view.bounds.size;
    [self.activePopoverController dismissPopoverAnimated:NO];
    self.activePopoverController =
      [[UIPopoverController alloc] initWithContentViewController:viewController];
    self.activePopoverController.backgroundColor =
      [NYPLReaderSettings sharedSettings].backgroundColor;
    self.activePopoverController.delegate = self;
    [self.activePopoverController
     presentPopoverFromBarButtonItem:self.settingsBarButtonItem
     permittedArrowDirections:UIPopoverArrowDirectionUp
     animated:YES];
  } else {
    readerSettingsView.frame = CGRectOffset(readerSettingsView.frame,
                                            0,
                                            (CGRectGetHeight(self.view.frame) -
                                             CGRectGetHeight(readerSettingsView.frame)));
    [self.view addSubview:readerSettingsView];
    self.readerSettingsViewPhone = readerSettingsView;
  }
}

- (void)didSelectTOC
{
  NYPLReaderTOCViewController *const viewController =
    [[NYPLReaderTOCViewController alloc] initWithNavigationElement:self.package.tableOfContents];
  
  viewController.delegate = self;
  
  if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
    [self.activePopoverController dismissPopoverAnimated:NO];
    self.activePopoverController =
      [[UIPopoverController alloc] initWithContentViewController:viewController];
    self.activePopoverController.delegate = self;
    self.activePopoverController.backgroundColor =
      [NYPLReaderSettings sharedSettings].backgroundColor;
    [self.activePopoverController
     presentPopoverFromBarButtonItem:self.navigationItem.rightBarButtonItem
     permittedArrowDirections:UIPopoverArrowDirectionUp
     animated:YES];
  } else {
    [self.navigationController pushViewController:viewController animated:YES];
  }
}

- (void)readiumInitialize
{
  if(!self.package.spineItems[0]) {
    self.bookIsCorrupt = YES;
    [[[UIAlertView alloc]
      initWithTitle:NSLocalizedString(@"ReaderViewControllerCorruptTitle", nil)
      message:NSLocalizedString(@"ReaderViewControllerCorruptMessage", nil)
      delegate:nil
      cancelButtonTitle:nil
      otherButtonTitles:NSLocalizedString(@"OK", nil), nil]
     show];
    return;
  }
  
  self.package.rootURL = [NSString stringWithFormat:@"http://127.0.0.1:%d/", self.server.port];

  NYPLBookLocation *const location = [[NYPLMyBooksRegistry sharedRegistry]
                                      locationForIdentifier:self.bookIdentifier];
  
  NSMutableDictionary *const dictionary = [NSMutableDictionary dictionary];
  dictionary[@"package"] = self.package.dictionary;
  dictionary[@"settings"] = [[NYPLReaderSettings sharedSettings] readiumSettingsRepresentation];
  if(location) {
    if(location.CFI) {
      dictionary[@"openPageRequest"] = @{@"idref": location.idref, @"elementCfi" : location.CFI};
    } else {
      dictionary[@"openPageRequest"] = @{@"idref": location.idref};
    }
  }
  
  NSData *data = NYPLJSONDataFromObject(dictionary);
  
  if(!data) {
    NYPLLOG(@"Failed to construct 'openBook' call.");
    return;
  }
  
  [self.webView stringByEvaluatingJavaScriptFromString:
   [NSString stringWithFormat:@"ReadiumSDK.reader.openBook(%@)",
    [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]];
}

- (void)readiumPaginationChangedWithDictionary:(NSDictionary *const)dictionary
{
  // If the book is finished opening, set all stylistic preferences.
  if(!self.paginationHasChanged) {
    self.paginationHasChanged = YES;
    [self readerSettingsView:nil
        didSelectColorScheme:[NYPLReaderSettings sharedSettings].colorScheme];
    [self readerSettingsView:nil
           didSelectFontSize:[NYPLReaderSettings sharedSettings].fontSize];
    [self readerSettingsView:nil
           didSelectFontFace:[NYPLReaderSettings sharedSettings].fontFace];
  }
  
  [self.webView stringByEvaluatingJavaScriptFromString:@"simplified.pageDidChange();"];
  
  // Use left-to-right unless it explicitly asks for right-to-left.
  self.pageProgressionIsLTR = ![dictionary[@"pageProgressionDirection"]
                                isEqualToString:@"rtl"];
  
  NSArray *const openPages = dictionary[@"openPages"];
  
  self.openPageCount = openPages.count;
  
  if(self.openPageCount >= 1) {
    NSDictionary *const page = openPages[0];
    self.pageInCurrentSpineItemCount =
    ((NSNumber *) page[@"spineItemPageCount"]).integerValue;
    self.pageInCurrentSpineItemIndex =
    ((NSNumber *) page[@"spineItemPageIndex"]).integerValue;
    self.spineItemIndex = ((NSNumber *) page[@"spineItemIndex"]).integerValue;
  }
  
  NSString *const locationJSON = [self.webView stringByEvaluatingJavaScriptFromString:
                                  @"ReadiumSDK.reader.bookmarkCurrentPage()"];
  
  NSDictionary *const locationDictionary =
    NYPLJSONObjectFromData([locationJSON dataUsingEncoding:NSUTF8StringEncoding]);
  
  NYPLBookLocation *const location = [[NYPLBookLocation alloc]
                                      initWithCFI:locationDictionary[@"contentCFI"]
                                      idref:locationDictionary[@"idref"]];
  
  if(location) {
    [[NYPLMyBooksRegistry sharedRegistry]
     setLocation:location
     forIdentifier:self.bookIdentifier];
  }
  
  self.webView.hidden = NO;
}

@end
