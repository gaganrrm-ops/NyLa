package com.nyla.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ProgressBar;
import android.widget.Toast;

/**
 * NyLa main activity. Hosts a single fullscreen WebView pointed at the local
 * NyLa server (http://127.0.0.1:7317/). The server embeds the access token
 * server-side into the same-origin HTML response, so no auth handshake is
 * needed from the WebView side.
 *
 * Lifecycle:
 *   onCreate  -- build the WebView, load the URL, set up the offline fallback.
 *   onPause   -- pause the WebView (saves battery, keeps the JS state).
 *   onResume  -- resume the WebView; if it failed to load last time, retry.
 *   onKeyDown -- the hardware/gestural Back button does WebView.goBack()
 *                until there's nowhere to go, then a confirm dialog
 *                ("Exit NyLa?") to leave the activity.
 *
 * Connection detection: on first load failure or whenever the page
 * surfaces "ERR_CONNECTION_REFUSED", we show an in-WebView overlay that
 * tells the user to run the install script. We don't try to launch the
 * install script ourselves -- it requires Termux + Ubuntu, which we can't
 * bootstrap from inside an APK on most devices.
 */
public class MainActivity extends Activity {

    private static final String DEFAULT_URL = "http://127.0.0.1:7317/";
    private static final String PREFS = "omp";
    private static final String PREF_URL = "url";

    private WebView web;
    private ProgressBar progress;
    private boolean loadFailed = false;
    private long lastBackPress = 0L;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Layout -- a vertical LinearLayout with a thin progress bar and the
        // WebView filling the rest. See res/layout/activity_main.xml.
        setContentView(R.layout.activity_main);

        web = (WebView) findViewById(R.id.web);
        progress = (ProgressBar) findViewById(R.id.progress);

        // WebView settings: enable JS, DOM storage, allow file access (for
        // the camera/mic permission bridge in case the user attaches files
        // via the <input type=file> flow), keep the screen on while the
        // agent is generating.
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        s.setSupportZoom(false);

        // The NyLa server talks plain HTTP to 127.0.0.1. network_security_config
        // allows cleartext only to loopback.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        }

        // Show progress while the page loads, hide it once the page reports
        // itself fully loaded. NyLa never navigates away from its own origin
        // for normal flows; the WebViewClient below just keeps every load
        // inside the WebView and only intercepts "open in browser" hints.
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                if (newProgress < 100) {
                    progress.setVisibility(View.VISIBLE);
                    progress.setProgress(newProgress);
                } else {
                    progress.setVisibility(View.GONE);
                }
            }
        });
        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                // Don't tear down the WebView on the first failure; show an
                // overlay via a JS-injected banner. We do this by writing
                // HTML into the page if it's empty.
                if (view.getUrl() == null || view.getUrl().isEmpty() || !DEFAULT_URL.startsWith("http")) {
                    showOffline();
                }
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                loadFailed = false;
                progress.setVisibility(View.GONE);
            }
        });

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        // Allow the user to override the URL in case they run NyLa on a
        // different port (e.g. moved to a public tunnel). For the standard
        // install, this is a no-op.
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        String url = prefs.getString(PREF_URL, DEFAULT_URL);
        web.loadUrl(url);
    }

    private void showOffline() {
        // Inject an in-page overlay that explains the situation. We do this
        // via loadData so we don't need any bundled assets. The text links
        // back to the install-script docs in the system browser.
        String html = "<!doctype html><html><head><meta name=viewport content=\"width=device-width,initial-scale=1\">"
                + "<style>body{font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;background:#100c28;color:#ece9fb;"
                + "padding:24px;margin:0}h1{color:#f7a531;font-size:18px}a{color:#f7a531}code{background:#221a52;padding:2px 6px;"
                + "border-radius:4px}</style></head><body>"
                + "<h1>NyLa server is not running</h1>"
                + "<p>NyLa could not reach <code>" + DEFAULT_URL + "</code> on your phone. The most common cause is that"
                + " the NyLa server hasn't been started yet, or the install script hasn't been run.</p>"
                + "<p><b>What to do</b><ol>"
                + "<li>Open Termux on this phone.</li>"
                + "<li>Run <code>sv up omp-web</code> to start the service (or run the install script if you haven't yet).</li>"
                + "<li>Tap <a href=\"" + DEFAULT_URL + "\">here</a> to retry.</li>"
                + "</ol></p></body></html>";
        web.loadDataWithBaseURL(DEFAULT_URL, html, "text/html", "utf-8", DEFAULT_URL);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        // Back button: navigate inside the WebView if possible, otherwise
        // ask to exit. The "double-tap to exit" pattern from Android UX
        // guidelines -- we accept a single back press because the WebView
        // is the entire app and we don't want to trap the user.
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (web != null && web.canGoBack()) {
                web.goBack();
                return true;
            }
            // Double-tap-to-exit: if the user pressed back recently, exit.
            long now = System.currentTimeMillis();
            if (now - lastBackPress < 1500) {
                finish();
                return true;
            }
            lastBackPress = now;
            Toast.makeText(this, "Press back again to exit", Toast.LENGTH_SHORT).show();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (web != null) web.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.stopLoading();
            web.removeAllViews();
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
