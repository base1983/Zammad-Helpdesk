package com.baseonline.zammadmobile.ui.screens

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.ApiException
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.managers.AuthenticationManager
import com.baseonline.zammadmobile.managers.PushManager
import com.baseonline.zammadmobile.ui.components.GlassCard
import com.baseonline.zammadmobile.ui.components.glassColor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class AuthMethod(val labelRes: Int) {
    PASSWORD(R.string.auth_method_password),
    SSO(R.string.auth_method_sso),
    TOKEN(R.string.auth_method_token),
}

private const val STEP_COUNT = 3
private val SuccessGreen = Color(0xFF34C759)
private val AccentBlue = Color(0xFF007AFF)

/**
 * First-run wizard (iOS `SetupWizardView`): server + sign-in, the paywall,
 * permissions. Pages can be swiped like on iOS, so the paywall is reachable
 * before any login, but finishing requires a connection that was verified
 * with the server.
 */
@Composable
fun SetupWizardScreen(onFinished: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val pagerState = rememberPagerState(pageCount = { STEP_COUNT })
    val currentStep = pagerState.currentPage

    var serverURL by rememberSaveable { mutableStateOf("") }
    var username by rememberSaveable { mutableStateOf("") }
    var authMethod by rememberSaveable { mutableStateOf(AuthMethod.PASSWORD) }
    // Secrets stay out of the saved instance state: the password is never
    // stored, and the token only goes to the encrypted store at the end.
    var password by remember { mutableStateOf("") }
    var apiToken by remember { mutableStateOf("") }
    var showSSO by remember { mutableStateOf(false) }
    var enableLock by rememberSaveable { mutableStateOf(false) }
    var enableNotifications by rememberSaveable { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }

    var isTesting by remember { mutableStateOf(false) }
    var resultText by remember { mutableStateOf<String?>(null) }
    var resultIsSuccess by remember { mutableStateOf(false) }
    /** The (url, token) pair the server accepted; any edit invalidates it. */
    var verified by remember { mutableStateOf<Pair<String, String>?>(null) }
    val isVerified = apiToken.isNotEmpty() && verified == (serverURL.trim() to apiToken)

    var showSplash by rememberSaveable { mutableStateOf(true) }

    val isPremium = SettingsManager.isPremium
    val connectionSuccessful = stringResource(R.string.connection_successful)
    val connectionFailed = stringResource(R.string.connection_failed)
    val loginFailed = stringResource(R.string.login_failed)
    val fillCredentials = stringResource(R.string.please_fill_credentials)

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        enableNotifications = granted
        permissionDenied = !granted
    }

    fun goTo(step: Int) {
        focusManager.clearFocus()
        scope.launch { pagerState.animateScrollToPage(step) }
    }

    fun fail(message: String) {
        resultText = message
        resultIsSuccess = false
        isTesting = false
    }

    fun testAndProceed() {
        val url = serverURL.trim()
        if (url.isEmpty()) { fail(connectionFailed); return }
        if (authMethod == AuthMethod.SSO && apiToken.isEmpty()) { showSSO = true; return }

        isTesting = true
        resultText = null
        scope.launch {
            try {
                val token = when (authMethod) {
                    AuthMethod.PASSWORD -> {
                        if (username.isBlank() || password.isEmpty()) { fail(fillCredentials); return@launch }
                        ZammadApi.createAccessToken(
                            url = url, username = username.trim(), password = password,
                            tokenName = "Android Helpdesk – ${Build.MODEL}",
                        ).also { apiToken = it }
                    }
                    AuthMethod.TOKEN, AuthMethod.SSO -> apiToken.trim().also { apiToken = it }
                }
                if (ZammadApi.testConnection(url, token)) {
                    resultText = connectionSuccessful
                    resultIsSuccess = true
                    password = ""
                    serverURL = url
                    verified = url to token
                    isTesting = false
                    delay(1000)
                    goTo(1)
                } else {
                    fail(connectionFailed)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiException.AuthenticationFailed) {
                fail(loginFailed)
            } catch (e: Exception) {
                fail(e.message ?: connectionFailed)
            }
        }
    }

    fun nextStep() {
        if (currentStep == 0 && !isVerified) testAndProceed() else goTo(currentStep + 1)
    }

    fun finishSetup() {
        val accepted = verified
        if (!isVerified || accepted == null) {
            // Swiped past the first page without a working sign-in.
            fail(connectionFailed)
            goTo(0)
            return
        }
        SettingsManager.saveServerURL(accepted.first)
        SettingsManager.saveToken(accepted.second)
        SettingsManager.saveLockEnabled(enableLock && AuthenticationManager.canLock(context))

        // Notifications are a Premium feature; the switch is disabled without
        // Premium, but guard here too in case the entitlement changed since.
        if (enableNotifications && SettingsManager.isPremium && PushManager.hasPermission(context)) {
            PushManager.enableNotifications()
        } else {
            SettingsManager.saveRealtimeNotificationsEnabled(false)
        }
        onFinished()
    }

    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            HorizontalPager(state = pagerState, modifier = Modifier.weight(1f).fillMaxWidth()) { page ->
                WizardPage {
                    when (page) {
                        0 -> {
                            WizardHeader(R.string.server_config_title, R.string.server_config_message)

                            WizardField(
                                value = serverURL, onValueChange = { serverURL = it },
                                label = stringResource(R.string.server_url),
                                placeholder = stringResource(R.string.zammad_instance_url),
                                keyboardType = KeyboardType.Uri,
                            )

                            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                                AuthMethod.entries.forEachIndexed { index, method ->
                                    SegmentedButton(
                                        selected = authMethod == method,
                                        onClick = { authMethod = method },
                                        shape = SegmentedButtonDefaults.itemShape(index, AuthMethod.entries.size),
                                        colors = SegmentedButtonDefaults.colors(inactiveContainerColor = glassColor()),
                                    ) { Text(stringResource(method.labelRes), maxLines = 1) }
                                }
                            }

                            when (authMethod) {
                                AuthMethod.SSO -> {
                                    Text(stringResource(R.string.sso_explainer),
                                        style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Button(
                                        onClick = { focusManager.clearFocus(); showSSO = true },
                                        enabled = serverURL.isNotBlank(),
                                        modifier = Modifier.fillMaxWidth(),
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = if (apiToken.isEmpty()) AccentBlue else Color.Gray,
                                            contentColor = Color.White),
                                    ) {
                                        Icon(Icons.Filled.Language, contentDescription = null)
                                        Spacer(Modifier.width(8.dp))
                                        Text(stringResource(R.string.login_with_sso))
                                    }
                                    if (apiToken.isNotEmpty()) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Icon(Icons.Filled.Verified, contentDescription = null, tint = SuccessGreen)
                                            Spacer(Modifier.width(8.dp))
                                            Text(stringResource(R.string.sso_token_ready), color = SuccessGreen,
                                                style = MaterialTheme.typography.bodyMedium)
                                        }
                                    }
                                }
                                AuthMethod.PASSWORD -> {
                                    WizardField(
                                        value = username, onValueChange = { username = it },
                                        label = stringResource(R.string.username),
                                        placeholder = stringResource(R.string.username_placeholder),
                                        keyboardType = KeyboardType.Email,
                                    )
                                    WizardField(
                                        value = password, onValueChange = { password = it },
                                        label = stringResource(R.string.password),
                                        placeholder = stringResource(R.string.password_placeholder),
                                        keyboardType = KeyboardType.Password, secure = true,
                                    )
                                }
                                AuthMethod.TOKEN -> WizardField(
                                    value = apiToken, onValueChange = { apiToken = it },
                                    label = stringResource(R.string.api_token),
                                    placeholder = stringResource(R.string.paste_api_token),
                                    keyboardType = KeyboardType.Password, secure = true,
                                )
                            }

                            if (isTesting) {
                                CircularProgressIndicator()
                            } else {
                                resultText?.let {
                                    Text(it, textAlign = TextAlign.Center,
                                        color = if (resultIsSuccess) SuccessGreen else MaterialTheme.colorScheme.error)
                                }
                            }
                        }

                        // The paywall is deliberately part of the wizard, so the
                        // purchases are reachable before any server login.
                        1 -> {
                            WizardHeader(R.string.premium_step_title, R.string.premium_step_message_android)
                            // Never blocks the wizard: without products it shows
                            // the store message and a retry, and Next still works.
                            PremiumContent(showAdPrivacyOptions = false)
                        }

                        else -> {
                            WizardHeader(R.string.permissions_title, R.string.permissions_message)

                            val canLock = remember { AuthenticationManager.canLock(context) }
                            GlassCard(Modifier.fillMaxWidth()) {
                                // No Android wording in the resources ("Face ID / Touch ID").
                                WizardSwitch(stringResource(R.string.enable_app_lock),
                                    checked = enableLock && canLock, enabled = canLock,
                                    onCheckedChange = { enableLock = it })
                            }

                            GlassCard(Modifier.fillMaxWidth()) {
                                WizardSwitch(stringResource(R.string.enable_notifications),
                                    checked = enableNotifications && isPremium, enabled = isPremium,
                                    onCheckedChange = { wanted ->
                                        permissionDenied = false
                                        if (wanted && Build.VERSION.SDK_INT >= 33 && !PushManager.hasPermission(context)) {
                                            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                        } else {
                                            enableNotifications = wanted
                                        }
                                    })
                                if (!isPremium) {
                                    Row(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp)) {
                                        Icon(Icons.Filled.WorkspacePremium, contentDescription = null,
                                            tint = Color(0xFFFFCC00), modifier = Modifier.size(20.dp))
                                        Spacer(Modifier.width(10.dp))
                                        Text(stringResource(R.string.notifications_premium_wizard_hint_android),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                                if (permissionDenied) {
                                    Text(stringResource(R.string.notification_permission_denied),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error,
                                        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp))
                                }
                            }
                        }
                    }
                }
            }

            // Page control
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                if (currentStep > 0) {
                    TextButton(onClick = { goTo(currentStep - 1) }) { Text(stringResource(R.string.previous_step)) }
                }
                Spacer(Modifier.weight(1f))
                when {
                    currentStep == STEP_COUNT - 1 ->
                        Button(onClick = { finishSetup() }) { Text(stringResource(R.string.finish_setup)) }
                    // SSO token received: highlight the next step.
                    currentStep == 0 && authMethod == AuthMethod.SSO && apiToken.isNotEmpty() ->
                        Button(
                            onClick = { nextStep() }, enabled = !isTesting,
                            colors = ButtonDefaults.buttonColors(containerColor = AccentBlue, contentColor = Color.White),
                        ) { Text(stringResource(R.string.next_step)) }
                    else ->
                        TextButton(onClick = { nextStep() }, enabled = !isTesting) {
                            Text(stringResource(R.string.next_step))
                        }
                }
            }
        }

        if (showSSO) {
            SetupSSOLogin(
                serverURL = serverURL,
                onToken = { token ->
                    apiToken = token
                    resultText = connectionSuccessful
                    resultIsSuccess = true
                    showSSO = false
                },
                onDismiss = { showSSO = false },
            )
        }

        AnimatedVisibility(visible = showSplash, enter = EnterTransition.None, exit = fadeOut(tween(700))) {
            SplashOverlay(onEnd = { showSplash = false })
        }
    }
}

