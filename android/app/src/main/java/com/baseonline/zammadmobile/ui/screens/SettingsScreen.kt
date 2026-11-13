package com.baseonline.zammadmobile.ui.screens

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.BackHand
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Password
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Watch
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.viewModelScope
import com.baseonline.zammadmobile.BuildConfig
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.chat.ChatBlockList
import com.baseonline.zammadmobile.chat.ChatCrypto
import com.baseonline.zammadmobile.chat.ChatDirectory
import com.baseonline.zammadmobile.chat.ChatHistoryStore
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.data.ApiException
import com.baseonline.zammadmobile.data.ColorSchemeOption
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.managers.AuthenticationManager
import com.baseonline.zammadmobile.managers.BackgroundRefreshWorker
import com.baseonline.zammadmobile.managers.DraftManager
import com.baseonline.zammadmobile.managers.PushManager
import com.baseonline.zammadmobile.managers.ReadStatusManager
import com.baseonline.zammadmobile.managers.WearSync
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.StyledSection
import com.baseonline.zammadmobile.ui.theme.ChatTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val SUPPORT_URL = "https://base1983.github.io/Zammad-Helpdesk/"
private const val PRIVACY_POLICY_URL = "https://base1983.github.io/Zammad-Helpdesk/privacy.html"

private val Green = Color(0xFF2E9E4F)
private val Orange = Color(0xFFE08A00)

/**
 * Settings. Appearance, chat, lock and notification choices are stored the
 * moment they change; the server address and token are only written by the
 * save action in the top bar (back discards those two edits), as on iOS.
 */
