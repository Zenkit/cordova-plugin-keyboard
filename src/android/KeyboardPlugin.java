package org.apache.cordova.labs.keyboard;

import android.content.Context;
import android.graphics.Point;
import android.graphics.Rect;
import android.os.Build;
import android.util.DisplayMetrics;
import android.view.Display;
import android.view.View;
import android.view.ViewTreeObserver.OnGlobalLayoutListener;
import android.view.inputmethod.InputMethodManager;
import org.apache.cordova.*;
import org.json.JSONArray;
import org.json.JSONException;

public class KeyboardPlugin extends CordovaPlugin {
    private View rootView;
    private boolean keyboardWasOpen = false;
    private OnGlobalLayoutListener listener;

    private InputMethodManager getInputManager() {
        return (InputMethodManager) cordova.getActivity().getSystemService(
            Context.INPUT_METHOD_SERVICE);
    }

    private void fireWindowEvent(String event) {
        cordova.getActivity().runOnUiThread((Runnable) () -> {
            String js = "cordova.fireWindowEvent('" + event + "');";
            webView.getEngine().evaluateJavascript(js, null);
        });
    }

    private int getScreenHeight() {
        if (Build.VERSION.SDK_INT < 21) {
            return rootView.getRootView().getHeight();
        }

        Point size = new Point();
        Display display = cordova.getActivity().getWindowManager().getDefaultDisplay();
        display.getSize(size);
        return size.y;
    }

    @Override
    protected void pluginInitialize() {
        super.pluginInitialize();

        DisplayMetrics dm = new DisplayMetrics();
        cordova.getActivity().getWindowManager().getDefaultDisplay().getMetrics(dm);
        final float density = dm.density;

        // TODO: Maybe use setOnApplyWindowInsetsListener to implement the will show/hide events
        rootView = cordova.getActivity().findViewById(android.R.id.content).getRootView();
        listener = () -> {
            Rect r = new Rect();
            rootView.getWindowVisibleDisplayFrame(r);
            int heightDiff = getScreenHeight() - r.bottom;

            // If the diff is more than 100 pixels, its probably a keyboard...
            boolean keyboardIsOpen = (heightDiff / density) > 100;
            if (keyboardWasOpen != keyboardIsOpen) {
                if (keyboardIsOpen) {
                    fireWindowEvent("keyboardWillShow");
                    fireWindowEvent("keyboardDidShow");
                } else {
                    fireWindowEvent("keyboardWillHide");
                    fireWindowEvent("keyboardDidHide");
                }
            }
            keyboardWasOpen = keyboardIsOpen;
        };

        rootView.getViewTreeObserver().addOnGlobalLayoutListener(listener);
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        rootView.getViewTreeObserver().removeOnGlobalLayoutListener(listener);
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
