package com.afidipro.app;

import com.getcapacitor.BridgeActivity;
import com.getcapacitor.BridgeWebViewClient;
import com.getcapacitor.WebViewListener;
import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

public class MainActivity extends BridgeActivity {
    // Doit correspondre à default_notification_channel_id dans AndroidManifest.xml
    private static final String CHANNEL_ID = "afidi_default";
    private static final String SITE_ORIGIN = "https://www.afidipro.com";
    private static final int REQUEST_NOTIFICATIONS = 1001;

    // Lien reçu d'un tap sur notification, en attente que la page soit chargée
    private String pendingLink;
    private boolean pageLoaded = false;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Configure le User-Agent pour être compatible avec Google OAuth
        // (suffixe AfidiApp conservé : le site s'en sert pour détecter l'app)
        String userAgent = "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 AfidiApp";
        WebSettings settings = getBridge().getWebView().getSettings();
        settings.setUserAgentString(userAgent);

        // Liens WhatsApp / Facebook : ouverts dans l'application correspondante
        getBridge().setWebViewClient(new BridgeWebViewClient(getBridge()) {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (openInNativeApp(request.getUrl())) return true;
                return super.shouldOverrideUrlLoading(view, request);
            }
        });

        createNotificationChannel();
        requestNotificationPermission();
        readLinkFromIntent(getIntent());

        // Le site distant est chargé dans la WebView : on injecte le pont push
        // à chaque fin de chargement de page (voir MOBILE_PUSH.md).
        final String pushScript = readAsset("native-push.js");
        getBridge().addWebViewListener(new WebViewListener() {
            @Override
            public void onPageLoaded(WebView webView) {
                if (pushScript != null) {
                    webView.evaluateJavascript(pushScript, null);
                }
                pageLoaded = true;
                openPendingLink(webView);
            }
        });
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        readLinkFromIntent(intent);
        if (pageLoaded) {
            openPendingLink(getBridge().getWebView());
        }
    }

    // Applications à essayer en premier pour chaque domaine (WhatsApp, puis WhatsApp Business).
    private static final String[] WHATSAPP_PACKAGES = { "com.whatsapp", "com.whatsapp.w4b" };
    private static final String[] FACEBOOK_PACKAGES = { "com.facebook.katana", "com.facebook.orca" };

    private static boolean hostMatches(String host, String domain) {
        return host.equals(domain) || host.endsWith("." + domain);
    }

    // Renvoie true si le lien a été confié à une autre application.
    // Sans l'application installée, le lien s'ouvre dans le navigateur du téléphone.
    private boolean openInNativeApp(Uri uri) {
        String scheme = uri.getScheme();
        String host = uri.getHost();
        if (scheme == null || host == null) return false;
        if (!scheme.equals("https") && !scheme.equals("http")) return false;
        host = host.toLowerCase();

        String[] packages;
        if (host.equals("wa.me") || hostMatches(host, "whatsapp.com")) {
            packages = WHATSAPP_PACKAGES;
        } else if (hostMatches(host, "facebook.com") || host.equals("fb.me")
                || host.equals("fb.com") || host.equals("m.me")) {
            packages = FACEBOOK_PACKAGES;
        } else {
            return false;
        }

        for (String pkg : packages) {
            try {
                Intent intent = new Intent(Intent.ACTION_VIEW, uri).setPackage(pkg);
                startActivity(intent);
                return true;
            } catch (ActivityNotFoundException ignored) {
                // application absente : on essaie la suivante
            }
        }
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri));
            return true;
        } catch (ActivityNotFoundException e) {
            return false;
        }
    }

    // Canal à importance HIGH : sans lui, FCM utilise un canal par défaut sans bannière.
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationChannel channel = new NotificationChannel(
            CHANNEL_ID, "Notifications AfidiPro", NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("Demandes de devis et messages");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    // Android 13+ : permission à accorder explicitement, demandée dès le lancement.
    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return;
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this, new String[] { Manifest.permission.POST_NOTIFICATIONS }, REQUEST_NOTIFICATIONS);
        }
    }

    // FCM place les champs "data" du message en extras de l'intent au tap.
    // data.link est un chemin relatif ; tout le reste est ignoré (jamais une autre origine).
    private void readLinkFromIntent(Intent intent) {
        if (intent == null) return;
        String link = intent.getStringExtra("link");
        if (link != null && link.startsWith("/") && !link.startsWith("//") && !link.contains("\\")) {
            pendingLink = link;
        }
        intent.removeExtra("link");
    }

    private void openPendingLink(WebView webView) {
        if (pendingLink == null) return;
        String url = SITE_ORIGIN + pendingLink;
        pendingLink = null;
        webView.loadUrl(url);
    }

    private String readAsset(String name) {
        try (InputStream in = getAssets().open(name)) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return null;
        }
    }
}
