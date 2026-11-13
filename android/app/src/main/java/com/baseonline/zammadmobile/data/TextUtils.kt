package com.baseonline.zammadmobile.data

import android.text.format.DateUtils
import androidx.core.text.HtmlCompat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Plain text from an HTML article body, keeping paragraph breaks. */
fun String.strippingHTML(): String {
    var s = replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), "\n")
    s = s.replace(Regex("</p\\s*>", RegexOption.IGNORE_CASE), "\n\n")
    s = s.replace(Regex("</div\\s*>", RegexOption.IGNORE_CASE), "\n")
    s = s.replace(Regex("<(style|script)[^>]*>.*?</\\1>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)), "")
    s = s.replace(Regex("<[^>]+>"), "")
    s = HtmlCompat.fromHtml(s.replace("\n", "<br>"), HtmlCompat.FROM_HTML_MODE_LEGACY).toString()
    s = s.replace(' ', ' ').replace(Regex("[ \\t]+"), " ").replace(Regex("\n{3,}"), "\n\n")
    return s.trim()
}

val String.looksLikeHTML: Boolean get() = Regex("<[a-zA-Z][^>]*>").containsMatchIn(this)

/** "5 minutes ago", localised by the system. */
fun Instant.timeAgoDisplay(): String = DateUtils.getRelativeTimeSpanString(
    toEpochMilli(), System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS, DateUtils.FORMAT_ABBREV_RELATIVE).toString()

private val dateTimeFormatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
private val timeFormatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
private val dateFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

fun Instant.formattedDateTime(): String = dateTimeFormatter.format(atZone(ZoneId.systemDefault()))
fun Instant.formattedTime(): String = timeFormatter.format(atZone(ZoneId.systemDefault()))
fun Instant.formattedDate(): String = dateFormatter.format(atZone(ZoneId.systemDefault()))