@Composable
fun SettingsScreen(vm: TicketViewModel, nav: Nav) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var serverURL by rememberSaveable { mutableStateOf(SettingsManager.loadServerURL()) }
    // Not saveable on purpose: the token must not end up in the saved instance state.
    var apiToken by remember { mutableStateOf(SettingsManager.loadToken() ?: "") }
    var showDisconnectConfirm by remember { mutableStateOf(false) }
    var isDisconnecting by remember { mutableStateOf(false) }

    fun saveAndClose() {
        SettingsManager.saveServerURL(serverURL.trim())
        SettingsManager.saveToken(apiToken.trim())
        WearSync.push(context)
        // The view model outlives this screen, so the reload survives the pop.
        vm.viewModelScope.launch { try { vm.refreshAllData() } catch (e: Exception) { } }
        nav.back()
    }

    /**
     * Wipes every trace of the account from this device and the watch, then
     * returns to the setup wizard. Order matters: the relay is told to stop
     * pushing while the proxy id it is registered under still exists.
     */
    fun disconnect() {
        if (isDisconnecting) return
        isDisconnecting = true
        scope.launch {
            // Never stop halfway, even if the screen goes away in the meantime.
            withContext(NonCancellable) {
                PushManager.updateRegistration(false)

                ChatService.reset()
                ChatDirectory.clear()
                ChatHistoryStore.clearAll()
                ChatCrypto.resetIdentity()
                ChatBlockList.removeAll()
                DraftManager.deleteAll()
                ReadStatusManager.reset()
                SettingsManager.clearAccountData()
                try { NotificationManagerCompat.from(context).cancelAll() } catch (e: Exception) { }
                BackgroundRefreshWorker.cancel(context)
                vm.reset()

                // Last: this swaps the whole UI back to the wizard.
                SettingsManager.saveSetupComplete(false)
                WearSync.push(context)
            }
        }
    }

    AppScaffold(
        title = stringResource(R.string.settings),
        onBack = { nav.back() },
        actions = {
            IconButton(onClick = { saveAndClose() }, enabled = !isDisconnecting) {
                Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.save))
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState())
                .padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            ServerSection(serverURL, { serverURL = it }, apiToken, { apiToken = it })
            SecuritySection()
            AppearanceSection(nav)
            ChatSection(nav)
            NotificationsSection(nav, hasToken = apiToken.isNotEmpty())

            // The one paywall, shared with the Premium screen (iOS: InAppPurchaseView).
            // It brings its own section header and, as on iOS, the ad privacy
            // options row (only where UMP requires one, never for Premium users).
            PremiumContent(Modifier.fillMaxWidth(), showBenefits = false)

            StyledSection(stringResource(R.string.wear_title), footer = stringResource(R.string.wear_sync_hint)) {
                // No string resource exists for this label yet (listed in the port report).
                NavRow(Icons.Outlined.Watch, stringResource(R.string.wear_sync_now), showChevron = false) {
                    WearSync.push(context)
                }
            }

            StyledSection(stringResource(R.string.about)) {
                NavRow(Icons.AutoMirrored.Outlined.OpenInNew, stringResource(R.string.support), showChevron = false) {
                    openInBrowser(context, SUPPORT_URL)
                }
                RowDivider()
                NavRow(Icons.AutoMirrored.Outlined.OpenInNew, stringResource(R.string.privacy_policy), showChevron = false) {
                    openInBrowser(context, PRIVACY_POLICY_URL)
                }
                RowDivider()
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.app_version), Modifier.weight(1f))
                    Text(BuildConfig.VERSION_NAME, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            StyledSection(footer = stringResource(R.string.disconnect_footer)) {
                Row(
                    Modifier.fillMaxWidth()
                        .clickable(enabled = !isDisconnecting) { showDisconnectConfirm = true }
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.AutoMirrored.Outlined.Logout, contentDescription = null,
                        tint = MaterialTheme.colorScheme.error)
                    Text(stringResource(R.string.disconnect), Modifier.weight(1f).padding(start = 12.dp),
                        color = MaterialTheme.colorScheme.error)
                    if (isDisconnecting) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                }
            }
        }
    }

    if (showDisconnectConfirm) {
        AlertDialog(
            onDismissRequest = { showDisconnectConfirm = false },
            title = { Text(stringResource(R.string.disconnect_confirm_title)) },
            text = { Text(stringResource(R.string.disconnect_confirm_message)) },
            confirmButton = {
                TextButton(onClick = { showDisconnectConfirm = false; disconnect() }) {
                    Text(stringResource(R.string.disconnect_confirm_button), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDisconnectConfirm = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

// MARK: - 1. Server

@Composable
private fun ServerSection(serverURL: String, onServerURL: (String) -> Unit, apiToken: String, onToken: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val successText = stringResource(R.string.connection_successful)
    val failedText = stringResource(R.string.connection_failed)
    var testStatus by remember { mutableStateOf<String?>(null) }
    var isTesting by remember { mutableStateOf(false) }
    var showToken by remember { mutableStateOf(false) }
    var showLogin by remember { mutableStateOf(false) }

    StyledSection(stringResource(R.string.server_configuration)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(
                value = serverURL, onValueChange = onServerURL, singleLine = true,
                placeholder = { Text(stringResource(R.string.zammad_instance_url)) },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri, capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = apiToken, onValueChange = onToken, singleLine = true,
                placeholder = { Text(stringResource(R.string.paste_api_token)) },
                visualTransformation = if (showToken) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                trailingIcon = {
                    IconButton(onClick = { showToken = !showToken }) {
                        Icon(if (showToken) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                            contentDescription = null)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )
            TextButton(onClick = { showLogin = true }, enabled = serverURL.isNotBlank()) {
                Icon(Icons.Outlined.Password, contentDescription = null)
                Text(stringResource(R.string.login_with_password), Modifier.padding(start = 8.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = !isTesting, onClick = {
                    isTesting = true
                    testStatus = null
                    scope.launch {
                        val ok = ZammadApi.testConnection(serverURL.trim(), apiToken.trim())
                        testStatus = if (ok) successText else failedText
                        isTesting = false
                    }
                }) { Text(stringResource(R.string.test_connection)) }
                if (isTesting) {
                    CircularProgressIndicator(Modifier.padding(start = 4.dp).size(18.dp), strokeWidth = 2.dp)
                    Text(stringResource(R.string.testing_connection), Modifier.padding(start = 8.dp),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                testStatus?.let {
                    Text(it, Modifier.weight(1f).padding(start = 8.dp), style = MaterialTheme.typography.bodySmall,
                        color = if (it == successText) Green else MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    if (showLogin) {
        PasswordLoginDialog(serverURL.trim(), onDismiss = { showLogin = false }) { newToken ->
            onToken(newToken)
            // Persist immediately so a freshly minted token survives even if
            // the settings screen is left without saving.
            SettingsManager.saveToken(newToken)
            testStatus = successText
            showLogin = false
        }
    }
}

/** Username/password sign-in that has Zammad mint a personal access token. */
@Composable
private fun PasswordLoginDialog(serverURL: String, onDismiss: () -> Unit, onTokenReceived: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val loginFailed = stringResource(R.string.login_failed)
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isLoggingIn by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!isLoggingIn) onDismiss() },
        title = { Text(stringResource(R.string.login_with_password)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = username, onValueChange = { username = it }, singleLine = true,
                    label = { Text(stringResource(R.string.username_placeholder)) },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Email, capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = password, onValueChange = { password = it }, singleLine = true,
                    label = { Text(stringResource(R.string.password_placeholder)) },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                    modifier = Modifier.fillMaxWidth(),
                )
                errorMessage?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
                Text(stringResource(R.string.password_login_explainer), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = {
            TextButton(
                enabled = !isLoggingIn && username.isNotEmpty() && password.isNotEmpty() && serverURL.isNotEmpty(),
                onClick = {
                    isLoggingIn = true
                    errorMessage = null
                    scope.launch {
                        try {
                            val token = ZammadApi.createAccessToken(
                                serverURL, username.trim(), password, "Android Helpdesk – ${Build.MODEL}")
                            onTokenReceived(token)
                        } catch (e: ApiException.AuthenticationFailed) {
                            errorMessage = loginFailed
                        } catch (e: Exception) {
                            errorMessage = e.message ?: e.toString()
                        } finally {
                            isLoggingIn = false
                        }
                    }
                },
            ) {
                if (isLoggingIn) CircularProgressIndicator(Modifier.padding(end = 8.dp).size(16.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.login))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isLoggingIn) { Text(stringResource(R.string.cancel)) }
        },
    )
}

// MARK: - 2. Security

@Composable
private fun SecuritySection() {
    val context = LocalContext.current
    // Without a screen lock on the device there is nothing to lock with.
    val canLock = remember { AuthenticationManager.canLock(context) }
    StyledSection(stringResource(R.string.security)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.enable_app_lock), Modifier.weight(1f))
            Switch(
                checked = SettingsManager.isLockEnabled,
                enabled = canLock || SettingsManager.isLockEnabled,
                onCheckedChange = { on -> if (!on || canLock) SettingsManager.saveLockEnabled(on) },
            )
        }
    }
}

// MARK: - 3. Appearance

@Composable
private fun AppearanceSection(nav: Nav) {
    StyledSection(stringResource(R.string.appearance)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
            val options = ColorSchemeOption.entries
            options.forEachIndexed { index, option ->
                SegmentedButton(
                    selected = SettingsManager.theme == option,
                    onClick = { SettingsManager.saveTheme(option) },
                    shape = SegmentedButtonDefaults.itemShape(index, options.size),
                ) { Text(stringResource(option.labelRes), maxLines = 1) }
            }
        }
        RowDivider()
        NavRow(Icons.Outlined.LightMode, stringResource(R.string.background_light_mode),
            trailing = { Swatch(24) { SettingsBackgroundPreview(SettingsManager.lightBackground, Modifier.fillMaxSize()) } },
        ) { nav.openBackgroundPicker(false) }
        RowDivider()
        NavRow(Icons.Outlined.DarkMode, stringResource(R.string.background_dark_mode),
            trailing = { Swatch(24) { SettingsBackgroundPreview(SettingsManager.darkBackground, Modifier.fillMaxSize()) } },
        ) { nav.openBackgroundPicker(true) }
        RowDivider()
        NavRow(Icons.Outlined.ChatBubbleOutline, stringResource(R.string.chat_theme_light_mode),
            trailing = { Swatch(30) { SettingsChatThemePreview(ChatTheme.current(false), Modifier.fillMaxSize()) } },
        ) { nav.openChatThemePicker(false) }
        RowDivider()
        NavRow(Icons.Rounded.ChatBubble, stringResource(R.string.chat_theme_dark_mode),
            trailing = { Swatch(30) { SettingsChatThemePreview(ChatTheme.current(true), Modifier.fillMaxSize()) } },
        ) { nav.openChatThemePicker(true) }
    }
}

/** Miniature preview of the current choice, shown at the end of a row. */
@Composable
private fun Swatch(width: Int, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(6.dp)
    Box(
        Modifier.width(width.dp).height(40.dp).clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f), shape)
    ) { content() }
}

// MARK: - 3b. Chat

private val retentionChoices = listOf(
    30 to R.string.chat_retention_30,
    90 to R.string.chat_retention_90,
    180 to R.string.chat_retention_180,
    365 to R.string.chat_retention_365,
    0 to R.string.chat_retention_forever,
)

@Composable
private fun ChatSection(nav: Nav) {
    val scope = rememberCoroutineScope()
    var showRetentionMenu by remember { mutableStateOf(false) }
    val days = SettingsManager.chatRetentionDays
    val currentLabel = retentionChoices.firstOrNull { it.first == days }?.second

    StyledSection(stringResource(R.string.chat), footer = stringResource(R.string.chat_history_retention_footer)) {
        NavRow(Icons.Outlined.History, stringResource(R.string.chat_history_retention), showChevron = false,
            trailing = {
                Box {
                    Text(currentLabel?.let { stringResource(it) } ?: days.toString(),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    DropdownMenu(expanded = showRetentionMenu, onDismissRequest = { showRetentionMenu = false }) {
                        retentionChoices.forEach { (value, label) ->
                            DropdownMenuItem(
                                text = { Text(stringResource(label)) },
                                trailingIcon = {
                                    if (value == days) Icon(Icons.Filled.Check, contentDescription = null)
                                },
                                onClick = {
                                    showRetentionMenu = false
                                    if (value != days) {
                                        SettingsManager.saveChatRetentionDays(value)
                                        // A shorter period takes effect right away.
                                        scope.launch(Dispatchers.IO) {
                                            try { ChatHistoryStore.pruneAll() } catch (e: Exception) { }
                                        }
                                    }
                                },
                            )
                        }
                    }
                }
            },
        ) { showRetentionMenu = true }
        RowDivider()
        NavRow(Icons.Outlined.BackHand, stringResource(R.string.chat_blocked_users)) { nav.openBlockedUsers() }
    }
}

// MARK: - 4. Notifications

@Composable
private fun NotificationsSection(nav: Nav, hasToken: Boolean) {
    val context = LocalContext.current
    val isPremium = SettingsManager.isPremium
    val isOn = SettingsManager.realtimeNotificationsEnabled
    val isAvailable = remember { PushManager.isAvailable }
    var showPremiumRequired by remember { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            permissionDenied = false
            PushManager.enableNotifications { }
        } else {
            permissionDenied = true
        }
    }

    fun toggle(on: Boolean) {
        permissionDenied = false
        when {
            !on -> PushManager.disableNotifications()
            !isPremium -> showPremiumRequired = true
            Build.VERSION.SDK_INT >= 33 && !PushManager.hasPermission(context) ->
                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            else -> PushManager.enableNotifications { }
        }
    }

    StyledSection(stringResource(R.string.notifications)) {
        if (!hasToken) {
            Text(stringResource(R.string.configure_server_for_notifications), Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@StyledSection
        }

        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(end = 12.dp)) {
                Text(stringResource(R.string.realtime_notifications), fontWeight = FontWeight.Medium)
                Text(stringResource(R.string.realtime_notifications_subtitle),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Switch(
                checked = isOn,
                enabled = isAvailable && !PushManager.isLoading,
                onCheckedChange = { toggle(it) },
            )
        }

        if (!isPremium) {
            // Real-time notifications and the icon badge are Premium.
            Row(
                Modifier.fillMaxWidth().clickable { nav.openPremium() }.padding(horizontal = 16.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(Icons.Filled.WorkspacePremium, contentDescription = null, tint = Color(0xFFE6B800))
                Text(stringResource(R.string.notifications_premium_required_android), Modifier.weight(1f),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        val error = when {
            !isAvailable -> stringResource(R.string.push_not_configured)
            permissionDenied -> stringResource(R.string.notification_permission_denied)
            // The premium case already has its own row above.
            isPremium -> PushManager.errorMessage
            else -> null
        }
        if (PushManager.isLoading) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.linking_to_zammad), Modifier.padding(start = 8.dp),
                    style = MaterialTheme.typography.bodySmall, color = Orange)
            }
        } else if (error != null) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(18.dp))
                Text(error, Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
        }

        // The webhook URL exists once this device is registered with the relay.
        val webhookURL = if (isOn && isPremium) SettingsManager.getWebhookURL() else null
        if (webhookURL != null) {
            RowDivider()
            WebhookURLRow(webhookURL)
        }
        if (isPremium) {
            RowDivider()
            NavRow(null, stringResource(R.string.setup_guide)) { nav.openWebhookGuide() }
        }
    }

    if (showPremiumRequired) {
        AlertDialog(
            onDismissRequest = { showPremiumRequired = false },
            icon = { Icon(Icons.Filled.WorkspacePremium, contentDescription = null, tint = Color(0xFFE6B800)) },
            text = { Text(stringResource(R.string.notifications_premium_required_android)) },
            confirmButton = {
                TextButton(onClick = { showPremiumRequired = false; nav.openPremium() }) {
                    Text(stringResource(R.string.premium_step_title))
                }
            },
            dismissButton = {
                TextButton(onClick = { showPremiumRequired = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun WebhookURLRow(webhookURL: String) {
    val context = LocalContext.current
    var showCopied by remember { mutableStateOf(false) }
    LaunchedEffect(showCopied) {
        if (showCopied) { delay(2000); showCopied = false }
    }
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Green, modifier = Modifier.size(18.dp))
            Text(
                stringResource(if (showCopied) R.string.copied else R.string.linked_set_url_in_zammad),
                Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                .padding(start = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(webhookURL, Modifier.weight(1f), fontFamily = FontFamily.Monospace, fontSize = 11.sp,
                maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
            IconButton(onClick = {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("Webhook URL", webhookURL))
                showCopied = true
            }) {
                Icon(
                    if (showCopied) Icons.Filled.Check else Icons.Outlined.ContentCopy,
                    contentDescription = stringResource(R.string.copied),
                    tint = if (showCopied) Green else MaterialTheme.colorScheme.tertiary,
                )
            }
        }
    }
}

// MARK: - Building blocks

@Composable
private fun RowDivider() {
    HorizontalDivider(Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
}

@Composable
private fun NavRow(
    icon: ImageVector?,
    title: String,
    showChevron: Boolean = true,
    trailing: @Composable () -> Unit = {},
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(12.dp))
        }
        Text(title, Modifier.weight(1f))
        trailing()
        if (showChevron) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 6.dp))
        }
    }
}

private fun openInBrowser(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    } catch (e: ActivityNotFoundException) {
        // No browser installed: nothing to open the page with.
    }
}
