package com.baseonline.zammadmobile.ui.screens

import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.TicketArticle
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.data.looksLikeHTML
import com.baseonline.zammadmobile.data.strippingHTML
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.abs

/**
 * Whether the body is HTML (by content type, or by the look of it when Zammad
 * labels an HTML mail as plain text). HTML articles render in a web view on a
 * light card; everything else is native text.
 */
val TicketArticle.isHTMLBody: Boolean
    get() = content_type.lowercase().contains("html") || body.looksLikeHTML

/**
 * Per-screen memory for article bodies. Rows of a lazy list are disposed when
 * they scroll away; keeping the prepared HTML, the measured height and the
 * expanded flag here means a row comes back as it left, without downloading
 * its inline images again.
 */
class TicketArticleBodyStore {
    internal val html = mutableStateMapOf<Int, String>()
    internal val heights = mutableStateMapOf<Int, Int>()
    internal val expanded = mutableStateMapOf<Int, Boolean>()
}

/** Tallest an HTML message is shown at before it is cut off behind "More". */
private val CollapsedHeight = 180.dp
/** Only collapse when there is clearly more to gain than the button costs. */
private val CollapseSlack = 40.dp
/** Plain-text line limit before "More" appears. */
private const val COLLAPSED_LINE_LIMIT = 6

/**
 * The body of one article: HTML in a script-less web view sized to its
 * content (always light, like a mail client does for messages that bring
 * their own colours), plain text as native text. Long bodies collapse behind
 * a "More" button. Text takes its colour from `LocalContentColor`.
 */
