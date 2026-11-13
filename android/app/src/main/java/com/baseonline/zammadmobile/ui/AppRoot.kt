package com.baseonline.zammadmobile.ui

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import coil3.compose.AsyncImage
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.data.BackgroundOption
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.WallpaperMode
import com.baseonline.zammadmobile.managers.AppOpenAdManager
import com.baseonline.zammadmobile.managers.AuthenticationManager
import com.baseonline.zammadmobile.managers.BackgroundRefreshWorker
import com.baseonline.zammadmobile.managers.CustomWallpaperStore
import com.baseonline.zammadmobile.managers.DeepLinkManager
import com.baseonline.zammadmobile.managers.InterstitialAdManager
import com.baseonline.zammadmobile.managers.WearSync
import com.baseonline.zammadmobile.managers.showsAds
import com.baseonline.zammadmobile.ui.screens.BackgroundPickerScreen
import com.baseonline.zammadmobile.ui.screens.BlockedUsersScreen
import com.baseonline.zammadmobile.ui.screens.ChatConversationScreen
import com.baseonline.zammadmobile.ui.screens.ChatListScreen
import com.baseonline.zammadmobile.ui.screens.ChatThemePickerScreen
import com.baseonline.zammadmobile.ui.screens.LockedScreen
import com.baseonline.zammadmobile.ui.screens.PremiumScreen
import com.baseonline.zammadmobile.ui.screens.SettingsScreen
import com.baseonline.zammadmobile.ui.screens.SetupWizardScreen
import com.baseonline.zammadmobile.ui.screens.TicketCreateScreen
import com.baseonline.zammadmobile.ui.screens.TicketDetailScreen
import com.baseonline.zammadmobile.ui.screens.TicketEditScreen
import com.baseonline.zammadmobile.ui.screens.TicketHandoffScreen
import com.baseonline.zammadmobile.ui.screens.TicketListScreen
import com.baseonline.zammadmobile.ui.screens.TicketReplyScreen
import com.baseonline.zammadmobile.ui.screens.TimeAccountingScreen
import com.baseonline.zammadmobile.ui.screens.WebhookGuideScreen
import com.baseonline.zammadmobile.ui.theme.HelpdeskTheme
import com.baseonline.zammadmobile.ui.theme.LocalIsDark

/**
 * The counterpart of the iOS `ContentView`: wallpaper behind everything, then
 * the setup wizard, the lock screen or the app, plus notification deep links.
 */
@Composable
fun AppRoot() {
    val setupComplete = SettingsManager.isSetupComplete
    // The wizard is always dark, like on iOS.
    HelpdeskTheme(forceDark = !setupComplete) {
        Box(Modifier.fillMaxSize()) {
            AppBackground()
            if (!setupComplete) {
                val context = LocalContext.current
                SetupWizardScreen(onFinished = {
                    SettingsManager.saveSetupComplete(true)
                    BackgroundRefreshWorker.schedule(context)
                    WearSync.push(context)
                })
            } else {
                MainApp()
            }
        }
    }
}

