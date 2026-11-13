package com.baseonline.zammadmobile.ui.screens

import android.annotation.SuppressLint
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.LocalActivity
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.ui.components.GlassCard
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONTokener
import java.util.concurrent.TimeUnit

private const val TAG = "SSO"

// Pretend to be a desktop browser: Google and Microsoft refuse sign-in from an
// embedded WebView ("; wv" in the user agent), and Zammad's mobile view hides
// the profile/token pages.
private const val DESKTOP_USER_AGENT =
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

// Same lookup order as iOS: Rails meta tag, Zammad's App.Config, then cookies.
private const val CSRF_JS = """
(function() {
    try {
        var meta = document.querySelector('meta[name="csrf-token"]');
        if (meta && meta.content) return meta.content;

        if (typeof App !== 'undefined' && App && App.Config && typeof App.Config.get === 'function') {
            var t = App.Config.get('csrf_token') || App.Config.get('csrfToken');
            if (t) return t;
        }

        var cookies = document.cookie.split(';');
        for (var i = 0; i < cookies.length; i++) {
            var parts = cookies[i].trim().split('=');
            var name = parts[0];
            if (name === 'XSRF-TOKEN' || name === '_csrf_token' || name.toLowerCase().indexOf('csrf') !== -1) {
                return decodeURIComponent(parts.slice(1).join('='));
            }
        }
    } catch (e) {}
    return '';
})()
"""

private enum class SSOPhase(val labelRes: Int) {
    LOADING(R.string.sso_status_loading),
    WAITING_FOR_LOGIN(R.string.sso_status_waiting),
    CREATING(R.string.sso_status_creating),
    FAILED(R.string.sso_status_failed),
}

/** `https://host` (no trailing slash) from what the user typed, or null when empty. */
private fun normalizedBaseURL(serverURL: String): String? {
    var u = serverURL.trim()
    if (u.isEmpty()) return null
    if (!u.lowercase().startsWith("http")) u = "https://$u"
    return u.trimEnd('/')
}

private fun cookieNames(cookieHeader: String): List<String> =
    cookieHeader.split(';').map { it.substringBefore('=').trim() }.filter { it.isNotEmpty() }

/**
 * Expires every cookie the WebView holds for the Zammad host. The app-wide
 * cookie store cannot be wiped as a whole (the ads SDK shares it), so the
 * session is removed cookie by cookie, for the host and its parent domains.
 */
private fun clearZammadCookies(baseUrl: String?) {
    baseUrl ?: return
    try {
        val manager = CookieManager.getInstance()
        val names = cookieNames(manager.getCookie(baseUrl) ?: "")
        if (names.isEmpty()) return
        val host = Uri.parse(baseUrl).host?.lowercase() ?: return
        val domains = mutableListOf<String?>(null)
        val labels = host.split('.')
        for (i in 0..(labels.size - 2).coerceAtLeast(0)) {
            val domain = labels.drop(i).joinToString(".")
            domains += domain
            domains += ".$domain"
        }
        for (name in names) for (domain in domains) {
            val suffix = if (domain != null) "; Domain=$domain" else ""
            manager.setCookie(baseUrl, "$name=; Max-Age=0; Path=/$suffix")
        }
        manager.flush()
    } catch (e: Exception) {
        // No WebView provider on this device: there are no cookies either.
        Log.i(TAG, "Cookie cleanup skipped: ${e.message}")
    }
}