@Composable
fun TicketArticleBody(article: TicketArticle, ticketId: Int, store: TicketArticleBodyStore, modifier: Modifier = Modifier) {
    val isHtml = article.isHTMLBody
    val isExpanded = store.expanded[article.id] == true
    val renderedHtml = store.html[article.id]
    val density = LocalDensity.current

    LaunchedEffect(article.id) {
        if (isHtml && store.html[article.id] == null) store.html[article.id] = prepareHtml(article, ticketId)
    }

    val plainText = remember(article.id, article.body) {
        if (isHtml) article.body.strippingHTML() else article.body.decodingHtmlEntities()
    }

    // HTML: decided by the measured document height. Plain text: by a rough
    // size heuristic, the same one iOS uses.
    val needsCollapse = if (isHtml && renderedHtml != null) {
        val measured = store.heights[article.id] ?: 0
        measured > with(density) { (CollapsedHeight + CollapseSlack).roundToPx() }
    } else {
        plainText.length > 400 || plainText.count { it == '\n' } >= COLLAPSED_LINE_LIMIT
    }

    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (isHtml && renderedHtml != null) {
            HtmlBody(renderedHtml, article.id, store, collapsed = needsCollapse && !isExpanded)
        } else {
            SelectionContainer {
                Text(
                    plainText,
                    maxLines = if (isExpanded || !needsCollapse) Int.MAX_VALUE else COLLAPSED_LINE_LIMIT,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        if (needsCollapse) {
            // Outlined on purpose: the app's accent is black/white, so a plain
            // text button would read as just another line of the message.
            val tint = LocalContentColor.current
            OutlinedButton(
                onClick = { store.expanded[article.id] = !isExpanded },
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = tint),
                modifier = Modifier.heightIn(min = 32.dp),
            ) {
                Icon(if (isExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(if (isExpanded) R.string.show_less else R.string.show_more),
                    style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/**
 * The web view always gets its full content height (it is measured without a
 * height limit), so it has nothing to scroll vertically and only pans
 * sideways for wide tables; the enclosing box does the collapsing.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun HtmlBody(html: String, articleId: Int, store: TicketArticleBodyStore, collapsed: Boolean) {
    val density = LocalDensity.current
    // Until this web view has reported a height, hold the height it had the
    // last time it was on screen so the list does not jump while it loads.
    var measuredHere by remember(articleId) { mutableStateOf(false) }
    val rememberedHeight = store.heights[articleId]

    val frame = when {
        collapsed -> Modifier.height(CollapsedHeight)
        !measuredHere && rememberedHeight != null -> Modifier.heightIn(min = with(density) { rememberedHeight.toDp() })
        else -> Modifier
    }
    Box(Modifier.fillMaxWidth().then(frame).clipToBounds()) {
        AndroidView(
            modifier = Modifier.fillMaxWidth().wrapContentHeight(align = Alignment.Top, unbounded = true),
            factory = { context ->
                WebView(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    isVerticalScrollBarEnabled = false
                    isHorizontalScrollBarEnabled = true
                    overScrollMode = View.OVER_SCROLL_NEVER
                    settings.apply {
                        // Mail content has no business running scripts.
                        javaScriptEnabled = false
                        allowFileAccess = false
                        allowContentAccess = false
                        setSupportZoom(false)
                        builtInZoomControls = false
                        displayZoomControls = false
                        // HTML mail is designed for a white page; never let the
                        // system recolour it for a dark theme.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) isAlgorithmicDarkeningAllowed = false
                    }
                    webViewClient = object : WebViewClient() {
                        // Nothing navigates inside the card; tapped links open
                        // in the browser (or mail/phone app).
                        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                            val scheme = request.url.scheme?.lowercase()
                            if (request.isForMainFrame && request.hasGesture() &&
                                scheme in listOf("http", "https", "mailto", "tel")) {
                                try {
                                    view.context.startActivity(
                                        Intent(Intent.ACTION_VIEW, request.url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                } catch (e: Exception) {
                                    Log.w("TicketArticleBody", "No app for ${request.url.scheme} link")
                                }
                            }
                            return true
                        }
                    }
                    addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
                        val height = view.height
                        if (height > 0) {
                            measuredHere = true
                            if (abs((store.heights[articleId] ?: 0) - height) > 1) store.heights[articleId] = height
                        }
                    }
                }
            },
            update = { webView ->
                if (webView.tag != html) {
                    webView.tag = html
                    webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
                }
            },
            onRelease = { webView ->
                webView.stopLoading()
                webView.destroy()
            },
        )
    }
}

// --- HTML preparation ---

/**
 * Inline images are referenced as `cid:` and live behind the authenticated
 * attachment endpoint, which a web view cannot reach on its own: download
 * them here and embed them as data URIs.
 */
private suspend fun prepareHtml(article: TicketArticle, ticketId: Int): String {
    var html = article.body
    val inlineAttachments = article.attachments.orEmpty().filter { it.isInline }
    for (attachment in inlineAttachments) {
        val cid = attachment.contentIDValue ?: continue
        // Skip the download when the body does not reference this image at all.
        if (!html.contains("cid:$cid", ignoreCase = true)) continue
        try {
            val bytes = ZammadApi.downloadAttachmentBytes(ticketId, article.id, attachment.id)
            html = withContext(Dispatchers.Default) {
                val dataUrl = "data:${attachment.resolvedMimeType};base64,${Base64.encodeToString(bytes, Base64.NO_WRAP)}"
                replaceCid(html, cid, dataUrl)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w("TicketArticleBody", "Inline attachment ${attachment.id} failed: ${e.message}")
        }
    }
    return wrapInTemplate(html)
}

private fun replaceCid(html: String, cid: String, replacement: String): String {
    val escaped = Regex.escape(cid)
    val patterns = listOf("src=\"cid:$escaped\"", "src='cid:$escaped'", "src=cid:$escaped")
    var result = html
    for (pattern in patterns) {
        result = Regex(pattern, RegexOption.IGNORE_CASE).replace(result) { "src=\"$replacement\"" }
    }
    return result
}

/** Always light: a dark scheme would turn unspecified text white on the mail's own white background. */
private fun wrapInTemplate(body: String): String = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
    :root { color-scheme: light; }
    html, body {
        margin: 0;
        padding: 0;
        font-family: sans-serif;
        font-size: 15px;
        line-height: 1.5;
        color: #1c1c1e;
        background: transparent;
        word-wrap: break-word;
        -webkit-text-size-adjust: 100%;
    }
    img { max-width: 100%; height: auto; }
    a { color: #0a60ff; }
    blockquote {
        border-left: 3px solid rgba(60,60,67,0.3);
        margin: 8px 0;
        padding: 4px 0 4px 10px;
        color: #3c3c43;
    }
    pre, code {
        background: rgba(120,120,128,0.12);
        border-radius: 4px;
        padding: 2px 4px;
        font-family: monospace;
    }
    pre { padding: 8px; overflow-x: auto; }
    table { border-collapse: collapse; max-width: 100%; }
    td, th { padding: 4px 8px; border: 1px solid rgba(60,60,67,0.25); }
</style>
</head>
<body>$body</body>
</html>
""".trimIndent()

private val entityRegex = Regex("&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});")
private val namedEntities = mapOf(
    "amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ",
    "euro" to "€", "copy" to "©", "reg" to "®", "hellip" to "…",
    "ndash" to "–", "mdash" to "—", "lsquo" to "‘", "rsquo" to "’",
    "ldquo" to "“", "rdquo" to "”",
)

/** Plain-text bodies can still carry entities (`&amp;`, `&#39;`); line breaks are kept as they are. */
internal fun String.decodingHtmlEntities(): String {
    if (!contains('&')) return this
    return entityRegex.replace(this) { match ->
        val name = match.groupValues[1]
        when {
            name.startsWith("#x") || name.startsWith("#X") -> name.drop(2).toIntOrNull(16)?.let(::codePointString)
            name.startsWith("#") -> name.drop(1).toIntOrNull()?.let(::codePointString)
            else -> namedEntities[name.lowercase()]
        } ?: match.value
    }
}

private fun codePointString(codePoint: Int): String? =
    if (Character.isValidCodePoint(codePoint) && codePoint != 0) String(Character.toChars(codePoint)) else null
