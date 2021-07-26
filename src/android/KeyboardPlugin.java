package org.apache.cordova.labs.keyboard;

import android.content.Context;
import android.graphics.Point;
import android.graphics.Rect;
import android.os.Build;
import android.view.Display;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.ViewTreeObserver.OnGlobalLayoutListener;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import org.apache.cordova.*;
import org.json.JSONArray;

public class KeyboardPlugin extends CordovaPlugin {
    private OnGlobalLayoutListener listener;
    private boolean keyboardWasVisible = false;
    private double KEYBOARD_MIN_HEIGHT_RATIO = 0.15;

    private InputMethodManager getInputManager() {
        return (InputMethodManager) cordova.getActivity().getSystemService(
            Context.INPUT_METHOD_SERVICE);
    }

    private View getContentView() {
        return cordova.getActivity().findViewById(android.R.id.content);
    }

    private ViewTreeObserver getRootViewTreeObserver() {
        return getContentView().getRootView().getViewTreeObserver();
    }
    private ViewTreeObserver getWebViewTreeObserver() {
        return webView.getView().getViewTreeObserver();
    }

    private void fireWindowEvent(String event) {
        cordova.getActivity().runOnUiThread((Runnable) () -> {
            String js = "cordova.fireWindowEvent('" + event + "');";
            webView.getEngine().evaluateJavascript(js, null);
        });
    }
    private void fireWindowEventAfterWebViewLayout(String event) {
        getWebViewTreeObserver().addOnGlobalLayoutListener(new OnGlobalLayoutListener() {
            @Override
            public void onGlobalLayout() {
                fireWindowEvent(event);
                getWebViewTreeObserver().removeOnGlobalLayoutListener(this);
            }
        });
    }

    private int getScreenHeight(View root) {
        if (Build.VERSION.SDK_INT < 21) {
            return root.getRootView().getHeight();
        }

        Point size = new Point();
        Display display = cordova.getActivity().getWindowManager().getDefaultDisplay();
        display.getSize(size);
        return size.y;
    }

    // NOTE: Determine if keyboard is visible
    // (Implementation adapted from https://github.com/yshrsmz/KeyboardVisibilityEvent)
    private boolean isKeyboardVisible() {
        Rect r = new Rect();
        View content = getContentView();
        View root = content.getRootView();
        root.getWindowVisibleDisplayFrame(r);

        int[] location = new int[2];
        content.getLocationOnScreen(location);

        int screenHeight = getScreenHeight(root);
        int heightDiff = screenHeight - r.height() - location[1];

        return heightDiff > screenHeight * KEYBOARD_MIN_HEIGHT_RATIO;
    }

    private boolean isSoftInputAdjustNothing() {
        int softInputMode = cordova.getActivity().getWindow().getAttributes().softInputMode;
        int softInputAdjust = softInputMode & WindowManager.LayoutParams.SOFT_INPUT_MASK_ADJUST;
        return (softInputAdjust & WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING)
            == WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING;
    }

    @Override
    protected void pluginInitialize() {
        super.pluginInitialize();

        // The window will not be resized in case of SOFT_INPUT_ADJUST_NOTHING
        if (isSoftInputAdjustNothing()) {
            return;
        }

        listener = () -> {
            boolean keyboardIsVisible = isKeyboardVisible();
            if (keyboardWasVisible != keyboardIsVisible) {
                if (keyboardIsVisible) {
                    fireWindowEvent("keyboardWillShow");
                    fireWindowEventAfterWebViewLayout("keyboardDidShow");
                } else {
                    fireWindowEvent("keyboardWillHide");
                    fireWindowEventAfterWebViewLayout("keyboardDidHide");
                }
            }
            keyboardWasVisible = keyboardIsVisible;
        };

        getRootViewTreeObserver().addOnGlobalLayoutListener(listener);
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (listener != null) {
            getRootViewTreeObserver().removeOnGlobalLayoutListener(listener);
        }
    }

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) {
        if ("show".equals(action)) {
            cordova.getThreadPool().execute((Runnable) () -> {
                getInputManager().toggleSoftInput(0, InputMethodManager.HIDE_IMPLICIT_ONLY);
                callbackContext.success();
            });
            return true;
        }
        if ("hide".equals(action)) {
            cordova.getThreadPool().execute((Runnable) () -> {
                View view = cordova.getActivity().getCurrentFocus();

                if (view == null) {
                    callbackContext.error("No current focus");
                    return;
                }

                getInputManager().hideSoftInputFromWindow(
                    view.getWindowToken(), InputMethodManager.HIDE_NOT_ALWAYS);
                callbackContext.success();
            });
            return true;
        }
        return false;
    }
}