/** State and logic of the SSO flow, the counterpart of the iOS `SSOController`. */
private class SSOController(
    private val serverURL: String,
    private val scope: CoroutineScope,
    private val onToken: (String) -> Unit,
) {
    var phase by mutableStateOf(SSOPhase.LOADING)
    var currentURL by mutableStateOf<String?>(null)
    var errorMessage by mutableStateOf<String?>(null)
    var cookieCount by mutableIntStateOf(0)
    var hasSessionCookie by mutableStateOf(false)

    var webView: WebView? = null
    private var attemptedAutoDetect = false
    val baseUrl: String? = normalizedBaseURL(serverURL)

    private val verifyClient by lazy {
        ZammadApi.client.newBuilder().followRedirects(false).callTimeout(10, TimeUnit.SECONDS).build()
    }

    private fun cookieHeader(): String = try {
        baseUrl?.let { CookieManager.getInstance().getCookie(it) } ?: ""
    } catch (e: Exception) { "" }

    fun loginURL(): String? = baseUrl?.let { "$it/#login" }
    fun profileURL(): String? = baseUrl?.let { "$it/#profile/token_access" }

    fun navigateToProfilePage() {
        profileURL()?.let { webView?.loadUrl(it) }
    }

    fun retryAutoDetect() {
        attemptedAutoDetect = false
        phase = SSOPhase.WAITING_FOR_LOGIN
        scope.launch { checkAutoDetect() }
    }

    /** Called every 1.5 s and on every navigation: is the user signed in yet? */
    suspend fun checkAutoDetect() {
        if (webView == null) return
        val header = cookieHeader()
        val names = cookieNames(header)
        cookieCount = names.size

        if (attemptedAutoDetect || (phase != SSOPhase.WAITING_FOR_LOGIN && phase != SSOPhase.LOADING)) return
        if (phase == SSOPhase.LOADING) phase = SSOPhase.WAITING_FOR_LOGIN

        // The anonymous Zammad page already sets a session cookie before login,
        // so verify with the API before triggering token creation.
        if (names.none { it.lowercase().contains("session") }) {
            hasSessionCookie = false
            return
        }
        val authenticated = verifyAuthenticated(header)
        hasSessionCookie = authenticated
        if (authenticated && !attemptedAutoDetect && phase == SSOPhase.WAITING_FOR_LOGIN) {
            attemptedAutoDetect = true
            attemptTokenCreation()
        }
    }

    private suspend fun verifyAuthenticated(cookieHeader: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder().url(ZammadApi.baseUrl(serverURL) + "users/me")
                .header("Accept", "application/json")
                .apply { if (cookieHeader.isNotEmpty()) header("Cookie", cookieHeader) }
                .build()
            verifyClient.newCall(request).execute().use { it.code in 200..299 }
        } catch (e: Exception) {
            false
        }
    }

    /** Reads the CSRF token from the page, then has Zammad mint an access token. */
    fun attemptTokenCreation() {
        val view = webView ?: return
        if (phase == SSOPhase.CREATING) return
        attemptedAutoDetect = true
        phase = SSOPhase.CREATING
        view.evaluateJavascript(CSRF_JS) { result ->
            val csrf = try {
                (JSONTokener(result ?: "null").nextValue() as? String)?.takeIf { it.isNotEmpty() }
            } catch (e: Exception) { null }
            scope.launch { createToken(csrf) }
        }
    }

    private suspend fun createToken(csrfToken: String?) {
        val header = cookieHeader()
        try {
            val token = ZammadApi.createAccessTokenWithSession(
                url = serverURL,
                cookieHeader = header,
                csrfToken = csrfToken,
                tokenName = "Android Helpdesk – ${Build.MODEL}",
            )
            // The browser session has served its purpose; the token replaces it.
            clearZammadCookies(baseUrl)
            onToken(token)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = listOf(
                e.message ?: e.javaClass.simpleName,
                "CSRF: ${if (csrfToken != null) "OK" else "missing"}",
                "Cookies: ${cookieNames(header).size}",
            ).joinToString(" • ")
            phase = SSOPhase.FAILED
            // Allow a manual retry after a failure.
            attemptedAutoDetect = false
        }
    }
}

