package app.yubbly.yubbly_app;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayDeque;
import java.util.Queue;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Runs the bundled yt-dlp/ejs n-signature solver in a hidden WebView. */
final class JsChallengeBridge {
    private static final String CHANNEL = "app.yubbly/js";
    private static final long TIMEOUT_MS = 45_000;

    private static final class Request {
        final String playerUrl;
        final String playerJs;
        final String challenge;
        final MethodChannel.Result result;

        Request(String playerUrl, String playerJs, String challenge, MethodChannel.Result result) {
            this.playerUrl = playerUrl;
            this.playerJs = playerJs;
            this.challenge = challenge;
            this.result = result;
        }
    }

    private final Context context;
    private final MethodChannel channel;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Queue<Request> queue = new ArrayDeque<>();
    private WebView webView;
    private String loadedSolver = "";
    // Sending the roughly 2.5 MB player script over the method channel for
    // every n challenge is wasteful. Dart sends it once per player URL and an
    // empty string afterwards; the bridge keeps the last script for that URL.
    private String cachedPlayerUrl = "";
    private String cachedPlayerJs = "";
    private boolean ready;
    private boolean active;
    private Runnable timeout;

    JsChallengeBridge(Context context, BinaryMessenger messenger) {
        this.context = context;
        this.channel = new MethodChannel(messenger, CHANNEL);
        channel.setMethodCallHandler(this::handle);
    }

    private void handle(MethodCall call, MethodChannel.Result result) {
        if (!"solve".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final String solver = call.argument("solver");
        final String playerUrl = call.argument("playerUrl");
        final String sentPlayerJs = call.argument("playerJs");
        final String challenge = call.argument("challenge");
        if (solver == null || playerUrl == null || sentPlayerJs == null || challenge == null) {
            result.error("SOLVER", "Nieprawidłowe dane solvera JavaScript.", null);
            return;
        }
        final String playerJs;
        if (!sentPlayerJs.isEmpty()) {
            cachedPlayerUrl = playerUrl;
            cachedPlayerJs = sentPlayerJs;
            playerJs = sentPlayerJs;
        } else if (playerUrl.equals(cachedPlayerUrl) && !cachedPlayerJs.isEmpty()) {
            playerJs = cachedPlayerJs;
        } else {
            result.error("SOLVER", "Brak skryptu odtwarzacza dla solvera.", null);
            return;
        }
        queue.add(new Request(playerUrl, playerJs, challenge, result));
        ensureWebView(solver);
        pump();
    }

    private void ensureWebView(String solver) {
        if (webView != null) {
            if (!loadedSolver.equals(solver)) {
                loadedSolver = solver;
                ready = false;
                load(solver);
            }
            return;
        }
        webView = new WebView(context);
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.setAlpha(0.01f);
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view, String url) {
                ready = true;
                pump();
            }

            @Override public void onReceivedError(
                    WebView view,
                    android.webkit.WebResourceRequest request,
                    android.webkit.WebResourceError error
            ) {
                // A missing favicon or other subresource must not discard the
                // loaded solver; only a failed main document is fatal.
                if (request.isForMainFrame()) {
                    failAll("Nie udało się uruchomić solvera JavaScript.");
                }
            }
        });
        loadedSolver = solver;
        load(solver);
    }

    private void load(String solver) {
        final String html = "<!doctype html><html><head><meta charset=\"utf-8\"></head>"
                + "<body><script>" + solver + "</script></body></html>";
        webView.loadDataWithBaseURL(
                "https://www.youtube.com/",
                html,
                "text/html",
                "UTF-8",
                null
        );
    }

    private void pump() {
        if (!ready || active || queue.isEmpty() || webView == null) return;
        active = true;
        final Request request = queue.remove();
        final String js = "window.__yubblySolveN("
                + JSONObject.quote(request.playerUrl) + ","
                + JSONObject.quote(request.playerJs) + ","
                + JSONObject.quote(request.challenge) + ");";
        timeout = () -> {
            if (!active) return;
            active = false;
            request.result.error("SOLVER", "Solver JavaScript przekroczył limit czasu.", null);
            pump();
        };
        handler.postDelayed(timeout, TIMEOUT_MS);
        webView.evaluateJavascript(js, value -> {
            handler.removeCallbacks(timeout);
            active = false;
            if (value == null || "null".equals(value)) {
                request.result.error("SOLVER", "Solver JavaScript nie zwrócił wyniku.", null);
            } else {
                try {
                    final String decoded = new JSONArray("[" + value + "]").getString(0);
                    request.result.success(decoded);
                } catch (Exception e) {
                    request.result.error("SOLVER", "Nieoczekiwany wynik solvera.", null);
                }
            }
            pump();
        });
    }

    private void failAll(String message) {
        ready = false;
        active = false;
        if (timeout != null) handler.removeCallbacks(timeout);
        while (!queue.isEmpty()) {
            queue.remove().result.error("SOLVER", message, null);
        }
    }

    void dispose() {
        channel.setMethodCallHandler(null);
        failAll("Solver JavaScript został zamknięty.");
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
    }
}
