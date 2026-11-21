#import "IOSShapingProbe.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// Isolated probe. The Objective-C WebKit calls avoid libswiftWebKit on older
// simulators. The Runner registration is installed only in a scratch project.
@interface Phase7BA4Renderer : UIPrintPageRenderer
@end

@implementation Phase7BA4Renderer
- (CGRect)paperRect { return CGRectMake(0, 0, 595.276, 841.89); }
- (CGRect)printableRect { return self.paperRect; }
@end

@interface Phase7BIOSShapingProbe : NSObject <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) FlutterResult pending;
- (void)render:(NSString *)html result:(FlutterResult)result;
@end

@implementation Phase7BIOSShapingProbe
- (void)render:(NSString *)html result:(FlutterResult)result {
  if (self.pending != nil) {
    result([FlutterError errorWithCode:@"busy" message:@"A probe is rendering." details:nil]);
    return;
  }
  UIWindow *window = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class]) continue;
    for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
      if (candidate.isKeyWindow) { window = candidate; break; }
    }
    if (window != nil) break;
  }
  UIView *root = window.rootViewController.view;
  if (root == nil) {
    result([FlutterError errorWithCode:@"no_window" message:@"No foreground probe window." details:nil]);
    return;
  }
  self.pending = result;
  WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
  configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
  configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
  self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 595, 842) configuration:configuration];
  self.webView.hidden = YES;
  self.webView.navigationDelegate = self;
  [root addSubview:self.webView];
  [self.webView loadHTMLString:html baseURL:nil];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSString *scheme = action.request.URL.scheme;
  decisionHandler(scheme == nil || [scheme isEqualToString:@"about"]
      ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  __weak Phase7BIOSShapingProbe *weakSelf = self;
  [webView callAsyncJavaScript:@"await Promise.all(Array.from(document.fonts).map(font => font.load())); return true;"
      arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result, NSError *error) {
    Phase7BIOSShapingProbe *owner = weakSelf;
    if (owner == nil || owner.webView != webView) return;
    if (error != nil) { [owner fail:@"font_load" error:error]; return; }
    Phase7BA4Renderer *renderer = [Phase7BA4Renderer new];
    [renderer addPrintFormatter:webView.viewPrintFormatter startingAtPageAtIndex:0];
    NSInteger count = renderer.numberOfPages;
    if (count < 1) {
      [owner finish:[FlutterError errorWithCode:@"empty" message:@"The formatter returned no pages." details:nil]];
      return;
    }
    UIGraphicsPDFRenderer *pdf = [[UIGraphicsPDFRenderer alloc] initWithBounds:renderer.paperRect];
    NSData *bytes = [pdf PDFDataWithActions:^(UIGraphicsPDFRendererContext *context) {
      [renderer prepareForDrawingPages:NSMakeRange(0, count)];
      for (NSInteger page = 0; page < count; page++) {
        [context beginPage];
        [renderer drawPageAtIndex:page inRect:renderer.paperRect];
      }
    }];
    [owner finish:[FlutterStandardTypedData typedDataWithBytes:bytes]];
  }];
}

- (void)webView:(WKWebView *)view didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  [self fail:@"navigation" error:error];
}

- (void)webView:(WKWebView *)view didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  [self fail:@"navigation" error:error];
}

- (void)fail:(NSString *)code error:(NSError *)error {
  [self finish:[FlutterError errorWithCode:code message:error.localizedDescription details:nil]];
}

- (void)finish:(id)value {
  [self.webView removeFromSuperview];
  self.webView = nil;
  FlutterResult callback = self.pending;
  self.pending = nil;
  if (callback != nil) callback(value);
}
@end

void InstallPhase7BIOSShapingProbe(NSObject<FlutterBinaryMessenger> *messenger) {
  Phase7BIOSShapingProbe *probe = [Phase7BIOSShapingProbe new];
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"cpd_tracker/phase7b_probe"
                                                            binaryMessenger:messenger];
  [channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    if (![call.method isEqualToString:@"render"] || ![call.arguments isKindOfClass:NSString.class]) {
      result(FlutterMethodNotImplemented);
      return;
    }
    [probe render:call.arguments result:result];
  }];
}
