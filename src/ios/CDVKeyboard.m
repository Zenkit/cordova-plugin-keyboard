#import "CDVKeyboard.h"
#import <Cordova/CDVAvailability.h>
#import <Cordova/NSDictionary+CordovaPreferences.h>
#import <objc/runtime.h>

@interface CDVKeyboard () <UIScrollViewDelegate>

@property(nonatomic, readwrite, assign) BOOL keyboardIsVisible;
@property(readwrite, assign, nonatomic) BOOL keyboardShrinksView;
@property(readwrite, assign, nonatomic) BOOL hideFormAccessoryBar;
@property(readwrite, assign, nonatomic) BOOL keyboardDisablesScrolling;
@property(readwrite, assign, nonatomic) UIKeyboardAppearance keyboardAppearance;

@end

@implementation CDVKeyboard

#pragma mark CordovaHelper
- (void)fireWindowEvent:(NSString *)event {
    NSString *js = [NSString stringWithFormat:@"cordova.fireWindowEvent('%@')", event];
    // Don't schedule the js in the run loop so the the window event handler can handle the events
    // as soon as possible.
    [self.commandDelegate evalJs:js scheduledOnRunLoop:false];
}

#pragma mark Initialize

NSString *WKClassString;
NSString *UITraitsClassString;

- (void)pluginInitialize {
    WKClassString = @"WKContentView";
    UITraitsClassString = @"UITextInputTraits";

    NSDictionary *settings = self.commandDelegate.settings;

    self.keyboardShrinksView = [settings cordovaBoolSettingForKey:@"KeyboardShrinksView"
                                                     defaultValue:YES];

    Boolean hide = [settings cordovaBoolSettingForKey:@"HideKeyboardFormAccessoryBar"
                                         defaultValue:YES];
    [self setHideFormAccessoryBar:hide];

    Boolean disabled = [settings cordovaBoolSettingForKey:@"KeyboardDisablesScrolling"
                                             defaultValue:YES];
    [self setKeyboardDisablesScrolling:disabled];

    NSString *keyboardStyle = [settings cordovaSettingForKey:@"KeyboardStyle"];

    if (keyboardStyle) {
        [self setKeyboardAppearanceForStyle:keyboardStyle];
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    [nc addObserver:self
           selector:@selector(onKeyboardWillHide:)
               name:UIKeyboardWillHideNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(onKeyboardDidHide:)
               name:UIKeyboardDidHideNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(onKeyboardWillShow:)
               name:UIKeyboardWillShowNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(onKeyboardDidShow:)
               name:UIKeyboardDidShowNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(onKeyboardWillChangeFrame:)
               name:UIKeyboardWillChangeFrameNotification
             object:nil];

    // Prevent WKWebView to resize window
    [nc removeObserver:self.webView name:UIKeyboardWillHideNotification object:nil];
    [nc removeObserver:self.webView name:UIKeyboardWillShowNotification object:nil];
    [nc removeObserver:self.webView name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc removeObserver:self.webView name:UIKeyboardDidChangeFrameNotification object:nil];
}

#pragma mark KeyboardEvents

- (void)onKeyboardWillShow:(NSNotification *)notification {
    [self fireWindowEvent:@"keyboardWillShow"];
    self.keyboardIsVisible = YES;
}
- (void)onKeyboardDidShow:(NSNotification *)notification {
    [self fireWindowEvent:@"keyboardDidShow"];
}
- (void)onKeyboardWillHide:(NSNotification *)notification {
    [self fireWindowEvent:@"keyboardWillHide"];
    self.keyboardIsVisible = NO;
}
- (void)onKeyboardDidHide:(NSNotification *)notification {
    [self fireWindowEvent:@"keyboardDidHide"];
}
- (void)onKeyboardWillChangeFrame:(NSNotification *)notification {
    // If the view is not visible, we should do nothing. E.g. if the inappbrowser
    // is open.
    if (!(self.viewController.isViewLoaded && self.viewController.view.window)) {
        return;
    }

    // Note: we check for _keyboardShrinksView at this point instead of the
    // beginning of the method to handle the case where the user disabled
    // shrinkView while the keyboard is showing.
    if (!_keyboardShrinksView) {
        return;
    }

    // Delay the actual resizing so the will show/hide events fire first.
    [self performSelector:@selector(resizeView:) withObject:notification afterDelay:0];
}

#pragma mark KeyboardAppearance

- (void)setKeyboardAppearance:(UIKeyboardAppearance)keyboardAppearance {
    if (keyboardAppearance == _keyboardAppearance) {
        return;
    }

    IMP appearanceImpl = imp_implementationWithBlock(^(id _s) {
      return keyboardAppearance;
    });

    for (NSString *classString in @[ WKClassString, UITraitsClassString ]) {
        Class class = NSClassFromString(classString);
        SEL selector = @selector(keyboardAppearance);
        Method method = class_getInstanceMethod(class, selector);

        if (method != NULL) {
            method_setImplementation(method, appearanceImpl);
        } else {
            class_addMethod(class, selector, appearanceImpl, "l@:");
        }
    }

    _keyboardAppearance = keyboardAppearance;
}

- (void)setKeyboardAppearanceForStyle:(NSString *)style {
    UIKeyboardAppearance appearance = UIKeyboardAppearanceLight;
    if ([[style lowercaseString] isEqualToString:@"dark"]) {
        appearance = UIKeyboardAppearanceDark;
    }
    [self setKeyboardAppearance:appearance];
}

#pragma mark HideFormAccessoryBar

static IMP WKOriginalImp;

- (void)setHideFormAccessoryBar:(BOOL)hideFormAccessoryBar {
    if (hideFormAccessoryBar == _hideFormAccessoryBar) {
        return;
    }

    Method WKMethod =
        class_getInstanceMethod(NSClassFromString(WKClassString), @selector(inputAccessoryView));

    if (hideFormAccessoryBar) {
        WKOriginalImp = method_getImplementation(WKMethod);

        IMP hideFormAccessoryBarImpl = imp_implementationWithBlock(^(id _s) {
          return nil;
        });

        method_setImplementation(WKMethod, hideFormAccessoryBarImpl);
    } else {
        method_setImplementation(WKMethod, WKOriginalImp);
    }

    _hideFormAccessoryBar = hideFormAccessoryBar;
}

#pragma mark KeyboardShrinksView

- (void)resizeView:(NSNotification *)notification {
    CGRect keyboardEnd =
        [[notification.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];

    double duration =
        [[notification.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve =
        [[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];

    CGRect frame = self.webView.frame;
    CGFloat maxHeight = self.webView.superview.frame.size.height;
    id coordinateSpace = self.webView.window.screen.coordinateSpace;
    CGFloat relativeFrameY =
        [self.webView convertPoint:frame.origin toCoordinateSpace:coordinateSpace].y;
    CGFloat keyboardY = [self.webView convertPoint:keyboardEnd.origin toView:nil].y;

    // NOTE: We set the web view height to the y position of keyboard, 
    // this should prevent an error in the calculation beeing carried over.
    // (e.g. the view could already be changed because we call this with a delay)
    // But we need to calculate the y position relative to the view position on the screem.
    // (e.g. to account for the statusbar or the "Slide Over" multitask mode on iPads)
    // We also don't allow the view to get height than it's superview, because this should never be valid.
    CGFloat relativeKeyboardY = keyboardY - relativeFrameY;
    CGFloat frameHeight = relativeKeyboardY > maxHeight ? maxHeight : relativeKeyboardY;
    frame.size.height = frameHeight;

    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    self.webView.frame = frame;
    [UIView commitAnimations];
}

#pragma mark KeyboardDisablesScrolling
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [scrollView setContentOffset:CGPointZero];
}

- (void)setKeyboardDisablesScrolling:(BOOL)keyboardDisablesScrolling {
    if (keyboardDisablesScrolling == _keyboardDisablesScrolling) {
        return;
    }

    if (keyboardDisablesScrolling) {
        self.webView.scrollView.scrollEnabled = NO;
        self.webView.scrollView.delegate = self;
    } else {
        self.webView.scrollView.scrollEnabled = YES;
        self.webView.scrollView.delegate = nil;
    }

    _keyboardDisablesScrolling = keyboardDisablesScrolling;
}

#pragma mark Plugin Interface

- (void)keyboardShrinksView:(CDVInvokedUrlCommand *)command {
    if (command.arguments.count > 0) {
        id value = [command.arguments objectAtIndex:0];
        if (!([value isKindOfClass:[NSNumber class]])) {
            value = [NSNumber numberWithBool:NO];
        }

        self.keyboardShrinksView = [value boolValue];
    }

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                  messageAsBool:self.keyboardShrinksView];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)keyboardDisablesScrolling:(CDVInvokedUrlCommand *)command {
    Boolean disabled = self.keyboardDisablesScrolling;
    if (command.arguments.count > 0) {
        id value = [command.arguments objectAtIndex:0];
        if (!([value isKindOfClass:[NSNumber class]])) {
            value = [NSNumber numberWithBool:NO];
        }

        disabled = [value boolValue];
    }

    [self setKeyboardDisablesScrolling:disabled];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                  messageAsBool:self.keyboardDisablesScrolling];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)hideFormAccessoryBar:(CDVInvokedUrlCommand *)command {
    Boolean hide = self.hideFormAccessoryBar;
    if (command.arguments.count > 0) {
        id value = [command.arguments objectAtIndex:0];
        if (!([value isKindOfClass:[NSNumber class]])) {
            value = [NSNumber numberWithBool:NO];
        }

        hide = [value boolValue];
    }

    [self setHideFormAccessoryBar:hide];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                  messageAsBool:self.hideFormAccessoryBar];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)hide:(CDVInvokedUrlCommand *)command {
    [self.webView endEditing:YES];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)setKeyboardStyle:(CDVInvokedUrlCommand *)command {
    NSString *style = @"light";
    id value = [command.arguments objectAtIndex:0];
    if ([value isKindOfClass:[NSString class]]) {
        style = (NSString *)value;
    }

    [self setKeyboardAppearanceForStyle:style];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark dealloc

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