@Composable
private fun WizardPage(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = content,
    )
}

@Composable
private fun WizardHeader(titleRes: Int, messageRes: Int) {
    Text(stringResource(titleRes), style = MaterialTheme.typography.headlineLarge,
        fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, color = Color.White)
    Text(stringResource(messageRes), textAlign = TextAlign.Center, color = Color.White)
}

@Composable
private fun WizardField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String,
    keyboardType: KeyboardType,
    secure: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        placeholder = { Text(placeholder) },
        singleLine = true,
        visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = keyboardType),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = glassColor(), unfocusedContainerColor = glassColor()),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun WizardSwitch(label: String, checked: Boolean, enabled: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f),
            color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled)
    }
}

/**
 * Launch splash over the wizard (iOS `SplashAnimationView`): the logo fades in
 * on black, holds, then the whole overlay fades away.
 */
@Composable
private fun SplashOverlay(onEnd: () -> Unit) {
    val logoAlpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        launch { logoAlpha.animateTo(1f, tween(1000)) }
        delay(2500)
        onEnd()
    }
    Box(
        Modifier.fillMaxSize().background(Color.Black)
            // Swallow touches so the wizard underneath cannot be used yet.
            .pointerInput(Unit) { detectTapGestures { } },
        contentAlignment = Alignment.Center,
    ) {
        Image(painterResource(R.drawable.splash_logo), contentDescription = null,
            modifier = Modifier.width(200.dp).alpha(logoAlpha.value))
    }
}
