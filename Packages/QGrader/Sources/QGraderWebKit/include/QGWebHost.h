#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns the bytes for a bundle-relative path, or nil when missing.
typedef NSData *_Nullable (^QGWebFileProvider)(NSString *path);

/// A hidden WKWebView serving the grader bundle from the custom scheme qgrader://grader/.
/// Written in Objective-C so QGrader never imports WebKit from Swift: that import
/// autolinks libswiftWebKit, which the Xcode 16.4 / iOS 18.5 simulator runtime does not
/// provide to test bundles (the host app and the package tests then crash at launch).
/// All methods must be called on the main thread.
@interface QGWebHost : NSObject

/// `onMessage` receives "ready" or "error: ..." posted by the page's module script.
- (instancetype)initWithIndexHTML:(NSString *)indexHTML
                         provider:(QGWebFileProvider)provider
                        onMessage:(void (^)(NSString *message))onMessage;

- (void)start;

/// Evaluates `return window.__qmGrade(json)` and passes the string result (or an error text).
- (void)gradeJSON:(NSString *)json completion:(void (^)(NSString *_Nullable result, NSString *_Nullable error))completion;

- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
