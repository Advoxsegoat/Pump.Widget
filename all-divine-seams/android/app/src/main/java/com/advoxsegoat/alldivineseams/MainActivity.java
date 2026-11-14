package com.advoxsegoat.alldivineseams;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.DisplayCutout;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.ValueCallback;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
import android.widget.FrameLayout;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * Hosts the web build of Between the Rooms (assets/index.html) in a full-screen WebView.
 *
 * The page is used exactly as built, touch controls and all. Android-specific behaviour lives
 * here (immersive full screen, the system back gesture acting as the game's Start, physical
 * gamepad buttons, pausing the game and its audio when the app leaves the screen) and in
 * assets/android-shell.js (clipboard and haptics), which is injected into the page once it loads.
 */
public class MainActivity extends Activity {
    private static final String GAME_URL = "file:///android_asset/index.html";
    private static final int INK = 0xFF07080F;

    private static final String AT_TITLE =
            "!!(window.AD&&AD.top&&AD.Title&&AD.top() instanceof AD.Title)";

    private FrameLayout root;
    private WebView web;
    private String shellJs; // assets/android-shell.js, run after each page load
    private Object backCallback;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams lp = getWindow().getAttributes();
            lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            getWindow().setAttributes(lp);
        }
        if (Build.VERSION.SDK_INT >= 30) getWindow().setDecorFitsSystemWindows(false);

        root = new FrameLayout(this);
        root.setBackgroundColor(INK);
        setContentView(root);

        // Keep the game clear of camera cutouts, any bars that cannot hide, and the keyboard.
        root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @SuppressWarnings("deprecation")
            @Override
            public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                if (Build.VERSION.SDK_INT >= 30) {
                    Insets i = insets.getInsets(WindowInsets.Type.systemBars()
                            | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                    v.setPadding(i.left, i.top, i.right, i.bottom);
                    return WindowInsets.CONSUMED;
                } else if (Build.VERSION.SDK_INT >= 28) {
                    DisplayCutout c = insets.getDisplayCutout();
                    if (c != null) {
                        v.setPadding(c.getSafeInsetLeft(), c.getSafeInsetTop(),
                                c.getSafeInsetRight(), c.getSafeInsetBottom());
                    } else {
                        v.setPadding(0, 0, 0, 0);
                    }
                    return insets.consumeDisplayCutout().consumeSystemWindowInsets();
                }
                return insets;
            }
        });

        shellJs = readAsset("android-shell.js");
        buildWebView();

        if (Build.VERSION.SDK_INT >= 33) {
            OnBackInvokedCallback cb = new OnBackInvokedCallback() {
                @Override
                public void onBackInvoked() {
                    handleBack();
                }
            };
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_DEFAULT, cb);
            backCallback = cb;
        }
        hideSystemBars();
    }

    // The WebView is built here rather than in onCreate so that a fresh one can replace it if its
    // renderer dies. Saves live in localStorage and survive the swap.
    @SuppressLint("SetJavaScriptEnabled")
    private void buildWebView() {
        web = new WebView(this);
        web.setBackgroundColor(INK);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        web.setVerticalScrollBarEnabled(false);
        web.setHorizontalScrollBarEnabled(false);
        root.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true); // save slots live in localStorage
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setTextZoom(100);
        s.setAllowContentAccess(false);
        s.setAllowFileAccess(false); // file:///android_asset stays readable regardless

        web.addJavascriptInterface(new Host(), "AndroidHost");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                return !("file".equals(u.getScheme()) && String.valueOf(u.getPath()).startsWith("/android_asset/"));
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                view.evaluateJavascript(shellJs, null);
            }

            // The page's renderer died, usually for memory. Without this the app is killed with
            // it; with it, the game reloads to the title screen.
            @Override
            public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
                if (view != web) return true;
                root.removeView(web);
                web.destroy();
                buildWebView();
                return true;
            }
        });

        web.loadUrl(GAME_URL);
        web.requestFocus();
    }

    private String readAsset(String name) {
        try {
            InputStream in = getAssets().open(name);
            try {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                byte[] buf = new byte[8192];
                for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
                return out.toString("UTF-8");
            } finally {
                in.close();
            }
        } catch (IOException e) {
            throw new IllegalStateException("missing asset " + name, e);
        }
    }

    // Back acts as the game's Start (pause in play, back out of a menu); on the title it leaves.
    private void handleBack() {
        web.evaluateJavascript(AT_TITLE, new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String atTitle) {
                if ("true".equals(atTitle)) finish();
                else sendKey("Escape", true, false);
            }
        });
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        handleBack();
    }

    // Controllers: WebView does not reliably expose the Gamepad API, so map buttons to the
    // keyboard keys the game already understands (D-pad arrows reach the page on their own).
    // Spec 4.2: south face attack, west face skill, east face or R1 roll, L1 equipment, L2/R2 the
    // quickslots, Start; Select opens the map and the north face the third quickslot.
    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        String key = gamepadKey(event.getKeyCode());
        if (key != null) {
            int action = event.getAction();
            if (action == KeyEvent.ACTION_DOWN) sendKey(key, true, event.getRepeatCount() > 0);
            else if (action == KeyEvent.ACTION_UP) sendKey(key, false, false);
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    private static String gamepadKey(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_BUTTON_A: return "z";
            case KeyEvent.KEYCODE_BUTTON_X: return "x";
            case KeyEvent.KEYCODE_BUTTON_B:
            case KeyEvent.KEYCODE_BUTTON_R1: return "c";
            case KeyEvent.KEYCODE_BUTTON_L1: return "v";
            case KeyEvent.KEYCODE_BUTTON_L2: return "1";
            case KeyEvent.KEYCODE_BUTTON_R2: return "2";
            case KeyEvent.KEYCODE_BUTTON_Y: return "3";
            case KeyEvent.KEYCODE_BUTTON_START: return "Escape";
            case KeyEvent.KEYCODE_BUTTON_SELECT: return "m";
            default: return null;
        }
    }

    private void sendKey(String key, boolean down, boolean repeat) {
        if (!down) {
            web.evaluateJavascript("window.dispatchEvent(new KeyboardEvent('keyup',{key:'" + key + "'}))", null);
        } else if (key.equals("Escape") && !repeat) {
            // a full tap: the game latches presses shorter than a frame
            web.evaluateJavascript("window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));"
                    + "window.dispatchEvent(new KeyboardEvent('keyup',{key:'Escape'}))", null);
        } else {
            web.evaluateJavascript("window.dispatchEvent(new KeyboardEvent('keydown',{key:'" + key
                    + "',repeat:" + repeat + "}))", null);
        }
    }

    @SuppressWarnings("deprecation")
    private void hideSystemBars() {
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.systemBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    | View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION);
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }

    // Leaving the app pauses the game and lets go of every button (the page's own handler for a
    // hidden page, which a paused WebView does not always fire), then silences it.
    @Override
    protected void onPause() {
        web.evaluateJavascript("window.AD&&AD.input&&AD.input.releaseAll('background');"
                + "window.AD&&AD.audio&&AD.audio.ctx&&AD.audio.ctx.suspend()", null);
        web.onPause();
        web.pauseTimers();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.resumeTimers();
        web.onResume();
        web.evaluateJavascript("window.AD&&AD.audio&&AD.audio.ctx&&AD.audio.ctx.resume()", null);
    }

    @Override
    protected void onDestroy() {
        if (Build.VERSION.SDK_INT >= 33 && backCallback != null) {
            getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback((OnBackInvokedCallback) backCallback);
        }
        root.removeView(web);
        web.destroy();
        super.onDestroy();
    }

    /** Exposed to the page as window.AndroidHost. Calls arrive on a WebView background thread. */
    private class Host {
        @JavascriptInterface
        public void copy(String text) {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("Between the Rooms seed", text));
        }

        // The game's buzz: 8 ms on landing a blow, 18 on a crit, 30 on being hurt. Haptic
        // feedback needs no VIBRATE permission, so the three map to a tap, a key and a long press.
        @JavascriptInterface
        public void haptic(final int ms) {
            root.post(new Runnable() {
                @Override
                public void run() {
                    root.performHapticFeedback(ms >= 30 ? HapticFeedbackConstants.LONG_PRESS
                            : ms >= 15 ? HapticFeedbackConstants.VIRTUAL_KEY
                            : HapticFeedbackConstants.KEYBOARD_TAP);
                }
            });
        }
    }
}
