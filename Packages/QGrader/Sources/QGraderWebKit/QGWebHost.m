#import "QGWebHost.h"
#import <WebKit/WebKit.h>

/// Forwards script messages without retaining the host (WKUserContentController retains its handlers).
@interface QGWeakScriptHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id<WKScriptMessageHandler> target;
@end

@implementation QGWeakScriptHandler
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.target userContentController:userContentController didReceiveScriptMessage:message];
}
@end

@interface QGWebHost () <WKScriptMessageHandler, WKURLSchemeHandler, WKNavigationDelegate>
@property (nonatomic, copy) NSString *indexHTML;
@property (nonatomic, copy) QGWebFileProvider provider;
@property (nonatomic, copy) void (^onMessage)(NSString *);
@property (nonatomic, strong, nullable) WKWebView *webView;
@end

@implementation QGWebHost

- (instancetype)initWithIndexHTML:(NSString *)indexHTML
                         provider:(QGWebFileProvider)provider
                        onMessage:(void (^)(NSString *))onMessage {
    self = [super init];
    if (self) {
        _indexHTML = [indexHTML copy];
        _provider = [provider copy];
        _onMessage = [onMessage copy];
    }
    return self;
}

- (void)start {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config setURLSchemeHandler:self forURLScheme:@"qgrader"];
    QGWeakScriptHandler *handler = [[QGWeakScriptHandler alloc] init];
    handler.target = self;
    [config.userContentController addScriptMessageHandler:handler name:@"qgrader"];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 1, 1) configuration:config];
    self.webView.navigationDelegate = self;
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"qgrader://grader/index.html"]]];
}

- (void)gradeJSON:(NSString *)json completion:(void (^)(NSString *_Nullable, NSString *_Nullable))completion {
    WKWebView *view = self.webView;
    if (view == nil) {
        completion(nil, @"web view released");
        return;
    }
    [view callAsyncJavaScript:@"return window.__qmGrade(json);"
                    arguments:@{@"json": json}
                      inFrame:nil
               inContentWorld:WKContentWorld.pageWorld
            completionHandler:^(id _Nullable result, NSError *_Nullable error) {
        if (error != nil) {
            completion(nil, error.description);
        } else if ([result isKindOfClass:[NSString class]]) {
            completion((NSString *)result, nil);
        } else {
            completion(nil, @"non-string result");
        }
    }];
}

- (void)shutdown {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"qgrader"];
    [self.webView stopLoading];
    self.webView = nil;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body isKindOfClass:[NSString class]]) {
        self.onMessage((NSString *)message.body);
    }
}

static NSString *QGMimeType(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"html"]) return @"text/html";
    if ([ext isEqualToString:@"js"] || [ext isEqualToString:@"mjs"]) return @"text/javascript";
    if ([ext isEqualToString:@"wasm"]) return @"application/wasm";
    if ([ext isEqualToString:@"json"]) return @"application/json";
    return @"application/octet-stream";
}

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    NSURL *url = urlSchemeTask.request.URL;
    NSString *path = url.path ?: @"";
    if ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
    NSData *data = nil;
    if ([path isEqualToString:@"index.html"]) {
        data = [self.indexHTML dataUsingEncoding:NSUTF8StringEncoding];
    } else if (self.provider != nil) {
        data = self.provider(path);
    }
    if (data == nil) {
        NSHTTPURLResponse *missing = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        [urlSchemeTask didReceiveResponse:missing];
        [urlSchemeTask didFinish];
        return;
    }
    NSDictionary *headers = @{
        @"Content-Type": QGMimeType(path),
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length],
        @"Access-Control-Allow-Origin": @"*",
        @"Cache-Control": @"no-store",
    };
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [urlSchemeTask didReceiveResponse:response];
    [urlSchemeTask didReceiveData:data];
    [urlSchemeTask didFinish];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.onMessage([NSString stringWithFormat:@"error: navigation failed: %@", error]);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.onMessage([NSString stringWithFormat:@"error: provisional navigation failed: %@", error]);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    self.onMessage(@"error: web content process terminated");
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
}

@end
