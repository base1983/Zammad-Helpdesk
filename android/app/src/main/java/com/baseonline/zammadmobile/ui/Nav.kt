package com.baseonline.zammadmobile.ui

import androidx.navigation.NavHostController

/** Typed navigation; screens never build route strings themselves. */
class Nav(val controller: NavHostController) {
    fun back() { if (!controller.popBackStack()) controller.navigate(Routes.TICKETS) }

    fun openTicket(id: Int) = controller.navigate("ticket/$id") { launchSingleTop = true }
    /** [replyToArticleId] quotes/answers a specific article; 0 = the ticket's customer. */
    fun openReply(ticketId: Int, isInternalNote: Boolean, replyToArticleId: Int = 0) =
        controller.navigate("ticket/$ticketId/reply?note=$isInternalNote&article=$replyToArticleId")
    fun openEdit(ticketId: Int) = controller.navigate("ticket/$ticketId/edit")
    fun openHandoff(ticketId: Int) = controller.navigate("ticket/$ticketId/handoff")
    fun openTimeAccounting(ticketId: Int) = controller.navigate("ticket/$ticketId/time")
    fun openCreateTicket() = controller.navigate(Routes.CREATE)

    fun openChatList() = controller.navigate(Routes.CHAT) { launchSingleTop = true }
    /** [targetId] is `dm-<chat user id>` or `group-<group id>` (see ChatDirectory). */
    fun openConversation(targetId: String) = controller.navigate("chat/$targetId") { launchSingleTop = true }

    fun openSettings() = controller.navigate(Routes.SETTINGS) { launchSingleTop = true }
    fun openBackgroundPicker(dark: Boolean) = controller.navigate("settings/background/$dark")
    fun openChatThemePicker(dark: Boolean) = controller.navigate("settings/chattheme/$dark")
    fun openBlockedUsers() = controller.navigate(Routes.BLOCKED)
    fun openWebhookGuide() = controller.navigate(Routes.WEBHOOK)
    fun openPremium() = controller.navigate(Routes.PREMIUM) { launchSingleTop = true }
}

object Routes {
    const val TICKETS = "tickets"
    const val CREATE = "tickets/create"
    const val CHAT = "chat"
    const val SETTINGS = "settings"
    const val BLOCKED = "settings/blocked"
    const val WEBHOOK = "settings/webhook"
    const val PREMIUM = "premium"
}