/** The chosen wallpaper (image, solid colour or the user's own photo), full screen. */
@Composable
fun AppBackground() {
    val dark = LocalIsDark.current
    val mode = if (dark) WallpaperMode.DARK else WallpaperMode.LIGHT
    var option = if (dark) SettingsManager.darkBackground else SettingsManager.lightBackground
    val customFile = option.customMode?.let { CustomWallpaperStore.file(it) }
    if (option.customMode != null && customFile == null) option = BackgroundOption.default(mode)
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        when {
            customFile != null -> AsyncImage(
                model = customFile, contentDescription = null,
                modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            option.imageRes != null -> Image(
                painterResource(option.imageRes!!), contentDescription = null,
                modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            option.color != null -> Box(Modifier.fillMaxSize().background(option.color!!))
        }
    }
}

@Composable
private fun MainApp() {
    val activity = LocalActivity.current as FragmentActivity
    val vm: TicketViewModel = viewModel(activity)
    val unlocked = AuthenticationManager.isUnlocked || !SettingsManager.isLockEnabled

    LaunchedEffect(Unit) { AuthenticationManager.authenticate(activity) }

    val navController = rememberNavController()
    val nav = remember(navController) { Nav(navController) }
    var isProcessingDeepLink by remember { mutableStateOf(false) }

    // Full-screen ads are preloaded as soon as this user may see ads at all.
    val ads = showsAds
    LaunchedEffect(ads) {
        if (ads) { AppOpenAdManager.preload(activity); InterstitialAdManager.preload(activity) }
    }

    // Notification / link routing. Ticket first: a chat push that references a
    // ticket (handoff) opens the ticket, as on iOS.
    val pendingTicket = DeepLinkManager.pendingTicketID
    LaunchedEffect(pendingTicket, unlocked) {
        val id = pendingTicket ?: return@LaunchedEffect
        if (!unlocked) return@LaunchedEffect
        isProcessingDeepLink = true
        val ticket = vm.handleDeepLink(id)
        DeepLinkManager.pendingTicketID = null
        isProcessingDeepLink = false
        if (ticket != null) nav.openTicket(ticket.id)
    }
    val pendingPartner = DeepLinkManager.pendingChatPartnerID
    LaunchedEffect(pendingPartner, unlocked) {
        val id = pendingPartner ?: return@LaunchedEffect
        if (!unlocked) return@LaunchedEffect
        DeepLinkManager.pendingChatPartnerID = null
        nav.openConversation("dm-$id")
    }
    val pendingGroup = DeepLinkManager.pendingChatGroupID
    LaunchedEffect(pendingGroup, unlocked) {
        val id = pendingGroup ?: return@LaunchedEffect
        if (!unlocked) return@LaunchedEffect
        DeepLinkManager.pendingChatGroupID = null
        nav.openConversation("group-$id")
    }

    Box(Modifier.fillMaxSize()) {
        NavHost(navController, startDestination = Routes.TICKETS) {
            composable(Routes.TICKETS) { TicketListScreen(vm, nav) }
            composable(Routes.CREATE) { TicketCreateScreen(vm, nav) }
            composable("ticket/{id}", listOf(navArgument("id") { type = NavType.IntType })) {
                TicketDetailScreen(vm, nav, it.arguments!!.getInt("id"))
            }
            composable(
                "ticket/{id}/reply?note={note}&article={article}",
                listOf(
                    navArgument("id") { type = NavType.IntType },
                    navArgument("note") { type = NavType.BoolType; defaultValue = false },
                    navArgument("article") { type = NavType.IntType; defaultValue = 0 },
                ),
            ) {
                val args = it.arguments!!
                TicketReplyScreen(vm, nav, args.getInt("id"), args.getBoolean("note"), args.getInt("article"))
            }
            composable("ticket/{id}/edit", listOf(navArgument("id") { type = NavType.IntType })) {
                TicketEditScreen(vm, nav, it.arguments!!.getInt("id"))
            }
            composable("ticket/{id}/handoff", listOf(navArgument("id") { type = NavType.IntType })) {
                TicketHandoffScreen(vm, nav, it.arguments!!.getInt("id"))
            }
            composable("ticket/{id}/time", listOf(navArgument("id") { type = NavType.IntType })) {
                TimeAccountingScreen(vm, nav, it.arguments!!.getInt("id"))
            }
            composable(Routes.CHAT) { ChatListScreen(vm, nav) }
            composable("chat/{target}") { ChatConversationScreen(vm, nav, it.arguments!!.getString("target")!!) }
            composable(Routes.SETTINGS) { SettingsScreen(vm, nav) }
            composable("settings/background/{dark}", listOf(navArgument("dark") { type = NavType.BoolType })) {
                BackgroundPickerScreen(nav, it.arguments!!.getBoolean("dark"))
            }
            composable("settings/chattheme/{dark}", listOf(navArgument("dark") { type = NavType.BoolType })) {
                ChatThemePickerScreen(nav, it.arguments!!.getBoolean("dark"))
            }
            composable(Routes.BLOCKED) { BlockedUsersScreen(nav) }
            composable(Routes.WEBHOOK) { WebhookGuideScreen(nav) }
            composable(Routes.PREMIUM) { PremiumScreen(onClose = { nav.back() }) }
        }

        // The lock is an overlay, not a replacement: the navigation stack (an
        // open reply, a picked attachment) survives the app being locked while
        // a system picker or the purchase sheet was in front.
        if (!unlocked) {
            Box(Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { } }) {
                AppBackground()
                LockedScreen(onUnlock = { AuthenticationManager.authenticate(activity) })
            }
        }

        if (isProcessingDeepLink) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f)), Alignment.Center) {
                Surface(shape = RoundedCornerShape(12.dp), tonalElevation = 6.dp) {
                    Column(Modifier.padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator()
                        Spacer(Modifier.height(20.dp))
                        Text(stringResource(R.string.loading_ticket), style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
    }
}
