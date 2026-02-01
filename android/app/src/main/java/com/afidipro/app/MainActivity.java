package com.afidipro.app;

import android.os.Bundle;
import android.webkit.WebSettings;
import androidx.core.splashscreen.SplashScreen;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        SplashScreen.installSplashScreen(this);
        super.onCreate(savedInstanceState);

        // Configure le User-Agent pour être compatible avec Google OAuth
        String userAgent = "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";
        WebSettings settings = getBridge().getWebView().getSettings();
        settings.setUserAgentString(userAgent);
    }
}