/**
 * Full-screen SSO sign-in (iOS `SSOLoginView`): the Zammad login page in a
 * WebView; once the session is authenticated a personal access token is minted
 * with it and handed to [onToken]. Fallbacks: "I'm logged in" (manual attempt),
 * the profile page, or creating a token in the browser and pasting it.
 * The caller closes the dialog in [onToken] / [onDismiss].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupSSOLogin(serverURL: String, onToken: (String) -> Unit, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val activity = LocalActivity.current
    val currentOnToken by rememberUpdatedState(onToken)
    val controller = remember(serverURL) { SSOController(serverURL, scope) { currentOnToken(it) } }

    var menuOpen by remember { mutableStateOf(false) }
    var showPasteDialog by remember { mutableStateOf(false) }
    var pastedToken by remember { mutableStateOf("") }
    var openedBrowser by remember { mutableStateOf(false) }

    // Back from the browser: assume the user made a token there.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        if (openedBrowser) { openedBrowser = false; showPasteDialog = true }
    }

    LaunchedEffect(controller) {
        while (true) {
            controller.checkAutoDetect()
            delay(1500)
        }
    }

    DisposableEffect(controller) {
        onDispose {
            controller.webView?.apply { stopLoading(); destroy() }
            controller.webView = null
            // Token minted or flow cancelled: either way the session goes.
            clearZammadCookies(controller.baseUrl)
        }
    }

    Dialog(
        onDismissRequest = {
            val view = controller.webView
            if (view != null && view.canGoBack()) view.goBack() else onDismiss()
        },
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false),
    ) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
            Scaffold(
                modifier = Modifier.safeDrawingPadding(),
                contentWindowInsets = WindowInsets(0, 0, 0, 0),
                topBar = {
                    TopAppBar(
                        windowInsets = WindowInsets(0, 0, 0, 0),
                        title = {
                            Text(stringResource(R.string.login_with_sso), maxLines = 1,
                                overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                        },
                        navigationIcon = {
                            IconButton(onClick = onDismiss) {
                                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel))
                            }
                        },
                        actions = {
                            IconButton(onClick = { menuOpen = true }) {
                                Icon(Icons.Filled.MoreVert, contentDescription = null)
                            }
                            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.open_in_browser)) },
                                    leadingIcon = { Icon(Icons.Filled.OpenInBrowser, contentDescription = null) },
                                    onClick = {
                                        menuOpen = false
                                        val url = controller.profileURL()
                                        if (url != null && activity != null) {
                                            try {
                                                CustomTabsIntent.Builder().build().launchUrl(activity, Uri.parse(url))
                                                openedBrowser = true
                                            } catch (e: Exception) {
                                                showPasteDialog = true
                                            }
                                        }
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.paste_token)) },
                                    leadingIcon = { Icon(Icons.Filled.ContentPaste, contentDescription = null) },
                                    onClick = { menuOpen = false; showPasteDialog = true },
                                )
                            }
                        },
                    )
                },
                bottomBar = {
                    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Button(
                            onClick = { controller.attemptTokenCreation() },
                            enabled = controller.phase != SSOPhase.CREATING && controller.phase != SSOPhase.LOADING,
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color(0xFF007AFF), contentColor = Color.White),
                        ) {
                            Icon(Icons.Filled.VerifiedUser, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.im_logged_in))
                        }
                        OutlinedButton(onClick = { controller.navigateToProfilePage() }) {
                            Icon(Icons.Filled.AccountCircle,
                                contentDescription = stringResource(R.string.open_profile_page))
                        }
                    }
                },
            ) { padding ->
                Column(Modifier.fillMaxSize().padding(padding)) {
                    StatusBar(controller)
                    Box(Modifier.fillMaxWidth().weight(1f)) {
                        SSOWebView(controller, scope)
                        if (controller.phase == SSOPhase.CREATING) {
                            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)),
                                contentAlignment = Alignment.Center) {
                                GlassCard(contentPadding = PaddingValues(28.dp)) {
                                    CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
                                    Text(stringResource(R.string.creating_token), Modifier.padding(top = 14.dp))
                                }
                            }
                        }
                    }
                }
            }
        }

        if (controller.phase == SSOPhase.FAILED) {
            AlertDialog(
                onDismissRequest = { controller.phase = SSOPhase.WAITING_FOR_LOGIN },
                title = { Text(stringResource(R.string.sso_failed_title)) },
                text = { Text(controller.errorMessage ?: stringResource(R.string.sso_failed_message)) },
                confirmButton = {
                    TextButton(onClick = { controller.retryAutoDetect() }) { Text(stringResource(R.string.retry)) }
                },
                dismissButton = {
                    Row {
                        TextButton(onClick = { controller.phase = SSOPhase.WAITING_FOR_LOGIN }) {
                            Text(stringResource(R.string.cancel))
                        }
                        TextButton(onClick = {
                            controller.phase = SSOPhase.WAITING_FOR_LOGIN
                            controller.navigateToProfilePage()
                        }) { Text(stringResource(R.string.open_profile_page)) }
                    }
                },
            )
        }

        if (showPasteDialog) {
            val trimmed = pastedToken.trim()
            AlertDialog(
                onDismissRequest = { showPasteDialog = false },
                title = { Text(stringResource(R.string.paste_token)) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(stringResource(R.string.paste_token_explainer_android),
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        OutlinedTextField(
                            value = pastedToken,
                            onValueChange = { pastedToken = it },
                            label = { Text(stringResource(R.string.api_token)) },
                            placeholder = { Text(stringResource(R.string.paste_api_token)) },
                            minLines = 2, maxLines = 5,
                            keyboardOptions = KeyboardOptions(
                                capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                },
                confirmButton = {
                    TextButton(enabled = trimmed.isNotEmpty(), onClick = {
                        showPasteDialog = false
                        currentOnToken(trimmed)
                    }) { Text(stringResource(R.string.save)) }
                },
                dismissButton = {
                    TextButton(onClick = { showPasteDialog = false }) { Text(stringResource(R.string.cancel)) }
                },
            )
        }
    }
}

@Composable
private fun StatusBar(controller: SSOController) {
    val color = when (controller.phase) {
        SSOPhase.LOADING -> MaterialTheme.colorScheme.onSurfaceVariant
        SSOPhase.WAITING_FOR_LOGIN -> MaterialTheme.colorScheme.tertiary
        SSOPhase.CREATING -> Color(0xFFFF9500)
        SSOPhase.FAILED -> MaterialTheme.colorScheme.error
    }
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(controller.phase.labelRes), style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold, color = color, modifier = Modifier.weight(1f))
            // Diagnostic line, not localised (hardcoded on iOS as well).
            Text("${controller.cookieCount} cookies · session: ${if (controller.hasSessionCookie) "✓" else "—"}",
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(controller.currentURL ?: "—", fontSize = 10.sp, fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun SSOWebView(controller: SSOController, scope: CoroutineScope) {
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context ->
            // Start from a clean session, like the non-persistent store on iOS.
            clearZammadCookies(controller.baseUrl)
            WebView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.userAgentString = DESKTOP_USER_AGENT
                // Desktop layout that the user can zoom, since it is a desktop page.
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
                settings.builtInZoomControls = true
                settings.displayZoomControls = false
                CookieManager.getInstance().setAcceptCookie(true)
                // Identity providers set their cookies from another site.
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                webViewClient = object : WebViewClient() {
                    override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                        controller.currentURL = url
                        scope.launch { controller.checkAutoDetect() }
                    }
                    override fun onPageFinished(view: WebView, url: String?) {
                        controller.currentURL = url
                        scope.launch { controller.checkAutoDetect() }
                    }
                }
                controller.webView = this
                controller.loginURL()?.let { loadUrl(it) }
            }
        },
    )
}
