package com.baseonline.zammadmobile.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.BackgroundOption
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.WallpaperMode
import com.baseonline.zammadmobile.managers.CustomWallpaperStore
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.GlassCard
import kotlinx.coroutines.launch

/**
 * Grid of wallpaper thumbnails and colour swatches for choosing a background,
 * plus a slot for the user's own photo.
 */
@Composable
fun BackgroundPickerScreen(nav: Nav, dark: Boolean) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mode = if (dark) WallpaperMode.DARK else WallpaperMode.LIGHT
    val wallpapers = if (dark) BackgroundOption.darkWallpapers else BackgroundOption.lightWallpapers
    val colors = if (dark) BackgroundOption.darkColors else BackgroundOption.lightColors
    val selection = if (dark) SettingsManager.darkBackground else SettingsManager.lightBackground
    val customOption = BackgroundOption.custom(mode)
    val hasPhoto = CustomWallpaperStore.hasImage(mode)
    var isImportingPhoto by remember { mutableStateOf(false) }

    fun select(option: BackgroundOption) {
        if (dark) SettingsManager.saveDarkBackground(option) else SettingsManager.saveLightBackground(option)
    }

    // The system photo picker needs no storage permission.
    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            isImportingPhoto = true
            scope.launch {
                try {
                    if (CustomWallpaperStore.save(context, uri, mode)) select(customOption)
                } finally {
                    isImportingPhoto = false
                }
            }
        }
    }

    AppScaffold(
        title = stringResource(if (dark) R.string.background_dark_mode else R.string.background_light_mode),
        onBack = { nav.back() },
    ) { padding ->
        GlassCard(Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(96.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                header("custom_header", R.string.custom_wallpaper_section)
                item(key = "custom", span = { GridItemSpan(maxLineSpan) }) {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        if (hasPhoto) {
                            BackgroundCell(customOption, selection == customOption, Modifier.width(110.dp)) {
                                select(customOption)
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            TextButton(
                                enabled = !isImportingPhoto,
                                onClick = {
                                    photoPicker.launch(
                                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                },
                            ) {
                                Icon(Icons.Outlined.PhotoLibrary, contentDescription = null)
                                Text(
                                    stringResource(if (hasPhoto) R.string.change_photo else R.string.choose_photo),
                                    Modifier.padding(start = 8.dp),
                                )
                            }
                            if (hasPhoto) {
                                TextButton(onClick = {
                                    // If the photo was the active background, fall back to the
                                    // default so the selection never points at nothing.
                                    CustomWallpaperStore.remove(mode)
                                    if (selection == customOption) select(BackgroundOption.default(mode))
                                }) {
                                    Icon(Icons.Outlined.Delete, contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error)
                                    Text(stringResource(R.string.remove_photo), Modifier.padding(start = 8.dp),
                                        color = MaterialTheme.colorScheme.error)
                                }
                            }
                            if (isImportingPhoto) {
                                CircularProgressIndicator(Modifier.padding(start = 12.dp).size(24.dp), strokeWidth = 2.dp)
                            }
                        }
                    }
                }

                header("wallpapers_header", R.string.wallpapers)
                items(wallpapers, key = { it.raw }) { option ->
                    BackgroundCell(option, selection == option) { select(option) }
                }

                header("colors_header", R.string.solid_colors)
                items(colors, key = { it.raw }) { option ->
                    BackgroundCell(option, selection == option) { select(option) }
                }
            }
        }
    }
}

private fun LazyGridScope.header(key: String, title: Int) {
    item(key = key, span = { GridItemSpan(maxLineSpan) }) {
        Text(
            stringResource(title).uppercase(), style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}

@Composable
private fun BackgroundCell(option: BackgroundOption, isSelected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    SettingsPickerCell(
        label = stringResource(option.labelRes), isSelected = isSelected,
        aspectRatio = 9f / 16f, onClick = onClick, modifier = modifier,
    ) { SettingsBackgroundPreview(option, Modifier.fillMaxSize()) }
}

/**
 * Renders a background option's preview: catalog thumbnail, solid colour, or
 * the user's own photo. Shared by the picker grid and the Settings swatch.
 */
@Composable
internal fun SettingsBackgroundPreview(option: BackgroundOption, modifier: Modifier = Modifier) {
    val customMode = option.customMode
    val customFile = customMode?.let { CustomWallpaperStore.file(it) }
    // A custom option whose photo is gone shows the mode's default instead.
    val shown = if (customMode != null && customFile == null) BackgroundOption.default(customMode) else option
    when {
        customFile != null -> AsyncImage(
            model = customFile, contentDescription = null, modifier = modifier, contentScale = ContentScale.Crop)
        shown.thumbRes != null -> Image(
            painterResource(shown.thumbRes), contentDescription = null,
            modifier = modifier, contentScale = ContentScale.Crop)
        shown.color != null -> Box(modifier.background(shown.color))
        else -> Box(modifier.background(MaterialTheme.colorScheme.surfaceVariant))
    }
}
