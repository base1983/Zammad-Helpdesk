package com.baseonline.zammadmobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.coerceAtLeast
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.GlassCard
import com.baseonline.zammadmobile.ui.theme.ChatTheme

/** Grid of chat theme preview cards (mini conversation mockups). */
@Composable
fun ChatThemePickerScreen(nav: Nav, dark: Boolean) {
    val themes = if (dark) ChatTheme.darkThemes else ChatTheme.lightThemes
    val selected = ChatTheme.current(dark)
    AppScaffold(
        title = stringResource(if (dark) R.string.chat_theme_dark_mode else R.string.chat_theme_light_mode),
        onBack = { nav.back() },
    ) { padding ->
        GlassCard(Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(96.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                items(themes, key = { it.raw }) { theme ->
                    SettingsPickerCell(
                        label = stringResource(theme.labelRes),
                        isSelected = theme == selected,
                        aspectRatio = 0.75f,
                        onClick = {
                            if (dark) SettingsManager.saveChatThemeDark(theme.raw)
                            else SettingsManager.saveChatThemeLight(theme.raw)
                        },
                    ) { SettingsChatThemePreview(theme, Modifier.fillMaxSize()) }
                }
            }
        }
    }
}

/**
 * Miniature conversation mockup: bubbles on the theme background. Scales
 * proportionally, so it works both as a tiny settings swatch and a grid card.
 */
@Composable
internal fun SettingsChatThemePreview(theme: ChatTheme, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.background(theme.background)) {
        val bubbleWidth = maxWidth * 0.55f
        val bubbleHeight = (maxHeight * 0.14f).coerceAtLeast(4.dp)
        Column(
            Modifier.fillMaxSize().padding(maxWidth * 0.1f),
            verticalArrangement = Arrangement.spacedBy(bubbleHeight * 0.5f, Alignment.CenterVertically),
        ) {
            Box(Modifier.width(bubbleWidth).height(bubbleHeight).background(theme.partnerBubble, CircleShape))
            Box(Modifier.align(Alignment.End).width(bubbleWidth).height(bubbleHeight).background(theme.myBubble, CircleShape))
            Box(Modifier.width(bubbleWidth * 0.7f).height(bubbleHeight).background(theme.partnerBubble, CircleShape))
        }
    }
}

/** A tappable thumbnail card with a selection ring and checkmark badge. */
@Composable
internal fun SettingsPickerCell(
    label: String,
    isSelected: Boolean,
    aspectRatio: Float,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    preview: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier
            .clip(shape)
            .clickable(role = Role.RadioButton, onClickLabel = label, onClick = onClick)
            .semantics { selected = isSelected },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(aspectRatio).clip(shape).border(
                if (isSelected) 3.dp else 1.dp,
                if (isSelected) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f),
                shape,
            )
        ) {
            preview()
            if (isSelected) {
                Icon(
                    Icons.Filled.Check, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.align(Alignment.TopEnd).padding(8.dp).size(22.dp)
                        .background(MaterialTheme.colorScheme.primary, CircleShape).padding(3.dp),
                )
            }
        }
        Text(label, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
